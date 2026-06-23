import AppKit

@MainActor
final class UsageWidgetView: NSView {
    enum DisplayMode {
        case ball
        case panel
    }

    enum BallPresentation {
        case sphere
        case edgeProgressBar
    }

    enum EdgeProgressAxis {
        case horizontal
        case vertical
    }

    var refreshAction: (() -> Void)?
    var expansionChanged: ((Bool) -> Void)?
    var dragBeganAction: (() -> Void)?
    var dragUpdatedAction: ((NSRect) -> NSRect)?
    var dragEndedAction: (() -> Void)?
    var statsRangeChanged: ((StatsRange) -> Void)?

    var ballPresentation: BallPresentation = .sphere {
        didSet {
            guard oldValue != ballPresentation else {
                return
            }
            needsDisplay = true
            updateAnimationScheduling()
        }
    }

    var edgeProgressAxis: EdgeProgressAxis = .horizontal {
        didSet {
            guard oldValue != edgeProgressAxis else {
                return
            }
            needsDisplay = true
        }
    }

    var snapshot: UsageSnapshot = .placeholder {
        didSet {
            guard shouldRedrawSnapshotChange(from: oldValue, to: snapshot) else {
                return
            }
            needsDisplay = true
            updateAnimationScheduling()
        }
    }

    var isExpanded = false {
        didSet {
            guard oldValue != isExpanded else {
                return
            }
            panelProgress = isExpanded ? max(panelProgress, 0.2) : panelProgress
            needsDisplay = true
            updateAnimationScheduling()
        }
    }

    override var isFlipped: Bool {
        true
    }

    private let ballSize: CGFloat = 80
    private let ballInset: CGFloat = 12
    private let panelMinWidth: CGFloat = 620
    private let panelCompactMinWidth: CGFloat = 420
    private let panelMaxWidth: CGFloat = 860
    private let panelWeeklyCardHeight: CGFloat = 166
    private let panelTotalCardHeight: CGFloat = 122
    private let panelCardGap: CGFloat = 16
    private let panelBottomPadding: CGFloat = 20
    private let statsHeaderHeight: CGFloat = 32
    private let panelContentInset: CGFloat = 20
    private let expandedRightPadding: CGFloat = 16

    private var animationPhase: CGFloat = 0
    private var panelProgress: CGFloat = 0
    private var animationActive = false
    private var currentAnimationInterval: TimeInterval?
    private var displayTimer: Timer?
    private var tracking: NSTrackingArea?
    private var pendingCollapse: DispatchWorkItem?
    private var statsRangeButtonRects: [(range: StatsRange, rect: NSRect)] = []
    private var collapseGeneration = 0
    private var dragOffsetInWindow: NSPoint?
    private var pointerIsHovering = false
    private let displayMode: DisplayMode

    init(frame frameRect: NSRect, displayMode: DisplayMode = .ball) {
        self.displayMode = displayMode
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        updateLayerScale()
    }

    required init?(coder: NSCoder) {
        self.displayMode = .ball
        super.init(coder: coder)
        updateLayerScale()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil else {
            return
        }
        pointerIsHovering = false
        cancelPendingCollapse()
        stopDisplayTimer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerScale()
        updateAnimationScheduling()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateLayerScale()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        pointerIsHovering = true
        updateAnimationScheduling()
        cancelPendingCollapse()
        expansionChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        pointerIsHovering = false
        updateAnimationScheduling()
        cancelPendingCollapse()
        collapseGeneration += 1
        let generation = collapseGeneration
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.collapseGeneration == generation else {
                    return
                }
                self.pendingCollapse = nil
                if self.pointerIsInsideWidget() {
                    return
                }
                self.expansionChanged?(false)
            }
        }
        pendingCollapse = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    override func mouseDown(with event: NSEvent) {
        if displayMode == .panel {
            handlePanelMouseDown(event)
            return
        }

        if displayMode == .ball {
            dragBeganAction?()
            if let window {
                let mouse = NSEvent.mouseLocation
                dragOffsetInWindow = NSPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard displayMode == .ball,
              let window,
              let dragOffsetInWindow
        else {
            return
        }

        let mouse = NSEvent.mouseLocation
        var proposedFrame = window.frame
        proposedFrame.origin = NSPoint(
            x: mouse.x - dragOffsetInWindow.x,
            y: mouse.y - dragOffsetInWindow.y
        )
        let targetFrame = dragUpdatedAction?(proposedFrame) ?? proposedFrame
        window.setFrame(targetFrame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard displayMode == .ball else {
            return
        }
        dragOffsetInWindow = nil
        dragEndedAction?()
    }

    private func handlePanelMouseDown(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for item in statsRangeButtonRects.reversed() {
            guard item.rect.contains(point),
                  snapshot.availableStatsRanges.contains(item.range)
            else {
                continue
            }
            statsRangeChanged?(item.range)
            return
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        switch displayMode {
        case .ball:
            switch ballPresentation {
            case .sphere:
                drawLiquidBall()
            case .edgeProgressBar:
                drawEdgeProgressBar()
            }
        case .panel:
            drawExpandedPanel(progress: 1)
        }
    }

    func preferredPanelSize(maxHeight: CGFloat? = nil, maxWidth: CGFloat? = nil) -> NSSize {
        var panelHeight = preferredPanelHeight()
        if let maxHeight {
            panelHeight = min(panelHeight, max(180, maxHeight - 12))
        }
        let width = preferredPanelWidth(maxWidth: maxWidth)
        let height = panelHeight
        return NSSize(width: width, height: height)
    }

    func setAnimationActive(_ active: Bool) {
        guard displayMode == .ball else {
            return
        }
        guard animationActive != active else {
            return
        }
        animationActive = active
        updateAnimationScheduling()
    }

    private func shouldRedrawSnapshotChange(from oldSnapshot: UsageSnapshot, to newSnapshot: UsageSnapshot) -> Bool {
        guard oldSnapshot != newSnapshot else {
            return false
        }

        guard displayMode == .ball else {
            return true
        }

        return oldSnapshot.weeklyRemaining != newSnapshot.weeklyRemaining
            || oldSnapshot.weeklyTotal != newSnapshot.weeklyTotal
            || oldSnapshot.weekEnd != newSnapshot.weekEnd
            || oldSnapshot.needsToken != newSnapshot.needsToken
    }

    private func startDisplayTimer(interval: TimeInterval) {
        guard displayMode == .ball else {
            return
        }
        displayTimer?.invalidate()
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(animationTimerFired),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = min(interval * 0.35, 0.08)
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
        currentAnimationInterval = interval
    }

    private func cancelPendingCollapse() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
        collapseGeneration += 1
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
        currentAnimationInterval = nil
    }

    private func updateAnimationScheduling() {
        guard displayMode == .ball else {
            return
        }
        guard ballPresentation == .sphere,
              animationActive,
              window?.isVisible == true,
              let interval = animationFrameInterval()
        else {
            stopDisplayTimer()
            return
        }

        if displayTimer == nil || currentAnimationInterval != interval {
            startDisplayTimer(interval: interval)
        }
    }

    private func animationFrameInterval() -> TimeInterval? {
        guard let percent = snapshot.weeklyPercent else {
            return nil
        }
        if percent <= 10 {
            return fluidAnimationBoosted ? 1.0 / 12.0 : 1.0 / 8.0
        }
        if percent <= 30 {
            return fluidAnimationBoosted ? 1.0 / 10.0 : 1.0 / 6.0
        }
        return fluidAnimationBoosted ? 1.0 / 10.0 : 1.0 / 4.0
    }

    @objc private func animationTimerFired(_ timer: Timer) {
        guard ballPresentation == .sphere,
              animationActive,
              window?.isVisible == true,
              let interval = currentAnimationInterval,
              let percent = snapshot.weeklyPercent
        else {
            updateAnimationScheduling()
            return
        }

        if animationFrameInterval() != interval {
            updateAnimationScheduling()
        } else {
            let phaseSpeed: CGFloat = percent <= 10 ? 1.6 : 1.05
            animationPhase += phaseSpeed * CGFloat(interval)
            setNeedsDisplay(ballRect().insetBy(dx: -4, dy: -4))
        }
    }

    private var fluidAnimationBoosted: Bool {
        pointerIsHovering || isExpanded
    }

    private func updateLayerScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
    }

    private func updatePanelProgress() {
        let target: CGFloat = isExpanded ? 1 : 0
        panelProgress += (target - panelProgress) * 0.24
        if abs(panelProgress - target) < 0.01 {
            panelProgress = target
        }
    }

    private func ballRect() -> NSRect {
        NSRect(x: ballInset, y: (bounds.height - ballSize) / 2, width: ballSize, height: ballSize)
    }

    private func pointerIsInsideWidget() -> Bool {
        guard let window else {
            return false
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.insetBy(dx: -2, dy: -2).contains(point)
    }

    private func drawLiquidBall() {
        let rect = ballRect()
        guard let percentValue = snapshot.weeklyPercent else {
            let idleColor = NSColor(hex: 0x9EDFFF)
            drawBallShadow(in: rect, color: idleColor, pulse: 0.35)

            let sphere = NSBezierPath(ovalIn: rect)
            NSGraphicsContext.saveGraphicsState()
            sphere.addClip()
            drawGlassHighlights(in: rect)
            NSGraphicsContext.restoreGraphicsState()

            drawBallBorder(in: rect, color: idleColor, pulse: 0.35, critical: false)
            drawWeeklyAmount(in: rect, color: NSColor(hex: 0xF3FAFF))
            return
        }

        let percent = CGFloat(max(0, min(100, percentValue)) / 100)
        let liquidColor = liquidColor(for: percentValue)
        let critical = percentValue <= 10
        let warning = percentValue <= 30
        let pulse = 0.55 + 0.45 * max(0, sin(animationPhase * (critical ? 5.4 : 2.8)))

        drawBallShadow(in: rect, color: warning ? liquidColor : NSColor(hex: 0x5FC8FF), pulse: pulse)

        let sphere = NSBezierPath(ovalIn: rect)
        NSGraphicsContext.saveGraphicsState()
        sphere.addClip()
        drawLiquid(in: rect, percent: percent, color: liquidColor, pulse: pulse, critical: critical)
        drawBubbles(in: rect, color: liquidColor, percent: percent)
        drawGlassHighlights(in: rect)
        NSGraphicsContext.restoreGraphicsState()

        drawBallBorder(in: rect, color: warning ? liquidColor : NSColor(hex: 0x9EDFFF), pulse: pulse, critical: critical)
        drawWeeklyAmount(in: rect, color: warning ? .white : NSColor(hex: 0xF3FAFF))
    }

    private func drawBallShadow(in rect: NSRect, color: NSColor, pulse: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        color.withAlphaComponent(0.14 + 0.06 * pulse).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: -2, dy: -2)).fill()
        color.withAlphaComponent(0.16 + 0.08 * pulse).setStroke()
        let glow = NSBezierPath(ovalIn: rect.insetBy(dx: -3, dy: -3))
        glow.lineWidth = 2
        glow.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawLiquid(in rect: NSRect, percent: CGFloat, color: NSColor, pulse: CGFloat, critical: Bool) {
        let waterTop = rect.maxY - rect.height * max(0.02, min(0.98, percent))
        let amplitude: CGFloat = critical ? 5.4 : 3.2
        let waveA = wavePath(in: rect, waterTop: waterTop, amplitude: amplitude, phase: animationPhase * 1.7)
        let waveB = wavePath(in: rect, waterTop: waterTop + 4, amplitude: amplitude * 0.68, phase: -animationPhase * 1.35 + 1.2)

        let fillPath = waveA.copy() as! NSBezierPath
        fillPath.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        fillPath.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        fillPath.close()

        NSGraphicsContext.saveGraphicsState()
        color.withAlphaComponent(0.82).setFill()
        fillPath.fill()
        color.blended(withFraction: 0.58, of: .white)?.withAlphaComponent(0.16).setFill()
        let sheen = waveA.copy() as! NSBezierPath
        sheen.line(to: NSPoint(x: rect.maxX, y: min(rect.maxY, waterTop + rect.height * 0.18)))
        sheen.line(to: NSPoint(x: rect.minX, y: min(rect.maxY, waterTop + rect.height * 0.18)))
        sheen.close()
        sheen.fill()
        NSGraphicsContext.restoreGraphicsState()

        color.withAlphaComponent(critical ? 0.9 * pulse : 0.75).setStroke()
        waveA.lineWidth = critical ? 2.1 : 1.6
        waveA.stroke()
        color.blended(withFraction: 0.35, of: .white)?.withAlphaComponent(0.42).setStroke()
        waveB.lineWidth = 1
        waveB.stroke()
    }

    private func wavePath(in rect: NSRect, waterTop: CGFloat, amplitude: CGFloat, phase: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let steps = 28
        for index in 0...steps {
            let t = CGFloat(index) / CGFloat(steps)
            let x = rect.minX + t * rect.width
            let y = waterTop + sin(t * .pi * 2.2 + phase) * amplitude + sin(t * .pi * 4.8 + phase * 0.6) * amplitude * 0.32
            if index == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }
        return path
    }

    private func drawBubbles(in rect: NSRect, color: NSColor, percent: CGFloat) {
        let waterTop = rect.maxY - rect.height * max(0.02, min(0.98, percent))
        let bubbles: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.28, 0.82, 2.2, 0.1),
            (0.42, 0.70, 1.5, 1.0),
            (0.66, 0.78, 2.8, 1.7),
            (0.72, 0.60, 1.8, 2.6),
            (0.36, 0.55, 1.3, 3.1)
        ]

        for bubble in bubbles {
            let drift = sin(animationPhase * 1.8 + bubble.3) * 3.2
            let rise = (animationPhase * 10 + bubble.3 * 17).truncatingRemainder(dividingBy: max(18, rect.maxY - waterTop))
            let x = rect.minX + rect.width * bubble.0 + drift
            let baseY = rect.minY + rect.height * bubble.1
            let y = max(waterTop + 6, baseY - rise)
            guard y >= waterTop, y <= rect.maxY - 8 else {
                continue
            }
            color.blended(withFraction: 0.7, of: .white)?.withAlphaComponent(0.34).setStroke()
            let path = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: bubble.2 * 2, height: bubble.2 * 2))
            path.lineWidth = 0.8
            path.stroke()
        }
    }

    private func drawGlassHighlights(in rect: NSRect) {
        NSColor.white.withAlphaComponent(0.18).setStroke()
        let highlight = NSBezierPath()
        highlight.appendArc(
            withCenter: NSPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.40),
            radius: rect.width * 0.33,
            startAngle: 205,
            endAngle: 288,
            clockwise: false
        )
        highlight.lineWidth = 1.2
        highlight.stroke()
    }

    private func drawBallBorder(in rect: NSRect, color: NSColor, pulse: CGFloat, critical: Bool) {
        let path = NSBezierPath(ovalIn: rect)
        color.withAlphaComponent(critical ? 0.62 + 0.34 * pulse : 0.58).setStroke()
        path.lineWidth = critical ? 2.2 : 1.5
        path.stroke()

        NSColor.white.withAlphaComponent(0.22).setStroke()
        let inner = NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4))
        inner.lineWidth = 0.8
        inner.stroke()
    }

    private func drawWeeklyAmount(in rect: NSRect, color: NSColor) {
        let amount = Formatters.usd(snapshot.weeklyRemaining)
        drawCentered(
            amount,
            rect: NSRect(x: rect.minX + 7, y: rect.midY - 16, width: rect.width - 14, height: 22),
            font: fittedMonospacedFont(text: amount, maxSize: 16, minSize: 10.5, width: rect.width - 14),
            color: color,
            shadow: NSColor.black.withAlphaComponent(0.72)
        )

        let time = weekRemainingText()
        drawCentered(
            time,
            rect: NSRect(x: rect.minX + 10, y: rect.midY + 7, width: rect.width - 20, height: 14),
            font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
            color: color.withAlphaComponent(0.86),
            shadow: NSColor.black.withAlphaComponent(0.66)
        )
    }

    private func drawEdgeProgressBar() {
        let visualThickness: CGFloat = 8
        let rect: NSRect
        switch edgeProgressAxis {
        case .horizontal:
            rect = pixelAligned(NSRect(
                x: 5,
                y: (bounds.height - visualThickness) / 2,
                width: bounds.width - 10,
                height: visualThickness
            ))
        case .vertical:
            rect = pixelAligned(NSRect(
                x: (bounds.width - visualThickness) / 2,
                y: 5,
                width: visualThickness,
                height: bounds.height - 10
            ))
        }
        let percentValue = snapshot.weeklyPercent
        let percent = CGFloat(max(0, min(100, percentValue ?? 0)) / 100)
        let tint = quotaColor(for: percentValue)
        let radius = min(rect.width, rect.height) / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.white.withAlphaComponent(0.72).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor(hex: 0xCBD5E1, alpha: 0.82).setStroke()
        path.lineWidth = 0.6
        path.stroke()

        if percent > 0 {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let fillRect: NSRect
            switch edgeProgressAxis {
            case .horizontal:
                let fillWidth = min(rect.width, max(2, rect.width * percent))
                fillRect = NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
            case .vertical:
                let fillHeight = min(rect.height, max(2, rect.height * percent))
                fillRect = NSRect(x: rect.minX, y: rect.maxY - fillHeight, width: rect.width, height: fillHeight)
            }
            tint.withAlphaComponent(0.92).setFill()
            NSBezierPath(rect: fillRect).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func liquidColor(for percent: Double?) -> NSColor {
        quotaColor(for: percent)
    }

    private func drawExpandedPanel(progress: CGFloat) {
        let state = QuotaState(percent: snapshot.weeklyPercent)
        let height = currentPanelHeight()
        let width = currentPanelWidth()
        let panelRect = NSRect(
            x: displayMode == .panel ? 0 : ballInset + ballSize + 12 - (1 - progress) * 18,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
        let alpha = min(1, max(0, progress))

        NSGraphicsContext.saveGraphicsState()
        drawPanelShell(panelRect, state: state, alpha: alpha)
        drawStatsSummary(in: panelRect, state: state, alpha: alpha)
        drawSubscriptionCards(in: panelRect, alpha: alpha)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawPanelShell(_ rect: NSRect, state: QuotaState, alpha: CGFloat) {
        let path = angledPanelPath(rect)
        NSColor(hex: 0xF4F5F7, alpha: alpha).setFill()
        path.fill()

        NSColor.white.withAlphaComponent(0.58 * alpha).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private enum StatIcon {
        case spending
        case requests
        case tokens
        case cache
        case wallet
    }

    private enum StatCardStyle {
        case inlineTrend
        case cacheBars
        case centeredValue
    }

    private enum StatTrendKind {
        case cost
        case requests
        case tokens
    }

    private struct StatCardContent {
        let title: String
        let value: String
        let icon: StatIcon
        let tint: NSColor
        let trend: StatTrendKind?
        let style: StatCardStyle
        let showsIcon: Bool
    }

    private func drawStatsSummary(in rect: NSRect, state: QuotaState, alpha: CGFloat) {
        statsRangeButtonRects.removeAll(keepingCapacity: true)
        let content = NSRect(
            x: rect.minX + panelContentInset,
            y: rect.minY + panelContentInset,
            width: rect.width - panelContentInset * 2,
            height: statsSectionHeight()
        )
        let title = "使用统计"
        let titleFont = sectionTitleFont()
        let titleWidth = measuredWidth(title, font: titleFont) + 4
        let refreshFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let refreshWidth = measuredWidth("刷新时间：00:00:00", font: refreshFont) + 6
        let rangeWidth = statsRangeButtonsWidth()
        let rangeStartX = content.maxX - rangeWidth
        let refreshX = content.minX + titleWidth + 14
        let availableRefreshWidth = max(88, rangeStartX - refreshX - 12)
        let refreshRect = NSRect(
            x: refreshX,
            y: content.minY + 5,
            width: min(refreshWidth, availableRefreshWidth),
            height: 14
        )
        drawStatsRangeButtons(
            in: content,
            startX: rangeStartX,
            maxX: content.maxX,
            alpha: alpha
        )
        drawText(
            title,
            rect: NSRect(x: content.minX + 2, y: content.minY + 2, width: titleWidth, height: 18),
            font: titleFont,
            color: NSColor(hex: 0x0A2540).withAlphaComponent(alpha)
        )
        drawText(
            "刷新时间：\(Formatters.time(snapshot.lastRefresh))",
            rect: refreshRect,
            font: refreshFont,
            color: NSColor(hex: 0x94A3B8).withAlphaComponent(alpha),
            alignment: .left
        )
        drawStatsStatus(in: content, refreshRect: refreshRect, rangeStartX: rangeStartX, alpha: alpha)

        let cards = [
            StatCardContent(
                title: "花费",
                value: Formatters.usd(snapshot.todayCost),
                icon: .spending,
                tint: NSColor(hex: 0x1A56DB),
                trend: .cost,
                style: .inlineTrend,
                showsIcon: true
            ),
            StatCardContent(
                title: "请求数",
                value: Formatters.integer(snapshot.requestCount),
                icon: .requests,
                tint: NSColor(hex: 0x7C3AED),
                trend: .requests,
                style: .inlineTrend,
                showsIcon: true
            ),
            StatCardContent(
                title: "Tokens",
                value: Formatters.compactInteger(snapshot.totalTokens),
                icon: .tokens,
                tint: NSColor(hex: 0xEA580C),
                trend: .tokens,
                style: .inlineTrend,
                showsIcon: true
            ),
            StatCardContent(
                title: "缓存率",
                value: "",
                icon: .cache,
                tint: NSColor(hex: 0x0D9F6E),
                trend: nil,
                style: .cacheBars,
                showsIcon: true
            ),
            StatCardContent(
                title: "钱包余额",
                value: Formatters.usd(snapshot.walletBalance),
                icon: .wallet,
                tint: NSColor(hex: 0x64748B),
                trend: nil,
                style: .centeredValue,
                showsIcon: true
            )
        ]

        let itemGap: CGFloat = 8
        let cardHeight = statsCardHeight()
        let cardY = content.minY + statsHeaderHeight
        let itemWidth: CGFloat = (content.width - itemGap * CGFloat(cards.count - 1)) / CGFloat(cards.count)
        for (index, item) in cards.enumerated() {
            let x = content.minX + CGFloat(index) * (itemWidth + itemGap)
            drawStatCard(
                item,
                rect: NSRect(x: x, y: cardY, width: itemWidth, height: cardHeight),
                alpha: alpha
            )
        }

        let line = NSBezierPath()
        line.move(to: NSPoint(x: content.minX, y: content.maxY - 1))
        line.line(to: NSPoint(x: content.maxX, y: content.maxY - 1))
        line.lineWidth = 1
        NSColor(hex: 0xDDE3EB, alpha: alpha).setStroke()
        line.stroke()
    }

    private func drawStatCard(
        _ content: StatCardContent,
        rect: NSRect,
        alpha: CGFloat
    ) {
        let card = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        statCardBackgroundColor(alpha: alpha).setFill()
        card.fill()
        statCardBorderColor(alpha: alpha).setStroke()
        card.lineWidth = 0.8
        card.stroke()

        let titleFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let iconRect: NSRect?
        switch content.style {
        case .inlineTrend:
            let titleWidth = measuredWidth(content.title, font: titleFont)
            let headerWidth = min(rect.width - 12, 22 + 6 + titleWidth)
            iconRect = content.showsIcon ? NSRect(x: rect.midX - headerWidth / 2, y: rect.minY + 9, width: 22, height: 22) : nil
        case .cacheBars, .centeredValue:
            let titleWidth = measuredWidth(content.title, font: titleFont)
            let headerWidth = min(rect.width - 12, 22 + 6 + titleWidth)
            iconRect = content.showsIcon ? NSRect(x: rect.midX - headerWidth / 2, y: rect.minY + 9, width: 22, height: 22) : nil
        }

        let titleRect: NSRect
        let valueRect: NSRect
        switch content.style {
        case .inlineTrend:
            let titleWidth = measuredWidth(content.title, font: titleFont) + 2
            let titleX = iconRect.map { $0.maxX + 6 } ?? rect.midX - titleWidth / 2
            titleRect = NSRect(
                x: titleX,
                y: rect.minY + 13,
                width: titleWidth,
                height: 14
            )
            valueRect = NSRect(
                x: rect.minX + 8,
                y: rect.maxY - 24,
                width: rect.width - 16,
                height: 17
            )
        case .cacheBars:
            let titleWidth = measuredWidth(content.title, font: titleFont) + 2
            let titleX = iconRect.map { $0.maxX + 6 } ?? rect.midX - titleWidth / 2
            titleRect = NSRect(x: titleX, y: rect.minY + 13, width: titleWidth, height: 14)
            valueRect = NSRect(x: rect.minX + 6, y: rect.minY + 43, width: rect.width - 12, height: 22)
        case .centeredValue:
            let titleWidth = measuredWidth(content.title, font: titleFont) + 2
            let titleX = iconRect.map { $0.maxX + 6 } ?? rect.midX - titleWidth / 2
            let lowerTop = rect.minY + 36
            let valueHeight: CGFloat = 22
            let lowerHeight = max(valueHeight, rect.maxY - lowerTop - 8)
            titleRect = NSRect(x: titleX, y: rect.minY + 13, width: titleWidth, height: 14)
            valueRect = NSRect(
                x: rect.minX + 6,
                y: lowerTop + (lowerHeight - valueHeight) / 2,
                width: rect.width - 12,
                height: valueHeight
            )
        }

        if let iconRect {
            content.tint.blended(withFraction: 0.90, of: .white)?.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: iconRect, xRadius: 5, yRadius: 5).fill()
            let iconInset = min(4.8, iconRect.width * 0.22)
            drawStatIcon(content.icon, in: iconRect.insetBy(dx: iconInset, dy: iconInset), tint: content.tint, alpha: alpha)
        }

        drawText(
            content.title,
            rect: titleRect,
            font: titleFont,
            color: NSColor(hex: 0x64748B).withAlphaComponent(alpha),
            alignment: .left
        )

        switch content.style {
        case .inlineTrend:
            if let trend = content.trend {
                drawSparkline(
                    trend: trend,
                    rect: sparklineRect(in: rect),
                    tint: content.tint,
                    alpha: alpha
                )
            }
            drawText(
                content.value,
                rect: valueRect,
                font: fittedMonospacedFont(text: content.value, maxSize: 12.8, minSize: 9.8, width: valueRect.width, weight: .bold),
                color: NSColor(hex: 0x0A2540).withAlphaComponent(alpha),
                alignment: .center
            )
        case .cacheBars:
            drawCacheRateBars(in: rect.insetBy(dx: 8, dy: 8), tint: content.tint, alpha: alpha)
        case .centeredValue:
            drawText(
                content.value,
                rect: valueRect,
                font: fittedMonospacedFont(text: content.value, maxSize: 16.2, minSize: 12.0, width: valueRect.width, weight: .semibold),
                color: NSColor(hex: 0x0A2540).withAlphaComponent(alpha),
                alignment: .center
            )
        }
        drawStatCardOverlayIfNeeded(in: rect, alpha: alpha)
    }

    private func drawStatsStatus(in content: NSRect, refreshRect: NSRect, rangeStartX: CGFloat, alpha: CGFloat) {
        let status: (text: String, color: NSColor)?
        if snapshot.isLoading {
            status = ("更新中", NSColor(hex: 0x1A56DB))
        } else if snapshot.lastError != nil {
            status = ("获取失败", NSColor(hex: 0xE02D3C))
        } else {
            status = nil
        }

        guard let status else {
            return
        }

        let font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        let width = min(56, max(44, measuredWidth(status.text, font: font) + 16))
        let rect = NSRect(
            x: min(refreshRect.maxX + 8, rangeStartX - width - 8),
            y: content.minY + 1,
            width: width,
            height: 20
        )
        guard rect.minX > refreshRect.minX else {
            return
        }

        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        status.color.withAlphaComponent(0.10 * alpha).setFill()
        path.fill()
        status.color.withAlphaComponent(0.30 * alpha).setStroke()
        path.lineWidth = 0.7
        path.stroke()
        drawText(
            status.text,
            rect: NSRect(x: rect.minX + 4, y: rect.minY + 5, width: rect.width - 8, height: 11),
            font: font,
            color: status.color.withAlphaComponent(alpha),
            alignment: .center
        )
    }

    private func statCardBackgroundColor(alpha: CGFloat) -> NSColor {
        if snapshot.isLoading {
            return NSColor(hex: 0xF6FAFF, alpha: alpha)
        }
        if snapshot.lastError != nil {
            return NSColor(hex: 0xFFF8F8, alpha: alpha)
        }
        return NSColor.white.withAlphaComponent(alpha)
    }

    private func statCardBorderColor(alpha: CGFloat) -> NSColor {
        if snapshot.isLoading {
            return NSColor(hex: 0xBBD4FF, alpha: 0.9 * alpha)
        }
        if snapshot.lastError != nil {
            return NSColor(hex: 0xF3B9BE, alpha: 0.9 * alpha)
        }
        return NSColor(hex: 0xE5EAF0, alpha: alpha)
    }

    private func drawStatCardOverlayIfNeeded(in rect: NSRect, alpha: CGFloat) {
        let text: String
        let color: NSColor
        if snapshot.isLoading {
            text = "更新中"
            color = NSColor(hex: 0x1A56DB)
        } else if snapshot.lastError != nil {
            text = "获取失败"
            color = NSColor(hex: 0xE02D3C)
        } else {
            return
        }

        drawText(
            text,
            rect: NSRect(x: rect.minX + 10, y: rect.maxY - 20, width: rect.width - 20, height: 12),
            font: .systemFont(ofSize: 10.5, weight: .semibold),
            color: color.withAlphaComponent(0.78 * alpha),
            alignment: .center
        )
    }

    private func drawStatsRangeButtons(in rect: NSRect, startX: CGFloat, maxX: CGFloat, alpha: CGFloat) {
        let ranges = StatsRange.allCases
        let font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        let gap: CGFloat = 4
        let widths = statsRangeButtonWidths(font: font)
        let totalWidth = statsRangeButtonsWidth(widths: widths, gap: gap)
        var x = min(startX, maxX - totalWidth)
        let y = rect.minY

        for (index, range) in ranges.enumerated() {
            let width = widths[index]
            let buttonRect = NSRect(x: x, y: y, width: width, height: 22)
            let enabled = snapshot.availableStatsRanges.contains(range)
            let selected = snapshot.statsRange == range
            let background: NSColor
            let foreground: NSColor
            let border: NSColor

            if selected {
                background = NSColor(hex: 0x1A56DB, alpha: 0.92 * alpha)
                foreground = NSColor.white.withAlphaComponent(alpha)
                border = NSColor(hex: 0x1A56DB, alpha: alpha)
            } else if enabled {
                background = NSColor.white.withAlphaComponent(0.88 * alpha)
                foreground = NSColor(hex: 0x475569).withAlphaComponent(alpha)
                border = NSColor(hex: 0xD8E0EA, alpha: alpha)
            } else {
                background = NSColor(hex: 0xE8EEF5, alpha: 0.55 * alpha)
                foreground = NSColor(hex: 0xA3AFBD).withAlphaComponent(0.72 * alpha)
                border = NSColor(hex: 0xD8E0EA, alpha: 0.45 * alpha)
            }

            let path = NSBezierPath(roundedRect: buttonRect, xRadius: 7, yRadius: 7)
            background.setFill()
            path.fill()
            border.setStroke()
            path.lineWidth = 0.7
            path.stroke()
            drawText(
                range.title,
                rect: NSRect(x: buttonRect.minX + 3, y: buttonRect.minY + 5, width: buttonRect.width - 6, height: 12),
                font: font,
                color: foreground,
                alignment: .center
            )

            statsRangeButtonRects.append((range, buttonRect))
            x += width + gap
        }
    }

    private func drawSparkline(trend: StatTrendKind, rect: NSRect, tint: NSColor, alpha: CGFloat) {
        let cleanValues = snapshot.trend.compactMap { point -> Double? in
            switch trend {
            case .cost:
                return point.cost?.isFinite == true ? point.cost : nil
            case .requests:
                return point.requestCount.map(Double.init)
            case .tokens:
                return point.tokens.map(Double.init)
            }
        }

        guard cleanValues.count >= 2 else {
            return
        }

        guard let minValue = cleanValues.min(),
              let maxValue = cleanValues.max()
        else {
            return
        }

        let plotRect = rect.insetBy(dx: 0, dy: 3)
        let valueRange = max(maxValue - minValue, 0.000_001)
        let stepX = cleanValues.count == 1 ? 0 : plotRect.width / CGFloat(cleanValues.count - 1)
        let path = NSBezierPath()

        for (index, value) in cleanValues.enumerated() {
            let normalized = CGFloat((value - minValue) / valueRange)
            let point = NSPoint(
                x: plotRect.minX + CGFloat(index) * stepX,
                y: plotRect.maxY - normalized * plotRect.height
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }

        tint.withAlphaComponent(0.88 * alpha).setStroke()
        path.lineWidth = 1.6
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
    }

    private func sparklineRect(in rect: NSRect) -> NSRect {
        let top = rect.minY + 36
        let bottomPadding: CGFloat = 30
        let availableHeight = max(18, rect.maxY - top - bottomPadding)
        let height = snapshot.cacheRates.count <= 1
            ? min(34, availableHeight)
            : availableHeight
        return NSRect(
            x: rect.minX + 9,
            y: top,
            width: rect.width - 18,
            height: height
        )
    }

    private func drawCacheRateBars(in rect: NSRect, tint: NSColor, alpha: CGFloat) {
        guard snapshot.cacheRates.isEmpty == false else {
            drawText(
                "--",
                rect: NSRect(x: rect.minX, y: rect.minY + 38, width: rect.width, height: 14),
                font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                color: NSColor(hex: 0x0F172A).withAlphaComponent(alpha),
                alignment: .center
            )
            return
        }

        let rates = snapshot.cacheRates
        let contentY = rect.minY + 32
        let contentHeight = max(18, rect.maxY - contentY - 2)
        let lineHeight = max(8.5, min(18, contentHeight / CGFloat(rates.count)))
        let labelFontSize = max(5.8, min(8.0, lineHeight * 0.42))
        let labelFont = NSFont.systemFont(ofSize: labelFontSize, weight: .medium)
        let barHeight = max(2.8, min(5.2, lineHeight * 0.34))
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: max(7.0, min(9.0, lineHeight * 0.46)), weight: .semibold)
        let valueWidth = max(28, measuredWidth("100%", font: valueFont) + 2)
        let barWidth = max(20, rect.width - valueWidth - 7)
        var y = contentY + max(0, (contentHeight - lineHeight * CGFloat(rates.count)) / 2)

        for (index, rate) in rates.enumerated() {
            let percent = max(0, min(100, rate.percent))
            let barTint = cacheRateColor(index: index)
            let rowRect = NSRect(x: rect.minX, y: y, width: rect.width, height: lineHeight)
            let labelHeight = max(6.2, min(8.8, lineHeight * 0.48))
            let labelRect = NSRect(
                x: rowRect.minX,
                y: rowRect.minY,
                width: barWidth,
                height: labelHeight
            )
            drawText(
                rate.name,
                rect: labelRect,
                font: fittedSystemFont(text: rate.name, maxSize: labelFont.pointSize, minSize: 5.4, width: labelRect.width, weight: .medium),
                color: NSColor(hex: 0x64748B).withAlphaComponent(alpha),
                alignment: .left
            )

            let trackY = min(rowRect.maxY - barHeight, labelRect.maxY + max(1, (rowRect.height - labelHeight - barHeight) / 2))
            let track = pixelAligned(NSRect(
                x: rect.minX,
                y: trackY,
                width: barWidth,
                height: barHeight
            ))
            let trackPath = NSBezierPath(roundedRect: track, xRadius: barHeight / 2, yRadius: barHeight / 2)
            NSColor(hex: 0xE8EEF5, alpha: alpha).setFill()
            trackPath.fill()

            if percent > 0 {
                NSGraphicsContext.saveGraphicsState()
                trackPath.addClip()
                barTint.withAlphaComponent(0.88 * alpha).setFill()
                NSBezierPath(rect: NSRect(
                    x: track.minX,
                    y: track.minY,
                    width: track.width * CGFloat(percent / 100),
                    height: track.height
                )).fill()
                NSGraphicsContext.restoreGraphicsState()
            }

            let valueRect = NSRect(x: track.maxX + 6, y: track.midY - 5, width: valueWidth, height: 10)
            drawText(
                String(format: "%.0f%%", percent),
                rect: valueRect,
                font: valueFont,
                color: NSColor(hex: 0x0F172A).withAlphaComponent(alpha),
                alignment: .right
            )
            y += lineHeight
        }
    }

    private func cacheRateColor(index: Int) -> NSColor {
        let palette = [
            NSColor(hex: 0x0D9F6E),
            NSColor(hex: 0x1A56DB),
            NSColor(hex: 0x7C3AED),
            NSColor(hex: 0xEA580C),
            NSColor(hex: 0x0891B2),
            NSColor(hex: 0xD97706)
        ]
        return palette[index % palette.count]
    }

    private func drawStatIcon(_ icon: StatIcon, in rect: NSRect, tint: NSColor, alpha: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        tint.withAlphaComponent(alpha).setStroke()
        tint.withAlphaComponent(alpha).setFill()

        switch icon {
        case .spending:
            let receipt = NSBezierPath(roundedRect: rect.insetBy(dx: 2.1, dy: 1.2), xRadius: 1.8, yRadius: 1.8)
            receipt.lineWidth = 1.25
            receipt.stroke()

            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX + 4.5, y: rect.minY + 4.7))
            path.line(to: NSPoint(x: rect.maxX - 4.5, y: rect.minY + 4.7))
            path.move(to: NSPoint(x: rect.minX + 4.5, y: rect.midY))
            path.line(to: NSPoint(x: rect.maxX - 5.6, y: rect.midY))
            path.move(to: NSPoint(x: rect.minX + 4.5, y: rect.maxY - 4.7))
            path.line(to: NSPoint(x: rect.maxX - 7.0, y: rect.maxY - 4.7))
            path.lineWidth = 1.15
            path.stroke()
        case .requests:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX + 3.0, y: rect.midY))
            path.line(to: NSPoint(x: rect.maxX - 3.4, y: rect.midY))
            path.move(to: NSPoint(x: rect.maxX - 6.3, y: rect.midY - 3.0))
            path.line(to: NSPoint(x: rect.maxX - 3.2, y: rect.midY))
            path.line(to: NSPoint(x: rect.maxX - 6.3, y: rect.midY + 3.0))
            path.move(to: NSPoint(x: rect.minX + 3.2, y: rect.minY + 3.0))
            path.line(to: NSPoint(x: rect.minX + 6.4, y: rect.minY + 3.0))
            path.move(to: NSPoint(x: rect.minX + 3.2, y: rect.maxY - 3.0))
            path.line(to: NSPoint(x: rect.minX + 6.4, y: rect.maxY - 3.0))
            path.lineWidth = 1.35
            path.stroke()
        case .tokens:
            let chip = NSBezierPath(roundedRect: rect.insetBy(dx: 2.0, dy: 2.0), xRadius: 2.6, yRadius: 2.6)
            chip.lineWidth = 1.25
            chip.stroke()

            let pins = NSBezierPath()
            let pinYs = [rect.minY + rect.height * 0.36, rect.minY + rect.height * 0.64]
            for y in pinYs {
                pins.move(to: NSPoint(x: rect.minX + 0.9, y: y))
                pins.line(to: NSPoint(x: rect.minX + 2.6, y: y))
                pins.move(to: NSPoint(x: rect.maxX - 2.6, y: y))
                pins.line(to: NSPoint(x: rect.maxX - 0.9, y: y))
            }
            pins.lineWidth = 1.0
            pins.stroke()

            let tokenMark = NSBezierPath()
            tokenMark.move(to: NSPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.38))
            tokenMark.line(to: NSPoint(x: rect.maxX - rect.width * 0.32, y: rect.minY + rect.height * 0.38))
            tokenMark.move(to: NSPoint(x: rect.midX, y: rect.minY + rect.height * 0.38))
            tokenMark.line(to: NSPoint(x: rect.midX, y: rect.maxY - rect.height * 0.30))
            tokenMark.lineWidth = 1.35
            tokenMark.lineCapStyle = .round
            tokenMark.stroke()
        case .cache:
            let top = NSBezierPath()
            top.move(to: NSPoint(x: rect.midX, y: rect.minY + 1.2))
            top.line(to: NSPoint(x: rect.maxX - 1.4, y: rect.minY + 4.4))
            top.line(to: NSPoint(x: rect.midX, y: rect.minY + 7.6))
            top.line(to: NSPoint(x: rect.minX + 1.4, y: rect.minY + 4.4))
            top.close()
            top.lineWidth = 1.2
            top.stroke()

            let mid = NSBezierPath()
            mid.move(to: NSPoint(x: rect.minX + 1.4, y: rect.midY + 0.6))
            mid.line(to: NSPoint(x: rect.midX, y: rect.midY + 3.8))
            mid.line(to: NSPoint(x: rect.maxX - 1.4, y: rect.midY + 0.6))
            mid.lineWidth = 1.2
            mid.stroke()

            let bottom = NSBezierPath()
            bottom.move(to: NSPoint(x: rect.minX + 1.4, y: rect.maxY - 3.0))
            bottom.line(to: NSPoint(x: rect.midX, y: rect.maxY - 0.3))
            bottom.line(to: NSPoint(x: rect.maxX - 1.4, y: rect.maxY - 3.0))
            bottom.lineWidth = 1.2
            bottom.stroke()
        case .wallet:
            let wallet = NSBezierPath(roundedRect: rect.insetBy(dx: 1.2, dy: 2.8), xRadius: 2.1, yRadius: 2.1)
            wallet.lineWidth = 1.35
            wallet.stroke()
            let seam = NSBezierPath()
            seam.move(to: NSPoint(x: rect.minX + 1.6, y: rect.midY - 0.8))
            seam.line(to: NSPoint(x: rect.maxX - 1.6, y: rect.midY - 0.8))
            seam.lineWidth = 1.2
            seam.stroke()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - 4.1, y: rect.midY + 1.0, width: 2.2, height: 2.2)).fill()
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSubscriptionCards(in rect: NSRect, alpha: CGFloat) {
        let listTop = rect.minY + panelListTopOffset()
        let titleY = listTop - 26
        drawText(
            "生效套餐",
            rect: NSRect(x: rect.minX + panelContentInset + 2, y: titleY, width: 120, height: 16),
            font: sectionTitleFont(),
            color: NSColor(hex: 0x0A2540).withAlphaComponent(alpha)
        )

        let listRect = NSRect(
            x: rect.minX + panelContentInset,
            y: listTop,
            width: rect.width - panelContentInset * 2,
            height: rect.maxY - listTop - panelBottomPadding
        )
        let items = snapshot.subscriptions
        guard items.isEmpty == false else {
            drawCentered(
                snapshot.needsToken ? "请先在菜单栏设置 Krill Token" : "暂无生效套餐",
                rect: listRect,
                font: .systemFont(ofSize: 12.6, weight: .medium),
                color: NSColor(hex: 0x64748B).withAlphaComponent(alpha)
            )
            return
        }

        var y = listRect.minY
        for item in items {
            let cardHeight = subscriptionCardHeight(item)
            drawSubscriptionCard(item, in: NSRect(x: listRect.minX, y: y, width: listRect.width, height: cardHeight), alpha: alpha)
            y += cardHeight + panelCardGap
        }
    }

    private func drawSubscriptionCard(_ item: SubscriptionDisplayItem, in rect: NSRect, alpha: CGFloat) {
        let hasWeeklyQuota = item.weeklyTotal != nil

        let card = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.white.withAlphaComponent(alpha).setFill()
        card.fill()
        NSColor(hex: 0xE5EAF0, alpha: alpha).setStroke()
        card.lineWidth = 0.8
        card.stroke()

        let body = rect.insetBy(dx: 16, dy: 14)
        let topY = body.minY
        let periodText = "\(Formatters.dateTime(item.start)) ~ \(Formatters.dateTime(item.expiry))"
        let periodFont = NSFont.monospacedDigitSystemFont(ofSize: 11.4, weight: .regular)
        let periodWidth = min(body.width * 0.68, measuredWidth(periodText, font: periodFont) + 2)
        let nameWidth = max(80, body.width - periodWidth - 14)
        let expiryStyle = expiryPillStyle(until: item.expiry, alpha: alpha)

        drawText(
            item.name,
            rect: NSRect(x: body.minX, y: topY, width: nameWidth, height: 18),
            font: .systemFont(ofSize: 15, weight: .medium),
            color: NSColor(hex: 0x0A2540).withAlphaComponent(alpha)
        )
        drawText(
            periodText,
            rect: NSRect(x: body.maxX - periodWidth, y: topY + 2, width: periodWidth, height: 15),
            font: periodFont,
            color: NSColor(hex: 0xA3AFBD).withAlphaComponent(alpha),
            alignment: .right
        )

        let totalPercent = quotaPercent(remaining: item.monthlyRemaining, total: item.monthlyTotal)
        let firstQuotaY = topY + 31
        if hasWeeklyQuota {
            drawQuotaProgressRow(
                label: "本周额度",
                remaining: item.weeklyRemaining,
                total: item.weeklyTotal,
                detail: remainingText(until: item.weekEnd, wrapped: false),
                rect: NSRect(x: body.minX, y: firstQuotaY, width: body.width, height: 25),
                tint: quotaColor(for: item.weeklyPercent),
                alpha: alpha,
                showStableDetail: true
            )

            drawQuotaProgressRow(
                label: "月额度",
                remaining: item.monthlyRemaining,
                total: item.monthlyTotal,
                detail: nil,
                rect: NSRect(x: body.minX, y: firstQuotaY + 44, width: body.width, height: 25),
                tint: quotaColor(for: totalPercent),
                alpha: alpha,
                showStableDetail: false
            )
        } else {
            drawQuotaProgressRow(
                label: "总额度",
                remaining: item.monthlyRemaining,
                total: item.monthlyTotal,
                detail: nil,
                rect: NSRect(x: body.minX, y: firstQuotaY, width: body.width, height: 25),
                tint: quotaColor(for: totalPercent),
                alpha: alpha,
                showStableDetail: false
            )
        }

        let footerY = rect.maxY - 34
        let line = NSBezierPath()
        line.move(to: NSPoint(x: body.minX, y: footerY - 8))
        line.line(to: NSPoint(x: body.maxX, y: footerY - 8))
        line.lineWidth = 0.8
        NSColor(hex: 0xE5EAF0, alpha: alpha).setStroke()
        line.stroke()

        let remaining = remainingText(until: item.expiry, wrapped: false)
        let pillWidth = min(max(measuredWidth(remaining, font: expiryStyle.font) + 36, 114), 176)
        let pillRect = NSRect(x: body.maxX - pillWidth, y: footerY, width: pillWidth, height: 22)
        let remainingPill = NSBezierPath(roundedRect: pillRect, xRadius: 11, yRadius: 11)
        expiryStyle.background.setFill()
        remainingPill.fill()
        expiryStyle.border.setStroke()
        remainingPill.lineWidth = 0.7
        remainingPill.stroke()
        drawClockIcon(
            in: NSRect(x: pillRect.minX + 9, y: pillRect.minY + 5.5, width: 11, height: 11),
            color: expiryStyle.foreground
        )
        drawText(
            remaining,
            rect: NSRect(x: pillRect.minX + 24, y: pillRect.minY + 4, width: pillRect.width - 32, height: 14),
            font: expiryStyle.font,
            color: expiryStyle.foreground,
            alignment: .center
        )
    }

    private struct ExpiryPillStyle {
        let foreground: NSColor
        let background: NSColor
        let border: NSColor
        let font: NSFont
    }

    private func expiryPillStyle(until date: Date?, alpha: CGFloat) -> ExpiryPillStyle {
        guard let date else {
            let neutral = NSColor(hex: 0x64748B)
            return ExpiryPillStyle(
                foreground: neutral.withAlphaComponent(alpha),
                background: NSColor(hex: 0xF1F5F9, alpha: 0.82 * alpha),
                border: NSColor(hex: 0xCBD5E1, alpha: 0.35 * alpha),
                font: .systemFont(ofSize: 10.8, weight: .semibold)
            )
        }

        let seconds = max(0, date.timeIntervalSince(Date()))
        if seconds <= 6 * 3_600 {
            return ExpiryPillStyle(
                foreground: NSColor(hex: 0xDC2626).withAlphaComponent(alpha),
                background: NSColor(hex: 0xFEE2E2, alpha: 0.92 * alpha),
                border: NSColor(hex: 0xFCA5A5, alpha: 0.55 * alpha),
                font: .systemFont(ofSize: 12.0, weight: .bold)
            )
        }

        if seconds <= 24 * 3_600 {
            return ExpiryPillStyle(
                foreground: NSColor(hex: 0xEA580C).withAlphaComponent(alpha),
                background: NSColor(hex: 0xFFEDD5, alpha: 0.90 * alpha),
                border: NSColor(hex: 0xFDBA74, alpha: 0.48 * alpha),
                font: .systemFont(ofSize: 11.7, weight: .bold)
            )
        }

        if seconds <= 3 * 86_400 {
            return ExpiryPillStyle(
                foreground: NSColor(hex: 0xB45309).withAlphaComponent(alpha),
                background: NSColor(hex: 0xFEF3C7, alpha: 0.88 * alpha),
                border: NSColor(hex: 0xFDE68A, alpha: 0.46 * alpha),
                font: .systemFont(ofSize: 11.4, weight: .semibold)
            )
        }

        let calm = NSColor(hex: 0x1A56DB)
        return ExpiryPillStyle(
            foreground: calm.withAlphaComponent(alpha),
            background: calm.blended(withFraction: 0.91, of: .white)?.withAlphaComponent(0.74 * alpha) ?? NSColor.white.withAlphaComponent(alpha),
            border: calm.withAlphaComponent(0.16 * alpha),
            font: .systemFont(ofSize: 11.2, weight: .semibold)
        )
    }

    private func drawQuotaProgressRow(
        label: String,
        remaining: Double?,
        total: Double?,
        detail: String?,
        rect: NSRect,
        tint: NSColor,
        alpha: CGFloat,
        showStableDetail: Bool
    ) {
        let labelFont = NSFont.systemFont(ofSize: 10.8, weight: .medium)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.8, weight: .medium)
        let detailFont = NSFont.monospacedDigitSystemFont(ofSize: 9.2, weight: .medium)
        let labelWidth = min(rect.width * 0.28, measuredWidth(label, font: labelFont) + 8)
        let value = "剩余 \(Formatters.usd(remaining)) / \(Formatters.usd(total))"

        drawText(
            label,
            rect: NSRect(x: rect.minX, y: rect.minY, width: labelWidth, height: 14),
            font: labelFont,
            color: NSColor(hex: 0x475569).withAlphaComponent(alpha)
        )

        if let detail, detail.isEmpty == false {
            let detailWidth = min(140, measuredWidth(detail, font: detailFont) + 34)
            let detailRect = NSRect(x: rect.minX + labelWidth, y: rect.minY - 1, width: detailWidth, height: 16)
            let detailTint = NSColor(hex: 0x1A56DB)
            let pill = NSBezierPath(roundedRect: detailRect, xRadius: 8, yRadius: 8)
            detailTint.blended(withFraction: 0.90, of: .white)?
                .withAlphaComponent(0.78 * alpha)
                .setFill()
            pill.fill()
            detailTint.withAlphaComponent((showStableDetail ? 0.16 : 0.10) * alpha).setStroke()
            pill.lineWidth = 0.6
            pill.stroke()
            drawClockIcon(
                in: NSRect(x: detailRect.minX + 8, y: detailRect.minY + 3, width: 10, height: 10),
                color: detailTint.withAlphaComponent(alpha)
            )
            drawText(
                detail,
                rect: NSRect(x: detailRect.minX + 23, y: detailRect.minY + 2, width: detailRect.width - 29, height: 12),
                font: detailFont,
                color: detailTint.withAlphaComponent(alpha)
            )
        }

        drawText(
            value,
            rect: NSRect(x: rect.minX + labelWidth, y: rect.minY, width: rect.width - labelWidth, height: 14),
            font: valueFont,
            color: NSColor(hex: 0x0F172A).withAlphaComponent(alpha),
            alignment: .right
        )

        let track = pixelAligned(NSRect(x: rect.minX, y: rect.minY + 18, width: rect.width, height: 5))
        let trackPath = NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5)
        NSColor(hex: 0xE8EEF5, alpha: alpha).setFill()
        trackPath.fill()

        let percent = CGFloat(max(0, min(100, quotaPercent(remaining: remaining, total: total) ?? 0)) / 100)
        guard percent > 0 else {
            return
        }

        NSGraphicsContext.saveGraphicsState()
        trackPath.addClip()
        let fillWidth = min(track.width, max(0, track.width * percent))
        let fill = NSRect(x: track.minX, y: track.minY, width: fillWidth, height: track.height)
        tint.withAlphaComponent(0.94 * alpha).setFill()
        NSBezierPath(rect: fill).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawClockIcon(in rect: NSRect, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        color.setStroke()
        let circle = NSBezierPath(ovalIn: rect)
        circle.lineWidth = 1.2
        circle.stroke()

        let hands = NSBezierPath()
        hands.move(to: NSPoint(x: rect.midX, y: rect.minY + rect.height * 0.28))
        hands.line(to: NSPoint(x: rect.midX, y: rect.midY))
        hands.line(to: NSPoint(x: rect.midX + rect.width * 0.24, y: rect.midY + rect.height * 0.15))
        hands.lineWidth = 1.2
        hands.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func quotaPercent(remaining: Double?, total: Double?) -> Double? {
        guard let remaining, let total, total > 0, remaining.isFinite, total.isFinite else {
            return nil
        }
        return max(0, min(100, remaining / total * 100))
    }

    private func quotaColor(for percent: Double?) -> NSColor {
        guard let percent else {
            return NSColor(hex: 0x94A3B8)
        }
        if percent > 60 {
            return NSColor(hex: 0x1A56DB)
        }
        if percent > 30 {
            return NSColor(hex: 0x0D9F6E)
        }
        if percent > 10 {
            return NSColor(hex: 0xD97706)
        }
        return NSColor(hex: 0xE02D3C)
    }

    private func sectionTitleFont() -> NSFont {
        .systemFont(ofSize: 14, weight: .medium)
    }

    private func remainingText(until date: Date?, wrapped: Bool = true) -> String {
        guard let date else {
            return wrapped ? "(剩余--)" : "剩余--"
        }
        let text = durationText(seconds: max(0, date.timeIntervalSince(Date())))
        return wrapped ? "(剩余\(text))" : "剩余\(text)"
    }

    private func weekRemainingText() -> String {
        guard let weekEnd = snapshot.weekEnd else {
            return "--"
        }
        return durationText(seconds: max(0, weekEnd.timeIntervalSince(Date())))
    }

    private func durationText(seconds: TimeInterval) -> String {
        if seconds <= 0 {
            return "0分"
        }
        if seconds >= 86_400 {
            let days = Int(seconds / 86_400)
            var hours = Int(ceil((seconds - Double(days) * 86_400) / 3_600))
            var normalizedDays = days
            if hours >= 24 {
                normalizedDays += 1
                hours = 0
            }
            return "\(normalizedDays)天\(hours)时"
        }
        if seconds >= 3_600 {
            let hours = Int(seconds / 3_600)
            var minutes = Int(ceil((seconds - Double(hours) * 3_600) / 60))
            var normalizedHours = hours
            if minutes >= 60 {
                normalizedHours += 1
                minutes = 0
            }
            return "\(normalizedHours)时\(minutes)分"
        }
        return "\(max(1, Int(ceil(seconds / 60))))分"
    }

    private func preferredPanelHeight() -> CGFloat {
        let cardStackHeight: CGFloat
        if snapshot.subscriptions.isEmpty {
            cardStackHeight = 68
        } else {
            cardStackHeight = snapshot.subscriptions.map(subscriptionCardHeight).reduce(0, +)
                + CGFloat(max(0, snapshot.subscriptions.count - 1)) * panelCardGap
        }
        return max(212, panelListTopOffset() + cardStackHeight + panelBottomPadding)
    }

    private func subscriptionCardHeight(_ item: SubscriptionDisplayItem) -> CGFloat {
        item.weeklyTotal == nil ? panelTotalCardHeight : panelWeeklyCardHeight
    }

    private func currentPanelHeight() -> CGFloat {
        min(preferredPanelHeight(), max(180, bounds.height - 12))
    }

    private func panelListTopOffset() -> CGFloat {
        panelContentInset + statsSectionHeight() + 36
    }

    private func statsSectionHeight() -> CGFloat {
        statsHeaderHeight + statsCardHeight() + 16
    }

    private func statsCardHeight() -> CGFloat {
        let channelCount = max(1, snapshot.cacheRates.count)
        if channelCount == 1 {
            return 86
        }
        return min(168, max(96, 64 + CGFloat(channelCount) * 14))
    }

    private func preferredPanelWidth(maxWidth: CGFloat? = nil) -> CGFloat {
        let calculatedWidth = max(panelMinWidth, preferredSubscriptionContentWidth(), preferredStatsContentWidth())
        let availableWidth = maxWidth.map { max(panelCompactMinWidth, $0) } ?? panelMaxWidth
        return min(calculatedWidth, min(panelMaxWidth, availableWidth))
    }

    private func currentPanelWidth() -> CGFloat {
        if displayMode == .panel {
            return min(preferredPanelWidth(maxWidth: bounds.width), max(panelMinWidth, bounds.width))
        }
        return min(preferredPanelWidth(maxWidth: bounds.width), max(panelMinWidth, bounds.width - ballInset - ballSize - 12 - expandedRightPadding))
    }

    private func preferredSubscriptionContentWidth() -> CGFloat {
        guard snapshot.subscriptions.isEmpty == false else {
            return panelMinWidth
        }

        let nameFont = NSFont.systemFont(ofSize: 15, weight: .medium)
        let periodFont = NSFont.monospacedDigitSystemFont(ofSize: 11.4, weight: .regular)
        let maxRowWidth = snapshot.subscriptions.reduce(CGFloat(0)) { width, item in
            let periodText = "\(Formatters.dateTime(item.start)) ~ \(Formatters.dateTime(item.expiry))"
            let nameWidth = measuredWidth(item.name, font: nameFont)
            let periodWidth = measuredWidth(periodText, font: periodFont)
            return max(width, nameWidth + 14 + periodWidth)
        }

        return maxRowWidth + panelContentInset * 2 + 32
    }

    private func preferredStatsContentWidth() -> CGFloat {
        let titleFont = sectionTitleFont()
        let rangeFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12.2, weight: .bold)
        let rangeWidth = statsRangeButtonsWidth(font: rangeFont)
        let refreshFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let refreshWidth = measuredWidth("刷新时间：00:00:00", font: refreshFont) + 6
        let headerWidth = measuredWidth("使用统计", font: titleFont) + 14 + refreshWidth + 12 + rangeWidth

        let inlineValues = [
            ("花费", Formatters.usd(snapshot.todayCost)),
            ("请求数", Formatters.integer(snapshot.requestCount)),
            ("Tokens", Formatters.compactInteger(snapshot.totalTokens))
        ]
        let inlineCardWidth = inlineValues.reduce(CGFloat(122)) { width, item in
            let titleWidth = measuredWidth(item.0, font: .systemFont(ofSize: 11, weight: .medium))
            let valueWidth = measuredWidth(item.1, font: valueFont)
            return max(width, titleWidth + 50, valueWidth + 24)
        }
        let centeredCardWidth = max(
            CGFloat(112),
            measuredWidth("钱包余额", font: .systemFont(ofSize: 11, weight: .medium)) + 46,
            measuredWidth(Formatters.usd(snapshot.walletBalance), font: .monospacedDigitSystemFont(ofSize: 16.2, weight: .semibold)) + 20
        )
        let cardsWidth = inlineCardWidth * 3 + centeredCardWidth * 2 + 8 * 4
        return max(headerWidth, cardsWidth) + panelContentInset * 2
    }

    private func statsRangeButtonWidths(font: NSFont = .systemFont(ofSize: 10.5, weight: .semibold)) -> [CGFloat] {
        StatsRange.allCases.map { max(36, measuredWidth($0.title, font: font) + 18) }
    }

    private func statsRangeButtonsWidth(
        font: NSFont = .systemFont(ofSize: 10.5, weight: .semibold),
        gap: CGFloat = 4
    ) -> CGFloat {
        statsRangeButtonsWidth(widths: statsRangeButtonWidths(font: font), gap: gap)
    }

    private func statsRangeButtonsWidth(widths: [CGFloat], gap: CGFloat) -> CGFloat {
        widths.reduce(0, +) + gap * CGFloat(max(0, widths.count - 1))
    }

    private func angledPanelPath(_ rect: NSRect) -> NSBezierPath {
        let radius: CGFloat = 16
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    private func fittedMonospacedFont(
        text: String,
        maxSize: CGFloat,
        minSize: CGFloat,
        width: CGFloat,
        weight: NSFont.Weight = .bold
    ) -> NSFont {
        var size = maxSize
        while size > minSize {
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            let measured = (text as NSString).size(withAttributes: [.font: font]).width
            if measured <= width {
                return font
            }
            size -= 0.5
        }
        return .monospacedDigitSystemFont(ofSize: minSize, weight: weight)
    }

    private func fittedSystemFont(
        text: String,
        maxSize: CGFloat,
        minSize: CGFloat,
        width: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> NSFont {
        var size = maxSize
        while size > minSize {
            let font = NSFont.systemFont(ofSize: size, weight: weight)
            let measured = (text as NSString).size(withAttributes: [.font: font]).width
            if measured <= width {
                return font
            }
            size -= 0.4
        }
        return .systemFont(ofSize: minSize, weight: weight)
    }

    private func measuredWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private func pixelAligned(_ rect: NSRect) -> NSRect {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return NSRect(
            x: pixelAligned(rect.origin.x, scale: scale),
            y: pixelAligned(rect.origin.y, scale: scale),
            width: pixelAligned(rect.width, scale: scale),
            height: pixelAligned(rect.height, scale: scale)
        )
    }

    private func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    private func drawCentered(
        _ text: String,
        rect: NSRect,
        font: NSFont,
        color: NSColor,
        kern: CGFloat = 0,
        shadow: NSColor? = nil
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
            .kern: kern
        ]

        if let shadow {
            let textShadow = NSShadow()
            textShadow.shadowColor = shadow
            textShadow.shadowBlurRadius = 12
            textShadow.shadowOffset = .zero
            attributes[.shadow] = textShadow
        }

        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private func drawText(
        _ text: String,
        rect: NSRect,
        font: NSFont,
        color: NSColor,
        kern: CGFloat = 0,
        alignment: NSTextAlignment = .left
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: kern,
            .paragraphStyle: style
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }
}
