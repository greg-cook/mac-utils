import AppKit
import DisplayCore

@MainActor
final class AppController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let store = DisplayStore()
    private var sliders: [CGDirectDisplayID: NSSlider] = [:]
    private var menuIsOpen = false
    private var keyTap: KeyTap!
    // When each display was last read. A key press after a long pause reads the display again.
    private var lastRead: [CGDirectDisplayID: Date] = [:]
    private var staleGuard = StaleReadGuard()

    override init() {
        super.init()
        keyTap = KeyTap { [weak self] direction in self?.handleBrightnessKey(direction) ?? false }
        if !keyTap.start() { NSLog("ExternalDisplayController: brightness keys need Accessibility") }
        statusItem.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "External display brightness")
        menu.delegate = self
        statusItem.menu = menu
        store.onChange = { [weak self] in
            guard let self, self.menuIsOpen else { return }
            self.rebuild()
        }
        store.scan()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // The user may have granted Accessibility since the last try.
        keyTap.start()
        store.rescanIfIncomplete()
        rebuild()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        // The display may have changed since the last read, for example from its own buttons.
        for display in store.displays { readAgain(display) }
    }

    private func readAgain(_ display: ExternalDisplay) {
        let id = display.displayID
        lastRead[id] = Date()
        let token = staleGuard.token(for: id)
        display.controller.readBrightness { value in
            guard let value else { return }
            Task { @MainActor in
                // A value set since the read started is newer than the reading.
                guard self.staleGuard.isCurrent(token, for: id) else { return }
                self.refresh(displayID: id, value: value)
            }
        }
    }

    /// Returns true if the key changed an external display, so that macOS does not also see it.
    private func handleBrightnessKey(_ direction: Direction) -> Bool {
        let pointerDisplay = store.displayID(at: NSEvent.mouseLocation).flatMap { store.controllableID(for: $0) }
        guard case .consume(let id) = KeyRouting.decide(pointerDisplay: pointerDisplay, controllable: store.controllableIDs),
              let display = store.display(withID: id) else { return false }
        let value = BrightnessStep.next(current: Int(display.cached.current), maximum: Int(display.cached.maximum), direction: direction)
        staleGuard.markChanged(id)
        display.controller.setBrightness(value)
        store.updateCached(displayID: id, value: VCPValue(current: UInt16(value), maximum: display.cached.maximum))
        sliders[id]?.doubleValue = Double(value)
        if Date().timeIntervalSince(lastRead[id] ?? .distantPast) > 30 { readAgain(display) }
        return true
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    private func refresh(displayID: CGDirectDisplayID, value: VCPValue) {
        store.updateCached(displayID: displayID, value: value)
        sliders[displayID]?.maxValue = Double(value.maximum)
        sliders[displayID]?.doubleValue = Double(value.current)
    }

    private func rebuild() {
        menu.removeAllItems()
        sliders = [:]
        switch store.state {
        case .interfaceUnavailable:
            menu.addItem(disabledItem("DDC interface unavailable"))
        case .noExternalDisplay:
            menu.addItem(disabledItem("No external display found"))
        case .unmatched:
            menu.addItem(disabledItem("Cannot match the displays to DDC services"))
        case .ready:
            for display in store.displays {
                menu.addItem(disabledItem(display.name))
                menu.addItem(sliderItem(for: display))
            }
        }
        if !keyTap.isActive {
            menu.addItem(.separator())
            menu.addItem(disabledItem("Keys need Accessibility"))
            // Without a target, AppKit looks for the action in the responder chain, which has no controller.
            let open = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit External Display Controller", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func sliderItem(for display: ExternalDisplay) -> NSMenuItem {
        let slider = NSSlider(value: Double(display.cached.current), minValue: 0, maxValue: Double(display.cached.maximum),
                              target: self, action: #selector(sliderMoved(_:)))
        slider.tag = Int(display.displayID)
        slider.isContinuous = true
        slider.frame = NSRect(x: 16, y: 4, width: 188, height: 20)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        container.addSubview(slider)
        sliders[display.displayID] = slider
        let item = NSMenuItem()
        item.view = container
        return item
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        let id = CGDirectDisplayID(sender.tag)
        guard let display = store.display(withID: id) else { return }
        let value = Int(sender.doubleValue.rounded())
        staleGuard.markChanged(id)
        display.controller.setBrightness(value)
        store.updateCached(displayID: id, value: VCPValue(current: UInt16(value), maximum: display.cached.maximum))
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let appController = AppController()
application.run()
