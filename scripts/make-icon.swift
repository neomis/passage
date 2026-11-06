// Draws Passage's app icon (a street lamp glowing in the snow) and writes Resources/AppIcon.icns.
// Run from the repo root:  swift scripts/make-icon.swift
import AppKit

func rgb(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255,
            blue: CGFloat(h & 255) / 255, alpha: a)
}

let skyTop = rgb(0x23315C), skyBottom = rgb(0x101830)
let iron = rgb(0x0B0F1C), glow: UInt32 = 0xFFD98A, snow = rgb(0xE9F1FF)

func drawIcon(size s: CGFloat) {
    // macOS icon grid: the rounded square fills about 80% of the canvas.
    let t = NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.1, dy: s * 0.1)
    let u = t.width
    NSBezierPath(roundedRect: t, xRadius: u * 0.225, yRadius: u * 0.225).addClip()
    NSGradient(starting: skyTop, ending: skyBottom)!.draw(in: t, angle: -90)

    let cx = t.midX, lampY = t.minY + u * 0.66
    func radial(_ colors: [NSColor], at y: CGFloat, radius: CGFloat) {
        let c = NSPoint(x: cx, y: y)
        NSGradient(colors: colors)!.draw(fromCenter: c, radius: 0, toCenter: c, radius: radius, options: [])
    }
    func fillRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius r: CGFloat = 0) {
        NSBezierPath(roundedRect: NSRect(x: cx + u * x, y: t.minY + u * y, width: u * w, height: u * h),
                     xRadius: u * r, yRadius: u * r).fill()
    }
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: cx + u * x, y: lampY + u * y) }

    // Glow around the lantern
    radial([rgb(glow, 0.75), rgb(glow, 0.25), rgb(glow, 0)], at: lampY, radius: u * 0.48)

    // Snowy ground and the pool of light on it
    let ground = NSBezierPath()
    ground.move(to: NSPoint(x: t.minX, y: t.minY + u * 0.16))
    ground.curve(to: NSPoint(x: t.maxX, y: t.minY + u * 0.13),
                 controlPoint1: NSPoint(x: t.minX + u * 0.35, y: t.minY + u * 0.24),
                 controlPoint2: NSPoint(x: t.minX + u * 0.65, y: t.minY + u * 0.20))
    ground.line(to: NSPoint(x: t.maxX, y: t.minY))
    ground.line(to: NSPoint(x: t.minX, y: t.minY))
    ground.close()
    snow.setFill(); ground.fill()
    radial([rgb(glow, 0.55), rgb(glow, 0)], at: t.minY + u * 0.17, radius: u * 0.28)

    // Base, post, collar and crossbar
    iron.setFill()
    fillRect(-0.07, 0.17, 0.14, 0.06, radius: 0.015)
    fillRect(-0.045, 0.22, 0.09, 0.06)
    fillRect(-0.022, 0.27, 0.044, 0.28)
    NSBezierPath(roundedRect: NSRect(x: cx - u * 0.06, y: lampY - u * 0.12, width: u * 0.12, height: u * 0.03),
                 xRadius: u * 0.01, yRadius: u * 0.01).fill()
    NSBezierPath(roundedRect: NSRect(x: cx - u * 0.13, y: lampY - u * 0.19, width: u * 0.26, height: u * 0.022),
                 xRadius: u * 0.01, yRadius: u * 0.01).fill()

    // Lantern: tapered glass with a flame
    let glass = NSBezierPath()
    glass.move(to: point(-0.055, -0.09)); glass.line(to: point(0.055, -0.09))
    glass.line(to: point(0.085, 0.07)); glass.line(to: point(-0.085, 0.07)); glass.close()
    rgb(0xFFFBEA).setFill(); glass.fill()
    rgb(glow).setFill()
    NSBezierPath(ovalIn: NSRect(x: cx - u * 0.03, y: lampY - u * 0.04, width: u * 0.06, height: u * 0.07)).fill()
    iron.setStroke()
    glass.lineWidth = max(1, u * 0.014); glass.stroke()
    let bar = NSBezierPath(); bar.move(to: point(0, -0.09)); bar.line(to: point(0, 0.07))
    bar.lineWidth = max(1, u * 0.01); bar.stroke()

    // Roof and finial
    iron.setFill()
    let roof = NSBezierPath()
    roof.move(to: point(-0.11, 0.07)); roof.line(to: point(0.11, 0.07))
    roof.line(to: point(0.02, 0.14)); roof.line(to: point(-0.02, 0.14)); roof.close(); roof.fill()
    NSBezierPath(ovalIn: NSRect(x: cx - u * 0.022, y: lampY + u * 0.13, width: u * 0.044, height: u * 0.044)).fill()

    // Snow on the roof
    NSColor.white.setFill()
    let cap = NSBezierPath()
    cap.move(to: point(-0.10, 0.08)); cap.line(to: point(-0.02, 0.14))
    cap.line(to: point(0.02, 0.14)); cap.line(to: point(0.10, 0.08))
    cap.curve(to: point(-0.10, 0.08), controlPoint1: point(0.04, 0.11), controlPoint2: point(-0.04, 0.11))
    cap.fill()

    // Falling snow
    let flakes: [(CGFloat, CGFloat, CGFloat)] = [(0.18, 0.82, 1), (0.30, 0.60, 0.7), (0.80, 0.78, 1), (0.70, 0.52, 0.8),
                                                 (0.22, 0.40, 0.8), (0.86, 0.36, 0.7), (0.40, 0.88, 0.6), (0.62, 0.90, 0.8),
                                                 (0.12, 0.62, 0.6), (0.90, 0.62, 0.6)]
    NSColor(white: 1, alpha: 0.85).setFill()
    for (fx, fy, fs) in flakes {
        let r = u * 0.012 * fs
        NSBezierPath(ovalIn: NSRect(x: t.minX + u * fx - r, y: t.minY + u * fy - r, width: 2 * r, height: 2 * r)).fill()
    }
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

try FileManager.default.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
