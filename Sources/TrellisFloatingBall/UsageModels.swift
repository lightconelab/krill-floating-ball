import AppKit
import Foundation

struct CacheRate: Equatable {
    let name: String
    let percent: Double
}

struct BalanceThresholds: Equatable {
    private enum Defaults {
        static let ampleKey = "balanceThresholdAmpleUsd"
        static let normalKey = "balanceThresholdNormalUsd"
        static let lowKey = "balanceThresholdLowUsd"
        static let ample = 50.0
        static let normal = 35.0
        static let low = 10.0
    }

    let ample: Double
    let normal: Double
    let low: Double

    static let standard = BalanceThresholds(
        ample: Defaults.ample,
        normal: Defaults.normal,
        low: Defaults.low
    )

    var isValid: Bool {
        ample > normal && normal > low && low >= 0
    }

    static func load() -> BalanceThresholds {
        let defaults = UserDefaults.standard
        let hasSavedValue = defaults.object(forKey: Defaults.ampleKey) != nil
            || defaults.object(forKey: Defaults.normalKey) != nil
            || defaults.object(forKey: Defaults.lowKey) != nil
        guard hasSavedValue else {
            return .standard
        }

        let loaded = BalanceThresholds(
            ample: defaults.double(forKey: Defaults.ampleKey),
            normal: defaults.double(forKey: Defaults.normalKey),
            low: defaults.double(forKey: Defaults.lowKey)
        )
        return loaded.isValid ? loaded : .standard
    }

    static func save(_ thresholds: BalanceThresholds) {
        guard thresholds.isValid else {
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(thresholds.ample, forKey: Defaults.ampleKey)
        defaults.set(thresholds.normal, forKey: Defaults.normalKey)
        defaults.set(thresholds.low, forKey: Defaults.lowKey)
    }

    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Defaults.ampleKey)
        defaults.removeObject(forKey: Defaults.normalKey)
        defaults.removeObject(forKey: Defaults.lowKey)
    }

    func signalPercent(for balance: Double?) -> Double? {
        guard let balance, balance > 0 else {
            return nil
        }
        if balance >= ample {
            return 100
        }
        if balance >= normal {
            return 45
        }
        if balance >= low {
            return 20
        }
        return 0
    }
}

enum PrimaryDisplayMode: Equatable {
    case quotaPool
    case balance
    case empty
}

enum StatsRange: String, CaseIterable, Equatable {
    case quotaWeek
    case subscriptionPeriod
    case today
    case last7Days
    case last30Days

    var title: String {
        switch self {
        case .quotaWeek:
            return "额度周"
        case .subscriptionPeriod:
            return "套餐期"
        case .today:
            return "今日"
        case .last7Days:
            return "7日"
        case .last30Days:
            return "30日"
        }
    }
}

struct StatsRangeContext: Equatable {
    let requested: StatsRange
    let effective: StatsRange
    let start: Date
    let end: Date
    let availableRanges: [StatsRange]
}

struct UsageTrendPoint: Equatable {
    let cost: Double?
    let requestCount: Int?
    let tokens: Int?
}

struct SubscriptionDisplayItem: Equatable {
    let name: String
    let start: Date?
    let expiry: Date?
    let weeklyRemaining: Double?
    let weeklyUsed: Double?
    let weeklyTotal: Double?
    let weekStart: Date?
    let weekEnd: Date?
    let monthlyRemaining: Double?
    let monthlyTotal: Double?

    var weeklyPercent: Double? {
        guard let weeklyRemaining, let weeklyTotal, weeklyTotal > 0 else {
            return nil
        }
        return max(0, min(100, weeklyRemaining / weeklyTotal * 100))
    }
}

struct UsageSnapshot: Equatable {
    var primaryMode: PrimaryDisplayMode
    var primaryAmount: Double?
    var primaryTotal: Double?
    var primaryEnd: Date?

    var weeklyRemaining: Double?
    var weeklyUsed: Double?
    var weeklyTotal: Double?
    var weekStart: Date?
    var weekEnd: Date?

    var monthlyRemaining: Double?
    var monthlyUsed: Double?
    var monthlyTotal: Double?
    var monthlyPercent: Double?
    var expiry: Date?
    var remainingDays: Int?

    var todayCost: Double?
    var walletBalance: Double?
    var requestCount: Int?
    var totalTokens: Int?
    var trend: [UsageTrendPoint]
    var statsRange: StatsRange
    var availableStatsRanges: [StatsRange]
    var cacheRates: [CacheRate]
    var subscriptions: [SubscriptionDisplayItem]

    var lastRefresh: Date?
    var isLoading: Bool
    var isStale: Bool
    var needsToken: Bool
    var lastError: String?

    var weeklyPercent: Double? {
        guard let remaining = weeklyRemaining, let total = weeklyTotal, total > 0 else {
            return nil
        }
        return max(0, min(100, remaining / total * 100))
    }

    var primaryPercent: Double? {
        guard primaryMode == .quotaPool,
              let amount = primaryAmount,
              let total = primaryTotal,
              total > 0
        else {
            return nil
        }
        return max(0, min(100, amount / total * 100))
    }

    static let placeholder = UsageSnapshot(
        primaryMode: .empty,
        primaryAmount: nil,
        primaryTotal: nil,
        primaryEnd: nil,
        weeklyRemaining: nil,
        weeklyUsed: nil,
        weeklyTotal: nil,
        weekStart: nil,
        weekEnd: nil,
        monthlyRemaining: nil,
        monthlyUsed: nil,
        monthlyTotal: nil,
        monthlyPercent: nil,
        expiry: nil,
        remainingDays: nil,
        todayCost: nil,
        walletBalance: nil,
        requestCount: nil,
        totalTokens: nil,
        trend: [],
        statsRange: .today,
        availableStatsRanges: [.today, .last7Days, .last30Days],
        cacheRates: [],
        subscriptions: [],
        lastRefresh: nil,
        isLoading: false,
        isStale: false,
        needsToken: true,
        lastError: nil
    )

    static func missingCredentials(previous: UsageSnapshot) -> UsageSnapshot {
        var next = previous
        next.primaryMode = .empty
        next.primaryAmount = nil
        next.primaryTotal = nil
        next.primaryEnd = nil
        next.weeklyRemaining = nil
        next.weeklyUsed = nil
        next.weeklyTotal = nil
        next.weekStart = nil
        next.weekEnd = nil
        next.needsToken = true
        next.isLoading = false
        next.isStale = previous.lastRefresh != nil
        next.lastError = "请通过菜单栏设置 Krill 账号"
        return next
    }
}

enum QuotaState {
    case healthy
    case caution
    case warning
    case critical

    init(percent: Double?) {
        guard let percent else {
            self = .critical
            return
        }

        if percent > 60 {
            self = .healthy
        } else if percent > 30 {
            self = .caution
        } else if percent > 10 {
            self = .warning
        } else {
            self = .critical
        }
    }

    var color: NSColor {
        switch self {
        case .healthy:
            return NSColor(hex: 0x1A56DB)
        case .caution:
            return NSColor(hex: 0x00D4FF)
        case .warning:
            return NSColor(hex: 0xF59E0B)
        case .critical:
            return NSColor(hex: 0xE02D3C)
        }
    }

    var secondaryColor: NSColor {
        switch self {
        case .healthy:
            return NSColor(hex: 0x9EDFFF)
        case .caution:
            return NSColor(hex: 0x7CEEFF)
        case .warning:
            return NSColor(hex: 0xFBBF24)
        case .critical:
            return NSColor(hex: 0xFB7185)
        }
    }

    var pulseRate: CGFloat {
        switch self {
        case .healthy:
            return 1.0
        case .caution:
            return 1.6
        case .warning:
            return 2.4
        case .critical:
            return 3.8
        }
    }
}

@MainActor
enum Formatters {
    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd"
        return formatter
    }()

    static func usd(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return "--"
        }
        return String(format: "$%.2f", value)
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return "N/A"
        }
        return String(format: "%.2f%%", max(0, min(100, value)))
    }

    static func compactInteger(_ value: Int?) -> String {
        guard let value else {
            return "--"
        }

        let sign = value < 0 ? "-" : ""
        let absolute = Double(abs(value))
        let units: [(trigger: Double, divisor: Double, suffix: String)] = [
            (999_500_000_000, 1_000_000_000_000, "T"),
            (999_500_000, 1_000_000_000, "B"),
            (999_500, 1_000_000, "M"),
            (1_000, 1_000, "K")
        ]

        guard let unit = units.first(where: { absolute >= $0.trigger }) else {
            return "\(value)"
        }

        let scaled = absolute / unit.divisor
        let number: String
        if scaled >= 10 {
            number = String(format: "%.0f", scaled)
        } else {
            number = String(format: "%.1f", scaled).replacingOccurrences(of: ".0", with: "")
        }
        return "\(sign)\(number)\(unit.suffix)"
    }

    static func integer(_ value: Int?) -> String {
        guard let value else {
            return "--"
        }
        return "\(value)"
    }

    static func date(_ value: Date?) -> String {
        guard let value else {
            return "--"
        }
        return date.string(from: value)
    }

    static func dateTime(_ value: Date?) -> String {
        guard let value else {
            return "--"
        }
        return dateTime.string(from: value)
    }

    static func monthDay(_ value: Date?) -> String {
        guard let value else {
            return "--"
        }
        return monthDay.string(from: value)
    }

    static func time(_ value: Date?) -> String {
        guard let value else {
            return "--:--:--"
        }
        return timeOnly.string(from: value)
    }
}

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
