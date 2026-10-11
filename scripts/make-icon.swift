// Draws the app icon and writes Resources/AppIcon.icns.
// Run from the project root: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawIcon() {
    // macOS icon grid: 824×824 body centered on a 1024 canvas, with room for the shadow.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x312E81).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Background gradient: indigo at the top, deep navy at the bottom.
    NSGradient(colors: [color(0x6366F1), color(0x4338CA), color(0x1E1B4B)])!
        .draw(in: shape, angle: -90)

    // Soft light at the top for depth.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [.white.withAlphaComponent(0.18), .white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Speech bubble (the subtitles), with a tail at the bottom left.
    let bubbleRect = NSRect(x: 215, y: 330, width: 594, height: 430)
    let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 120, yRadius: 120)
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 300, y: 360))
    tail.line(to: NSPoint(x: 250, y: 228))
    tail.line(to: NSPoint(x: 420, y: 340))
    tail.close()
    bubble.append(tail)

    NSGraphicsContext.saveGraphicsState()
    let bubbleShadow = NSShadow()
    bubbleShadow.shadowColor = .black.withAlphaComponent(0.3)
    bubbleShadow.shadowBlurRadius = 24
    bubbleShadow.shadowOffset = NSSize(width: 0, height: -10)
    bubbleShadow.set()
    color(0xFFFFFF).setFill()
    bubble.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0xFFFFFF), color(0xE0E7FF)])!.draw(in: bubble, angle: -90)

    // Play button (movies) inside the bubble.
    let center = NSPoint(x: bubbleRect.midX - 30, y: bubbleRect.midY)
    let circle = NSBezierPath(ovalIn: NSRect(x: center.x - 135, y: center.y - 135, width: 270, height: 270))
    NSGradient(colors: [color(0xFB923C), color(0xEA580C)])!.draw(in: circle, angle: -90)

    let play = NSBezierPath()
    play.move(to: NSPoint(x: center.x - 38, y: center.y + 68))
    play.line(to: NSPoint(x: center.x + 72, y: center.y))
    play.line(to: NSPoint(x: center.x - 38, y: center.y - 68))
    play.close()
    play.lineJoinStyle = .round
    play.lineWidth = 18
    NSColor.white.setFill()
    NSColor.white.setStroke()
    play.fill()
    play.stroke()

    // Music note (songs) at the top right of the bubble.
    let noteColor = color(0xFACC15)
    NSGraphicsContext.saveGraphicsState()
    let noteShadow = NSShadow()
    noteShadow.shadowColor = .black.withAlphaComponent(0.35)
    noteShadow.shadowBlurRadius = 14
    noteShadow.shadowOffset = NSSize(width: 0, height: -6)
    noteShadow.set()
    noteColor.setFill()

    let headA = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 92, height: 70))
    let headB = NSBezierPath(ovalIn: NSRect(x: 150, y: 30, width: 92, height: 70))
    let stems = NSBezierPath()
    stems.appendRect(NSRect(x: 72, y: 34, width: 22, height: 200))
    stems.appendRect(NSRect(x: 222, y: 64, width: 22, height: 200))
    let beam = NSBezierPath()
    beam.move(to: NSPoint(x: 72, y: 234))
    beam.line(to: NSPoint(x: 244, y: 264))
    beam.line(to: NSPoint(x: 244, y: 214))
    beam.line(to: NSPoint(x: 72, y: 184))
    beam.close()

    // Each piece is filled on its own: overlapping subpaths in a single path cancel out.
    var transform = AffineTransform(scaleByX: 0.85, byY: 0.85)
    transform.rotate(byDegrees: -8)
    transform.append(AffineTransform(translationByX: 630, byY: 640))
    NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
    for piece in [headA, headB, stems, beam] {
        piece.transform(using: transform)
        piece.fill()
    }
    NSGraphicsContext.current?.cgContext.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fileManager = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try render(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

try fileManager.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
try render(size: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try? fileManager.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Resources/AppIcon.icns criado" : "iconutil falhou")
