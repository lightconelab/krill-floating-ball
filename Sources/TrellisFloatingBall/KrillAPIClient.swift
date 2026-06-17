import Foundation

enum KrillAPIError: LocalizedError {
    case invalidResponse
    case badStatus(Int)
    case missingData

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "接口响应无效"
        case .badStatus(let status):
            return "接口返回 HTTP \(status)"
        case .missingData:
            return "接口响应缺少 data 字段"
        }
    }
}

struct APIBundle {
    let subscription: SubscriptionEnvelope
    let stats: StatsEnvelope
}

struct KrillAPIClient {
    private let subscriptionURL = URL(string: "https://www.krill-ai.com/api/subscription")!
    private let statsURL = URL(string: "https://www.krill-ai.com/api/request-logs/stats")!

    func fetchAll(token: String, now: Date = Date()) async throws -> APIBundle {
        async let subscription = fetchSubscription(token: token)
        async let stats = fetchTodayStats(token: token, now: now)
        return try await APIBundle(subscription: subscription, stats: stats)
    }

    private func fetchSubscription(token: String) async throws -> SubscriptionEnvelope {
        var request = URLRequest(url: subscriptionURL)
        request.httpMethod = "GET"
        applyCommonHeaders(to: &request, token: token)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder().decode(SubscriptionEnvelope.self, from: data)
    }

    private func fetchTodayStats(token: String, now: Date) async throws -> StatsEnvelope {
        var request = URLRequest(url: statsURL)
        request.httpMethod = "POST"
        applyCommonHeaders(to: &request, token: token)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("https://www.krill-ai.com", forHTTPHeaderField: "origin")

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let payload = StatsRequestPayload(
            startTime: LocalProtocolDateFormatter.string(from: start),
            endTime: LocalProtocolDateFormatter.string(from: now)
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder().decode(StatsEnvelope.self, from: data)
    }

    private func applyCommonHeaders(to request: inout URLRequest, token: String) {
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "accept")
        request.setValue("zh", forHTTPHeaderField: "accept-language")
        request.setValue("zh", forHTTPHeaderField: "x-language")
        request.setValue("https://www.krill-ai.com/app", forHTTPHeaderField: "referer")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TrellisFloatingBall/1.0",
            forHTTPHeaderField: "user-agent"
        )
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw KrillAPIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw KrillAPIError.badStatus(http.statusCode)
        }
    }
}

private struct StatsRequestPayload: Encodable {
    let startTime: String
    let endTime: String

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

enum LocalProtocolDateFormatter {
    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct SubscriptionEnvelope: Decodable {
    let code: Int?
    let data: SubscriptionPayload?
    let success: Bool?
}

struct SubscriptionPayload: Decodable {
    let creditBalanceUsd: String?
    let subscriptions: [SubscriptionItem]
    let welfareBalanceUsd: String?

    enum CodingKeys: String, CodingKey {
        case creditBalanceUsd = "credit_balance_usd"
        case subscriptions
        case welfareBalanceUsd = "welfare_balance_usd"
    }
}

struct SubscriptionItem: Decodable {
    let plan: Plan?
    let quota: Quota?
    let subscriptionEndAt: String?
    let subscriptionStartAt: String?
    let totalUsedUsd: String?

    enum CodingKeys: String, CodingKey {
        case plan
        case quota
        case subscriptionEndAt = "subscription_end_at"
        case subscriptionStartAt = "subscription_start_at"
        case totalUsedUsd = "total_used_usd"
    }
}

struct Plan: Decodable {
    let active: Bool?
    let billingType: String?
    let dailyQuotaUsd: String?
    let durationDays: Int?
    let entryRouteKeys: [String]?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case active
        case billingType = "billing_type"
        case dailyQuotaUsd = "daily_quota_usd"
        case durationDays = "duration_days"
        case entryRouteKeys = "entry_route_keys"
        case name
    }
}

struct Quota: Decodable {
    let dailyLimitUsd: String?
    let forwardedLimitUsd: String?
    let forwardedRemainingUsd: String?
    let forwardedUsedUsd: String?
    let remainingUsd: String?
    let usedUsd: String?
    let windowResetAt: String?
    let windowStartAt: String?

    enum CodingKeys: String, CodingKey {
        case dailyLimitUsd = "daily_limit_usd"
        case forwardedLimitUsd = "forwarded_limit_usd"
        case forwardedRemainingUsd = "forwarded_remaining_usd"
        case forwardedUsedUsd = "forwarded_used_usd"
        case remainingUsd = "remaining_usd"
        case usedUsd = "used_usd"
        case windowResetAt = "window_reset_at"
        case windowStartAt = "window_start_at"
    }
}

struct StatsEnvelope: Decodable {
    let code: Int?
    let data: StatsPayload?
    let success: Bool?
}

struct StatsPayload: Decodable {
    let channelCacheRates: [ChannelCacheRate]?
    let totalCostUsd: String?
    let totalRequests: Int?

    enum CodingKeys: String, CodingKey {
        case channelCacheRates = "channel_cache_rates"
        case totalCostUsd = "total_cost_usd"
        case totalRequests = "total_requests"
    }
}

struct ChannelCacheRate: Decodable {
    let cacheRate: Double?
    let channelName: String?

    enum CodingKeys: String, CodingKey {
        case cacheRate = "cache_rate"
        case channelName = "channel_name"
    }
}
