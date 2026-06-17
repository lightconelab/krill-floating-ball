import AppKit

@MainActor
final class FloatingBallController {
    private enum Layout {
        static let collapsedSize = NSSize(width: 104, height: 104)
        static let defaultExpandedWidth: CGFloat = 700
        static let panelGap: CGFloat = 8
    }

    private let store: UsageStore
    private let ballView: UsageWidgetView
    private let panelView: UsageWidgetView
    private lazy var window: NSPanel = makeWindow(contentView: ballView, frame: defaultFrame())
    private var panelWindow: NSPanel?
    private var isExpanded = false
    private var moveObserver: NSObjectProtocol?

    init(store: UsageStore) {
        self.store = store
        self.ballView = UsageWidgetView(frame: NSRect(origin: .zero, size: Layout.collapsedSize), displayMode: .ball)
        self.panelView = UsageWidgetView(frame: NSRect(origin: .zero, size: NSSize(width: 500, height: 240)), displayMode: .panel)

        ballView.refreshAction = { [weak store] in
            store?.refresh(manual: true)
        }
        ballView.expansionChanged = { [weak self] expanded in
            self?.setExpanded(expanded)
        }
        panelView.expansionChanged = { [weak self] expanded in
            self?.setExpanded(expanded)
        }
    }

    func show() {
        if window.isVisible == false {
            window.setFrame(defaultFrame(), display: true)
        } else {
            window.setFrame(pixelAligned(window.frame, on: window.screen), display: true)
        }
        window.orderFrontRegardless()
        installMoveObserverIfNeeded()
    }

    func hide() {
        hidePanel(animated: false)
        window.orderOut(nil)
    }

    func update(snapshot: UsageSnapshot) {
        ballView.snapshot = snapshot
        panelView.snapshot = snapshot
        if isExpanded, panelWindow?.isVisible == true {
            positionPanel(animated: false)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard window.isVisible else {
            return
        }

        if expanded {
            guard isExpanded == false else {
                return
            }
            isExpanded = true
            showPanel()
            return
        }

        guard pointerIsInsideWindows() == false else {
            return
        }
        isExpanded = false
        hidePanel(animated: true)
    }

    private func makeWindow(contentView: NSView, frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        panel.contentView = contentView
        return panel
    }

    private func installMoveObserverIfNeeded() {
        guard moveObserver == nil else {
            return
        }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                let aligned = self.pixelAligned(self.window.frame, on: self.window.screen)
                if self.framesAreEqual(self.window.frame, aligned) == false {
                    self.window.setFrame(aligned, display: true)
                }
                self.positionPanel(animated: false)
            }
        }
    }

    private func showPanel() {
        let targetFrame = targetPanelFrame()
        let startFrame = pixelAligned(targetFrame.offsetBy(dx: -6, dy: 0), on: window.screen)
        let panelWindow = ensurePanelWindow()
        panelView.frame = NSRect(origin: .zero, size: targetFrame.size)
        panelWindow.setFrame(startFrame, display: true)
        panelWindow.alphaValue = 0
        panelWindow.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panelWindow.animator().alphaValue = 1
            panelWindow.animator().setFrame(targetFrame, display: true)
        }
    }

    private func hidePanel(animated: Bool) {
        guard let panelWindow else {
            return
        }
        guard panelWindow.isVisible else {
            return
        }
        guard animated else {
            panelWindow.orderOut(nil)
            panelWindow.alphaValue = 1
            return
        }

        let endFrame = pixelAligned(panelWindow.frame.offsetBy(dx: -6, dy: 0), on: panelWindow.screen)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panelWindow.animator().alphaValue = 0
            panelWindow.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isExpanded == false else {
                    return
                }
                self.panelWindow?.orderOut(nil)
                self.panelWindow?.alphaValue = 1
            }
        }
    }

    private func positionPanel(animated: Bool) {
        guard let panelWindow, panelWindow.isVisible else {
            return
        }
        let frame = targetPanelFrame()
        panelView.frame = NSRect(origin: .zero, size: frame.size)
        if animated {
            panelWindow.animator().setFrame(frame, display: true)
        } else {
            panelWindow.setFrame(frame, display: true)
        }
    }

    private func targetPanelFrame() -> NSRect {
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxHeight = visible.height - 24
        let size = panelView.preferredPanelSize(maxHeight: maxHeight)
        let ballFrame = window.frame
        var frame = NSRect(
            x: ballFrame.maxX + Layout.panelGap,
            y: ballFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )

        if frame.maxX > visible.maxX - 12 {
            frame.origin.x = ballFrame.minX - size.width - Layout.panelGap
        }
        frame.origin.x = min(frame.origin.x, visible.maxX - frame.width - 12)
        frame.origin.x = max(frame.origin.x, visible.minX + 12)
        frame.origin.y = min(frame.origin.y, visible.maxY - frame.height - 12)
        frame.origin.y = max(frame.origin.y, visible.minY + 12)
        return pixelAligned(frame, on: window.screen)
    }

    private func defaultPanelFrame() -> NSRect {
        let size = panelView.preferredPanelSize(maxHeight: NSScreen.main.map { $0.visibleFrame.height - 24 })
        return pixelAligned(NSRect(origin: defaultFrame().origin, size: size), on: NSScreen.main)
    }

    private func ensurePanelWindow() -> NSPanel {
        if let panelWindow {
            return panelWindow
        }
        let panel = makeWindow(contentView: panelView, frame: defaultPanelFrame())
        panelWindow = panel
        return panel
    }

    private func pointerIsInsideWindows() -> Bool {
        pointerIsInside(window) || panelWindow.map(pointerIsInside) == true
    }

    private func pointerIsInside(_ panel: NSPanel) -> Bool {
        guard panel.isVisible, let contentView = panel.contentView else {
            return false
        }
        let point = contentView.convert(panel.mouseLocationOutsideOfEventStream, from: nil)
        return contentView.bounds.insetBy(dx: -2, dy: -2).contains(point)
    }

    private func defaultFrame() -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.maxX - Layout.defaultExpandedWidth - 80
        let y = screenFrame.midY - Layout.collapsedSize.height / 2
        return pixelAligned(NSRect(
            x: max(screenFrame.minX + 24, x),
            y: max(screenFrame.minY + 24, y),
            width: Layout.collapsedSize.width,
            height: Layout.collapsedSize.height
        ), on: NSScreen.main)
    }

    private func pixelAligned(_ frame: NSRect, on screen: NSScreen?) -> NSRect {
        let scale = screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return NSRect(
            x: pixelAligned(frame.origin.x, scale: scale),
            y: pixelAligned(frame.origin.y, scale: scale),
            width: pixelAligned(frame.width, scale: scale),
            height: pixelAligned(frame.height, scale: scale)
        )
    }

    private func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    private func framesAreEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.001
            && abs(lhs.origin.y - rhs.origin.y) < 0.001
            && abs(lhs.width - rhs.width) < 0.001
            && abs(lhs.height - rhs.height) < 0.001
    }
}
