import AppKit

// Shows how much of Claude's 5-hour and weekly limits is left, as "77% / 84%" in the menu bar.
// Clicking it shows when each limit resets. The numbers come from Anthropic's usage endpoint, see
// Fetcher.swift. When that fails, it falls back to the file that `ClaudeUsage capture` writes when
// Claude Code runs it as its statusLine command, see Usage.swift. Whichever reading is newer wins.
@MainActor
final class UsageController: NSObject, NSMenuDelegate {
    private static let interval: TimeInterval = 15
    // How often to ask Anthropic. Failures back off, doubling up to ten minutes.
    private static let fetchInterval: TimeInterval = 120
    private static let maxBackoff: TimeInterval = 600
    private static let font = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.systemFontSize, weight: .regular)

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var usage: Usage?
    private var fetched: Usage?
    private var fetchFailure: Fetcher.Failure?
    private var failures = 0
    private var lastAttempt = Date.distantPast
    private var fetching = false

    private let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.setLocalizedDateFormatFromTemplate("EEE HH:mm")
        return formatter
    }()

    override init() {
        super.init()
        item.autosaveName = "ClaudeUsage"
        menu.delegate = self
        item.menu = menu
        refresh()
        fetchIfDue()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.fetchIfDue()
            }
        }
        timer.tolerance = 5
        // A window can reset while the Mac sleeps, so redraw on wake rather than wait for the timer.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.fetchIfDue(force: true)
            }
        }
    }

    private func fetchIfDue(force: Bool = false) {
        let wait = min(Self.maxBackoff, Self.fetchInterval * pow(2, Double(failures)))
        guard !fetching, Date().timeIntervalSince(lastAttempt) >= (force ? 30 : wait) else { return }
        fetching = true
        lastAttempt = Date()
        Task {
            let result = await Fetcher.fetch()
            fetching = false
            switch result {
            case .success(let usage):
                fetched = usage
                fetchFailure = nil
                failures = 0
            case .failure(let failure):
                fetchFailure = failure
                failures += 1
                NSLog("ClaudeUsage: fetch failed: %@", String(describing: failure))
            }
            refresh()
        }
    }

    private func refresh() {
        usage = [fetched, Usage.load()].compactMap { $0 }.max { $0.receivedAt < $1.receivedAt }
        let now = Date()
        let five = usage?.fiveHour.map { "\($0.remainingPercentage(at: now))%" } ?? "–%"
        let week = usage?.sevenDay.map { "\($0.remainingPercentage(at: now))%" } ?? "–%"
        item.button?.attributedTitle = NSAttributedString(string: "\(five) / \(week)",
                                                          attributes: [.font: Self.font])
        item.button?.setAccessibilityLabel("Claude usage left: 5 hour \(five), weekly \(week)")
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
        fetchIfDue(force: true)
        menu.removeAllItems()
        guard let usage else {
            menu.addDisabled("No usage data yet")
            if let fetchFailure { menu.addDisabled("Anthropic: \(fetchFailure)") }
            addQuit()
            return
        }
        let now = Date()
        addWindow("5-hour limit", usage.fiveHour, now: now, time: { self.clockTime($0) })
        menu.addItem(.separator())
        addWindow("Weekly limit", usage.sevenDay, now: now, time: { self.resetFormatter.string(from: $0) })
        menu.addItem(.separator())
        let age = Format.duration(now.timeIntervalSince(usage.receivedAt))
        switch usage.source {
        case .anthropic:
            menu.addDisabled("Updated \(age) ago")
        case .claudeCode:
            menu.addDisabled("From Claude Code, \(age) ago")
            if let fetchFailure { menu.addDisabled("Anthropic: \(fetchFailure)") }
        }
        addQuit()
    }

    private func addWindow(_ name: String, _ window: LimitWindow?, now: Date,
                           time: (Date) -> String) {
        guard let window else {
            menu.addDisabled("\(name): no data")
            return
        }
        menu.addDisabled("\(name): \(window.remainingPercentage(at: now))% left")
        if window.resetsAt > now {
            menu.addDisabled("Resets in \(Format.duration(window.resetsAt.timeIntervalSince(now))), "
                             + time(window.resetsAt))
        } else {
            menu.addDisabled("Has reset")
        }
    }

    // The 5-hour window always resets within hours, so the time alone is enough.
    private func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func addQuit() {
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Claude Usage", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
    }
}

extension NSMenu {
    func addDisabled(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }
}

if CommandLine.arguments.dropFirst().first == "capture" {
    runCapture()
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let controller = UsageController()
    withExtendedLifetime(controller) { app.run() }
}
