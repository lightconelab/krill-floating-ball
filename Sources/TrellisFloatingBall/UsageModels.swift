import AppKit
import Foundation

struct CacheRate: Equatable {
    let name: String
    let percent: Double
}

struct SubscriptionDisplayItem: Equatable {
    let name: String
    let start: Date?
    let expiry: Date?
    let endpoints: [String]
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

    static let placeholder = UsageSnapshot(
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
        cacheRates: [],
        subscriptions: [],
        lastRefresh: nil,
        isLoading: false,
        isStale: false,
        needsToken: true,
        lastError: nil
    )

    static func missingToken(previous: UsageSnapshot) -> UsageSnapshot {
        var next = previous
        next.needsToken = true
        next.isLoading = false
        next.isStale = previous.lastRefresh != nil
        next.lastError = "请通过菜单栏设置 Krill Token"
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
            return NSColor(hex: 0x00FF88)
        case .caution:
            return NSColor(hex: 0xFFAA00)
        case .warning:
            return NSColor(hex: 0xFF5533)
        case .critical:
            return NSColor(hex: 0xFF0044)
        }
    }

    var secondaryColor: NSColor {
        switch self {
        case .healthy:
            return NSColor(hex: 0x00D4FF)
        case .caution:
            return NSColor(hex: 0xFFE16A)
        case .warning:
            return NSColor(hex: 0xFF8A45)
        case .critical:
            return NSColor(hex: 0xFF3F7E)
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
