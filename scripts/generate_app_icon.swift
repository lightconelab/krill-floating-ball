import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = root.appendingPathComponent("Resources", isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")

let icons: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for icon in icons {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: icon.pixels,
        pixelsHigh: icon.pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [.alphaFirst],
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: icon.pixels, height: icon.pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(in: NSRect(x: 0, y: 0, width: icon.pixels, height: icon.pixels))
    NSGraphicsContext.restoreGraphicsState()

    let outputURL = iconsetURL.appendingPathComponent(icon.name)
    try rep.representation(using: .png, properties: [:])!.write(to: outputURL)
}

try? FileManager.default.removeItem(at: icnsURL)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    throw NSError(
        domain: "KrillFloatingBall.IconGenerator",
        code: Int(iconutil.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: "iconutil failed with status \(iconutil.terminationStatus)"]
    )
}

try? FileManager.default.removeItem(at: iconsetURL)
print(icnsURL.path)

func drawIcon(in rect: NSRect) {
    NSColor.clear.setFill()
    rect.fill()

    let inset = rect.width * 0.075
    let ballRect = rect.insetBy(dx: inset, dy: inset)
    let center = NSPoint(x: ballRect.midX, y: ballRect.midY)
    let ballPath = NSBezierPath(ovalIn: ballRect)

    NSGraphicsContext.current?.cgContext.setShadow(
        offset: CGSize(width: 0, height: -rect.width * 0.025),
        blur: rect.width * 0.04,
        color: NSColor.black.withAlphaComponent(0.32).cgColor
    )
    NSColor.black.withAlphaComponent(0.18).setFill()
    ballPath.fill()
    NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

    ballPath.addClip()

    let topRect = NSRect(x: ballRect.minX, y: center.y, width: ballRect.width, height: ballRect.height / 2)
    let bottomRect = NSRect(x: ballRect.minX, y: ballRect.minY, width: ballRect.width, height: ballRect.height / 2)

    NSGradient(colors: [
        NSColor(calibratedRed: 1.0, green: 0.20, blue: 0.22, alpha: 1),
        NSColor(calibratedRed: 0.64, green: 0.02, blue: 0.08, alpha: 1),
    ])!.draw(in: topRect, angle: 90)

    NSGradient(colors: [
        NSColor(calibratedWhite: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.82, green: 0.88, blue: 0.94, alpha: 1),
    ])!.draw(in: bottomRect, angle: -90)

    let bandHeight = rect.width * 0.09
    let bandRect = NSRect(
        x: ballRect.minX,
        y: center.y - bandHeight / 2,
        width: ballRect.width,
        height: bandHeight
    )
    NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
    NSBezierPath(rect: bandRect).fill()

    let highlight = NSBezierPath(ovalIn: NSRect(
        x: ballRect.minX + ballRect.width * 0.18,
        y: ballRect.midY + ballRect.height * 0.17,
        width: ballRect.width * 0.28,
        height: ballRect.height * 0.15
    ))
    NSColor.white.withAlphaComponent(0.24).setFill()
    highlight.fill()

    let buttonDiameter = rect.width * 0.31
    let buttonRect = NSRect(
        x: center.x - buttonDiameter / 2,
        y: center.y - buttonDiameter / 2,
        width: buttonDiameter,
        height: buttonDiameter
    )
    NSColor(calibratedWhite: 0.045, alpha: 1).setFill()
    NSBezierPath(ovalIn: buttonRect.insetBy(dx: -rect.width * 0.018, dy: -rect.width * 0.018)).fill()

    NSGradient(colors: [
        NSColor.white,
        NSColor(calibratedRed: 0.86, green: 0.91, blue: 0.96, alpha: 1),
    ])!.draw(in: NSBezierPath(ovalIn: buttonRect), angle: 90)

    drawK(in: buttonRect, pixelWidth: rect.width)

    NSColor.black.withAlphaComponent(0.58).setStroke()
    ballPath.lineWidth = max(1.0, rect.width * 0.025)
    ballPath.stroke()
}

func drawK(in rect: NSRect, pixelWidth: CGFloat) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let font = NSFont.systemFont(ofSize: pixelWidth * 0.22, weight: .black)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.15, alpha: 1),
        .paragraphStyle: paragraph,
    ]

    let text = NSString(string: "K")
    let textSize = text.size(withAttributes: attributes)
    let textRect = NSRect(
        x: rect.midX - textSize.width / 2,
        y: rect.midY - textSize.height / 2 - pixelWidth * 0.008,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: textRect, withAttributes: attributes)
}
