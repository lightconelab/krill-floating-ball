import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let keychain = KeychainStore(
        service: "com.liguanqin.trellis-floating-ball"
    )

    private lazy var usageStore = UsageStore(keychain: keychain)
    private lazy var floatingController = FloatingBallController(store: usageStore)
    private var statusItem: NSStatusItem?
    private var refreshIntervalMenuItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?
    private var edgeProgressMenuItem: NSMenuItem?

    private enum CredentialsPromptContext {
        case initialLaunch
        case menuAction
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        setupStatusItem()

        usageStore.onSnapshotChange = { [weak self] snapshot in
            self?.floatingController.update(snapshot: snapshot)
            self?.updateStatusTooltip(snapshot)
        }

        let hasCredentials = keychain.loadCredentials() != nil
        if hasCredentials {
            floatingController.show()
        }
        usageStore.start()

        if hasCredentials == false {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.promptForCredentials(context: .initialLaunch)
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
        let edgeItem = NSMenuItem(title: "贴边进度条", action: #selector(toggleEdgeProgress), keyEquivalent: "")
        edgeProgressMenuItem = edgeItem
        menu.addItem(edgeItem)
        menu.addItem(NSMenuItem(title: "设置 Krill 账号...", action: #selector(setCredentials), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "清除登录信息", action: #selector(clearCredentials), keyEquivalent: ""))
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

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "退出 Krill Floating Ball", action: #selector(quit), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateLaunchAtLoginMenuItem()
        updateEdgeProgressMenuItem()
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

    @objc private func toggleEdgeProgress() {
        let enabled = EdgeProgressPreference.isEnabled == false
        floatingController.setEdgeProgressEnabled(enabled)
        updateEdgeProgressMenuItem()
    }

    @objc private func setCredentials() {
        promptForCredentials(context: .menuAction)
    }

    @objc private func clearCredentials() {
        keychain.deleteCredentials()
        usageStore.credentialsDidChangeAndRefreshNow()
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

    private func promptForCredentials(context: CredentialsPromptContext) {
        NSApp.activate(ignoringOtherApps: true)
        let shouldRestoreFloating = floatingController.temporarilyHideForModal()

        let existing = keychain.loadCredentials()
        let alert = NSAlert()
        alert.messageText = "设置 Krill 登录账号"
        alert.informativeText = "请输入 Krill AI 的邮箱和密码。凭据会保存到 macOS Keychain，源码和配置文件不会保存该信息。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "登录并刷新")
        alert.addButton(withTitle: "取消")

        let emailInput = ShortcutTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        emailInput.placeholderString = "邮箱"
        emailInput.stringValue = existing?.email ?? ""
        configureCredentialInput(emailInput)

        let passwordInput = ShortcutSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        passwordInput.placeholderString = existing == nil ? "密码" : "留空则保留原密码"
        configureCredentialInput(passwordInput)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.addArrangedSubview(labeledField(title: "邮箱", field: emailInput))
        stack.addArrangedSubview(labeledField(title: "密码", field: passwordInput))
        stack.frame = NSRect(x: 0, y: 0, width: 420, height: 64)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = existing?.email.isEmpty == false ? passwordInput : emailInput

        guard alert.runModal() == .alertFirstButtonReturn else {
            floatingController.restoreAfterModalIfNeeded(shouldRestoreFloating)
            return
        }

        let email = emailInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordInput.stringValue.isEmpty
            ? (existing?.password ?? "")
            : passwordInput.stringValue
        guard email.isEmpty == false, password.isEmpty == false else {
            floatingController.restoreAfterModalIfNeeded(shouldRestoreFloating)
            return
        }

        do {
            try keychain.saveCredentials(KrillCredentials(email: email, password: password))
            if shouldRestoreFloating {
                floatingController.restoreAfterModalIfNeeded(true)
            } else if context == .initialLaunch || existing == nil {
                floatingController.show()
            }
            usageStore.credentialsDidChangeAndRefreshNow()
        } catch {
            floatingController.restoreAfterModalIfNeeded(shouldRestoreFloating)
            let errorAlert = NSAlert(error: error)
            errorAlert.messageText = "登录凭据保存失败"
            errorAlert.runModal()
        }
    }

    private func labeledField(title: String, field: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 0, y: 0, width: 44, height: 24)

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.addArrangedSubview(label)
        row.addArrangedSubview(field)
        row.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
        return row
    }

    private func configureCredentialInput(_ field: NSTextField) {
        if #available(macOS 11.0, *) {
            field.contentType = nil
        }
        field.isAutomaticTextCompletionEnabled = false
        field.usesSingleLineMode = true
        field.allowsEditingTextAttributes = false
        field.importsGraphics = false
        if #available(macOS 15.2, *) {
            field.allowsWritingTools = false
        }
        if #available(macOS 15.4, *) {
            field.allowsWritingToolsAffordance = false
        }
    }

    private func refreshIntervalTitle() -> String {
        "刷新间隔：\(usageStore.currentRefreshIntervalSeconds()) 秒..."
    }

    private func updateEdgeProgressMenuItem() {
        edgeProgressMenuItem?.state = EdgeProgressPreference.isEnabled ? .on : .off
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

private final class ShortcutTextField: NSTextField {
    override func keyDown(with event: NSEvent) {
        guard handleStandardEditingShortcut(event, field: self) == false else {
            return
        }
        super.keyDown(with: event)
    }
}

private final class ShortcutSecureTextField: NSSecureTextField {
    override func keyDown(with event: NSEvent) {
        guard handleStandardEditingShortcut(event, field: self) == false else {
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
private func handleStandardEditingShortcut(_ event: NSEvent, field: NSTextField) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags.contains(.command) || flags.contains(.control),
          flags.contains(.option) == false
    else {
        return false
    }

    let key = event.charactersIgnoringModifiers?.lowercased() ?? keyEquivalent(for: event.keyCode)
    switch key {
    case "v":
        return performTextAction(#selector(NSText.paste(_:)), field: field)
    case "c":
        return performTextAction(#selector(NSText.copy(_:)), field: field)
    case "x":
        return performTextAction(#selector(NSText.cut(_:)), field: field)
    case "a":
        return performTextAction(#selector(NSText.selectAll(_:)), field: field)
    case "z" where flags.contains(.shift):
        return performTextAction(Selector(("redo:")), field: field)
    case "z":
        return performTextAction(Selector(("undo:")), field: field)
    default:
        return false
    }
}

private func keyEquivalent(for keyCode: UInt16) -> String? {
    switch keyCode {
    case 0:
        return "a"
    case 6:
        return "z"
    case 7:
        return "x"
    case 8:
        return "c"
    case 9:
        return "v"
    default:
        return nil
    }
}

@MainActor
private func performTextAction(_ action: Selector, field: NSTextField) -> Bool {
    if NSApp.sendAction(action, to: nil, from: field) {
        return true
    }

    guard let editor = field.currentEditor() else {
        return false
    }
    editor.perform(action, with: field)
    return true
}
