import Darwin
import Foundation
import Security

enum KrillAPIError: LocalizedError {
    case invalidResponse
    case badStatus(Int)
    case missingData
    case unauthorized
    case edgeRejected(Int)
    case apiError(Int?, String?)
    case loginFailed(String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "接口响应无效"
        case .badStatus(let status):
            return "接口返回 HTTP \(status)"
        case .missingData:
            return "接口响应缺少 data 字段"
        case .unauthorized:
            return "登录已失效，正在尝试重新登录"
        case .edgeRejected(let status):
            return "接口请求被边缘层拒绝（HTTP \(status)）"
        case .apiError(let code, let message):
            if let message, message.isEmpty == false {
                return message
            }
            if let code {
                return "接口返回错误码 \(code)"
            }
            return "接口返回错误"
        case .loginFailed(let message):
            if let message, message.isEmpty == false {
                return message
            }
            return "登录失败，请重新设置 Krill 账号"
        }
    }
}

struct APIBundle {
    let subscription: SubscriptionEnvelope
    let stats: StatsEnvelope
    let statsRangeContext: StatsRangeContext
}

final class KrillAPIClient: @unchecked Sendable {
    fileprivate enum Network {
        static let requestTimeout: TimeInterval = 12
        static let resourceTimeout: TimeInterval = 20
        static let retryDelayNanoseconds: UInt64 = 350_000_000
        static let sampledTrendLimit = 32
        static let chunkedStatsThreshold: TimeInterval = 7 * 86_400
        static let statsChunkLength: TimeInterval = 7 * 86_400
    }

    private let loginURL = URL(string: "https://www.krill-ai.com/api/auth/login")!
    private let subscriptionURL = URL(string: "https://www.krill-ai.com/api/subscription")!
    private let statsURL = URL(string: "https://www.krill-ai.com/api/request-logs/stats")!
    private let session: URLSession
    private let fingerprintStore: KrillFingerprintStore
    private let codingLock = NSLock()
    private let requestEncoder = JSONEncoder()
    private let responseDecoder = JSONDecoder()

    init(session: URLSession? = nil, fingerprintStore: KrillFingerprintStore = .shared) {
        self.session = session ?? URLSession(configuration: Self.makeSessionConfiguration())
        self.fingerprintStore = fingerprintStore
    }

    deinit {
        session.invalidateAndCancel()
    }

    private static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = Network.requestTimeout
        configuration.timeoutIntervalForResource = Network.resourceTimeout
        configuration.httpMaximumConnectionsPerHost = 2
        return configuration
    }

    func login(credentials: KrillCredentials) async throws -> String {
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.timeoutInterval = Network.requestTimeout
        applyLoginHeaders(to: &request)
        applyBrowserFetchHeaders(to: &request, referer: "https://www.krill-ai.com/login")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("https://www.krill-ai.com", forHTTPHeaderField: "origin")
        request.httpBody = try encode(LoginRequestPayload(
            email: credentials.email,
            password: credentials.password
        ))

        let (data, response) = try await loadData(for: request)
        try validateLoginResponse(response, data: data)
        return try extractLoginToken(from: data)
    }

    func fetchSubscription(token: String) async throws -> SubscriptionEnvelope {
        var request = URLRequest(url: subscriptionURL)
        request.httpMethod = "GET"
        request.timeoutInterval = Network.requestTimeout
        applyCommonHeaders(to: &request, token: token)
        request.setValue("https://www.krill-ai.com/app/profile", forHTTPHeaderField: "referer")

        let (data, response) = try await loadData(for: request)
        try validate(response, data: data, allowUnauthorized: true)
        let envelope = try decode(SubscriptionEnvelope.self, from: data)
        try validateAPIStatus(success: envelope.success, code: envelope.code, message: envelope.message)
        return envelope
    }

    func fetchStats(token: String, range: StatsRangeContext) async throws -> StatsEnvelope {
        guard shouldChunkStats(range) == false else {
            let envelope = try await fetchChunkedStats(token: token, range: range)
            releaseUnusedHeapMemory()
            return envelope
        }

        let envelope = try await fetchStatsChunk(token: token, range: range)
        releaseUnusedHeapMemory()
        return envelope
    }

    private func fetchStatsChunk(token: String, range: StatsRangeContext) async throws -> StatsEnvelope {
        var request = URLRequest(url: statsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = Network.resourceTimeout
        applyCommonHeaders(to: &request, token: token)
        request.setValue("https://www.krill-ai.com/app/activity", forHTTPHeaderField: "referer")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("https://www.krill-ai.com", forHTTPHeaderField: "origin")

        let payload = StatsRequestPayload(
            startTime: LocalProtocolDateFormatter.string(from: range.start),
            endTime: LocalProtocolDateFormatter.string(from: range.end)
        )
        request.httpBody = try encode(payload)

        let (fileURL, response) = try await downloadFile(for: request)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        try validate(response, dataURL: fileURL, allowUnauthorized: true)
        let envelope = try StatsJSONParser.decodeEnvelope(from: fileURL, trendLimit: Network.sampledTrendLimit)
        try validateAPIStatus(success: envelope.success, code: envelope.code, message: envelope.message)
        return envelope
    }

    private func fetchChunkedStats(token: String, range: StatsRangeContext) async throws -> StatsEnvelope {
        var accumulator = StatsAccumulator()
        var chunkStart = range.start
        var chunkCount = 0

        while chunkStart < range.end {
            try Task.checkCancellation()
            let chunkEnd = min(chunkStart.addingTimeInterval(Network.statsChunkLength), range.end)
            let chunkRange = StatsRangeContext(
                requested: range.requested,
                effective: range.effective,
                start: chunkStart,
                end: chunkEnd,
                availableRanges: range.availableRanges
            )
            let envelope = try await fetchStatsChunk(token: token, range: chunkRange)
            accumulator.append(envelope.data)
            chunkStart = chunkEnd
            chunkCount += 1
            if chunkCount.isMultiple(of: 3) {
                releaseUnusedHeapMemory()
            }
            await Task.yield()
        }

        return StatsEnvelope(code: nil, data: accumulator.payload(), success: true, message: nil)
    }

    private func shouldChunkStats(_ range: StatsRangeContext) -> Bool {
        range.end.timeIntervalSince(range.start) > Network.chunkedStatsThreshold
    }

    private func loadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withTransientNetworkRetry {
            try await self.session.data(for: request)
        }
    }

    private func downloadFile(for request: URLRequest) async throws -> (URL, URLResponse) {
        try await withTransientNetworkRetry {
            let (temporaryURL, response) = try await self.session.download(for: request)
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("krill-stats-\(UUID().uuidString).json")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            return (destination, response)
        }
    }

    private func applyCommonHeaders(to request: inout URLRequest, token: String) {
        applyLoginHeaders(to: &request)
        applyBrowserFetchHeaders(to: &request, referer: "https://www.krill-ai.com/app")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
    }

    private func applyLoginHeaders(to request: inout URLRequest) {
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "accept")
        request.setValue("zh", forHTTPHeaderField: "accept-language")
        request.setValue("zh", forHTTPHeaderField: "X-Language")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36", forHTTPHeaderField: "user-agent")
        request.setValue("_kfp=\(fingerprintStore.value())", forHTTPHeaderField: "cookie")
    }

    private func applyBrowserFetchHeaders(to request: inout URLRequest, referer: String) {
        request.setValue(referer, forHTTPHeaderField: "referer")
        request.setValue("no-cache", forHTTPHeaderField: "cache-control")
        request.setValue("1", forHTTPHeaderField: "dnt")
        request.setValue("1", forHTTPHeaderField: "sec-gpc")
        request.setValue("\"Google Chrome\";v=\"149\", \"Chromium\";v=\"149\", \"Not)A;Brand\";v=\"24\"", forHTTPHeaderField: "sec-ch-ua")
        request.setValue("?0", forHTTPHeaderField: "sec-ch-ua-mobile")
        request.setValue("\"macOS\"", forHTTPHeaderField: "sec-ch-ua-platform")
        request.setValue("empty", forHTTPHeaderField: "sec-fetch-dest")
        request.setValue("cors", forHTTPHeaderField: "sec-fetch-mode")
        request.setValue("same-origin", forHTTPHeaderField: "sec-fetch-site")
        request.setValue("u=1, i", forHTTPHeaderField: "priority")
    }

    private func validateLoginResponse(_ response: URLResponse, data: Data) throws {
        try validateHTTPStatus(
            response,
            jsonUnauthorized: responseLooksLikeJSON(response, data: data),
            onJSONUnauthorized: .allowLoginParsing
        )
    }

    private func validate(_ response: URLResponse, data: Data, allowUnauthorized: Bool) throws {
        try validateHTTPStatus(
            response,
            jsonUnauthorized: allowUnauthorized && responseLooksLikeJSON(response, data: data),
            onJSONUnauthorized: .throwUnauthorized
        )
    }

    private func validate(_ response: URLResponse, dataURL: URL, allowUnauthorized: Bool) throws {
        try validateHTTPStatus(
            response,
            jsonUnauthorized: allowUnauthorized && responseLooksLikeJSON(response, dataURL: dataURL),
            onJSONUnauthorized: .throwUnauthorized
        )
    }

    private enum JSONUnauthorizedHandling {
        case allowLoginParsing
        case throwUnauthorized
    }

    private func validateHTTPStatus(
        _ response: URLResponse,
        jsonUnauthorized: @autoclosure () -> Bool,
        onJSONUnauthorized handling: JSONUnauthorizedHandling
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw KrillAPIError.invalidResponse
        }

        if http.statusCode == 401 {
            switch handling {
            case .allowLoginParsing where jsonUnauthorized():
                return
            case .throwUnauthorized where jsonUnauthorized():
                throw KrillAPIError.unauthorized
            default:
                throw KrillAPIError.edgeRejected(http.statusCode)
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            throw KrillAPIError.badStatus(http.statusCode)
        }
    }

    private func responseLooksLikeJSON(_ response: URLResponse, data: Data) -> Bool {
        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "content-type")
        return responseLooksLikeJSON(contentType: contentType, data: data)
    }

    private func responseLooksLikeJSON(_ response: URLResponse, dataURL: URL) -> Bool {
        if (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "content-type")?
            .localizedCaseInsensitiveContains("json") == true {
            return true
        }

        guard let handle = try? FileHandle(forReadingFrom: dataURL) else {
            return false
        }
        defer {
            try? handle.close()
        }

        let data = handle.readData(ofLength: 512)
        return responseLooksLikeJSON(contentType: nil, data: data)
    }

    private func responseLooksLikeJSON(contentType: String?, data: Data) -> Bool {
        if contentType?.localizedCaseInsensitiveContains("json") == true {
            return true
        }
        return data.first { byte in
            byte != 9 && byte != 10 && byte != 13 && byte != 32
        } == UInt8(ascii: "{")
    }

    private func validateAPIStatus(success: Bool?, code: Int?, message: String?) throws {
        let normalizedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if code == 401 || normalizedMessage?.contains("invalid token") == true {
            throw KrillAPIError.unauthorized
        }
        if success == false {
            throw KrillAPIError.apiError(code, message)
        }
    }

    private func extractLoginToken(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        if let envelope = object as? [String: Any] {
            let success = envelope["success"] as? Bool
            let code = flexibleInt(envelope["code"])
            let message = envelope["message"] as? String
            if code == 401 || success == false {
                throw KrillAPIError.loginFailed(message)
            }
        }

        guard let token = findToken(in: object) else {
            throw KrillAPIError.missingData
        }

        let normalized = normalizedToken(token)
        guard normalized.isEmpty == false else {
            throw KrillAPIError.missingData
        }
        return normalized
    }

    private func findToken(in value: Any) -> String? {
        let tokenKeys: Set<String> = [
            "token",
            "access_token",
            "accessToken",
            "auth_token",
            "authToken",
            "jwt",
            "id_token",
            "idToken",
            "authorization"
        ]

        if let dictionary = value as? [String: Any] {
            for key in tokenKeys {
                if let token = dictionary[key] as? String, token.isEmpty == false {
                    return token
                }
            }
            if let token = dictionary["data"] as? String, looksLikeToken(token) {
                return token
            }
            for nested in dictionary.values {
                if let token = findToken(in: nested) {
                    return token
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let token = findToken(in: nested) {
                    return token
                }
            }
        }

        return nil
    }

    private func looksLikeToken(_ value: String) -> Bool {
        let normalized = normalizedToken(value)
        return normalized.hasPrefix("eyJ") && normalized.split(separator: ".").count >= 3
    }

    private func normalizedToken(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("bearer ") {
            return String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func flexibleInt(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let double = value as? Double, double.isFinite {
            return Int(double.rounded())
        }
        if let string = value as? String {
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func withTransientNetworkRetry<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            guard isTransientNetworkError(error) else {
                throw error
            }
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: Network.retryDelayNanoseconds)
            return try await operation()
        }
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }

        switch urlError.code {
        case .timedOut,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try autoreleasepool {
            codingLock.lock()
            defer {
                codingLock.unlock()
            }
            return try responseDecoder.decode(type, from: data)
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try autoreleasepool {
            codingLock.lock()
            defer {
                codingLock.unlock()
            }
            return try requestEncoder.encode(value)
        }
    }

    @discardableResult
    private func releaseUnusedHeapMemory() -> Int {
        malloc_zone_pressure_relief(nil, 0)
    }
}

final class KrillFingerprintStore: @unchecked Sendable {
    static let shared = KrillFingerprintStore()

    private enum Defaults {
        static let key = "krillFingerprintCookie"
        static let byteCount = 16
    }

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func value() -> String {
        lock.lock()
        defer { lock.unlock() }

        if let saved = defaults.string(forKey: Defaults.key),
           Self.isValid(saved) {
            return saved
        }

        let generated = Self.generate()
        defaults.set(generated, forKey: Defaults.key)
        return generated
    }

    private static func isValid(_ value: String) -> Bool {
        value.count == Defaults.byteCount * 2
            && value.allSatisfy { character in
                character.isHexDigit
            }
    }

    private static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: Defaults.byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

private struct LoginRequestPayload: Encodable {
    let email: String
    let password: String
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
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()

    static func string(from date: Date) -> String {
        lock.lock()
        defer {
            lock.unlock()
        }
        return formatter.string(from: date)
    }
}

struct SubscriptionEnvelope: Decodable {
    let code: Int?
    let data: SubscriptionPayload?
    let message: String?
    let success: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.code = container.decodeFlexibleInt(forKey: .code)
        self.data = (try? container.decodeIfPresent(SubscriptionPayload.self, forKey: .data)) ?? nil
        self.message = container.decodeFlexibleString(forKey: .message)
        self.success = try container.decodeIfPresent(Bool.self, forKey: .success)
    }

    enum CodingKeys: String, CodingKey {
        case code
        case data
        case message
        case success
    }
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
    let message: String?

    init(code: Int?, data: StatsPayload?, success: Bool?, message: String?) {
        self.code = code
        self.data = data
        self.success = success
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.code = container.decodeFlexibleInt(forKey: .code)
        self.data = (try? container.decodeIfPresent(StatsPayload.self, forKey: .data)) ?? nil
        self.success = try container.decodeIfPresent(Bool.self, forKey: .success)
        self.message = container.decodeFlexibleString(forKey: .message)
    }

    enum CodingKeys: String, CodingKey {
        case code
        case data
        case message
        case success
    }
}

struct StatsPayload: Decodable {
    let channelCacheRates: [ChannelCacheRate]?
    let totalCostUsd: String?
    let totalRequests: Int?
    let totalTokens: Int?
    let trend: [StatsTrendPoint]?

    init(
        channelCacheRates: [ChannelCacheRate]?,
        totalCostUsd: String?,
        totalRequests: Int?,
        totalTokens: Int?,
        trend: [StatsTrendPoint]?
    ) {
        self.channelCacheRates = channelCacheRates
        self.totalCostUsd = totalCostUsd
        self.totalRequests = totalRequests
        self.totalTokens = totalTokens
        self.trend = trend
    }

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

    init(requestCount: Int?, totalCostUsd: String?, totalTokens: Int?) {
        self.requestCount = requestCount
        self.totalCostUsd = totalCostUsd
        self.totalTokens = totalTokens
    }

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

    init(cacheRate: Double?, channelName: String?) {
        self.cacheRate = cacheRate
        self.channelName = channelName
    }

    enum CodingKeys: String, CodingKey {
        case cacheRate = "cache_rate"
        case channelName = "channel_name"
    }
}

private struct StatsAccumulator {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    private var totalCost = 0.0
    private var hasTotalCost = false
    private var totalRequests = 0
    private var hasTotalRequests = false
    private var totalTokens = 0
    private var hasTotalTokens = false
    private var trend: [StatsTrendPoint] = []
    private var cacheRates: [String: CacheRateAccumulator] = [:]

    mutating func append(_ payload: StatsPayload?) {
        guard let payload else {
            return
        }

        if let costText = payload.totalCostUsd,
           let cost = Double(costText.trimmingCharacters(in: .whitespacesAndNewlines)),
           cost.isFinite {
            totalCost += cost
            hasTotalCost = true
        }
        if let requests = payload.totalRequests {
            totalRequests += requests
            hasTotalRequests = true
        }
        if let tokens = payload.totalTokens {
            totalTokens += tokens
            hasTotalTokens = true
        }

        if let points = payload.trend, points.isEmpty == false {
            trend.append(contentsOf: points)
            if trend.count > KrillAPIClient.Network.sampledTrendLimit * 4 {
                trend = downsample(trend, maxCount: KrillAPIClient.Network.sampledTrendLimit * 2)
            }
        }

        let cacheWeight = max(1, payload.totalRequests ?? 0)
        for rate in payload.channelCacheRates ?? [] {
            let name = rate.channelName ?? "未知渠道"
            guard let percent = rate.cacheRate, percent.isFinite else {
                continue
            }
            cacheRates[name, default: CacheRateAccumulator()].append(rate: percent, weight: cacheWeight)
        }
    }

    func payload() -> StatsPayload {
        let channels = cacheRates
            .map { name, accumulator in
                ChannelCacheRate(cacheRate: accumulator.rate, channelName: name)
            }
            .sorted { ($0.channelName ?? "") < ($1.channelName ?? "") }

        return StatsPayload(
            channelCacheRates: channels.isEmpty ? nil : channels,
            totalCostUsd: hasTotalCost ? formatDecimal(totalCost) : nil,
            totalRequests: hasTotalRequests ? totalRequests : nil,
            totalTokens: hasTotalTokens ? totalTokens : nil,
            trend: trend.isEmpty ? nil : downsample(trend, maxCount: KrillAPIClient.Network.sampledTrendLimit)
        )
    }

    private func downsample<T>(_ items: [T], maxCount: Int) -> [T] {
        guard items.count > maxCount, maxCount > 1 else {
            return items
        }

        let step = Double(items.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { index in
            let sourceIndex = min(items.count - 1, Int((Double(index) * step).rounded()))
            return items[sourceIndex]
        }
    }

    private func formatDecimal(_ value: Double) -> String {
        let formatted = String(format: "%.6f", locale: Self.posixLocale, value)
        return formatted
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

private struct CacheRateAccumulator {
    private var weightedRate = 0.0
    private var totalWeight = 0

    var rate: Double? {
        guard totalWeight > 0 else {
            return nil
        }
        return weightedRate / Double(totalWeight)
    }

    mutating func append(rate: Double, weight: Int) {
        let clampedWeight = max(1, weight)
        weightedRate += max(0, min(1, rate)) * Double(clampedWeight)
        totalWeight += clampedWeight
    }
}

enum StatsJSONParser {
    static func decodeEnvelope(from fileURL: URL, trendLimit: Int) throws -> StatsEnvelope {
        try autoreleasepool {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            var scanner = JSONScanner(data: data, trendLimit: trendLimit)
            return try scanner.parseStatsEnvelope()
        }
    }
}

private enum JSONScanError: Error {
    case unexpectedEnd
    case unexpectedToken
    case invalidString
}

private struct JSONScanner {
    private let data: Data
    private let trendLimit: Int
    private var index: Data.Index

    init(data: Data, trendLimit: Int) {
        self.data = data
        self.trendLimit = trendLimit
        self.index = data.startIndex
    }

    mutating func parseStatsEnvelope() throws -> StatsEnvelope {
        try consumeObjectStart()
        var code: Int?
        var payload: StatsPayload?
        var message: String?
        var success: Bool?

        while try consumeObjectEndIfPresent() == false {
            let key = try parseString()
            try consumeColon()
            switch key {
            case "code":
                code = try parseFlexibleInt()
            case "data":
                payload = try consumeNullIfPresent() ? nil : parseStatsPayload()
            case "message":
                message = try parseFlexibleString()
            case "success":
                success = try parseBoolOrNull()
            default:
                try skipValue()
            }
            try consumeCommaOrObjectEnd()
            if previousByteWasObjectEnd {
                break
            }
        }

        return StatsEnvelope(code: code, data: payload, success: success, message: message)
    }

    private mutating func parseStatsPayload() throws -> StatsPayload {
        try consumeObjectStart()
        var channelCacheRates: [ChannelCacheRate]?
        var totalCostUsd: String?
        var totalRequests: Int?
        var totalTokens: Int?
        var trend: [StatsTrendPoint]?

        while try consumeObjectEndIfPresent() == false {
            let key = try parseString()
            try consumeColon()
            switch key {
            case "channel_cache_rates":
                channelCacheRates = try parseChannelCacheRates()
            case "total_cost_usd":
                totalCostUsd = try parseFlexibleString()
            case "total_requests":
                totalRequests = try parseFlexibleInt()
            case "total_tokens":
                totalTokens = try parseFlexibleInt()
            case "trend":
                trend = try parseTrendArray()
            default:
                try skipValue()
            }
            try consumeCommaOrObjectEnd()
            if previousByteWasObjectEnd {
                break
            }
        }

        return StatsPayload(
            channelCacheRates: channelCacheRates,
            totalCostUsd: totalCostUsd,
            totalRequests: totalRequests,
            totalTokens: totalTokens,
            trend: trend
        )
    }

    private mutating func parseChannelCacheRates() throws -> [ChannelCacheRate]? {
        if try consumeNullIfPresent() {
            return nil
        }
        try consumeArrayStart()
        var rates: [ChannelCacheRate] = []

        while try consumeArrayEndIfPresent() == false {
            rates.append(try parseChannelCacheRate())
            try consumeCommaOrArrayEnd()
            if previousByteWasArrayEnd {
                break
            }
        }

        return rates
    }

    private mutating func parseChannelCacheRate() throws -> ChannelCacheRate {
        try consumeObjectStart()
        var cacheRate: Double?
        var channelName: String?

        while try consumeObjectEndIfPresent() == false {
            let key = try parseString()
            try consumeColon()
            switch key {
            case "cache_rate":
                cacheRate = try parseFlexibleDouble()
            case "channel_name":
                channelName = try parseFlexibleString()
            default:
                try skipValue()
            }
            try consumeCommaOrObjectEnd()
            if previousByteWasObjectEnd {
                break
            }
        }

        return ChannelCacheRate(cacheRate: cacheRate, channelName: channelName)
    }

    private mutating func parseTrendArray() throws -> [StatsTrendPoint]? {
        if try consumeNullIfPresent() {
            return nil
        }
        try consumeArrayStart()
        var points: [StatsTrendPoint] = []
        points.reserveCapacity(min(trendLimit * 2, 128))

        while try consumeArrayEndIfPresent() == false {
            points.append(try parseTrendPoint())
            if points.count > trendLimit * 4 {
                points = downsample(points, maxCount: trendLimit * 2)
            }
            try consumeCommaOrArrayEnd()
            if previousByteWasArrayEnd {
                break
            }
        }

        return points.isEmpty ? nil : downsample(points, maxCount: trendLimit)
    }

    private mutating func parseTrendPoint() throws -> StatsTrendPoint {
        try consumeObjectStart()
        var requestCount: Int?
        var totalCostUsd: String?
        var totalTokens: Int?

        while try consumeObjectEndIfPresent() == false {
            let key = try parseString()
            try consumeColon()
            switch key {
            case "request_count":
                requestCount = try parseFlexibleInt()
            case "total_cost_usd":
                totalCostUsd = try parseFlexibleString()
            case "total_tokens":
                totalTokens = try parseFlexibleInt()
            default:
                try skipValue()
            }
            try consumeCommaOrObjectEnd()
            if previousByteWasObjectEnd {
                break
            }
        }

        return StatsTrendPoint(requestCount: requestCount, totalCostUsd: totalCostUsd, totalTokens: totalTokens)
    }

    private var previousByteWasObjectEnd = false
    private var previousByteWasArrayEnd = false

    private mutating func consumeObjectStart() throws {
        previousByteWasObjectEnd = false
        try consume(123)
    }

    private mutating func consumeArrayStart() throws {
        previousByteWasArrayEnd = false
        try consume(91)
    }

    private mutating func consumeObjectEndIfPresent() throws -> Bool {
        skipWhitespace()
        if currentByte == 125 {
            advance()
            previousByteWasObjectEnd = true
            return true
        }
        previousByteWasObjectEnd = false
        return false
    }

    private mutating func consumeArrayEndIfPresent() throws -> Bool {
        skipWhitespace()
        if currentByte == 93 {
            advance()
            previousByteWasArrayEnd = true
            return true
        }
        previousByteWasArrayEnd = false
        return false
    }

    private mutating func consumeCommaOrObjectEnd() throws {
        skipWhitespace()
        if currentByte == 44 {
            advance()
            previousByteWasObjectEnd = false
            return
        }
        if currentByte == 125 {
            advance()
            previousByteWasObjectEnd = true
            return
        }
        throw JSONScanError.unexpectedToken
    }

    private mutating func consumeCommaOrArrayEnd() throws {
        skipWhitespace()
        if currentByte == 44 {
            advance()
            previousByteWasArrayEnd = false
            return
        }
        if currentByte == 93 {
            advance()
            previousByteWasArrayEnd = true
            return
        }
        throw JSONScanError.unexpectedToken
    }

    private mutating func consumeColon() throws {
        try consume(58)
    }

    private mutating func consume(_ byte: UInt8) throws {
        skipWhitespace()
        guard currentByte == byte else {
            throw JSONScanError.unexpectedToken
        }
        advance()
    }

    private mutating func parseString() throws -> String {
        skipWhitespace()
        guard currentByte == 34 else {
            throw JSONScanError.unexpectedToken
        }
        advance()

        var segmentStart = index
        var escapedResult: String?

        while let byte = currentByte {
            if byte == 34 {
                let segmentEnd = index
                advance()
                if var result = escapedResult {
                    result += try string(from: segmentStart..<segmentEnd)
                    return result
                }
                return try string(from: segmentStart..<segmentEnd)
            }
            if byte == 92 {
                if escapedResult == nil {
                    escapedResult = ""
                }
                escapedResult? += try string(from: segmentStart..<index)
                advance()
                escapedResult? += try parseEscapedCharacter()
                segmentStart = index
            } else {
                advance()
            }
        }

        throw JSONScanError.unexpectedEnd
    }

    private func string(from range: Range<Data.Index>) throws -> String {
        guard range.isEmpty == false else {
            return ""
        }
        guard let text = String(bytes: data[range], encoding: .utf8) else {
            throw JSONScanError.invalidString
        }
        return text
    }

    private mutating func parseEscapedCharacter() throws -> String {
        guard let byte = currentByte else {
            throw JSONScanError.unexpectedEnd
        }
        advance()

        switch byte {
        case 34:
            return "\""
        case 92:
            return "\\"
        case 47:
            return "/"
        case 98:
            return "\u{08}"
        case 102:
            return "\u{0C}"
        case 110:
            return "\n"
        case 114:
            return "\r"
        case 116:
            return "\t"
        case 117:
            return try parseUnicodeEscape()
        default:
            throw JSONScanError.invalidString
        }
    }

    private mutating func parseUnicodeEscape() throws -> String {
        let value = try parseFourHexDigits()
        if (0xD800...0xDBFF).contains(value) {
            guard currentByte == 92 else {
                throw JSONScanError.invalidString
            }
            advance()
            guard currentByte == 117 else {
                throw JSONScanError.invalidString
            }
            advance()

            let low = try parseFourHexDigits()
            guard (0xDC00...0xDFFF).contains(low) else {
                throw JSONScanError.invalidString
            }

            let scalarValue = 0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00)
            guard let scalar = UnicodeScalar(scalarValue) else {
                throw JSONScanError.invalidString
            }
            return String(scalar)
        }

        guard (0xDC00...0xDFFF).contains(value) == false else {
            throw JSONScanError.invalidString
        }

        guard let scalar = UnicodeScalar(value) else {
            throw JSONScanError.invalidString
        }
        return String(scalar)
    }

    private mutating func parseFourHexDigits() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = currentByte, let digit = hexValue(byte) else {
                throw JSONScanError.invalidString
            }
            value = value * 16 + UInt32(digit)
            advance()
        }
        return value
    }

    private func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57:
            return byte - 48
        case 65...70:
            return byte - 55
        case 97...102:
            return byte - 87
        default:
            return nil
        }
    }

    private mutating func parseFlexibleString() throws -> String? {
        if try consumeNullIfPresent() {
            return nil
        }
        if currentByte == 34 {
            return try parseString()
        }
        return try parseNumberString()
    }

    private mutating func parseFlexibleInt() throws -> Int? {
        if try consumeNullIfPresent() {
            return nil
        }
        let text = currentByte == 34 ? try parseString() : try parseNumberString()
        guard let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite else {
            return nil
        }
        return Int(number.rounded())
    }

    private mutating func parseFlexibleDouble() throws -> Double? {
        if try consumeNullIfPresent() {
            return nil
        }
        let text = currentByte == 34 ? try parseString() : try parseNumberString()
        guard let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite else {
            return nil
        }
        return number
    }

    private mutating func parseBoolOrNull() throws -> Bool? {
        if try consumeNullIfPresent() {
            return nil
        }
        if consumeLiteral("true") {
            return true
        }
        if consumeLiteral("false") {
            return false
        }
        throw JSONScanError.unexpectedToken
    }

    private mutating func parseNumberString() throws -> String {
        skipWhitespace()
        let start = index
        while let byte = currentByte, isNumberByte(byte) {
            advance()
        }
        guard start != index else {
            throw JSONScanError.unexpectedToken
        }
        return String(decoding: data[start..<index], as: UTF8.self)
    }

    private func isNumberByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 43, 45, 46, 48...57, 69, 101:
            return true
        default:
            return false
        }
    }

    private mutating func consumeNullIfPresent() throws -> Bool {
        skipWhitespace()
        return consumeLiteral("null")
    }

    private mutating func consumeLiteral(_ literal: String) -> Bool {
        let bytes = Array(literal.utf8)
        guard data.distance(from: index, to: data.endIndex) >= bytes.count else {
            return false
        }
        var cursor = index
        for byte in bytes {
            guard data[cursor] == byte else {
                return false
            }
            cursor = data.index(after: cursor)
        }
        index = cursor
        return true
    }

    private mutating func skipValue() throws {
        skipWhitespace()
        guard let byte = currentByte else {
            throw JSONScanError.unexpectedEnd
        }

        switch byte {
        case 123:
            try skipObject()
        case 91:
            try skipArray()
        case 34:
            try skipString()
        case 110:
            guard try consumeNullIfPresent() else {
                throw JSONScanError.unexpectedToken
            }
        case 116, 102:
            _ = try parseBoolOrNull()
        default:
            _ = try parseNumberString()
        }
    }

    private mutating func skipObject() throws {
        try consumeObjectStart()
        while try consumeObjectEndIfPresent() == false {
            try skipString()
            try consumeColon()
            try skipValue()
            try consumeCommaOrObjectEnd()
            if previousByteWasObjectEnd {
                break
            }
        }
    }

    private mutating func skipArray() throws {
        try consumeArrayStart()
        while try consumeArrayEndIfPresent() == false {
            try skipValue()
            try consumeCommaOrArrayEnd()
            if previousByteWasArrayEnd {
                break
            }
        }
    }

    private mutating func skipWhitespace() {
        while let byte = currentByte, byte == 32 || byte == 10 || byte == 13 || byte == 9 {
            advance()
        }
    }

    private mutating func skipString() throws {
        skipWhitespace()
        guard currentByte == 34 else {
            throw JSONScanError.unexpectedToken
        }
        advance()

        while let byte = currentByte {
            advance()
            if byte == 34 {
                return
            }
            if byte == 92 {
                try skipEscapedCharacter()
            }
        }

        throw JSONScanError.unexpectedEnd
    }

    private mutating func skipEscapedCharacter() throws {
        guard let byte = currentByte else {
            throw JSONScanError.unexpectedEnd
        }
        advance()

        switch byte {
        case 34, 47, 92, 98, 102, 110, 114, 116:
            return
        case 117:
            _ = try parseFourHexDigits()
        default:
            throw JSONScanError.invalidString
        }
    }

    private var currentByte: UInt8? {
        guard index < data.endIndex else {
            return nil
        }
        return data[index]
    }

    private mutating func advance() {
        index = data.index(after: index)
    }

    private func downsample<T>(_ items: [T], maxCount: Int) -> [T] {
        guard items.count > maxCount, maxCount > 1 else {
            return items
        }

        let step = Double(items.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { index in
            let sourceIndex = min(items.count - 1, Int((Double(index) * step).rounded()))
            return items[sourceIndex]
        }
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
