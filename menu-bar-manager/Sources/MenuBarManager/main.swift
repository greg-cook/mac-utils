import AppKit
import MenuBarRestriction

// Hides the menu bar icons of every app not listed in ~/.config/menu-bar-manager/visible-apps, using
// macOS 27's own menu bar restriction. macOS's items and this app's chevron always stay visible.
// Right-clicking the chevron lists the apps with icons, to choose which are hidden.
@MainActor
final class MenuBarController: NSObject {
    private static let autoCollapseDelay: TimeInterval = 5
    private static let visibleAppsFile = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/menu-bar-manager/visible-apps")

    private let toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var isCollapsed = false
    private var restriction: MBMMenuBarRestriction?
    private var mouseMonitor: Any?
    private var collapseTimer: Timer?

    override init() {
        super.init()
        toggle.autosaveName = "MenuBarManagerToggle"
        toggle.button?.target = self
        toggle.button?.action = #selector(clicked)
        toggle.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        setCollapsed(false)
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            setCollapsed(!isCollapsed)
        }
    }

    private func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        updateImage()
        if collapsed {
            stopAutoCollapse()
            hideApps()
        } else {
            restriction?.invalidate()
            restriction = nil
            startAutoCollapse()
        }
    }

    private func updateImage() {
        let symbol = isCollapsed ? "chevron.left" : "chevron.right"
        toggle.button?.image = NSImage(systemSymbolName: symbol,
                                       accessibilityDescription: "Toggle hidden items")
    }

    private func hideApps() {
        var visible = Self.readVisibleApps()
        if let ownID = Bundle.main.bundleIdentifier {
            visible.append(ownID)
        }
        MBMMenuBarRestriction.activateAllowingBundleIdentifiers(visible) { [weak self] restriction, error in
            guard let self else { return }
            if let error {
                NSLog("MenuBarManager: could not hide menu bar items: %@", error.localizedDescription)
                NSSound.beep()
                // Not restarting auto-collapse avoids retrying and beeping every few seconds.
                isCollapsed = false
                updateImage()
            } else if isCollapsed {
                self.restriction = restriction
            } else {
                // Expanded again before the restriction took effect.
                restriction?.invalidate()
            }
        }
    }

    // One bundle ID per line; blank lines and text after # are ignored.
    private static func readVisibleApps() -> [String] {
        guard let text = try? String(contentsOf: visibleAppsFile, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let id = line.prefix { $0 != "#" }.trimmingCharacters(in: .whitespaces)
            return id.isEmpty ? nil : id
        }
    }

    // Comments out or uncomments the app's line, appending one if there is none, so the file's
    // other comments survive.
    private static func setVisible(_ visible: Bool, bundleID: String, name: String) throws {
        let text = (try? String(contentsOf: visibleAppsFile, encoding: .utf8)) ?? ""
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        var found = false
        for (i, line) in lines.enumerated() {
            guard let entry = entry(in: line), entry.id == bundleID else { continue }
            if entry.active && !visible {
                lines[i] = "# " + line
            } else if !entry.active && visible && !found {
                lines[i] = String(line.dropFirst(line.hasPrefix("# ") ? 2 : 1))
            }
            found = found || visible
        }
        if visible && !found {
            lines.append(bundleID.padding(toLength: max(35, bundleID.count + 1), withPad: " ",
                                          startingAt: 0) + "# " + name)
        }
        try (lines.joined(separator: "\n") + "\n").write(to: visibleAppsFile, atomically: true,
                                                           encoding: .utf8)
    }

    // The bundle ID on a line and whether it is in effect or commented out. Prose comments are not
    // entries, because bundle IDs contain no spaces.
    private static func entry(in line: String) -> (id: String, active: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let active = !trimmed.hasPrefix("#")
        let body = active ? Substring(trimmed) : trimmed.dropFirst()
        let id = body.prefix { $0 != "#" }.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !id.contains(where: \.isWhitespace) else { return nil }
        return (id, active)
    }

    // Mouse movement is watched only while the hidden items are showing. Global mouse monitors need
    // no permission, but they miss events over this app's own item, so the timer rechecks the
    // pointer position before collapsing.
    private func startAutoCollapse() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }
        scheduleCollapse()
    }

    private func stopAutoCollapse() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        collapseTimer?.invalidate()
        collapseTimer = nil
    }

    private func mouseMoved() {
        if isMouseOverMenuBar() {
            collapseTimer?.invalidate()
            collapseTimer = nil
        } else if collapseTimer == nil {
            scheduleCollapse()
        }
    }

    private func scheduleCollapse(after delay: TimeInterval = autoCollapseDelay) {
        collapseTimer = Timer.scheduledTimer(withTimeInterval: delay,
                                             repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoCollapse() }
        }
    }

    private func autoCollapse() {
        collapseTimer = nil
        guard !isMouseOverMenuBar() else { return }
        // No mouse events may arrive while the pointer rests in a menu, so poll until it closes,
        // then give the full delay.
        if isMenuOpen() {
            collapseTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.waitForMenusToClose() }
            }
            return
        }
        setCollapsed(true)
    }

    private func waitForMenusToClose() {
        collapseTimer = nil
        if isMenuOpen() {
            autoCollapse()
        } else {
            scheduleCollapse()
        }
    }

    // Open menus from any app are windows on the pop-up menu layer. Reading window layers needs no
    // Screen Recording permission.
    private func isMenuOpen() -> Bool {
        let menuLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                 kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { $0[kCGWindowLayer as String] as? Int == menuLayer }
    }

    private func isMouseOverMenuBar() -> Bool {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
        else { return false }
        // visibleFrame excludes the menu bar, which is taller than the status bar on notched screens.
        let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        return point.y >= screen.frame.maxY - barHeight
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(.sectionHeader(title: "Hide Icons"))
        if AXIsProcessTrusted() {
            let visible = Set(Self.readVisibleApps())
            for app in Self.appsWithMenuBarItems() {
                guard let id = app.bundleIdentifier else { continue }
                let item = NSMenuItem(title: app.localizedName ?? id,
                                      action: #selector(toggleHidden(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = id
                item.state = visible.contains(id) ? .off : .on
                item.image = app.icon
                item.image?.size = NSSize(width: 16, height: 16)
                menu.addItem(item)
            }
        } else {
            let item = NSMenuItem(title: "Allow Accessibility to List Apps…",
                                  action: #selector(requestAccessibility), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Menu Bar Manager", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        // Assigning the menu only for this click keeps left clicks going to the toggle action.
        toggle.menu = menu
        toggle.button?.performClick(nil)
        toggle.menu = nil
    }

    // macOS 27 draws every app's icon in MenuBarAgent's window, so the window list cannot tell the
    // owners apart. Accessibility can: apps with icons have an extras menu bar. macOS's own items
    // are always visible, so Apple apps are left out.
    private static func appsWithMenuBarItems() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                  !id.hasPrefix("com.apple."), app.activationPolicy != .prohibited
            else { return false }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            // A hung app would otherwise hold the menu open for the default 6 seconds.
            AXUIElementSetMessagingTimeout(element, 0.25)
            var extras: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, kAXExtrasMenuBarAttribute as CFString,
                                                 &extras) == .success
        }
        .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    @objc private func toggleHidden(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        do {
            try Self.setVisible(sender.state == .on, bundleID: id, name: sender.title)
        } catch {
            NSLog("MenuBarManager: could not update %@: %@", Self.visibleAppsFile.path,
                  error.localizedDescription)
            NSSound.beep()
            return
        }
        if isCollapsed {
            restriction?.invalidate()
            restriction = nil
            hideApps()
        }
    }

    @objc private func requestAccessibility() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = MenuBarController()
app.run()
