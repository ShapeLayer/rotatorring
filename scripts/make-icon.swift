// Draws the app icon and writes apps/macos/Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: locations)!
}

let extend: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]

// A plain window: white body and a tinted title bar whose dots use the tile's colors.
func drawWindow(_ ctx: CGContext, _ rect: CGRect) {
    let radius: CGFloat = 40, bar: CGFloat = 70
    let body = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(0x3a1740, 0.45))
    ctx.addPath(body); ctx.setFillColor(color(0xffffff)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    ctx.setFillColor(color(0xffe4ea))
    ctx.fill(CGRect(x: rect.minX, y: rect.maxY - bar, width: rect.width, height: bar))
    for (i, hex) in [0xff8a5c, 0xe0457b, 0x5b2a86].enumerated() {
        let d: CGFloat = 24
        let x = rect.minX + 34 + CGFloat(i) * 40
        ctx.setFillColor(color(UInt32(hex)))
        ctx.fillEllipse(in: CGRect(x: x, y: rect.maxY - bar / 2 - d / 2, width: d, height: d))
    }
    ctx.restoreGState()
}

// Draws on a 1024-point canvas, scaled to `px`.
func render(_ px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    let c = CGPoint(x: 512, y: 512)

    // Tile: macOS icon grid (824pt, drop shadow), warm coral-to-plum.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(tilePath); ctx.setFillColor(color(0x3a1740)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    ctx.drawLinearGradient(gradient([color(0xff8a5c), color(0xe0457b), color(0x5b2a86)], [0, 0.5, 1]),
                           start: CGPoint(x: 160, y: 924), end: CGPoint(x: 864, y: 100), options: extend)
    ctx.restoreGState()

    // The window's original landscape frame, as a dashed outline.
    let win = CGRect(x: c.x - 250, y: c.y - 170, width: 500, height: 340)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: win, cornerWidth: 34, cornerHeight: 34, transform: nil))
    ctx.setStrokeColor(color(0xffffff, 0.55)); ctx.setLineWidth(10)
    ctx.setLineDash(phase: 0, lengths: [28, 20]); ctx.strokePath()
    ctx.restoreGState()

    // Rotation arrow: a quarter arc outside the top-right corner, clockwise.
    let r: CGFloat = 318
    let a0: CGFloat = .pi * 0.56, a1: CGFloat = .pi * 0.1
    let arc = CGMutablePath()
    arc.addArc(center: c, radius: r, startAngle: a0, endAngle: a1, clockwise: true)
    ctx.saveGState()
    ctx.addPath(arc); ctx.setStrokeColor(color(0xffffff)); ctx.setLineWidth(34); ctx.setLineCap(.round)
    ctx.strokePath()
    let tip = CGPoint(x: c.x + r * cos(a1), y: c.y + r * sin(a1))
    let t = CGPoint(x: sin(a1), y: -cos(a1)), n = CGPoint(x: cos(a1), y: sin(a1))
    let head = CGMutablePath()
    head.move(to: CGPoint(x: tip.x + t.x * 70, y: tip.y + t.y * 70))
    head.addLine(to: CGPoint(x: tip.x + n.x * 52, y: tip.y + n.y * 52))
    head.addLine(to: CGPoint(x: tip.x - n.x * 52, y: tip.y - n.y * 52))
    head.closeSubpath()
    ctx.addPath(head); ctx.setFillColor(color(0xffffff)); ctx.fillPath()
    ctx.restoreGState()

    // The window, turned clockwise partway around its center.
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: -.pi / 7); ctx.translateBy(x: -c.x, y: -c.y)
    drawWindow(ctx, win)
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    writePNG(render(size), to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    writePNG(render(size * 2), to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
writePNG(render(1024), to: root.appendingPathComponent("apps/macos/Resources/AppIcon.png"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("apps/macos/Resources/AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
print("Wrote apps/macos/Resources/AppIcon.icns and apps/macos/Resources/AppIcon.png")
