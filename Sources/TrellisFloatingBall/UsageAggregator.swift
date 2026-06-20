import Foundation

@MainActor
enum UsageAggregator {
    static func makeSnapshot(bundle: APIBundle, now: Date = Date()) throws -> UsageSnapshot {
        guard let subscriptionData = bundle.subscription.data else {
            throw KrillAPIError.missingData
        }

        let activeSubscriptions = subscriptionData.subscriptions.filter { item in
            guard item.plan?.active == true,
                  let start = APIDateParser.parse(item.subscriptionStartAt),
                  let end = APIDateParser.parse(item.subscriptionEndAt)
            else {
                return false
            }

            return start <= now && now < end
        }

        let subscriptionDisplays = activeSubscriptions.map { item in
            let start = APIDateParser.parse(item.subscriptionStartAt)
            let expiry = APIDateParser.parse(item.subscriptionEndAt)
            let weekStart = APIDateParser.parse(item.quota?.windowStartAt)
            let weekEnd = APIDateParser.parse(item.quota?.windowResetAt)
            let weeklyTotal = weeklyLimit(item)
            let weeklyUsed = weeklyTotal.map { _ in weeklyUsedAmount(item) }
            let weeklyRemaining = weeklyTotal.map { total in
                weeklyRemainingAmountFromAPI(item) ?? max(0, total - (weeklyUsed ?? 0))
            }
            let monthlyTotal = totalLimit(item)
            let monthlyUsed = monthlyTotal.map { _ in decimal(item.totalUsedUsd) }
            let monthlyRemaining = monthlyTotal.map { total in max(0, total - (monthlyUsed ?? 0)) }

            return SubscriptionDisplayItem(
                name: item.plan?.name ?? "未命名套餐",
                start: start,
                expiry: expiry,
                weeklyRemaining: weeklyRemaining,
                weeklyUsed: weeklyUsed,
                weeklyTotal: weeklyTotal,
                weekStart: weekStart,
                weekEnd: weekEnd,
                monthlyRemaining: monthlyRemaining,
                monthlyTotal: monthlyTotal
            )
        }.sorted { left, right in
            let leftRemaining = left.monthlyRemaining ?? -.infinity
            let rightRemaining = right.monthlyRemaining ?? -.infinity

            if leftRemaining != rightRemaining {
                return leftRemaining > rightRemaining
            }

            return (left.expiry ?? .distantPast) > (right.expiry ?? .distantPast)
        }

        let weeklyQuotaSubscriptions = activeSubscriptions.filter { weeklyLimit($0) != nil }
        let weekStarts = weeklyQuotaSubscriptions.compactMap { APIDateParser.parse($0.quota?.windowStartAt) }
        let weekEnds = weeklyQuotaSubscriptions.compactMap { APIDateParser.parse($0.quota?.windowResetAt) }
        let weekWindowStart = weekStarts.min()
        let weekWindowEnd = weekEnds.max()
        let overlappingTotalSubscriptions = activeSubscriptions.filter { item in
            guard weeklyLimit(item) == nil,
                  totalLimit(item) != nil,
                  let weekWindowStart,
                  let weekWindowEnd
            else {
                return false
            }
            return subscription(item, overlapsWindowStart: weekWindowStart, windowEnd: weekWindowEnd)
        }

        let weeklyTotal = weeklyQuotaSubscriptions.reduce(0.0) { partial, item in
            partial + (weeklyLimit(item) ?? 0)
        } + overlappingTotalSubscriptions.reduce(0.0) { partial, item in
            partial + (totalLimit(item) ?? 0)
        }
        let weeklyUsed = weeklyQuotaSubscriptions.reduce(0.0) { partial, item in
            partial + (weeklyLimit(item).map { _ in weeklyUsedAmount(item) } ?? 0)
        } + overlappingTotalSubscriptions.reduce(0.0) { partial, item in
            partial + decimal(item.totalUsedUsd)
        }
        let weeklyRemaining = weeklyQuotaSubscriptions.reduce(0.0) { partial, item in
            let total = weeklyLimit(item) ?? 0
            let remaining = weeklyRemainingAmountFromAPI(item) ?? max(0, total - weeklyUsedAmount(item))
            return partial + remaining
        } + overlappingTotalSubscriptions.reduce(0.0) { partial, item in
            let total = totalLimit(item) ?? 0
            return partial + Swift.max(0, total - decimal(item.totalUsedUsd))
        }
        let subscriptionsWithTotalLimit = activeSubscriptions.filter { totalLimit($0) != nil }

        let monthlyTotal = subscriptionsWithTotalLimit.reduce(0) { partial, item in
            partial + (totalLimit(item) ?? 0)
        }
        let monthlyUsed = subscriptionsWithTotalLimit.reduce(0) { partial, item in
            partial + decimal(item.totalUsedUsd)
        }
        let monthlyRemaining = monthlyTotal > 0 ? max(0, monthlyTotal - monthlyUsed) : nil
        let monthlyPercent = monthlyTotal > 0
            ? max(0, min(100, (monthlyRemaining ?? 0) / monthlyTotal * 100))
            : nil

        let maxEnd = activeSubscriptions
            .compactMap { APIDateParser.parse($0.subscriptionEndAt) }
            .max()

        let remainingDays = maxEnd.map { end in
            max(0, Int(ceil(end.timeIntervalSince(now) / 86_400)))
        }

        let stats = bundle.stats.data
        let cacheRates = (stats?.channelCacheRates ?? []).map { rate in
            CacheRate(
                name: rate.channelName ?? "未知渠道",
                percent: max(0, min(100, (rate.cacheRate ?? 0) * 100))
            )
        }

        let walletBalance = decimal(subscriptionData.creditBalanceUsd) + decimal(subscriptionData.welfareBalanceUsd)

        return UsageSnapshot(
            weeklyRemaining: weeklyTotal > 0 ? weeklyRemaining : nil,
            weeklyUsed: weeklyTotal > 0 ? weeklyUsed : nil,
            weeklyTotal: weeklyTotal > 0 ? weeklyTotal : nil,
            weekStart: weekStarts.min(),
            weekEnd: weekEnds.max(),
            monthlyRemaining: monthlyRemaining,
            monthlyUsed: monthlyTotal > 0 ? monthlyUsed : nil,
            monthlyTotal: monthlyTotal > 0 ? monthlyTotal : nil,
            monthlyPercent: monthlyPercent,
            expiry: maxEnd,
            remainingDays: remainingDays,
            todayCost: decimal(stats?.totalCostUsd),
            walletBalance: walletBalance,
            requestCount: stats?.totalRequests,
            cacheRates: cacheRates,
            subscriptions: subscriptionDisplays,
            lastRefresh: now,
            isLoading: false,
            isStale: false,
            needsToken: false,
            lastError: nil
        )
    }

    private static func weeklyLimit(_ item: SubscriptionItem) -> Double? {
        let billing = billingType(item)
        let dailyLimit = decimal(item.quota?.dailyLimitUsd)

        if billing == "usd_monthly" {
            return nil
        }

        if billing == "usd_weekly" || billing.contains("weekly") || billing.contains("week") {
            return dailyLimit > 0 ? dailyLimit : nil
        }

        let legacyLimit = dailyLimit + decimal(item.quota?.forwardedLimitUsd)
        return legacyLimit > 0 ? legacyLimit : nil
    }

    private static func totalLimit(_ item: SubscriptionItem) -> Double? {
        let billing = billingType(item)
        let dailyLimit = decimal(item.quota?.dailyLimitUsd)

        if billing == "usd_monthly" {
            return dailyLimit > 0 ? dailyLimit : nil
        }

        if billing == "usd_weekly" || billing.contains("weekly") || billing.contains("week") {
            let total = dailyLimit * 4
            return total > 0 ? total : nil
        }

        if isMonthlySubscription(item) {
            let total = dailyLimit * 4
            return total > 0 ? total : nil
        }

        return nil
    }

    private static func weeklyUsedAmount(_ item: SubscriptionItem) -> Double {
        let billing = billingType(item)
        if billing == "usd_weekly" || billing.contains("weekly") || billing.contains("week") {
            return decimal(item.quota?.usedUsd)
        }
        return decimal(item.quota?.usedUsd) + decimal(item.quota?.forwardedUsedUsd)
    }

    private static func weeklyRemainingAmountFromAPI(_ item: SubscriptionItem) -> Double? {
        guard hasDecimalValue(item.quota?.remainingUsd) else {
            return nil
        }

        let billing = billingType(item)
        if billing == "usd_weekly" || billing.contains("weekly") || billing.contains("week") {
            return decimal(item.quota?.remainingUsd)
        }
        return decimal(item.quota?.remainingUsd) + decimal(item.quota?.forwardedRemainingUsd)
    }

    private static func isMonthlySubscription(_ item: SubscriptionItem) -> Bool {
        let duration = item.plan?.durationDays ?? 0
        let billing = billingType(item)
        return duration >= 30 || billing.contains("month")
    }

    private static func subscription(
        _ item: SubscriptionItem,
        overlapsWindowStart windowStart: Date,
        windowEnd: Date
    ) -> Bool {
        guard let start = APIDateParser.parse(item.subscriptionStartAt),
              let end = APIDateParser.parse(item.subscriptionEndAt)
        else {
            return false
        }
        return start < windowEnd && windowStart < end
    }

    private static func billingType(_ item: SubscriptionItem) -> String {
        (item.plan?.billingType ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func hasDecimalValue(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    static func decimal(_ value: String?) -> Double {
        guard let value else {
            return 0
        }

        return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}

@MainActor
enum APIDateParser {
    private static let internetDateTimeWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, value.isEmpty == false else {
            return nil
        }

        if let date = internetDateTimeWithFractionalSeconds.date(from: value) {
            return date
        }

        if let date = internetDateTime.date(from: value) {
            return date
        }

        dateOnlyFormatter.timeZone = TimeZone.current
        return dateOnlyFormatter.date(from: value)
    }
}
