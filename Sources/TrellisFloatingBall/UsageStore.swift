import Darwin
import Foundation

@MainActor
final class UsageStore {
    var onSnapshotChange: ((UsageSnapshot) -> Void)?

    private enum Defaults {
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let defaultRefreshIntervalSeconds = 30
        static let minimumRefreshIntervalSeconds = 5
    }

    private enum RefreshReason: Int {
        case automatic = 0
        case credentialsChanged = 1
        case statsRangeChanged = 2
        case manual = 3

        var bypassCodexModelIQCache: Bool {
            self == .manual
        }
    }

    private let keychain: KeychainStore
    private let client = KrillAPIClient()
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var snapshot = UsageSnapshot.placeholder
    private var isRunning = false
    private var isRefreshing = false
    private var queuedRefreshReason: RefreshReason?
    private var refreshGeneration = 0
    private var refreshIntervalSeconds: Int
    private var selectedStatsRange: StatsRange = .today
    private var cachedToken: String?

    init(keychain: KeychainStore) {
        self.keychain = keychain
        let saved = UserDefaults.standard.integer(forKey: Defaults.refreshIntervalSeconds)
        self.refreshIntervalSeconds = saved > 0
            ? max(Defaults.minimumRefreshIntervalSeconds, saved)
            : Defaults.defaultRefreshIntervalSeconds
    }

    func start() {
        isRunning = true
        emit()
        refresh(reason: .automatic)
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        cachedToken = nil
    }

    func currentRefreshIntervalSeconds() -> Int {
        refreshIntervalSeconds
    }

    func setRefreshIntervalSeconds(_ seconds: Int) {
        refreshIntervalSeconds = max(Defaults.minimumRefreshIntervalSeconds, seconds)
        UserDefaults.standard.set(refreshIntervalSeconds, forKey: Defaults.refreshIntervalSeconds)
        guard isRunning, isRefreshing == false else {
            return
        }
        scheduleNextRefresh()
    }

    func setStatsRange(_ range: StatsRange) {
        guard selectedStatsRange != range || snapshot.statsRange != range else {
            return
        }
        selectedStatsRange = range
        cancelCurrentRefreshForImmediateReplacement()
        if snapshot.availableStatsRanges.contains(range), snapshot.statsRange != range {
            snapshot.statsRange = range
            snapshot.todayCost = nil
            snapshot.requestCount = nil
            snapshot.totalTokens = nil
            snapshot.trend = []
            snapshot.cacheRates = []
            snapshot.isLoading = true
            snapshot.lastError = nil
            emit()
        }
        refresh(reason: .statsRangeChanged)
    }

    func credentialsDidChangeAndRefreshNow() {
        cachedToken = nil
        cancelCurrentRefreshForImmediateReplacement()
        if keychain.hasStoredCredentials() == false {
            selectedStatsRange = .today
        }
        refresh(reason: .credentialsChanged)
    }

    func refresh(manual: Bool) {
        refresh(reason: manual ? .manual : .automatic)
    }

    private func refresh(reason: RefreshReason) {
        guard isRunning || reason != .automatic else {
            return
        }

        timer?.invalidate()
        timer = nil

        guard isRefreshing == false else {
            queueRefresh(reason)
            return
        }

        guard let credentials = keychain.loadCredentials() else {
            cachedToken = nil
            updateSnapshotIfChanged(.missingCredentials(previous: snapshot))
            return
        }

        markRefreshStarted()

        isRefreshing = true
        let requestedRange = selectedStatsRange
        let generation = refreshGeneration

        refreshTask = Task { [weak self] in
            await self?.load(
                credentials: credentials,
                requestedRange: requestedRange,
                generation: generation,
                reason: reason
            )
        }
    }

    private func scheduleNextRefresh() {
        timer?.invalidate()
        guard isRunning, snapshot.needsToken == false else {
            timer = nil
            return
        }

        let timer = Timer(timeInterval: TimeInterval(refreshIntervalSeconds), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(manual: false)
            }
        }
        timer.tolerance = min(TimeInterval(refreshIntervalSeconds) * 0.1, 2)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func markRefreshStarted() {
        var next = snapshot
        next.needsToken = false
        next.isLoading = true
        next.lastError = nil
        if next != snapshot {
            snapshot = next
            emit()
        }
    }

    private func load(
        credentials: KrillCredentials,
        requestedRange: StatsRange,
        generation: Int,
        reason: RefreshReason
    ) async {
        var didUpdateSnapshot = false

        defer {
            if generation == refreshGeneration {
                isRefreshing = false
                refreshTask = nil
                if let queuedRefreshReason, isRunning {
                    self.queuedRefreshReason = nil
                    if didUpdateSnapshot {
                        emit()
                    }
                    refresh(reason: queuedRefreshReason)
                } else {
                    if didUpdateSnapshot {
                        emit()
                    }
                    scheduleNextRefresh()
                }
            }
            malloc_zone_pressure_relief(nil, 0)
        }

        do {
            let bundle = try await fetchWithLogin(
                credentials: credentials,
                requestedStatsRange: requestedRange,
                generation: generation,
                forceCodexModelIQRefresh: reason.bypassCodexModelIQCache
            )
            guard isCurrentRefresh(generation: generation, requestedRange: requestedRange) else {
                return
            }

            let next = try UsageAggregator.makeSnapshot(bundle: bundle, previous: snapshot)
            selectedStatsRange = next.statsRange
            snapshot = next
            didUpdateSnapshot = true
        } catch {
            if isCancellation(error) {
                return
            }

            guard isCurrentRefresh(generation: generation, requestedRange: requestedRange) else {
                return
            }

            snapshot.isStale = snapshot.lastRefresh != nil
            snapshot.isLoading = false
            snapshot.lastError = error.localizedDescription
            if requiresCredentialReset(error) {
                cachedToken = nil
                snapshot.needsToken = true
            }
            didUpdateSnapshot = true
        }
    }

    private func cancelCurrentRefreshForImmediateReplacement() {
        refreshGeneration += 1
        queuedRefreshReason = nil
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
    }

    private func queueRefresh(_ reason: RefreshReason) {
        guard let queuedRefreshReason else {
            self.queuedRefreshReason = reason
            return
        }
        if reason.rawValue > queuedRefreshReason.rawValue {
            self.queuedRefreshReason = reason
        }
    }

    private func fetchWithLogin(
        credentials: KrillCredentials,
        requestedStatsRange: StatsRange,
        generation: Int,
        forceCodexModelIQRefresh: Bool
    ) async throws -> APIBundle {
        do {
            let token = try await loginIfNeeded(credentials: credentials, force: false)
            return try await fetchBundle(
                token: token,
                requestedStatsRange: requestedStatsRange,
                generation: generation,
                forceCodexModelIQRefresh: forceCodexModelIQRefresh
            )
        } catch KrillAPIError.unauthorized {
            cachedToken = nil
            let token = try await loginIfNeeded(credentials: credentials, force: true)
            do {
                return try await fetchBundle(
                    token: token,
                    requestedStatsRange: requestedStatsRange,
                    generation: generation,
                    forceCodexModelIQRefresh: forceCodexModelIQRefresh
                )
            } catch KrillAPIError.unauthorized {
                cachedToken = nil
                throw KrillAPIError.loginFailed("登录状态已失效，请重新设置 Krill 账号")
            }
        }
    }

    private func fetchBundle(
        token: String,
        requestedStatsRange: StatsRange,
        generation: Int,
        forceCodexModelIQRefresh: Bool
    ) async throws -> APIBundle {
        let subscription = try await client.fetchSubscription(token: token)
        let rangeContext = try UsageAggregator.statsRangeContext(
            subscription: subscription,
            requested: requestedStatsRange,
            now: Date()
        )
        try publishSubscriptionSnapshot(
            subscription: subscription,
            rangeContext: rangeContext,
            generation: generation,
            requestedRange: requestedStatsRange
        )
        let stats = try await client.fetchStats(token: token, range: rangeContext)
        let codexModelIQ: CodexModelIQSnapshot?
        let codexModelIQDidFail: Bool
        do {
            codexModelIQ = try await client.fetchCodexModelIQ(forceRefresh: forceCodexModelIQRefresh)
            codexModelIQDidFail = false
        } catch {
            codexModelIQ = nil
            codexModelIQDidFail = true
        }
        return APIBundle(
            subscription: subscription,
            stats: stats,
            statsRangeContext: rangeContext,
            codexModelIQ: codexModelIQ,
            codexModelIQDidFail: codexModelIQDidFail
        )
    }

    private func publishSubscriptionSnapshot(
        subscription: SubscriptionEnvelope,
        rangeContext: StatsRangeContext,
        generation: Int,
        requestedRange: StatsRange
    ) throws {
        guard isCurrentRefresh(generation: generation, requestedRange: requestedRange) else {
            throw CancellationError()
        }

        let next = try UsageAggregator.makeSubscriptionSnapshot(
            subscription: subscription,
            statsRangeContext: rangeContext,
            previous: snapshot
        )
        if next != snapshot {
            snapshot = next
            emit()
        }
    }

    private func loginIfNeeded(credentials: KrillCredentials, force: Bool) async throws -> String {
        if force == false, let cachedToken, cachedToken.isEmpty == false {
            return cachedToken
        }

        let token = try await client.login(credentials: credentials)
        cachedToken = token
        return token
    }

    private func requiresCredentialReset(_ error: Error) -> Bool {
        guard let apiError = error as? KrillAPIError else {
            return false
        }

        switch apiError {
        case .loginFailed:
            return true
        default:
            return false
        }
    }

    private func isCurrentRefresh(generation: Int, requestedRange: StatsRange) -> Bool {
        generation == refreshGeneration && requestedRange == selectedStatsRange
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        return (error as? URLError)?.code == .cancelled
    }

    private func emit() {
        onSnapshotChange?(snapshot)
    }

    private func updateSnapshotIfChanged(_ next: UsageSnapshot) {
        guard next != snapshot else {
            return
        }
        snapshot = next
        emit()
    }
}
