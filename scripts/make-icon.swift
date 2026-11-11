// Draws an app icon, an SF Symbol in white on a rounded square with a vertical gradient, as an
// .iconset folder for iconutil. Run by each app's build-app.sh:
//   swift ../scripts/make-icon.swift <symbol> <top hex colour> <bottom hex colour> <output.iconset>
import AppKit

let args = CommandLine.arguments
guard args.count == 5 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift symbol top bottom out.iconset\n".utf8))
    exit(2)
}
let (symbolName, top, bottom, output) = (args[1], args[2], args[3], URL(fileURLWithPath: args[4]))

func color(_ hex: String) -> NSColor {
    let value = Int(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
    return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}

guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
    FileHandle.standardError.write(Data("no SF Symbol named \(symbolName)\n".utf8))
    exit(1)
}

// Proportions of Apple's macOS icon grid: on a 1024 canvas, an 824 square with 185 corners and
// room around it for the shadow.
func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let scale = CGFloat(pixels) / 1024
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let tile = NSRect(x: 100, y: 100, width: 824, height: 824).applying(.init(scaleX: scale, y: scale))
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * scale, yRadius: 185 * scale)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -8 * scale)
    shadow.set()
    color(bottom).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(top), ending: color(bottom))!.draw(in: shape, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: 420 * scale, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    let glyph = symbol.withSymbolConfiguration(config)!
    // Fit the symbol inside the middle of the tile whatever its aspect ratio.
    let fit = min(460 * scale / glyph.size.width, 460 * scale / glyph.size.height)
    let size = NSSize(width: glyph.size.width * fit, height: glyph.size.height * fit)
    glyph.draw(in: NSRect(x: tile.midX - size.width / 2, y: tile.midY - size.height / 2,
                          width: size.width, height: size.height))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: output.appending(path: "icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: output.appending(path: "icon_\(points)x\(points)@2x.png"))
}
