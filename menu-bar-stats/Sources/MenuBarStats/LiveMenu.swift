import AppKit

// A menu of rows that refresh only while it is open, ending with a Quit item.
@MainActor
final class LiveMenu: NSObject, NSMenuDelegate {
    typealias Refresh = @MainActor (@escaping @MainActor @Sendable ([NSAttributedString]) -> Void) -> Void

    let menu = NSMenu()
    private let rows: [NSMenuItem]
    private let interval: TimeInterval
    private let refresh: Refresh
    private var timer: Timer?
    // Counts openings, so a refresh that finishes after its menu closed is dropped.
    private var opening = 0
    private var isOpen = false

    init(title: String, rowCount: Int, placeholder: String, interval: TimeInterval,
         refresh: @escaping Refresh) {
        self.interval = interval
        self.refresh = refresh
        rows = (0..<rowCount).map { _ in NSMenuItem() }
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(NSMenuItem.sectionHeader(title: title))
        rows.forEach(menu.addItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Menu Bar Stats", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        show([Self.row(placeholder)])
    }

    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
        opening += 1
        load(opening)
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
        timer?.invalidate()
        timer = nil
    }

    private func load(_ opening: Int) {
        refresh { [weak self] lines in
            guard let self, isOpen, opening == self.opening else { return }
            show(lines)
            // Common modes keep the timer firing while the menu tracks the mouse.
            let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.load(opening) }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func show(_ lines: [NSAttributedString]) {
        for (index, row) in rows.enumerated() {
            row.isHidden = index >= lines.count
            if index < lines.count { row.attributedTitle = lines[index] }
        }
    }

    // A name, then values right-aligned in columns, such as a process and its CPU use.
    static func row(_ name: String, values: [String] = []) -> NSAttributedString {
        let columnWidth: CGFloat = 64
        let style = NSMutableParagraphStyle()
        style.tabStops = values.indices.map { index in
            NSTextTab(textAlignment: .right, location: 200 + CGFloat(index + 1) * columnWidth)
        }
        let shortName = name.count > 32 ? name.prefix(31) + "…" : name
        let text = ([String(shortName)] + values).joined(separator: "\t")
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .paragraphStyle: style,
        ])
    }
}
