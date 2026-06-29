import Foundation

@MainActor
enum UsageAggregator {
    private struct QuotaAmounts {
        let remaining: Double
        let used: Double
        let total: Double
        let start: Date?
        let end: Date?
    }

    private struct SubscriptionQuotaSummary {
        let displayItem: SubscriptionDisplayItem
        let poolQuota: QuotaAmounts?
        let totalQuota: QuotaAmounts?
        let recurringWindowStart: Date?
        let recurringWindowEnd: Date?
    }

    static func makeSnapshot(bundle: APIBundle, now: Date = Date()) throws -> UsageSnapshot {
        try makeSnapshot(
            subscription: bundle.subscription,
            stats: bundle.stats,
            statsRangeContext: bundle.statsRangeContext,
            previous: nil,
            now: now,
            lastRefresh: now,
            isLoading: false,
            isStale: false,
            lastError: nil
        )
    }

    static func makeSubscriptionSnapshot(
        subscription: SubscriptionEnvelope,
        statsRangeContext: StatsRangeContext,
        previous: UsageSnapshot,
        now: Date = Date()
    ) throws -> UsageSnapshot {
        try makeSnapshot(
            subscription: subscription,
            stats: nil,
            statsRangeContext: statsRangeContext,
            previous: previous,
            now: now,
            lastRefresh: previous.lastRefresh,
            isLoading: true,
            isStale: previous.lastRefresh != nil,
            lastError: nil
        )
    }

    private static func makeSnapshot(
        subscription: SubscriptionEnvelope,
        stats: StatsEnvelope?,
        statsRangeContext: StatsRangeContext,
        previous: UsageSnapshot?,
        now: Date,
        lastRefresh: Date?,
        isLoading: Bool,
        isStale: Bool,
        lastError: String?
    ) throws -> UsageSnapshot {
        guard let subscriptionData = subscription.data else {
            throw KrillAPIError.missingData
        }

        let activeSubscriptions = activeSubscriptions(in: subscription, now: now)
        let quotaSummaries = activeSubscriptions.map { subscriptionQuotaSummary(for: $0) }
        let subscriptionDisplays = quotaSummaries.map(\.displayItem)
        let poolQuotas = quotaSummaries.compactMap(\.poolQuota)
        let recurringStarts = quotaSummaries.compactMap(\.recurringWindowStart)
        let recurringEnds = quotaSummaries.compactMap(\.recurringWindowEnd)
        let poolTotal = poolQuotas.reduce(0) { $0 + $1.total }
        let poolUsed = poolQuotas.reduce(0) { $0 + $1.used }
        let poolRemaining = poolQuotas.reduce(0) { $0 + $1.remaining }
        let poolEnd = recurringEnds.min() ?? poolQuotas.compactMap(\.end).min()

        let totalQuotas = quotaSummaries.compactMap(\.totalQuota)
        let monthlyTotal = totalQuotas.reduce(0) { $0 + $1.total }
        let monthlyUsed = totalQuotas.reduce(0) { $0 + $1.used }
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
        let walletBalance = decimal(subscriptionData.creditBalanceUsd) + decimal(subscriptionData.welfareBalanceUsd)
        let primaryMode: PrimaryDisplayMode
        let primaryAmount: Double?
        let primaryTotal: Double?
        let primaryEnd: Date?
        if poolTotal > 0 {
            if poolRemaining > 0 {
                primaryMode = .quotaPool
                primaryAmount = poolRemaining
                primaryTotal = poolTotal
                primaryEnd = poolEnd
            } else if walletBalance > 0 {
                primaryMode = .balance
                primaryAmount = walletBalance
                primaryTotal = nil
                primaryEnd = nil
            } else {
                primaryMode = .empty
                primaryAmount = nil
                primaryTotal = nil
                primaryEnd = nil
            }
        } else if walletBalance > 0 {
            primaryMode = .balance
            primaryAmount = walletBalance
            primaryTotal = nil
            primaryEnd = nil
        } else {
            primaryMode = .empty
            primaryAmount = nil
            primaryTotal = nil
            primaryEnd = nil
        }

        let statsPayload = stats?.data
        let shouldReusePreviousStats = statsPayload == nil && previous?.statsRange == statsRangeContext.effective
        let previousSnapshot = shouldReusePreviousStats ? previous : nil
        let cacheRates = statsPayload.map { payload in
            (payload.channelCacheRates ?? []).map { rate in
                CacheRate(
                    name: rate.channelName ?? "未知渠道",
                    percent: max(0, min(100, (rate.cacheRate ?? 0) * 100))
                )
            }
        } ?? previousSnapshot?.cacheRates ?? []

        let trend = statsPayload.map { payload in
            downsample(payload.trend ?? [], maxCount: 32).map { point in
                UsageTrendPoint(
                    cost: point.totalCostUsd.map(decimal),
                    requestCount: point.requestCount,
                    tokens: point.totalTokens
                )
            }
        } ?? previousSnapshot?.trend ?? []
        let cost = statsPayload.map { decimal($0.totalCostUsd) } ?? previousSnapshot?.todayCost
        let requests = statsPayload?.totalRequests ?? previousSnapshot?.requestCount
        let tokens = statsPayload?.totalTokens ?? previousSnapshot?.totalTokens

        return UsageSnapshot(
            primaryMode: primaryMode,
            primaryAmount: primaryAmount,
            primaryTotal: primaryTotal,
            primaryEnd: primaryEnd,
            weeklyRemaining: poolTotal > 0 ? poolRemaining : nil,
            weeklyUsed: poolTotal > 0 ? poolUsed : nil,
            weeklyTotal: poolTotal > 0 ? poolTotal : nil,
            weekStart: recurringStarts.min() ?? poolQuotas.compactMap(\.start).min(),
            weekEnd: poolEnd,
            monthlyRemaining: monthlyRemaining,
            monthlyUsed: monthlyTotal > 0 ? monthlyUsed : nil,
            monthlyTotal: monthlyTotal > 0 ? monthlyTotal : nil,
            monthlyPercent: monthlyPercent,
            expiry: maxEnd,
            remainingDays: remainingDays,
            todayCost: cost,
            walletBalance: walletBalance,
            requestCount: requests,
            totalTokens: tokens,
            trend: trend,
            statsRange: statsRangeContext.effective,
            availableStatsRanges: statsRangeContext.availableRanges,
            cacheRates: cacheRates,
            subscriptions: subscriptionDisplays,
            lastRefresh: lastRefresh,
            isLoading: isLoading,
            isStale: isStale,
            needsToken: false,
            lastError: lastError
        )
    }

    private static func downsample<T>(_ items: [T], maxCount: Int) -> [T] {
        guard items.count > maxCount, maxCount > 1 else {
            return items
        }

        let step = Double(items.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { index in
            let sourceIndex = min(items.count - 1, Int((Double(index) * step).rounded()))
            return items[sourceIndex]
        }
    }

    static func statsRangeContext(
        subscription: SubscriptionEnvelope,
        requested: StatsRange,
        now: Date
    ) throws -> StatsRangeContext {
        let activeSubscriptions = activeSubscriptions(in: subscription, now: now)
        let monthlySubscription = earliestStartedMonthlySubscription(in: activeSubscriptions)
        let monthWindowStart = monthlySubscription.flatMap { APIDateParser.parse($0.quota?.windowStartAt) }
        let monthWindowEnd = monthlySubscription.flatMap { APIDateParser.parse($0.quota?.windowResetAt) }
        let monthSubscriptionStart = monthlySubscription.flatMap { APIDateParser.parse($0.subscriptionStartAt) }
        let monthSubscriptionEnd = monthlySubscription.flatMap { APIDateParser.parse($0.subscriptionEndAt) }

        var available: [StatsRange] = [.today, .last7Days, .last30Days]
        if monthWindowStart != nil, monthWindowEnd != nil {
            available.insert(.quotaWeek, at: 0)
        }

        if monthSubscriptionStart != nil, monthSubscriptionEnd != nil {
            let insertionIndex = available.contains(.quotaWeek) ? 1 : 0
            available.insert(.subscriptionPeriod, at: insertionIndex)
        }

        let effective = available.contains(requested) ? requested : .today
        let calendar = Calendar.current
        let start: Date

        switch effective {
        case .quotaWeek:
            start = monthWindowStart ?? calendar.startOfDay(for: now)
        case .subscriptionPeriod:
            start = monthSubscriptionStart ?? calendar.startOfDay(for: now)
        case .today:
            start = calendar.startOfDay(for: now)
        case .last7Days:
            start = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 86_400)
        case .last30Days:
            start = calendar.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86_400)
        }

        return StatsRangeContext(
            requested: requested,
            effective: effective,
            start: min(start, now),
            end: now,
            availableRanges: available
        )
    }

    private static func earliestStartedMonthlySubscription(in items: [SubscriptionItem]) -> SubscriptionItem? {
        items
            .filter(isMonthlyWindowSubscription)
            .min { lhs, rhs in
                let lhsStart = APIDateParser.parse(lhs.subscriptionStartAt) ?? .distantFuture
                let rhsStart = APIDateParser.parse(rhs.subscriptionStartAt) ?? .distantFuture
                return lhsStart < rhsStart
            }
    }

    private static func isMonthlyWindowSubscription(_ item: SubscriptionItem) -> Bool {
        guard let durationDays = item.plan?.durationDays,
              durationDays >= 28,
              durationDays <= 31
        else {
            return false
        }
        return recurringWindowQuota(item) != nil
    }

    static func activeSubscriptions(in envelope: SubscriptionEnvelope, now: Date) -> [SubscriptionItem] {
        guard let subscriptionData = envelope.data else {
            return []
        }

        return subscriptionData.subscriptions.filter { item in
            guard item.plan?.active == true,
                  let start = APIDateParser.parse(item.subscriptionStartAt),
                  let end = APIDateParser.parse(item.subscriptionEndAt)
            else {
                return false
            }

            return start <= now && now < end
        }
    }

    static func weeklyLimit(_ item: SubscriptionItem) -> Double? {
        recurringWindowQuota(item)?.total
    }

    static func totalLimit(_ item: SubscriptionItem) -> Double? {
        totalQuota(item)?.total
    }

    private static func subscriptionQuotaSummary(for item: SubscriptionItem) -> SubscriptionQuotaSummary {
        let start = APIDateParser.parse(item.subscriptionStartAt)
        let expiry = APIDateParser.parse(item.subscriptionEndAt)
        let recurringQuota = recurringWindowQuota(item)
        let totalQuota = totalQuota(item)
        let weeklyQuota = recurringQuota
        let displayTotalQuota = totalQuota ?? recurringQuota

        let display = SubscriptionDisplayItem(
            name: item.plan?.name ?? "未命名套餐",
            start: start,
            expiry: expiry,
            weeklyRemaining: weeklyQuota?.remaining,
            weeklyUsed: weeklyQuota?.used,
            weeklyTotal: weeklyQuota?.total,
            weekStart: weeklyQuota?.start,
            weekEnd: weeklyQuota?.end,
            monthlyRemaining: displayTotalQuota?.remaining,
            monthlyTotal: displayTotalQuota?.total
        )

        return SubscriptionQuotaSummary(
            displayItem: display,
            poolQuota: recurringQuota ?? totalQuota,
            totalQuota: displayTotalQuota,
            recurringWindowStart: recurringQuota?.start,
            recurringWindowEnd: recurringQuota?.end
        )
    }

    private static func recurringWindowQuota(_ item: SubscriptionItem) -> QuotaAmounts? {
        guard let start = APIDateParser.parse(item.quota?.windowStartAt),
              let end = APIDateParser.parse(item.quota?.windowResetAt),
              end > start,
              (item.plan?.durationDays ?? 0) > 7
        else {
            return nil
        }

        let total = decimal(item.quota?.dailyLimitUsd)
        guard total > 0 else {
            return nil
        }

        let used = decimal(item.quota?.usedUsd)
        let remaining = hasDecimalValue(item.quota?.remainingUsd)
            ? decimal(item.quota?.remainingUsd)
            : max(0, total - used)
        return QuotaAmounts(
            remaining: max(0, remaining),
            used: max(0, used),
            total: total,
            start: start,
            end: end
        )
    }

    private static func totalQuota(_ item: SubscriptionItem) -> QuotaAmounts? {
        if let recurring = recurringWindowQuota(item) {
            let total = recurring.total * recurringWindowCount(item)
            let used = decimal(item.totalUsedUsd)
            return QuotaAmounts(
                remaining: max(0, total - used),
                used: max(0, used),
                total: total,
                start: APIDateParser.parse(item.subscriptionStartAt),
                end: APIDateParser.parse(item.subscriptionEndAt)
            )
        }

        let forwardedTotal = decimal(item.quota?.forwardedLimitUsd)
        if forwardedTotal > 0 {
            let used = decimal(item.quota?.forwardedUsedUsd)
            let remaining = hasDecimalValue(item.quota?.forwardedRemainingUsd)
                ? decimal(item.quota?.forwardedRemainingUsd)
                : max(0, forwardedTotal - used)
            return QuotaAmounts(
                remaining: max(0, remaining),
                used: max(0, used),
                total: forwardedTotal,
                start: APIDateParser.parse(item.subscriptionStartAt),
                end: APIDateParser.parse(item.subscriptionEndAt)
            )
        }

        let total = decimal(item.quota?.dailyLimitUsd)
        guard total > 0 else {
            return nil
        }

        let usedFromQuota = decimal(item.quota?.usedUsd)
        let used = usedFromQuota > 0 ? usedFromQuota : decimal(item.totalUsedUsd)
        let remaining = hasDecimalValue(item.quota?.remainingUsd)
            ? decimal(item.quota?.remainingUsd)
            : max(0, total - used)
        return QuotaAmounts(
            remaining: max(0, remaining),
            used: max(0, used),
            total: total,
            start: APIDateParser.parse(item.subscriptionStartAt),
            end: APIDateParser.parse(item.subscriptionEndAt)
        )
    }

    private static func recurringWindowCount(_ item: SubscriptionItem) -> Double {
        let durationDays = item.plan?.durationDays ?? 0
        if durationDays >= 28, durationDays <= 31 {
            return 4
        }
        return max(1, floor(Double(durationDays) / 7))
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
