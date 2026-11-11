import Darwin

// Share of time all cores spent busy since the previous sample, as a percentage.
final class CPUUsage {
    private let host = mach_host_self()
    private var previous = host_cpu_load_info()

    init() { previous = read() }

    func sample() -> Double {
        let current = read()
        func delta(_ state: Int32) -> Double {
            let index = Int(state)
            return Double(tuple(current)[index] &- tuple(previous)[index])
        }
        let busy = delta(CPU_STATE_USER) + delta(CPU_STATE_SYSTEM) + delta(CPU_STATE_NICE)
        let total = busy + delta(CPU_STATE_IDLE)
        previous = current
        return total > 0 ? busy / total * 100 : 0
    }

    private func read() -> host_cpu_load_info {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return info
    }

    private func tuple(_ info: host_cpu_load_info) -> [UInt32] {
        let ticks = info.cpu_ticks
        return [ticks.0, ticks.1, ticks.2, ticks.3]
    }
}

// Bytes per second received and sent over the physical (en*) interfaces since the previous
// sample. Tunnels such as VPNs are left out because their traffic also crosses a physical
// interface and would be counted twice.
final class NetworkThroughput {
    private var previous: [String: (received: UInt32, sent: UInt32)]
    private var previousTime = ContinuousClock.now

    init() { previous = Self.read() }

    func sample() -> (received: Double, sent: Double) {
        let current = Self.read()
        let now = ContinuousClock.now
        let elapsed = (now - previousTime) / .seconds(1)
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (name, counters) in current {
            guard let old = previous[name] else { continue }
            // The counters are 32-bit, so wrapping subtraction survives a rollover.
            received += UInt64(counters.received &- old.received)
            sent += UInt64(counters.sent &- old.sent)
        }
        previous = current
        previousTime = now
        guard elapsed > 0 else { return (0, 0) }
        return (Double(received) / elapsed, Double(sent) / elapsed)
    }

    private static func read() -> [String: (received: UInt32, sent: UInt32)] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [:] }
        defer { freeifaddrs(first) }
        var counters: [String: (received: UInt32, sent: UInt32)] = [:]
        var next = first
        while let entry = next?.pointee {
            next = entry.ifa_next
            guard entry.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self).pointee
            else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") else { continue }
            counters[name] = (data.ifi_ibytes, data.ifi_obytes)
        }
        return counters
    }
}
