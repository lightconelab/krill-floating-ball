import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let keychain = KeychainStore(
        service: "com.liguanqin.trellis-floating-ball"
    )

    private lazy var usageStore = UsageStore(keychain: keychain)
    private lazy var floatingController = FloatingBallController(store: usageStore)
    private let credentialValidationClient = KrillAPIClient()
    private var statusItem: NSStatusItem?
    private var refreshIntervalMenuItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?
    private var edgeProgressMenuItem: NSMenuItem?
    private var floatingBallMenuItem: NSMenuItem?
    private var didPromptForCredentialFailure = false
    private var credentialsWindowController: CredentialsWindowController?
    private var credentialValidationTask: Task<Void, Never>?

    private enum CredentialsPromptContext {
        case initialLaunch
        case menuAction
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        setupStatusItem()

        usageStore.onSnapshotChange = { [weak self] snapshot in
            guard let self else {
                return
            }
            floatingController.update(snapshot: snapshot)
            updateStatusTooltip(snapshot)
            promptForCredentialsIfNeeded(snapshot)
        }

        let hasCredentials = keychain.hasStoredCredentials()
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
        credentialValidationTask?.cancel()
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

        menu.addItem(.separator())
        let floatingItem = NSMenuItem(title: "桌面悬浮球", action: #selector(toggleFloatingBall), keyEquivalent: "s")
        floatingBallMenuItem = floatingItem
        menu.addItem(floatingItem)
        let edgeItem = NSMenuItem(title: "贴边进度条", action: #selector(toggleEdgeProgress), keyEquivalent: "")
        edgeProgressMenuItem = edgeItem
        menu.addItem(edgeItem)

        menu.addItem(.separator())
        let intervalItem = NSMenuItem(title: refreshIntervalTitle(), action: #selector(setRefreshInterval), keyEquivalent: "i")
        refreshIntervalMenuItem = intervalItem
        menu.addItem(intervalItem)
        menu.addItem(NSMenuItem(title: "余额提醒区间", action: #selector(setBalanceThresholds), keyEquivalent: ""))
        let launchItem = NSMenuItem(title: LaunchAtLoginController.menuTitle(), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem = launchItem
        menu.addItem(launchItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Krill 账号", action: #selector(setCredentials), keyEquivalent: ","))
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
        updateFloatingBallMenuItem()
        updateLaunchAtLoginMenuItem()
        updateEdgeProgressMenuItem()
    }

    private func updateStatusTooltip(_ snapshot: UsageSnapshot) {
        guard let button = statusItem?.button else {
            return
        }

        let label: String
        let amount: String
        switch snapshot.primaryMode {
        case .quotaPool:
            label = "额度池"
            amount = Formatters.usd(snapshot.primaryAmount)
        case .balance:
            label = "余额"
            amount = Formatters.usd(snapshot.primaryAmount ?? snapshot.walletBalance)
        case .empty:
            label = snapshot.emptyDisplayText
            amount = ""
        }
        let time = Formatters.time(snapshot.lastRefresh)
        button.toolTip = amount.isEmpty
            ? "\(label) · 刷新时间 \(time)"
            : "\(label) \(amount) · 刷新时间 \(time)"
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

    @objc private func setBalanceThresholds() {
        NSApp.activate(ignoringOtherApps: true)
        let shouldRestoreFloating = floatingController.temporarilyHideForModal()
        defer {
            floatingController.restoreAfterModalIfNeeded(shouldRestoreFloating)
        }

        var current = BalanceThresholds.load()

        while true {
            let alert = NSAlert()
            alert.messageText = "设置余额提醒区间"
            alert.informativeText = "余额模式颜色固定复用额度水位颜色，只配置金额区间。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "保存")
            alert.addButton(withTitle: "恢复默认")
            alert.addButton(withTitle: "取消")

            let ampleInput = thresholdInput(value: current.ample)
            let normalInput = thresholdInput(value: current.normal)
            let lowInput = thresholdInput(value: current.low)

            let stack = NSStackView()
            stack.orientation = .vertical
            stack.spacing = 8
            stack.alignment = .leading
            stack.addArrangedSubview(thresholdRow(title: "充足 >=", field: ampleInput))
            stack.addArrangedSubview(thresholdRow(title: "正常 >=", field: normalInput))
            stack.addArrangedSubview(thresholdRow(title: "偏低 >=", field: lowInput))
            stack.frame = NSRect(x: 0, y: 0, width: 320, height: 88)
            alert.accessoryView = stack
            alert.window.initialFirstResponder = ampleInput

            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                BalanceThresholds.reset()
                floatingController.preferencesDidChange()
                return
            }
            guard response == .alertFirstButtonReturn else {
                return
            }

            guard let ample = parseThreshold(ampleInput.stringValue),
                  let normal = parseThreshold(normalInput.stringValue),
                  let low = parseThreshold(lowInput.stringValue)
            else {
                showBalanceThresholdValidationAlert("请输入有效的非负数字。")
                continue
            }

            let next = BalanceThresholds(ample: ample, normal: normal, low: low)
            guard next.isValid else {
                current = next
                showBalanceThresholdValidationAlert("阈值必须满足：充足 > 正常 > 偏低 >= 0。")
                continue
            }

            BalanceThresholds.save(next)
            floatingController.preferencesDidChange()
            return
        }
    }

    @objc private func setCredentials() {
        promptForCredentials(context: .menuAction)
    }

    private func clearCredentialsAndRefresh() {
        didPromptForCredentialFailure = false
        credentialValidationTask?.cancel()
        credentialValidationTask = nil
        keychain.deleteCredentials()
        usageStore.credentialsDidChangeAndRefreshNow()
    }

    @objc private func toggleFloatingBall() {
        if floatingController.isVisible {
            floatingController.hide()
        } else {
            floatingController.show()
        }
        updateFloatingBallMenuItem()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func promptForCredentials(context: CredentialsPromptContext, initialError: String? = nil) {
        NSApp.activate(ignoringOtherApps: true)

        if let credentialsWindowController {
            credentialsWindowController.reveal()
            if let initialError {
                credentialsWindowController.showError(initialError)
            }
            return
        }

        let shouldRestoreFloating = floatingController.temporarilyHideForModal()

        let existing = keychain.cachedCredentialsIfLoaded()
        let controller = CredentialsWindowController(
            existing: existing,
            canClearCredentials: keychain.hasStoredCredentials()
        )
        credentialsWindowController = controller

        controller.onSubmit = { [weak self, weak controller] emailValue, passwordValue in
            guard let self, let controller else {
                return
            }
            let email = emailValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let password = passwordValue.isEmpty
                ? (existing?.password ?? "")
                : passwordValue
            guard email.isEmpty == false else {
                controller.showError("请输入 Krill AI 邮箱。")
                return
            }
            guard password.isEmpty == false else {
                controller.showError("请输入 Krill AI 密码。")
                return
            }

            let credentials = KrillCredentials(email: email, password: password)
            controller.setSubmitting(true)
            credentialValidationTask?.cancel()
            credentialValidationTask = Task { [weak self, weak controller] in
                guard let self, let controller else {
                    return
                }

                do {
                    _ = try await credentialValidationClient.login(credentials: credentials)
                    try Task.checkCancellation()
                    try keychain.saveCredentials(credentials)
                    didPromptForCredentialFailure = false
                    controller.finishSuccessfully()
                } catch {
                    guard Task.isCancelled == false else {
                        return
                    }
                    controller.setSubmitting(false)
                    controller.showError("登录失败：\(error.localizedDescription)")
                }
            }
        }

        controller.onClose = { [weak self] completed in
            guard let self else {
                return
            }

            credentialValidationTask?.cancel()
            credentialValidationTask = nil
            credentialsWindowController = nil
            if completed {
                if shouldRestoreFloating {
                    floatingController.restoreAfterModalIfNeeded(true)
                } else if context == .initialLaunch || existing == nil {
                    floatingController.show()
                }
                usageStore.credentialsDidChangeAndRefreshNow()
            } else {
                floatingController.restoreAfterModalIfNeeded(shouldRestoreFloating)
            }
        }

        controller.onClearCredentials = { [weak self] in
            self?.clearCredentialsAndRefresh()
        }

        controller.reveal()
        if let initialError {
            controller.showError(initialError)
        }
    }

    private func promptForCredentialsIfNeeded(_ snapshot: UsageSnapshot) {
        guard snapshot.needsToken else {
            if snapshot.isLoading == false,
               snapshot.lastError == nil,
               snapshot.lastRefresh != nil {
                didPromptForCredentialFailure = false
            }
            return
        }
        guard didPromptForCredentialFailure == false,
              credentialsWindowController == nil,
              keychain.hasStoredCredentials(),
              snapshot.lastError?.contains("登录失败") == true
        else {
            return
        }

        didPromptForCredentialFailure = true
        let loginErrorMessage = snapshot.lastError ?? "登录失败，请重新输入 Krill AI 账号和密码。"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self,
                  self.keychain.hasStoredCredentials()
            else {
                return
            }
            self.promptForCredentials(context: .initialLaunch, initialError: loginErrorMessage)
        }
    }

    private func thresholdRow(title: String, field: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.frame = NSRect(x: 0, y: 0, width: 72, height: 24)

        let prefix = NSTextField(labelWithString: "$")
        prefix.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        prefix.textColor = .secondaryLabelColor
        prefix.frame = NSRect(x: 0, y: 0, width: 12, height: 24)

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        row.addArrangedSubview(label)
        row.addArrangedSubview(prefix)
        row.addArrangedSubview(field)
        row.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        return row
    }

    private func thresholdInput(value: Double) -> NSTextField {
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        input.stringValue = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
        input.usesSingleLineMode = true
        return input
    }

    private func parseThreshold(_ value: String) -> Double? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let number = Double(normalized), number.isFinite, number >= 0 else {
            return nil
        }
        return number
    }

    private func showBalanceThresholdValidationAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "余额提醒区间无效"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "重新输入")
        alert.runModal()
    }

    private func refreshIntervalTitle() -> String {
        "刷新间隔：\(usageStore.currentRefreshIntervalSeconds()) 秒..."
    }

    private func updateEdgeProgressMenuItem() {
        edgeProgressMenuItem?.state = EdgeProgressPreference.isEnabled ? .on : .off
    }

    private func updateFloatingBallMenuItem() {
        floatingBallMenuItem?.state = floatingController.isVisible ? .on : .off
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

            let buttonRadius: CGFloat = 3.4
            let dividerGap = buttonRadius + 1.0
            let divider = NSBezierPath()
            divider.move(to: NSPoint(x: bounds.minX + 1.4, y: center.y))
            divider.line(to: NSPoint(x: center.x - dividerGap, y: center.y))
            divider.move(to: NSPoint(x: center.x + dividerGap, y: center.y))
            divider.line(to: NSPoint(x: bounds.maxX - 1.4, y: center.y))
            divider.lineWidth = 1.7
            divider.stroke()

            let buttonOuter = NSBezierPath(ovalIn: NSRect(
                x: center.x - buttonRadius,
                y: center.y - buttonRadius,
                width: buttonRadius * 2,
                height: buttonRadius * 2
            ))
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

@MainActor
private final class CredentialsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    var onSubmit: ((_ email: String, _ password: String) -> Void)?
    var onClearCredentials: (() -> Void)?
    var onClose: ((_ completed: Bool) -> Void)?

    private let existing: KrillCredentials?
    private let canClearCredentials: Bool
    private let emailInput = NSTextField(frame: .zero)
    private let passwordInput = NSSecureTextField(frame: .zero)
    private let errorLabel = NSTextField(labelWithString: "")
    private let clearButton = NSButton(title: "清除登录信息", target: nil, action: nil)
    private let submitButton = NSButton(title: "登录并刷新", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private var completed = false
    private var isSubmitting = false

    init(existing: KrillCredentials?, canClearCredentials: Bool) {
        self.existing = existing
        self.canClearCredentials = canClearCredentials

        let panel = CredentialsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 226),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Krill 账号"
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace]

        super.init(window: panel)

        panel.delegate = self
        buildContent(in: panel, existing: existing)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reveal() {
        guard let window else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        if window.isVisible == false {
            window.center()
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let window = self.window
            else {
                return
            }
            window.makeFirstResponder(self.existing?.email.isEmpty == false ? self.passwordInput : self.emailInput)
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(completed)
        onClose = nil
        onSubmit = nil
        onClearCredentials = nil
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            submit()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancel()
            return true
        default:
            return false
        }
    }

    private func buildContent(in panel: NSWindow, existing: KrillCredentials?) {
        let contentView = NSView()
        panel.contentView = contentView

        let titleLabel = NSTextField(labelWithString: "Krill 账号")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .labelColor

        let descriptionLabel = NSTextField(
            wrappingLabelWithString: "请输入 Krill AI 的邮箱和密码。凭据会保存到 macOS Keychain，源码和配置文件不会保存该信息。"
        )
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = .secondaryLabelColor

        emailInput.placeholderString = "邮箱"
        emailInput.stringValue = existing?.email ?? ""
        emailInput.delegate = self
        configureCredentialInput(emailInput, contentType: .username)

        passwordInput.placeholderString = existing == nil ? "密码" : "留空则保留原密码"
        passwordInput.delegate = self
        configureCredentialInput(passwordInput, contentType: .password)

        errorLabel.font = .systemFont(ofSize: 12, weight: .medium)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        errorLabel.lineBreakMode = .byTruncatingTail

        clearButton.target = self
        clearButton.action = #selector(clearStoredCredentials)
        clearButton.isHidden = canClearCredentials == false
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        submitButton.target = self
        submitButton.action = #selector(submit)
        submitButton.keyEquivalent = "\r"
        submitButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [cancelButton, submitButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .centerY

        let buttonContainer = NSView()
        buttonContainer.addSubview(clearButton)
        buttonContainer.addSubview(buttonRow)

        let stack = NSStackView(views: [
            titleLabel,
            descriptionLabel,
            inputRow(title: "邮箱", field: emailInput),
            inputRow(title: "密码", field: passwordInput),
            errorLabel,
            buttonContainer
        ])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        clearButton.setContentHuggingPriority(.required, for: .horizontal)
        buttonRow.setContentHuggingPriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            descriptionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            emailInput.widthAnchor.constraint(equalToConstant: 360),
            passwordInput.widthAnchor.constraint(equalToConstant: 360),
            errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            clearButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            clearButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor),
            buttonRow.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
        ])

        panel.initialFirstResponder = existing?.email.isEmpty == false ? passwordInput : emailInput
        panel.defaultButtonCell = submitButton.cell as? NSButtonCell
    }

    private func inputRow(title: String, field: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [label, field])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 44),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
        ])
        return row
    }

    @objc private func submit() {
        guard isSubmitting == false else {
            return
        }
        clearError()
        onSubmit?(emailInput.stringValue, passwordInput.stringValue)
    }

    @objc private func cancel() {
        close()
    }

    @objc private func clearStoredCredentials() {
        guard isSubmitting == false else {
            return
        }
        onClearCredentials?()
        close()
    }

    func setSubmitting(_ submitting: Bool) {
        isSubmitting = submitting
        emailInput.isEnabled = submitting == false
        passwordInput.isEnabled = submitting == false
        clearButton.isEnabled = submitting == false
        cancelButton.isEnabled = submitting == false
        submitButton.isEnabled = submitting == false
        submitButton.title = submitting ? "登录中..." : "登录并刷新"
    }

    func finishSuccessfully() {
        completed = true
        close()
    }

    func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false
        window?.makeFirstResponder(message.contains("邮箱") ? emailInput : passwordInput)
    }

    private func clearError() {
        errorLabel.stringValue = ""
        errorLabel.isHidden = true
    }
}

@MainActor
private func configureCredentialInput(_ field: NSTextField, contentType: NSTextContentType) {
    field.translatesAutoresizingMaskIntoConstraints = false
    if #available(macOS 11.0, *) {
        field.contentType = contentType
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

private final class CredentialsWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleStandardEditingShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private func handleStandardEditingShortcut(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags.contains(.command) || flags.contains(.control),
          flags.contains(.option) == false
    else {
        return false
    }

    let key = event.charactersIgnoringModifiers?.lowercased() ?? keyEquivalent(for: event.keyCode)
    switch key {
    case "v":
        return performTextAction(#selector(NSText.paste(_:)))
    case "c":
        return performTextAction(#selector(NSText.copy(_:)))
    case "x":
        return performTextAction(#selector(NSText.cut(_:)))
    case "a":
        return performTextAction(#selector(NSText.selectAll(_:)))
    case "z" where flags.contains(.shift):
        return performTextAction(Selector(("redo:")))
    case "z":
        return performTextAction(Selector(("undo:")))
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
private func performTextAction(_ action: Selector) -> Bool {
    if NSApp.sendAction(action, to: nil, from: NSApp.keyWindow) {
        return true
    }

    guard let editor = NSApp.keyWindow?.firstResponder as? NSText else {
        return false
    }
    editor.perform(action, with: nil)
    return true
}
