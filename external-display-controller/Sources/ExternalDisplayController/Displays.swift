import AppKit
import DisplayCore
import DisplayDDC

// Owns the array that DDCCopyExternalServices returns. Every controller keeps it alive, so a rescan never
// frees a service that a queued DDC call still uses.
final class ServiceList: @unchecked Sendable {
    private let services: UnsafeMutablePointer<OpaquePointer>?
    let count: Int

    init() {
        var found = 0
        services = DDCCopyExternalServices(&found)
        count = found
    }

    deinit { DDCFreeServices(services, count) }

    subscript(index: Int) -> OpaquePointer { services![index] }
}

// Sends brightness to one display. All DDC traffic runs on one serial queue, because the display answers
// one request at a time and the main thread must never wait for it.
final class DisplayController: @unchecked Sendable {
    private static let brightnessCode: UInt8 = 0x10
    private static let pause: useconds_t = 50_000

    private let owner: ServiceList
    private let service: OpaquePointer
    private let queue = DispatchQueue(label: "external-display-controller.ddc", qos: .userInitiated)
    private let mailbox = LatestValueMailbox<Int>()

    init(owner: ServiceList, index: Int) {
        self.owner = owner
        service = owner[index]
    }

    func readBrightness(completion: @escaping @Sendable (VCPValue?) -> Void) {
        queue.async { completion(self.read()) }
    }

    /// Sends the newest value. A value set while a write is in flight replaces any older waiting value.
    func setBrightness(_ value: Int) {
        if mailbox.put(value) { queue.async { self.drain() } }
    }

    private func drain() {
        while let value = mailbox.take() { write(value) }
    }

    private func read() -> VCPValue? {
        let request = DDCPacket.getVCPRequest(code: Self.brightnessCode)
        for _ in 0..<3 {
            if DDCWrite(service, DDCPacket.chipAddress, DDCPacket.dataAddress, request, request.count) {
                usleep(Self.pause)
                var reply = [UInt8](repeating: 0, count: 11)
                if DDCRead(service, DDCPacket.chipAddress, DDCPacket.dataAddress, &reply, reply.count),
                   let value = DDCPacket.parseGetReply(reply, code: Self.brightnessCode) {
                    return value
                }
            }
            usleep(Self.pause)
        }
        return nil
    }

    private func write(_ value: Int) {
        let packet = DDCPacket.setVCP(code: Self.brightnessCode, value: UInt16(clamping: value))
        if !DDCWrite(service, DDCPacket.chipAddress, DDCPacket.dataAddress, packet, packet.count) {
            NSLog("ExternalDisplayController: brightness write failed")
        }
        usleep(Self.pause)
    }
}

struct ExternalDisplay {
    let displayID: CGDirectDisplayID
    let name: String
    let controller: DisplayController
    var cached: VCPValue
}

/// Finds the external displays that answer DDC and keeps one controller for each.
@MainActor
final class DisplayStore {
    enum State {
        case interfaceUnavailable, noExternalDisplay, ready
    }

    private(set) var displays: [ExternalDisplay] = []
    private(set) var state: State = .noExternalDisplay
    var onChange: (() -> Void)?

    // A new scan bumps this, which cancels the retries of the scan before it.
    private var generation = 0

    init() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
    }

    var controllableIDs: Set<UInt32> { Set(displays.map(\.displayID)) }

    /// The display under a point in screen coordinates, such as `NSEvent.mouseLocation`.
    func displayID(at point: NSPoint) -> CGDirectDisplayID? {
        NSScreen.screens.first { $0.frame.contains(point) }?.displayID
    }

    /// Maps a screen to the display that answers DDC. A mirrored screen maps to the member of its set that does.
    func controllableID(for displayID: CGDirectDisplayID) -> CGDirectDisplayID? {
        let known = controllableIDs
        if known.contains(displayID) { return displayID }
        let master = CGDisplayMirrorsDisplay(displayID)
        if known.contains(master) { return master }
        return known.first { CGDisplayMirrorsDisplay($0) == displayID }
    }

    func display(withID id: CGDirectDisplayID) -> ExternalDisplay? {
        displays.first { $0.displayID == id }
    }

    func updateCached(displayID: CGDirectDisplayID, value: VCPValue) {
        guard let index = displays.firstIndex(where: { $0.displayID == displayID }) else { return }
        displays[index].cached = value
    }

    func scan() {
        generation += 1
        displays = []
        guard DDCInterfaceAvailable() else {
            state = .interfaceUnavailable
            onChange?()
            return
        }
        let services = ServiceList()
        let screens = Self.externalDisplayIDs()
        if services.count != screens.count {
            NSLog("ExternalDisplayController: %d DDC services for %d external screens", services.count, screens.count)
        }
        // No registry property links a service to a screen, so they are paired by position.
        for index in 0..<min(services.count, screens.count) {
            probe(controller: DisplayController(owner: services, index: index), displayID: screens[index], attempt: 0, generation: generation)
        }
        state = .noExternalDisplay
        onChange?()
    }

    private func probe(controller: DisplayController, displayID: CGDirectDisplayID, attempt: Int, generation: Int) {
        controller.readBrightness { value in
            Task { @MainActor in
                guard generation == self.generation else { return }
                if let value {
                    self.displays.append(ExternalDisplay(displayID: displayID, name: Self.name(of: displayID), controller: controller, cached: value))
                    self.displays.sort { $0.displayID < $1.displayID }
                    self.state = .ready
                    self.onChange?()
                } else if attempt < ScanRetryPolicy.delays.count {
                    try? await Task.sleep(for: .seconds(ScanRetryPolicy.delays[attempt]))
                    guard generation == self.generation else { return }
                    self.probe(controller: controller, displayID: displayID, attempt: attempt + 1, generation: generation)
                }
            }
        }
    }

    private static func externalDisplayIDs() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }.sorted()
    }

    private static func name(of displayID: CGDirectDisplayID) -> String {
        NSScreen.screens.first { $0.displayID == displayID }?.localizedName ?? "External display"
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
