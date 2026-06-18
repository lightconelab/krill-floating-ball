import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let keychain = KeychainStore(
        service: "com.liguanqin.trellis-floating-ball",
        account: "krill-api-token"
    )

    private lazy var usageStore = UsageStore(keychain: keychain)
    private lazy var floatingController = FloatingBallController(store: usageStore)
    private var statusItem: NSStatusItem?
    private var refreshIntervalMenuItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

        usageStore.onSnapshotChange = { [weak self] snapshot in
            self?.floatingController.update(snapshot: snapshot)
            self?.updateStatusTooltip(snapshot)
        }

        floatingController.show()
        usageStore.start()

        if keychain.loadToken() == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.promptForToken()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageStore.stop()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.image = makeStatusBarCaptureBallIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "Krill Floating Ball"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r"))
        let intervalItem = NSMenuItem(title: refreshIntervalTitle(), action: #selector(setRefreshInterval), keyEquivalent: "i")
        refreshIntervalMenuItem = intervalItem
        menu.addItem(intervalItem)
        let launchItem = NSMenuItem(title: LaunchAtLoginController.menuTitle(), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem = launchItem
        menu.addItem(launchItem)
        menu.addItem(NSMenuItem(title: "设置 Krill Token...", action: #selector(setToken), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "清除 Token", action: #selector(clearToken), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "显示悬浮球", action: #selector(showFloatingBall), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "隐藏悬浮球", action: #selector(hideFloatingBall), keyEquivalent: "h"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        menu.delegate = self
        item.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateLaunchAtLoginMenuItem()
    }

    private func updateStatusTooltip(_ snapshot: UsageSnapshot) {
        guard let button = statusItem?.button else {
            return
        }

        let weekly = Formatters.usd(snapshot.weeklyRemaining)
        let time = Formatters.time(snapshot.lastRefresh)
        button.toolTip = "周剩余 \(weekly) · 刷新时间 \(time)"
    }

    @objc private func refreshNow() {
        usageStore.refresh(manual: true)
    }

    @objc private func setRefreshInterval() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "设置自动刷新间隔"
        alert.informativeText = "请输入自动刷新的间隔时间，单位为秒。默认值为 30 秒。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.placeholderString = "30"
        input.stringValue = "\(usageStore.currentRefreshIntervalSeconds())"
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let seconds = Int(input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 30
        usageStore.setRefreshIntervalSeconds(seconds)
        refreshIntervalMenuItem?.title = refreshIntervalTitle()
    }

    @objc private func toggleLaunchAtLogin() {
        if LaunchAtLoginController.requiresApproval {
            showLaunchAtLoginApprovalAlert()
            updateLaunchAtLoginMenuItem()
            return
        }

        do {
            try LaunchAtLoginController.setEnabled(LaunchAtLoginController.isEnabled == false)
            updateLaunchAtLoginMenuItem()

            if LaunchAtLoginController.requiresApproval {
                showLaunchAtLoginApprovalAlert()
            }
        } catch {
            updateLaunchAtLoginMenuItem()
            showLaunchAtLoginErrorAlert(error)
        }
    }

    @objc private func setToken() {
        promptForToken()
    }

    @objc private func clearToken() {
        keychain.deleteToken()
        usageStore.refresh(manual: true)
    }

    @objc private func showFloatingBall() {
        floatingController.show()
    }

    @objc private func hideFloatingBall() {
        floatingController.hide()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func promptForToken() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "设置 Krill API Token"
        alert.informativeText = "请输入 krill-ai 的 Bearer Token。Token 会保存到 macOS Keychain，源码和配置文件不会保存该凭证。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存并刷新")
        alert.addButton(withTitle: "取消")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        input.placeholderString = "Bearer eyJ... 或 eyJ..."
        input.stringValue = keychain.loadToken() ?? ""
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let token = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.isEmpty == false else {
            return
        }

        do {
            try keychain.saveToken(token)
            usageStore.refresh(manual: true)
        } catch {
            let errorAlert = NSAlert(error: error)
            errorAlert.messageText = "Token 保存失败"
            errorAlert.runModal()
        }
    }

    private func refreshIntervalTitle() -> String {
        "刷新间隔：\(usageStore.currentRefreshIntervalSeconds()) 秒..."
    }

    private func updateLaunchAtLoginMenuItem() {
        launchAtLoginMenuItem?.title = LaunchAtLoginController.menuTitle()
        launchAtLoginMenuItem?.state = LaunchAtLoginController.isEnabled ? .on : .off
        launchAtLoginMenuItem?.isEnabled = LaunchAtLoginController.status != .notFound
    }

    private func showLaunchAtLoginApprovalAlert() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "需要在系统设置中批准"
        alert.informativeText = "macOS 需要用户手动允许 Krill Floating Ball 作为登录项。请在系统设置的登录项中允许该应用。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后处理")

        guard alert.runModal() == .alertFirstButtonReturn,
              let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func showLaunchAtLoginErrorAlert(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert(error: error)
        alert.messageText = "开机启动设置失败"
        alert.runModal()
    }

    private func makeStatusBarCaptureBallIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let strokeColor = NSColor.black
            let bounds = rect.insetBy(dx: 2, dy: 2)
            let center = NSPoint(x: bounds.midX, y: bounds.midY)

            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(ovalIn: bounds).addClip()
            strokeColor.withAlphaComponent(0.22).setFill()
            NSBezierPath(rect: NSRect(x: bounds.minX, y: center.y, width: bounds.width, height: bounds.height / 2)).fill()
            NSGraphicsContext.restoreGraphicsState()

            strokeColor.setStroke()

            let outer = NSBezierPath(ovalIn: bounds)
            outer.lineWidth = 1.7
            outer.stroke()

            let divider = NSBezierPath()
            divider.move(to: NSPoint(x: bounds.minX + 1.4, y: center.y))
            divider.line(to: NSPoint(x: bounds.maxX - 1.4, y: center.y))
            divider.lineWidth = 1.7
            divider.stroke()

            let buttonOuter = NSBezierPath(ovalIn: NSRect(x: center.x - 3.4, y: center.y - 3.4, width: 6.8, height: 6.8))
            buttonOuter.lineWidth = 1.7
            buttonOuter.stroke()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 5.9, weight: .black),
                .foregroundColor: strokeColor,
                .paragraphStyle: paragraph,
            ]
            let text = NSString(string: "K")
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                in: NSRect(
                    x: center.x - textSize.width / 2,
                    y: center.y - textSize.height / 2 - 0.2,
                    width: textSize.width,
                    height: textSize.height
                ),
                withAttributes: attributes
            )

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Krill Floating Ball"
        return image
    }
}
