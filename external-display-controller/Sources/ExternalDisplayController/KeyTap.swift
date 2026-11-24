import AppKit
import ApplicationServices
@preconcurrency import CoreGraphics
import DisplayCore

// Sees the brightness keys before macOS does. An active event tap needs the Accessibility permission.
// If the tap is unavailable or disabled, every key reaches macOS as usual.
@MainActor
final class KeyTap {
    private static let systemDefinedEvent: UInt32 = 14
    private static let mediaKeySubtype: Int16 = 8

    private let handle: @MainActor (Direction) -> Bool
    private var tap: CFMachPort?
    // Keys whose press was consumed, so that their release is consumed too.
    private var consumed: Set<Int> = []

    /// `handle` gets each brightness key press and returns true if it used the key.
    init(handle: @escaping @MainActor (Direction) -> Bool) {
        self.handle = handle
    }

    var isActive: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// Returns false if Accessibility is off or the tap cannot be created.
    @discardableResult
    func start() -> Bool {
        if isActive { return true }
        guard AXIsProcessTrusted() else { return false }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            let keyTap = Unmanaged<KeyTap>.fromOpaque(userInfo!).takeUnretainedValue()
            // The tap's run loop source is on the main run loop.
            return MainActor.assumeIsolated { keyTap.receive(type: type, event: event) }
        }
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << CGEventMask(Self.systemDefinedEvent),
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        tap = created
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, created, 0), .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        return true
    }

    private func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough
        }
        guard type.rawValue == Self.systemDefinedEvent,
              let systemEvent = NSEvent(cgEvent: event),
              systemEvent.subtype.rawValue == Self.mediaKeySubtype,
              let key = MediaKeyDecoder.decode(data1: systemEvent.data1) else { return passThrough }

        let id = key.key == .up ? 1 : 0
        if key.isDown {
            if handle(key.key) {
                consumed.insert(id)
                return nil
            }
            return passThrough
        }
        return consumed.remove(id) != nil ? nil : passThrough
    }
}
