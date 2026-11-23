import AppKit
import DisplayCore
import DisplayDDC
import IOKit

// Temporary: `probe` prints what the DDC interface sees, so the display-to-service match can be chosen.
// It is removed when the menu bar app replaces it.

func registryName(_ entry: io_registry_entry_t) -> String {
    var name = [CChar](repeating: 0, count: 128)
    IORegistryEntryGetName(entry, &name)
    return String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

func dumpProperties(_ entry: io_registry_entry_t, indent: String) {
    var properties: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return }
    for key in dictionary.keys.sorted() {
        print("\(indent)\(key) = \(String(describing: dictionary[key]!).prefix(160))")
    }
}

func readBrightness(_ service: OpaquePointer) -> [UInt8]? {
    let request = DDCPacket.getVCPRequest(code: 0x10)
    guard DDCWrite(service, DDCPacket.chipAddress, DDCPacket.dataAddress, request, request.count) else { return nil }
    usleep(50_000)
    var reply = [UInt8](repeating: 0, count: 11)
    guard DDCRead(service, DDCPacket.chipAddress, DDCPacket.dataAddress, &reply, reply.count) else { return nil }
    return reply
}

func probe() {
    print("DDC interface available: \(DDCInterfaceAvailable())")

    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var displayCount: UInt32 = 0
    CGGetActiveDisplayList(16, &ids, &displayCount)
    for id in ids.prefix(Int(displayCount)) {
        print("display \(id): builtin=\(CGDisplayIsBuiltin(id) != 0) vendor=\(CGDisplayVendorNumber(id)) model=\(CGDisplayModelNumber(id)) serial=\(CGDisplaySerialNumber(id)) mirrors=\(CGDisplayMirrorsDisplay(id))")
    }

    var count = 0
    guard let services = DDCCopyExternalServices(&count) else {
        print("no external services")
        return
    }
    defer { DDCFreeServices(services, count) }
    for index in 0..<count {
        let service = services[index]
        let entry = DDCServiceRegistryEntry(service)
        print("\nservice \(index): \(registryName(entry))")
        dumpProperties(entry, indent: "  ")
        var current = entry
        for _ in 0..<4 {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { break }
            print("  parent: \(registryName(parent))")
            dumpProperties(parent, indent: "    ")
            current = parent
        }
        if let reply = readBrightness(service) {
            let hex = reply.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("  brightness reply: \(hex)")
            print("  parsed: \(String(describing: DDCPacket.parseGetReply(reply, code: 0x10)))")
        } else {
            print("  brightness read failed")
        }
    }
}

if CommandLine.arguments.contains("probe") {
    probe()
}
