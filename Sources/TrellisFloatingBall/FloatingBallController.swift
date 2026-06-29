import AppKit
import Darwin

enum EdgeProgressPreference {
    private static let defaultsKey = "edgeProgressEnabled"
    private static let legacyDisplayModeKey = "edgeDisplayMode"

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: defaultsKey) != nil {
                return UserDefaults.standard.bool(forKey: defaultsKey)
            }
            if let legacyMode = UserDefaults.standard.string(forKey: legacyDisplayModeKey) {
                return legacyMode != "off"
            }
            return true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            UserDefaults.standard.removeObject(forKey: legacyDisplayModeKey)
        }
    }
}

@MainActor
final class FloatingBallController {
    private enum ScreenEdge {
        case left
        case right
        case top
        case bottom
    }

    private enum Layout {
        static let ballSize: CGFloat = 80
        static let ballInset: CGFloat = 12
        static let collapsedSize = NSSize(width: 104, height: 104)
        static let edgeProgressHorizontalSize = NSSize(width: 112, height: 18)
        static let edgeProgressVerticalSize = NSSize(width: 18, height: 112)
        static let defaultExpandedWidth: CGFloat = 700
        static let panelGap: CGFloat = 8
        static let screenInset: CGFloat = 8
        static let edgeInset: CGFloat = 3
        static let attachThreshold: CGFloat = 24
        static let minimumVisibleLength: CGFloat = 28
        static let sharedEdgeTolerance: CGFloat = 2
        static let edgeHoverPadding: CGFloat = 14
        static let panelBridgePadding: CGFloat = 10
    }

    private let store: UsageStore
    private let ballView: UsageWidgetView
    private lazy var window: NSPanel = makeWindow(contentView: ballView, frame: defaultFrame())
    private var panelView: UsageWidgetView?
    private var panelWindow: NSPanel?
    private var isExpanded = false
    private var moveObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var edgeProgressEnabled = EdgeProgressPreference.isEnabled
    private var attachedEdge: ScreenEdge?
    private var dragStartFrame: NSRect?
    private var isApplyingFrame = false
    private var latestSnapshot = UsageSnapshot.placeholder
    private var requestedVisible = false

    init(store: UsageStore) {
        self.store = store
        self.ballView = UsageWidgetView(frame: NSRect(origin: .zero, size: Layout.collapsedSize), displayMode: .ball)

        ballView.expansionChanged = { [weak self] expanded in
            self?.setExpanded(expanded)
        }
        ballView.dragBeganAction = { [weak self] in
            self?.beginUserDrag()
        }
        ballView.dragUpdatedAction = { [weak self] proposedFrame in
            self?.constrainFrameDuringDrag(proposedFrame) ?? proposedFrame
        }
        ballView.dragEndedAction = { [weak self] in
            self?.finishUserDrag()
        }
    }

    var isVisible: Bool {
        requestedVisible
    }

    func show() {
        requestedVisible = true
        collapsePanel(animated: false)
        if window.isVisible == false {
            attachedEdge = nil
            let frame = defaultFrame()
            ballView.ballPresentation = .sphere
            ballView.frame = NSRect(origin: .zero, size: frame.size)
            window.setFrame(frame, display: true)
        } else {
            window.setFrame(pixelAligned(window.frame, on: window.screen), display: true)
        }
        window.orderFrontRegardless()
        ballView.setAnimationActive(true)
        installMoveObserverIfNeeded()
        installScreenObserverIfNeeded()
    }

    func hide() {
        requestedVisible = false
        collapsePanel(animated: false)
        ballView.setAnimationActive(false)
        window.orderOut(nil)
        removeWindowObservers()
    }

    func temporarilyHideForModal() -> Bool {
        guard requestedVisible,
              window.isVisible
        else {
            return false
        }

        collapsePanel(animated: false)
        ballView.setAnimationActive(false)
        window.orderOut(nil)
        removeWindowObservers()
        return true
    }

    func restoreAfterModalIfNeeded(_ shouldRestore: Bool) {
        guard shouldRestore else {
            return
        }

        window.setFrame(pixelAligned(window.frame, on: window.screen), display: true)
        window.orderFrontRegardless()
        ballView.setAnimationActive(true)
        installMoveObserverIfNeeded()
        installScreenObserverIfNeeded()
    }

    func setEdgeProgressEnabled(_ enabled: Bool) {
        edgeProgressEnabled = enabled
        EdgeProgressPreference.isEnabled = enabled
        applyEdgePolicy(animated: true, preserveAttachedEdge: true)
    }

    func preferencesDidChange() {
        ballView.reloadPreferences()
        panelView?.reloadPreferences()
    }

    func update(snapshot: UsageSnapshot) {
        latestSnapshot = snapshot
        ballView.snapshot = snapshot
        if isExpanded, panelWindow?.isVisible == true, let panelView {
            panelView.snapshot = snapshot
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
            ballView.isExpanded = true
            showPanel()
            return
        }

        guard pointerIsInsideWindows() == false else {
            return
        }
        isExpanded = false
        ballView.isExpanded = false
        panelView?.isExpanded = false
        hidePanel(animated: true)
    }

    private func collapsePanel(animated: Bool) {
        isExpanded = false
        ballView.isExpanded = false
        panelView?.isExpanded = false
        hidePanel(animated: animated)
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
                guard self.isApplyingFrame == false else {
                    return
                }
                let screen = self.screenForFrame(self.window.frame)
                let rawFrame = self.dragStartFrame == nil
                    ? self.window.frame
                    : self.constrainedDragFrame(self.window.frame, on: screen)
                let aligned = self.pixelAligned(rawFrame, on: screen)
                if self.framesAreEqual(self.window.frame, aligned) == false {
                    self.isApplyingFrame = true
                    self.window.setFrame(aligned, display: true)
                    self.isApplyingFrame = false
                }
                self.positionPanel(animated: false)
            }
        }
    }

    private func installScreenObserverIfNeeded() {
        guard screenObserver == nil else {
            return
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyEdgePolicy(animated: false, preserveAttachedEdge: true)
            }
        }
    }

    private func removeWindowObservers() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    private func beginUserDrag() {
        guard window.isVisible else {
            return
        }
        if isExpanded {
            collapsePanel(animated: false)
        }

        if ballView.ballPresentation != .sphere {
            let screen = screenForFrame(window.frame)
            let restoreFrame: NSRect
            if let attachedEdge {
                restoreFrame = fullBallFrame(for: attachedEdge, from: window.frame, on: screen)
            } else {
                restoreFrame = constrainedFullBallFrame(fullBallFrame(from: window.frame, on: screen), on: screen)
            }
            attachedEdge = nil
            setBallFrame(restoreFrame, presentation: .sphere, on: screen, animated: false)
        }

        dragStartFrame = window.frame
    }

    private func finishUserDrag() {
        let movedDistance = dragStartFrame.map { start in
            hypot(window.frame.midX - start.midX, window.frame.midY - start.midY)
        } ?? 0
        dragStartFrame = nil
        applyEdgePolicy(animated: true, preserveAttachedEdge: movedDistance < 6)
    }

    private func constrainFrameDuringDrag(_ proposedFrame: NSRect) -> NSRect {
        let screen = screenForFrame(proposedFrame)
        return pixelAligned(constrainedDragFrame(proposedFrame, on: screen), on: screen)
    }

    private func showPanel() {
        let panelView = ensurePanelView()
        panelView.snapshot = latestSnapshot
        panelView.isExpanded = true
        let targetFrame = targetPanelFrame()
        let startFrame = pixelAligned(targetFrame.offsetBy(dx: panelSlideOffset(for: targetFrame), dy: 0), on: window.screen)
        let panelWindow = ensurePanelWindow()
        panelView.frame = NSRect(origin: .zero, size: targetFrame.size)
        panelWindow.setFrame(startFrame, display: true)
        panelWindow.alphaValue = 0
        panelWindow.orderFrontRegardless()
        keepBallWindowAbovePanel()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panelWindow.animator().alphaValue = 1
            panelWindow.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.keepBallWindowAbovePanel()
            }
        }
    }

    private func hidePanel(animated: Bool) {
        guard let panelWindow else {
            return
        }
        guard panelWindow.isVisible else {
            releasePanelWindow()
            return
        }
        guard animated else {
            releasePanelWindow()
            return
        }

        let endFrame = pixelAligned(panelWindow.frame.offsetBy(dx: panelSlideOffset(for: panelWindow.frame), dy: 0), on: panelWindow.screen)
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
                self.releasePanelWindow()
            }
        }
    }

    private func releasePanelWindow() {
        panelWindow?.orderOut(nil)
        panelWindow?.alphaValue = 1
        panelWindow?.contentView = nil
        panelWindow = nil
        panelView?.snapshot = .placeholder
        panelView = nil
        malloc_zone_pressure_relief(nil, 0)
    }

    private func positionPanel(animated: Bool) {
        guard let panelWindow, panelWindow.isVisible, let panelView else {
            return
        }
        let frame = targetPanelFrame()
        let panelContentFrame = NSRect(origin: .zero, size: frame.size)
        if framesAreEqual(panelView.frame, panelContentFrame) == false {
            panelView.frame = panelContentFrame
        }
        guard framesAreEqual(panelWindow.frame, frame) == false else {
            return
        }
        if animated {
            panelWindow.animator().setFrame(frame, display: true)
        } else {
            panelWindow.setFrame(frame, display: true)
        }
        keepBallWindowAbovePanel()
    }

    private func targetPanelFrame() -> NSRect {
        let panelView = ensurePanelView()
        let screen = screenForFrame(window.frame)
        let visible = screen.visibleFrame
        let maxHeight = visible.height - 24
        let maxWidth = visible.width - 24
        let ballFrame = panelAnchorFrame(on: screen)
        let horizontalInset: CGFloat = 12
        let preferredRight = panelShouldOpenRight(anchor: ballFrame, visible: visible)
        let rightSpace = visible.maxX - ballFrame.maxX - Layout.panelGap - horizontalInset
        let leftSpace = ballFrame.minX - visible.minX - Layout.panelGap - horizontalInset
        let minimumUsefulPanelWidth: CGFloat = 420
        let shouldOpenRight: Bool

        if preferredRight {
            shouldOpenRight = rightSpace >= minimumUsefulPanelWidth
                || (leftSpace < minimumUsefulPanelWidth && rightSpace >= leftSpace)
        } else {
            shouldOpenRight = !(leftSpace >= minimumUsefulPanelWidth
                || (rightSpace < minimumUsefulPanelWidth && leftSpace > rightSpace))
        }

        let sideSpace = shouldOpenRight ? rightSpace : leftSpace
        let constrainedMaxWidth = min(maxWidth, max(minimumUsefulPanelWidth, sideSpace))
        let size = panelView.preferredPanelSize(maxHeight: maxHeight, maxWidth: constrainedMaxWidth)
        var frame = NSRect(
            x: shouldOpenRight ? ballFrame.maxX + Layout.panelGap : ballFrame.minX - size.width - Layout.panelGap,
            y: ballFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )

        frame.origin.x = min(frame.origin.x, visible.maxX - frame.width - 12)
        frame.origin.x = max(frame.origin.x, visible.minX + 12)
        frame.origin.y = min(frame.origin.y, visible.maxY - frame.height - 12)
        frame.origin.y = max(frame.origin.y, visible.minY + 12)
        return pixelAligned(frame, on: screen)
    }

    private func defaultPanelFrame() -> NSRect {
        let panelView = ensurePanelView()
        let size = panelView.preferredPanelSize(
            maxHeight: NSScreen.main.map { $0.visibleFrame.height - 24 },
            maxWidth: NSScreen.main.map { $0.visibleFrame.width - 24 }
        )
        return pixelAligned(NSRect(origin: defaultFrame().origin, size: size), on: NSScreen.main)
    }

    private func ensurePanelWindow() -> NSPanel {
        if let panelWindow {
            return panelWindow
        }
        let panelView = ensurePanelView()
        let panel = makeWindow(contentView: panelView, frame: defaultPanelFrame())
        panelWindow = panel
        return panel
    }

    private func ensurePanelView() -> UsageWidgetView {
        if let panelView {
            return panelView
        }

        let view = UsageWidgetView(frame: NSRect(origin: .zero, size: NSSize(width: 500, height: 240)), displayMode: .panel)
        let store = self.store
        view.expansionChanged = { [weak self] expanded in
            self?.setExpanded(expanded)
        }
        view.statsRangeChanged = { [weak store] range in
            store?.setStatsRange(range)
        }
        panelView = view
        return view
    }

    private func keepBallWindowAbovePanel() {
        guard let panelWindow, panelWindow.isVisible else {
            return
        }
        window.order(.above, relativeTo: panelWindow.windowNumber)
    }

    private func panelSlideOffset(for frame: NSRect) -> CGFloat {
        frame.midX < window.frame.midX ? 6 : -6
    }

    private func pointerIsInsideWindows() -> Bool {
        pointerIsInside(window)
            || panelWindow.map(pointerIsInside) == true
            || pointerIsInsidePanelBridge()
    }

    private func pointerIsInside(_ panel: NSPanel) -> Bool {
        guard panel.isVisible, let contentView = panel.contentView else {
            return false
        }
        let point = contentView.convert(panel.mouseLocationOutsideOfEventStream, from: nil)
        let margin = panel === window && ballView.ballPresentation == .edgeProgressBar
            ? Layout.edgeHoverPadding
            : 2
        return contentView.bounds.insetBy(dx: -margin, dy: -margin).contains(point)
    }

    private func pointerIsInsidePanelBridge() -> Bool {
        guard isExpanded,
              let panelWindow,
              panelWindow.isVisible
        else {
            return false
        }

        let point = NSEvent.mouseLocation
        let bridge = window.frame.union(panelWindow.frame).insetBy(
            dx: -Layout.panelBridgePadding,
            dy: -Layout.panelBridgePadding
        )
        return bridge.contains(point)
    }

    private func applyEdgePolicy(animated: Bool, preserveAttachedEdge: Bool) {
        guard window.isVisible else {
            return
        }

        let screen = screenForFrame(window.frame)
        let currentFrame = window.frame
        let fullFrame = fullBallFrame(from: window.frame, on: screen)

        guard edgeProgressEnabled else {
            attachedEdge = nil
            setBallFrame(constrainedFullBallFrame(fullFrame, on: screen), presentation: .sphere, on: screen, animated: animated)
            return
        }

        let edge = preserveAttachedEdge
            ? attachedEdge.flatMap { isOuterEdge($0, of: screen) ? $0 : nil } ?? attachedEdgeCandidate(for: currentFrame, on: screen)
            : attachedEdgeCandidate(for: currentFrame, on: screen)

        guard let edge else {
            attachedEdge = nil
            setBallFrame(constrainedFullBallFrame(fullFrame, on: screen), presentation: .sphere, on: screen, animated: animated)
            return
        }

        attachedEdge = edge
        ballView.edgeProgressAxis = edge == .left || edge == .right ? .vertical : .horizontal
        setBallFrame(edgeProgressFrame(for: edge, from: fullFrame, on: screen), presentation: .edgeProgressBar, on: screen, animated: animated)
    }

    private func setBallFrame(
        _ frame: NSRect,
        presentation: UsageWidgetView.BallPresentation,
        on screen: NSScreen?,
        animated: Bool
    ) {
        let targetFrame = pixelAligned(frame, on: screen)
        ballView.ballPresentation = presentation
        let ballContentFrame = NSRect(origin: .zero, size: targetFrame.size)
        if framesAreEqual(ballView.frame, ballContentFrame) == false {
            ballView.frame = ballContentFrame
        }

        guard framesAreEqual(window.frame, targetFrame) == false else {
            positionPanel(animated: false)
            return
        }

        isApplyingFrame = true
        guard animated else {
            window.setFrame(targetFrame, display: true)
            isApplyingFrame = false
            positionPanel(animated: false)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.isApplyingFrame = false
                self.positionPanel(animated: false)
            }
        }
    }

    private func fullBallFrame(from frame: NSRect, on screen: NSScreen) -> NSRect {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let visible = screen.visibleFrame
        let halfWidth = Layout.collapsedSize.width / 2
        let halfHeight = Layout.collapsedSize.height / 2
        let x = min(max(center.x - halfWidth, visible.minX - Layout.collapsedSize.width), visible.maxX)
        let y = min(max(center.y - halfHeight, visible.minY - Layout.collapsedSize.height), visible.maxY)
        return NSRect(origin: NSPoint(x: x, y: y), size: Layout.collapsedSize)
    }

    private func fullBallFrame(for edge: ScreenEdge, from frame: NSRect, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let x: CGFloat
        let y: CGFloat

        switch edge {
        case .left:
            x = visible.minX + Layout.screenInset
            y = clamped(center.y - Layout.collapsedSize.height / 2, min: visible.minY + Layout.screenInset, max: visible.maxY - Layout.collapsedSize.height - Layout.screenInset)
        case .right:
            x = visible.maxX - Layout.collapsedSize.width - Layout.screenInset
            y = clamped(center.y - Layout.collapsedSize.height / 2, min: visible.minY + Layout.screenInset, max: visible.maxY - Layout.collapsedSize.height - Layout.screenInset)
        case .top:
            x = clamped(center.x - Layout.collapsedSize.width / 2, min: visible.minX + Layout.screenInset, max: visible.maxX - Layout.collapsedSize.width - Layout.screenInset)
            y = visible.maxY - Layout.collapsedSize.height - Layout.screenInset
        case .bottom:
            x = clamped(center.x - Layout.collapsedSize.width / 2, min: visible.minX + Layout.screenInset, max: visible.maxX - Layout.collapsedSize.width - Layout.screenInset)
            y = visible.minY + Layout.screenInset
        }

        return NSRect(x: x, y: y, width: Layout.collapsedSize.width, height: Layout.collapsedSize.height)
    }

    private func constrainedFullBallFrame(_ frame: NSRect, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let minX = visible.minX + Layout.screenInset
        let maxX = visible.maxX - frame.width - Layout.screenInset
        let minY = visible.minY + Layout.screenInset
        let maxY = visible.maxY - frame.height - Layout.screenInset
        return NSRect(
            x: min(max(frame.origin.x, minX), maxX),
            y: min(max(frame.origin.y, minY), maxY),
            width: frame.width,
            height: frame.height
        )
    }

    private func constrainedDragFrame(_ frame: NSRect, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let visual = sphereRect(in: frame)
        let minimumVisible = Layout.minimumVisibleLength
        var adjusted = frame

        if visual.maxX < visible.minX + minimumVisible {
            adjusted.origin.x += visible.minX + minimumVisible - visual.maxX
        }
        if visual.minX > visible.maxX - minimumVisible {
            adjusted.origin.x -= visual.minX - (visible.maxX - minimumVisible)
        }
        if visual.maxY < visible.minY + minimumVisible {
            adjusted.origin.y += visible.minY + minimumVisible - visual.maxY
        }
        if visual.minY > visible.maxY - minimumVisible {
            adjusted.origin.y -= visual.minY - (visible.maxY - minimumVisible)
        }

        return adjusted
    }

    private func edgeProgressFrame(for edge: ScreenEdge, from frame: NSRect, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let sphere = sphereRect(in: frame)
        let size = edge == .left || edge == .right
            ? Layout.edgeProgressVerticalSize
            : Layout.edgeProgressHorizontalSize
        let x: CGFloat
        let y: CGFloat

        switch edge {
        case .left:
            x = visible.minX + Layout.edgeInset
            y = clamped(sphere.midY - size.height / 2, min: visible.minY + Layout.screenInset, max: visible.maxY - size.height - Layout.screenInset)
        case .right:
            x = visible.maxX - size.width - Layout.edgeInset
            y = clamped(sphere.midY - size.height / 2, min: visible.minY + Layout.screenInset, max: visible.maxY - size.height - Layout.screenInset)
        case .top:
            x = clamped(sphere.midX - size.width / 2, min: visible.minX + Layout.screenInset, max: visible.maxX - size.width - Layout.screenInset)
            y = visible.maxY - size.height - Layout.edgeInset
        case .bottom:
            x = clamped(sphere.midX - size.width / 2, min: visible.minX + Layout.screenInset, max: visible.maxX - size.width - Layout.screenInset)
            y = visible.minY + Layout.edgeInset
        }

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func attachedEdgeCandidate(for frame: NSRect, on screen: NSScreen) -> ScreenEdge? {
        let visible = screen.visibleFrame
        let visual = attachmentRect(in: frame)
        let threshold = Layout.attachThreshold
        let candidates: [(ScreenEdge, CGFloat)] = [
            (.left, abs(visual.minX - visible.minX)),
            (.right, abs(visible.maxX - visual.maxX)),
            (.top, abs(visible.maxY - visual.maxY)),
            (.bottom, abs(visual.minY - visible.minY))
        ].filter { edge, distance in
            guard isOuterEdge(edge, of: screen) else {
                return false
            }
            switch edge {
            case .left:
                return visual.minX <= visible.minX + threshold
            case .right:
                return visual.maxX >= visible.maxX - threshold
            case .top:
                return visual.maxY >= visible.maxY - threshold
            case .bottom:
                return visual.minY <= visible.minY + threshold
            }
        }

        return candidates.min { $0.1 < $1.1 }?.0
    }

    private func screenForFrame(_ frame: NSRect) -> NSScreen {
        let screens = NSScreen.screens
        if let best = screens.max(by: { intersectionArea($0.frame, frame) < intersectionArea($1.frame, frame) }),
           intersectionArea(best.frame, frame) > 0 {
            return best
        }

        let center = NSPoint(x: frame.midX, y: frame.midY)
        return screens.min { distance(center, to: $0.frame) < distance(center, to: $1.frame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    private func panelAnchorFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        return NSIntersectionRect(window.frame, visible).isEmpty
            ? constrainedFullBallFrame(fullBallFrame(from: window.frame, on: screen), on: screen)
            : NSIntersectionRect(window.frame, visible)
    }

    private func panelShouldOpenRight(anchor: NSRect, visible: NSRect) -> Bool {
        if attachedEdge == .right {
            return false
        }
        if attachedEdge == .left {
            return true
        }
        let rightSpace = visible.maxX - anchor.maxX
        let leftSpace = anchor.minX - visible.minX
        return rightSpace >= leftSpace
    }

    private func sphereRect(in windowFrame: NSRect) -> NSRect {
        NSRect(
            x: windowFrame.minX + Layout.ballInset,
            y: windowFrame.minY + (windowFrame.height - Layout.ballSize) / 2,
            width: Layout.ballSize,
            height: Layout.ballSize
        )
    }

    private func attachmentRect(in windowFrame: NSRect) -> NSRect {
        switch ballView.ballPresentation {
        case .sphere:
            return sphereRect(in: windowFrame)
        case .edgeProgressBar:
            return windowFrame
        }
    }

    private func isOuterEdge(_ edge: ScreenEdge, of screen: NSScreen) -> Bool {
        let frame = screen.frame
        return NSScreen.screens.contains { other in
            guard other !== screen else {
                return false
            }
            let otherFrame = other.frame
            switch edge {
            case .left:
                return abs(otherFrame.maxX - frame.minX) <= Layout.sharedEdgeTolerance
                    && rangesOverlap(frame.minY...frame.maxY, otherFrame.minY...otherFrame.maxY)
            case .right:
                return abs(otherFrame.minX - frame.maxX) <= Layout.sharedEdgeTolerance
                    && rangesOverlap(frame.minY...frame.maxY, otherFrame.minY...otherFrame.maxY)
            case .top:
                return abs(otherFrame.minY - frame.maxY) <= Layout.sharedEdgeTolerance
                    && rangesOverlap(frame.minX...frame.maxX, otherFrame.minX...otherFrame.maxX)
            case .bottom:
                return abs(otherFrame.maxY - frame.minY) <= Layout.sharedEdgeTolerance
                    && rangesOverlap(frame.minX...frame.maxX, otherFrame.minX...otherFrame.maxX)
            }
        } == false
    }

    private func rangesOverlap(_ lhs: ClosedRange<CGFloat>, _ rhs: ClosedRange<CGFloat>) -> Bool {
        min(lhs.upperBound, rhs.upperBound) - max(lhs.lowerBound, rhs.lowerBound) > 12
    }

    private func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard intersection.isNull == false else {
            return 0
        }
        return max(0, intersection.width) * max(0, intersection.height)
    }

    private func distance(_ point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return sqrt(dx * dx + dy * dy)
    }

    private func clamped(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        min(max(value, minValue), maxValue)
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
