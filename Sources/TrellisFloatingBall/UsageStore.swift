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
    private var isRefreshing = false
    private var refreshIntervalSeconds: Int

    init(keychain: KeychainStore) {
        self.keychain = keychain
        let saved = UserDefaults.standard.integer(forKey: Defaults.refreshIntervalSeconds)
        self.refreshIntervalSeconds = saved > 0
            ? max(Defaults.minimumRefreshIntervalSeconds, saved)
            : Defaults.defaultRefreshIntervalSeconds
    }

    func start() {
        emit()
        scheduleTimer()
        refresh(manual: false)
    }

    func stop() {
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
        scheduleTimer()
    }

    func refresh(manual: Bool) {
        guard isRefreshing == false else {
            return
        }

        guard let token = keychain.loadToken(), token.isEmpty == false else {
            updateSnapshotIfChanged(.missingToken(previous: snapshot))
            return
        }

        isRefreshing = true
        snapshot.isLoading = true
        snapshot.needsToken = false
        snapshot.lastError = nil

        refreshTask = Task { [weak self] in
            await self?.load(token: token)
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: TimeInterval(refreshIntervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(manual: false)
            }
        }
        timer.tolerance = min(TimeInterval(refreshIntervalSeconds) * 0.1, 2)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func load(token: String) async {
        defer {
            isRefreshing = false
            snapshot.isLoading = false
            refreshTask = nil
            emit()
        }

        do {
            let bundle = try await client.fetchAll(token: token)
            snapshot = try UsageAggregator.makeSnapshot(bundle: bundle)
        } catch {
            snapshot.isStale = snapshot.lastRefresh != nil
            snapshot.lastError = error.localizedDescription
        }
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
