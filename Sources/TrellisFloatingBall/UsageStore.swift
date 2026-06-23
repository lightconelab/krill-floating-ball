import Foundation

@MainActor
final class UsageStore {
    var onSnapshotChange: ((UsageSnapshot) -> Void)?

    private enum Defaults {
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let defaultRefreshIntervalSeconds = 30
        static let minimumRefreshIntervalSeconds = 5
    }

    private let keychain: KeychainStore
    private let client = KrillAPIClient()
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var snapshot = UsageSnapshot.placeholder
    private var isRunning = false
    private var isRefreshing = false
    private var needsRefreshAfterCurrent = false
    private var refreshGeneration = 0
    private var refreshIntervalSeconds: Int
    private var selectedStatsRange: StatsRange = .quotaWeek

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
        refresh(manual: false)
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
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
        refreshGeneration += 1
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
        if isRefreshing {
            needsRefreshAfterCurrent = true
            refreshTask?.cancel()
        }
        refresh(manual: true)
    }

    func refresh(manual: Bool) {
        guard isRunning || manual else {
            return
        }

        timer?.invalidate()
        timer = nil

        guard isRefreshing == false else {
            if manual {
                needsRefreshAfterCurrent = true
            }
            return
        }

        guard let token = keychain.loadToken(), token.isEmpty == false else {
            updateSnapshotIfChanged(.missingToken(previous: snapshot))
            scheduleNextRefresh()
            return
        }

        isRefreshing = true
        let requestedRange = selectedStatsRange
        let generation = refreshGeneration

        refreshTask = Task { [weak self] in
            await self?.load(token: token, requestedRange: requestedRange, generation: generation)
        }
    }

    private func scheduleNextRefresh() {
        timer?.invalidate()
        guard isRunning else {
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

    private func load(token: String, requestedRange: StatsRange, generation: Int) async {
        var didUpdateSnapshot = false

        defer {
            isRefreshing = false
            refreshTask = nil
            let shouldRefreshAgain = needsRefreshAfterCurrent
            needsRefreshAfterCurrent = false
            if shouldRefreshAgain, isRunning {
                if didUpdateSnapshot {
                    emit()
                }
                refresh(manual: false)
            } else {
                if didUpdateSnapshot {
                    emit()
                }
                scheduleNextRefresh()
            }
        }

        do {
            let bundle = try await client.fetchAll(token: token, requestedStatsRange: requestedRange)
            guard isCurrentRefresh(generation: generation, requestedRange: requestedRange) else {
                needsRefreshAfterCurrent = true
                return
            }

            let next = try UsageAggregator.makeSnapshot(bundle: bundle)
            selectedStatsRange = next.statsRange
            snapshot = next
            didUpdateSnapshot = true
        } catch {
            if isCancellation(error) {
                return
            }

            guard isCurrentRefresh(generation: generation, requestedRange: requestedRange) else {
                needsRefreshAfterCurrent = true
                return
            }

            snapshot.isStale = snapshot.lastRefresh != nil
            snapshot.isLoading = false
            snapshot.lastError = error.localizedDescription
            didUpdateSnapshot = true
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
