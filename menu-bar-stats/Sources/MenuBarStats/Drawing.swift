import AppKit

// Menu bar items are drawn as template images, so macOS tints them for light and dark menu bars.
// Every column has a fixed width, which keeps the numbers and the items beside them from moving.
@MainActor
enum Drawing {
    static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    static let rateFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
    static let iconGap: CGFloat = 2
    static let margin: CGFloat = 2

    static func templateImage(width: CGFloat, height: CGFloat,
                              draw: @escaping (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { bounds in
            draw(bounds)
            return true
        }
        image.isTemplate = true
        return image
    }

    // Returns the x after the icon.
    static func drawIcon(_ icon: NSImage, at x: CGFloat, in bounds: NSRect) -> CGFloat {
        let y = ((bounds.height - icon.size.height) / 2).rounded()
        icon.draw(in: NSRect(origin: NSPoint(x: x, y: y), size: icon.size))
        return x + icon.size.width
    }

    // Returns the x after the column.
    @discardableResult
    static func drawText(_ text: String, _ font: NSFont, rightAlignedIn x: CGFloat,
                         _ width: CGFloat, y: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textWidth = (text as NSString).size(withAttributes: attributes).width
        (text as NSString).draw(at: NSPoint(x: x + width - textWidth, y: y), withAttributes: attributes)
        return x + width
    }

    static func centredY(_ font: NSFont, in bounds: NSRect) -> CGFloat {
        (bounds.height - lineHeight(font)) / 2
    }

    static func symbol(_ name: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage()
    }

    static func width(_ text: String, _ font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    static func lineHeight(_ font: NSFont) -> CGFloat {
        ("0" as NSString).size(withAttributes: [.font: font]).height
    }
}

// An icon followed by a right-aligned value, such as the CPU chip and "28%".
@MainActor
final class IconValueRenderer {
    let width: CGFloat
    private let icon: NSImage
    private let valueWidth: CGFloat

    init(symbol: String, widestValue: String) {
        icon = Drawing.symbol(symbol)
        valueWidth = Drawing.width(widestValue, Drawing.valueFont)
        width = (Drawing.margin * 2 + icon.size.width + Drawing.iconGap + valueWidth).rounded(.up)
    }

    func image(value: String, height: CGFloat) -> NSImage {
        Drawing.templateImage(width: width, height: height) { [icon, valueWidth] bounds in
            let x = Drawing.drawIcon(icon, at: Drawing.margin, in: bounds) + Drawing.iconGap
            Drawing.drawText(value, Drawing.valueFont, rightAlignedIn: x, valueWidth,
                             y: Drawing.centredY(Drawing.valueFont, in: bounds))
        }
    }
}

// Upload above download in small text, each with its arrow in a column of its own.
@MainActor
final class RatesRenderer {
    let width: CGFloat
    private let arrowWidth = Drawing.width("↑", Drawing.rateFont)
    private let rateWidth = Drawing.width("999Mb", Drawing.rateFont)

    init() {
        width = (Drawing.margin * 2 + arrowWidth + rateWidth).rounded(.up)
    }

    func image(sent: String, received: String, height: CGFloat) -> NSImage {
        Drawing.templateImage(width: width, height: height) { [arrowWidth, rateWidth] bounds in
            // The two lines overlap slightly, as their line height includes spare leading.
            let upY = bounds.midY - 1
            let downY = bounds.midY - Drawing.lineHeight(Drawing.rateFont) + 1
            var x = Drawing.margin
            Drawing.drawText("↑", Drawing.rateFont, rightAlignedIn: x, arrowWidth, y: upY)
            Drawing.drawText("↓", Drawing.rateFont, rightAlignedIn: x, arrowWidth, y: downY)
            x += arrowWidth
            Drawing.drawText(sent, Drawing.rateFont, rightAlignedIn: x, rateWidth, y: upY)
            Drawing.drawText(received, Drawing.rateFont, rightAlignedIn: x, rateWidth, y: downY)
        }
    }
}

enum Format {
    // Bits per second in at most three digits and a unit, such as "1.2Mb" or "87kb".
    static func rate(_ bytesPerSecond: Double) -> String {
        var value = bytesPerSecond * 8
        for unit in ["b", "kb", "Mb"] {
            if value.rounded() < 1000 {
                let digits = value < 9.95 && unit != "b" ? String(format: "%.1f", value)
                                                         : String(Int(value.rounded()))
                return digits + unit
            }
            value /= 1000
        }
        return String(format: value < 9.95 ? "%.1f" : "%.0f", value) + "Gb"
    }
}
