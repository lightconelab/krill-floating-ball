import Foundation

@MainActor
final class UsageStore {
    var onSnapshotChange: ((UsageSnapshot) -> Void)?

    private enum Defaults {
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let defaultRefreshIntervalSeconds = 30
    }

    private let keychain: KeychainStore
    private let client = KrillAPIClient()
    private var timer: Timer?
    private var snapshot = UsageSnapshot.placeholder
    private var isRefreshing = false
    private var refreshIntervalSeconds: Int

    init(keychain: KeychainStore) {
        self.keychain = keychain
        let saved = UserDefaults.standard.integer(forKey: Defaults.refreshIntervalSeconds)
        self.refreshIntervalSeconds = saved > 0 ? saved : Defaults.defaultRefreshIntervalSeconds
    }

    func start() {
        emit()
        scheduleTimer()
        refresh(manual: false)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func currentRefreshIntervalSeconds() -> Int {
        refreshIntervalSeconds
    }

    func setRefreshIntervalSeconds(_ seconds: Int) {
        refreshIntervalSeconds = max(1, seconds)
        UserDefaults.standard.set(refreshIntervalSeconds, forKey: Defaults.refreshIntervalSeconds)
        scheduleTimer()
    }

    func refresh(manual: Bool) {
        guard isRefreshing == false else {
            return
        }

        guard let token = keychain.loadToken(), token.isEmpty == false else {
            snapshot = .missingToken(previous: snapshot)
            emit()
            return
        }

        isRefreshing = true
        snapshot.isLoading = true
        snapshot.needsToken = false
        snapshot.lastError = nil
        emit()

        Task { [weak self] in
            await self?.load(token: token)
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshIntervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(manual: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func load(token: String) async {
        defer {
            isRefreshing = false
            snapshot.isLoading = false
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
}
