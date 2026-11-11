import AppKit
import DieSensors

// Shows CPU usage, network throughput, the hottest CPU die temperature and optionally a clock as
// separate menu bar items. Clicking CPU or network lists the busiest processes. The clock shows only
// when ~/.config/menu-bar-stats/clock exists; its text is the time zone, such as Europe/London, and
// an empty file means the Mac's own zone.
@MainActor
final class StatsController: NSObject {
    private static let interval: TimeInterval = 3
    private static let height = NSStatusBar.system.thickness
    private static let zoneClock = ZoneClock.fromFile(FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/menu-bar-stats/clock"))

    // macOS places each new item to the left of the last, so they are created right to left.
    private let clockItem = zoneClock != nil ? StatsController.statusItem("MenuBarStatsClock") : nil
    private let temperatureItem = StatsController.statusItem("MenuBarStatsTemperature")
    private let networkItem = StatsController.statusItem("MenuBarStatsNetwork")
    private let cpuItem = StatsController.statusItem("MenuBarStatsCPU")

    private let cpu = CPUUsage()
    private let network = NetworkThroughput()
    private let sensors = MBSDieSensorsCreate()
    private let cpuRenderer = IconValueRenderer(symbol: "cpu", widestValue: "100%")
    private let ratesRenderer = RatesRenderer()
    private let temperatureRenderer = IconValueRenderer(symbol: "thermometer.medium",
                                                        widestValue: "100°")
    private let clock = zoneClock

    private let cpuMenu = LiveMenu(title: "Top processes by CPU", rowCount: TopProcesses.limit,
                                   placeholder: "Loading…", interval: interval) { show in
        TopProcesses.byCPU { rows in
            show(rows.map { LiveMenu.row(TopProcesses.displayName(of: $0),
                                         values: [String(format: "%.1f%%", $0.cpu)]) })
        }
    }
    private let networkMenu = LiveMenu(title: "Top processes by network", rowCount: TopProcesses.limit,
                                       placeholder: "Measuring…", interval: interval - 1) { show in
        TopProcesses.byNetwork { rows in
            guard !rows.isEmpty else { return show([LiveMenu.row("No network activity")]) }
            show(rows.map { LiveMenu.row(TopProcesses.displayName(of: $0),
                                         values: ["↓" + Format.rate($0.received),
                                                  "↑" + Format.rate($0.sent)]) })
        }
    }
    private let clockMenu: LiveMenu?

    override init() {
        clockMenu = clock.map { clock in
            LiveMenu(title: clock.city, rowCount: 1, placeholder: "", interval: Self.interval) {
                show in show([LiveMenu.row(clock.longDescription())])
            }
        }
        super.init()
        cpuItem.length = cpuRenderer.width
        cpuItem.menu = cpuMenu.menu
        networkItem.length = ratesRenderer.width
        networkItem.menu = networkMenu.menu
        temperatureItem.length = temperatureRenderer.width
        temperatureItem.menu = Self.quitMenu()
        clockItem?.menu = clockMenu?.menu
        clock?.onTick = { [weak self] in self?.updateClock() }

        update()
        updateClock()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        timer.tolerance = 0.5
    }

    private func update() {
        let percent = "\(Int(cpu.sample().rounded()))%"
        cpuItem.button?.image = cpuRenderer.image(value: percent, height: Self.height)
        cpuItem.button?.setAccessibilityLabel("CPU \(percent)")

        let (received, sent) = network.sample()
        networkItem.button?.image = ratesRenderer.image(sent: Format.rate(sent),
                                                        received: Format.rate(received),
                                                        height: Self.height)
        networkItem.button?.setAccessibilityLabel(
            "Network up \(Format.rate(sent))/s, down \(Format.rate(received))/s")

        var celsius = 0.0
        let hasTemperature = sensors.map { MBSDieSensorsReadMax($0, &celsius) } ?? false
        let degrees = hasTemperature ? "\(Int(celsius.rounded()))°" : "–°"
        temperatureItem.button?.image = temperatureRenderer.image(value: degrees, height: Self.height)
        temperatureItem.button?.setAccessibilityLabel(
            hasTemperature ? "Temperature \(degrees)" : "Temperature unknown")
    }

    private func updateClock() {
        guard let clock else { return }
        clockItem?.button?.attributedTitle = NSAttributedString(
            string: "\(clock.city) \(clock.shortDescription())",
            attributes: [.font: Drawing.valueFont])
    }

    private static func statusItem(_ autosaveName: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
        return item
    }

    private static func quitMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Menu Bar Stats", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        return menu
    }
}

// The time in one zone, ticking on each minute boundary. Each tick schedules the next from the
// current time, so the clock stays right after sleep or a system clock change.
@MainActor
final class ZoneClock {
    var onTick: (() -> Void)?
    // The city part of the zone's identifier, such as "London" for Europe/London.
    let city: String
    private let short: DateFormatter
    private let long: DateFormatter
    private var timer: Timer?

    // The file holds a time zone identifier such as Europe/London, on its first line that is not a
    // comment. An empty file means the Mac's own zone. An unknown identifier gives no clock.
    static func fromFile(_ url: URL) -> ZoneClock? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let name = text.split(whereSeparator: \.isNewline)
            .map { $0.prefix { $0 != "#" }.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let zone = name.map(TimeZone.init(identifier:)) ?? .current else {
            NSLog("MenuBarStats: unknown time zone in %@", url.path)
            return nil
        }
        return ZoneClock(zone: zone)
    }

    private init(zone: TimeZone) {
        city = zone.identifier.split(separator: "/").last
            .map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
        short = Self.formatter("HH:mm", zone: zone)
        long = Self.formatter("EEEE d MMMM, HH:mm zzz", zone: zone)
        scheduleTick()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.tick() }
        }
        NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func shortDescription() -> String { short.string(from: Date()) }
    func longDescription() -> String { long.string(from: Date()) }

    private func tick() {
        onTick?()
        scheduleTick()
    }

    private func scheduleTick() {
        timer?.invalidate()
        let now = Date().timeIntervalSinceReferenceDate
        let nextMinute = Date(timeIntervalSinceReferenceDate: (now / 60).rounded(.down) * 60 + 60)
        let timer = Timer(fire: nextMinute, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private static func formatter(_ format: String, zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = StatsController()
app.run()
