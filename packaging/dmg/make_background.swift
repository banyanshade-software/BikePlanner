// Draws the background of the BikePlanner DMG window (#37): background.png (1x) and background@2x.png.
//   swift packaging/dmg/make_background.swift <output dir> [version]
// Called by scripts/make_dmg.sh with the app's CFBundleShortVersionString (MARKETING_VERSION), shown in the title.
// The layout must match scripts/make_dmg.sh: window 660 x 480 points, 100 pt icons centered at
// (165, 165) for the app, (495, 165) for the Applications link, and (270, 360) / (390, 360) for the
// "Read Me" / "Lisez-moi" files (Finder coordinates, origin top left).

import AppKit

let width: CGFloat = 660, height: CGFloat = 480
let appCenter = CGPoint(x: 165, y: height - 165)       // drawing coordinates, origin bottom left
let appsCenter = CGPoint(x: 495, y: height - 165)
let version = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func drawBackground() {
    // soft daylight gradient
    NSGradient(colors: [color(0xF7F9F4), color(0xE4EEE2)])!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

    // faint contour lines, like a topographic map
    color(0x7FA07A, 0.16).setStroke()
    for i in 0..<9 {
        let p = NSBezierPath()
        let base = CGFloat(i) * 52 - 40
        p.move(to: CGPoint(x: -20, y: base))
        p.curve(to: CGPoint(x: width + 20, y: base + 60),
                controlPoint1: CGPoint(x: width * 0.3, y: base + 110),
                controlPoint2: CGPoint(x: width * 0.65, y: base - 50))
        p.lineWidth = 1
        p.stroke()
    }

    // a bike route along the bottom: reference trace (orange) and route (blue) with waypoints
    let route = NSBezierPath()
    route.move(to: CGPoint(x: 40, y: 38))
    route.curve(to: CGPoint(x: 250, y: 62), controlPoint1: CGPoint(x: 110, y: 90), controlPoint2: CGPoint(x: 180, y: 20))
    route.curve(to: CGPoint(x: 430, y: 48), controlPoint1: CGPoint(x: 320, y: 100), controlPoint2: CGPoint(x: 370, y: 10))
    route.curve(to: CGPoint(x: 620, y: 70), controlPoint1: CGPoint(x: 500, y: 90), controlPoint2: CGPoint(x: 560, y: 30))
    route.lineCapStyle = .round
    route.transform(using: AffineTransform(scaleByX: 1, byY: 0.45))   // a low band: the read-me icons are above
    let trace = route.copy() as! NSBezierPath
    trace.transform(using: AffineTransform(translationByX: 0, byY: -5))
    trace.lineWidth = 5
    color(0xF29B38, 0.35).setStroke()
    trace.stroke()
    route.lineWidth = 3
    color(0x2F7BD9, 0.55).setStroke()
    route.stroke()
    for (pt, fill) in [(CGPoint(x: 40, y: 38 * 0.45), color(0x8E8E93)), (CGPoint(x: 250, y: 62 * 0.45), color(0xF2C230)),
                       (CGPoint(x: 430, y: 48 * 0.45), color(0xF2C230)), (CGPoint(x: 620, y: 70 * 0.45), color(0xFFFFFF))] {
        let dot = NSBezierPath(ovalIn: NSRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10))
        fill.setFill()
        dot.fill()
        color(0x3A3A3C, 0.6).setStroke()
        dot.lineWidth = 1
        dot.stroke()
    }

    // title, with the version
    let title = NSMutableAttributedString(string: "BikePlanner", attributes: [
        .font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: color(0x2C3A2B)])
    if !version.isEmpty {
        title.append(NSAttributedString(string: "  " + version, attributes: [
            .font: NSFont.systemFont(ofSize: 20, weight: .regular), .foregroundColor: color(0x5E7A5B)]))
    }
    let ts = title.size()
    title.draw(at: CGPoint(x: (width - ts.width) / 2, y: height - 62))

    // arrow from the app to the Applications folder; the line stops at the base of the head (opaque colors, so
    // nothing shows through where they meet)
    let start = CGPoint(x: appCenter.x + 72, y: appCenter.y + 4)
    let end = CGPoint(x: appsCenter.x - 76, y: appsCenter.y + 4)
    let c2 = CGPoint(x: end.x - 50, y: end.y + 34)
    let angle = atan2(end.y - c2.y, end.x - c2.x) // end tangent
    let len: CGFloat = 26, spread: CGFloat = .pi / 6
    let lineEnd = CGPoint(x: end.x - len * 0.75 * cos(angle), y: end.y - len * 0.75 * sin(angle))
    let arrowColor = color(0x3F86DC)
    let arrow = NSBezierPath()
    arrow.move(to: start)
    arrow.curve(to: lineEnd, controlPoint1: CGPoint(x: start.x + 50, y: start.y + 34),
                controlPoint2: CGPoint(x: c2.x, y: c2.y - 6))
    arrow.lineWidth = 7
    arrow.lineCapStyle = .round
    arrowColor.setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: end)
    head.line(to: CGPoint(x: end.x - len * cos(angle - spread), y: end.y - len * sin(angle - spread)))
    head.line(to: CGPoint(x: end.x - len * cos(angle + spread), y: end.y - len * sin(angle + spread)))
    head.close()
    head.lineJoinStyle = .round
    head.lineWidth = 2
    arrowColor.setFill()
    arrowColor.setStroke()
    head.fill()
    head.stroke()

    // hint
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let hint = NSAttributedString(string: "Drag BikePlanner onto the Applications folder to install it", attributes: [
        .font: NSFont.systemFont(ofSize: 13), .foregroundColor: color(0x4A5A48), .paragraphStyle: style])
    hint.draw(in: NSRect(x: 0, y: height - 262, width: width, height: 20))

    // first launch: see the read-me files below (the app is not notarized)
    let readme = NSAttributedString(string: "First launch: read me — Premier lancement : lisez-moi", attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: color(0x8A5A12), .paragraphStyle: style])
    readme.draw(in: NSRect(x: 0, y: height - 300, width: width, height: 18))
}

func render(scale: CGFloat, to url: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height) // 72 dpi at 1x, 144 dpi at 2x
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawBackground()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try render(scale: 1, to: dir.appendingPathComponent("background.png"))
try render(scale: 2, to: dir.appendingPathComponent("background@2x.png"))
print("wrote background.png and background@2x.png in \(dir.path)")
