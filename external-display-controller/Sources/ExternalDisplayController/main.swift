import AppKit
import DisplayCore

@MainActor
final class AppController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let store = DisplayStore()
    private var sliders: [CGDirectDisplayID: NSSlider] = [:]
    private var menuIsOpen = false

    override init() {
        super.init()
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
        rebuild()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        // The display may have changed since the last read, for example from its own buttons.
        for display in store.displays {
            let id = display.displayID
            display.controller.readBrightness { value in
                guard let value else { return }
                Task { @MainActor in self.refresh(displayID: id, value: value) }
            }
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
        case .ready:
            for display in store.displays {
                menu.addItem(disabledItem(display.name))
                menu.addItem(sliderItem(for: display))
            }
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
        display.controller.setBrightness(value)
        store.updateCached(displayID: id, value: VCPValue(current: UInt16(value), maximum: display.cached.maximum))
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let appController = AppController()
application.run()
