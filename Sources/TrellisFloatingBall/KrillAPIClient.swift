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
    let statsRangeContext: StatsRangeContext
}

@MainActor
struct KrillAPIClient {
    fileprivate enum Network {
        static let requestTimeout: TimeInterval = 12
        static let resourceTimeout: TimeInterval = 20
        static let sampledTrendLimit = 64
    }

    private let subscriptionURL = URL(string: "https://www.krill-ai.com/api/subscription")!
    private let statsURL = URL(string: "https://www.krill-ai.com/api/request-logs/stats")!
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = Network.requestTimeout
        configuration.timeoutIntervalForResource = Network.resourceTimeout
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()

    func fetchAll(token: String, requestedStatsRange: StatsRange, now: Date = Date()) async throws -> APIBundle {
        let subscription = try await fetchSubscription(token: token)
        let rangeContext = try UsageAggregator.statsRangeContext(
            subscription: subscription,
            requested: requestedStatsRange,
            now: now
        )
        let stats = try await fetchStats(token: token, range: rangeContext)
        return APIBundle(subscription: subscription, stats: stats, statsRangeContext: rangeContext)
    }

    private func fetchSubscription(token: String) async throws -> SubscriptionEnvelope {
        var request = URLRequest(url: subscriptionURL)
        request.httpMethod = "GET"
        request.timeoutInterval = Network.requestTimeout
        applyCommonHeaders(to: &request, token: token)

        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decode(SubscriptionEnvelope.self, from: data)
    }

    private func fetchStats(token: String, range: StatsRangeContext) async throws -> StatsEnvelope {
        var request = URLRequest(url: statsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = Network.resourceTimeout
        applyCommonHeaders(to: &request, token: token)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("https://www.krill-ai.com", forHTTPHeaderField: "origin")

        let payload = StatsRequestPayload(
            startTime: LocalProtocolDateFormatter.string(from: range.start),
            endTime: LocalProtocolDateFormatter.string(from: range.end)
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decode(StatsEnvelope.self, from: data)
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

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try autoreleasepool {
            try JSONDecoder().decode(type, from: data)
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

@MainActor
enum LocalProtocolDateFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()

    static func string(from date: Date) -> String {
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
    let name: String?

    enum CodingKeys: String, CodingKey {
        case active
        case billingType = "billing_type"
        case dailyQuotaUsd = "daily_quota_usd"
        case durationDays = "duration_days"
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
    let totalTokens: Int?
    let trend: [StatsTrendPoint]?

    enum CodingKeys: String, CodingKey {
        case channelCacheRates = "channel_cache_rates"
        case totalCostUsd = "total_cost_usd"
        case totalRequests = "total_requests"
        case totalTokens = "total_tokens"
        case trend
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.channelCacheRates = (try? container.decodeIfPresent([ChannelCacheRate].self, forKey: .channelCacheRates)) ?? nil
        self.totalCostUsd = container.decodeFlexibleString(forKey: .totalCostUsd)
        self.totalRequests = container.decodeFlexibleInt(forKey: .totalRequests)
        self.totalTokens = container.decodeFlexibleInt(forKey: .totalTokens)
        self.trend = try? container.decodeSampledArray(
            StatsTrendPoint.self,
            forKey: .trend,
            maxCount: KrillAPIClient.Network.sampledTrendLimit
        )
    }
}

struct StatsTrendPoint: Decodable {
    let requestCount: Int?
    let totalCostUsd: String?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case requestCount = "request_count"
        case totalCostUsd = "total_cost_usd"
        case totalTokens = "total_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.requestCount = container.decodeFlexibleInt(forKey: .requestCount)
        self.totalCostUsd = container.decodeFlexibleString(forKey: .totalCostUsd)
        self.totalTokens = container.decodeFlexibleInt(forKey: .totalTokens)
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

private extension KeyedDecodingContainer {
    func decodeSampledArray<T: Decodable>(
        _ type: T.Type,
        forKey key: Key,
        maxCount: Int
    ) throws -> [T]? {
        guard contains(key) else {
            return nil
        }

        var container = try nestedUnkeyedContainer(forKey: key)
        guard maxCount > 0 else {
            return []
        }

        guard let count = container.count else {
            var values: [T] = []
            values.reserveCapacity(maxCount)
            while container.isAtEnd == false, values.count < maxCount {
                values.append(try container.decode(T.self))
            }
            return values
        }

        guard count > maxCount, maxCount > 1 else {
            var values: [T] = []
            values.reserveCapacity(min(count, maxCount))
            while container.isAtEnd == false {
                values.append(try container.decode(T.self))
            }
            return values
        }

        let step = Double(count - 1) / Double(maxCount - 1)
        let targetIndices = (0..<maxCount).map { index in
            min(count - 1, Int((Double(index) * step).rounded()))
        }
        var nextTargetOffset = 0
        var values: [T] = []
        values.reserveCapacity(maxCount)

        while container.isAtEnd == false {
            let currentIndex = container.currentIndex
            if nextTargetOffset < targetIndices.count, currentIndex == targetIndices[nextTargetOffset] {
                values.append(try container.decode(T.self))
                repeat {
                    nextTargetOffset += 1
                } while nextTargetOffset < targetIndices.count && targetIndices[nextTargetOffset] <= currentIndex
            } else {
                _ = try container.decode(DiscardedJSONValue.self)
            }
        }

        return values
    }

    func decodeFlexibleString(forKey key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(Double.self, forKey: key), value.isFinite {
            return Int(value.rounded())
        }
        if let value = try? decode(String.self, forKey: key),
           let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
           number.isFinite {
            return Int(number.rounded())
        }
        return nil
    }
}

private struct DiscardedJSONValue: Decodable {
    init(from decoder: Decoder) throws {
        if var container = try? decoder.unkeyedContainer() {
            while container.isAtEnd == false {
                _ = try container.decode(DiscardedJSONValue.self)
            }
            return
        }

        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            for key in container.allKeys {
                _ = try container.decode(DiscardedJSONValue.self, forKey: key)
            }
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            return
        }
        if (try? container.decode(Bool.self)) != nil {
            return
        }
        if (try? container.decode(Double.self)) != nil {
            return
        }
        _ = try container.decode(String.self)
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
