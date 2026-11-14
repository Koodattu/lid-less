import AppKit

// Reproducible vector artwork; no external assets or fonts.
let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
func draw(size: Int, name: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 196, yRadius: 196)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSGradient(starting: NSColor(calibratedRed: 0.33, green: 0.74, blue: 0.62, alpha: 1),
               ending: NSColor(calibratedRed: 0.05, green: 0.28, blue: 0.25, alpha: 1))!.draw(in: tile, angle: -70)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.32).setStroke()
    tile.lineWidth = 3
    tile.stroke()
    let screen = NSBezierPath(roundedRect: NSRect(x: 260, y: 385, width: 504, height: 320), xRadius: 28, yRadius: 28)
    NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
    screen.fill()
    let display = NSBezierPath(roundedRect: NSRect(x: 282, y: 410, width: 460, height: 272), xRadius: 10, yRadius: 10)
    NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.35, blue: 0.32, alpha: 1),
               ending: NSColor(calibratedRed: 0.24, green: 0.62, blue: 0.52, alpha: 1))!.draw(in: display, angle: 40)
    let base = NSBezierPath()
    base.move(to: NSPoint(x: 244, y: 365))
    base.line(to: NSPoint(x: 780, y: 365))
    base.line(to: NSPoint(x: 834, y: 302))
    base.curve(to: NSPoint(x: 802, y: 278), controlPoint1: NSPoint(x: 840, y: 282), controlPoint2: NSPoint(x: 820, y: 278))
    base.line(to: NSPoint(x: 222, y: 278))
    base.curve(to: NSPoint(x: 190, y: 302), controlPoint1: NSPoint(x: 204, y: 278), controlPoint2: NSPoint(x: 184, y: 282))
    base.close()
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    base.fill()
    NSColor(calibratedRed: 0.50, green: 0.67, blue: 0.61, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 449, y: 337, width: 126, height: 13), xRadius: 6, yRadius: 6).fill()
    // One light in the display: a quiet signal that work continues.
    NSColor(calibratedRed: 0.78, green: 0.99, blue: 0.87, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 487, y: 520, width: 50, height: 50)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
}
for size in [16, 32, 128, 256, 512] {
    try draw(size: size, name: "icon_\(size)x\(size).png")
    try draw(size: size * 2, name: "icon_\(size)x\(size)@2x.png")
}
