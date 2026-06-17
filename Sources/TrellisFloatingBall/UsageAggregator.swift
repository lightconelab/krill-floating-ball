import Foundation

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
            let weeklyTotal = effectiveWeeklyLimit(item.quota)
            let weeklyUsed = decimal(item.quota?.usedUsd) + decimal(item.quota?.forwardedUsedUsd)
            let apiRemaining = decimal(item.quota?.remainingUsd) + decimal(item.quota?.forwardedRemainingUsd)
            let weeklyRemaining = apiRemaining > 0 ? apiRemaining : max(0, weeklyTotal - weeklyUsed)
            let isMonthly = isMonthlySubscription(item)
            let monthlyTotal = isMonthly ? monthlyLimit(item.quota) : nil
            let monthlyUsed = isMonthly ? decimal(item.totalUsedUsd) : nil
            let monthlyRemaining = isMonthly ? max(0, (monthlyTotal ?? 0) - (monthlyUsed ?? 0)) : nil

            return SubscriptionDisplayItem(
                name: item.plan?.name ?? "未命名套餐",
                start: start,
                expiry: expiry,
                endpoints: item.plan?.entryRouteKeys ?? [],
                weeklyRemaining: weeklyTotal > 0 ? weeklyRemaining : nil,
                weeklyUsed: weeklyTotal > 0 ? weeklyUsed : nil,
                weeklyTotal: weeklyTotal > 0 ? weeklyTotal : nil,
                weekStart: weekStart,
                weekEnd: weekEnd,
                monthlyRemaining: monthlyRemaining,
                monthlyTotal: monthlyTotal
            )
        }.sorted { left, right in
            (left.expiry ?? .distantPast) > (right.expiry ?? .distantPast)
        }

        let weeklyTotal = activeSubscriptions.reduce(0) { partial, item in
            partial + effectiveWeeklyLimit(item.quota)
        }
        let weeklyUsed = activeSubscriptions.reduce(0) { partial, item in
            partial + decimal(item.quota?.usedUsd) + decimal(item.quota?.forwardedUsedUsd)
        }
        let weeklyRemainingFromAPI = activeSubscriptions.reduce(0) { partial, item in
            partial + decimal(item.quota?.remainingUsd) + decimal(item.quota?.forwardedRemainingUsd)
        }
        let weeklyRemaining = weeklyRemainingFromAPI > 0
            ? weeklyRemainingFromAPI
            : max(0, weeklyTotal - weeklyUsed)

        let weekStarts = activeSubscriptions.compactMap { APIDateParser.parse($0.quota?.windowStartAt) }
        let weekEnds = activeSubscriptions.compactMap { APIDateParser.parse($0.quota?.windowResetAt) }

        let monthlySubscriptions = activeSubscriptions.filter(isMonthlySubscription)

        let monthlyTotal = monthlySubscriptions.reduce(0) { partial, item in
            partial + monthlyLimit(item.quota)
        }
        let monthlyUsed = monthlySubscriptions.reduce(0) { partial, item in
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

    private static func effectiveWeeklyLimit(_ quota: Quota?) -> Double {
        decimal(quota?.dailyLimitUsd) + decimal(quota?.forwardedLimitUsd)
    }

    private static func monthlyLimit(_ quota: Quota?) -> Double {
        decimal(quota?.dailyLimitUsd) * 4
    }

    private static func isMonthlySubscription(_ item: SubscriptionItem) -> Bool {
        let duration = item.plan?.durationDays ?? 0
        let billing = item.plan?.billingType?.lowercased() ?? ""
        return duration >= 30 || billing.contains("month")
    }

    static func decimal(_ value: String?) -> Double {
        guard let value else {
            return 0
        }

        return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}

enum APIDateParser {
    static func parse(_ value: String?) -> Date? {
        guard let value, value.isEmpty == false else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.calendar = Calendar(identifier: .gregorian)
        dateOnlyFormatter.timeZone = TimeZone.current
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        return dateOnlyFormatter.date(from: value)
    }
}
