import AppKit

struct ProcessRow: Sendable {
    let pid: pid_t
    let name: String
    let cpu: Double
    let received: Double
    let sent: Double
}

// The busiest processes, read only while a menu is open. Both tools run as separate processes off
// the main thread.
enum TopProcesses {
    static let limit = 5

    // `ps` is setuid root, so unlike this app it can read every process, system daemons included.
    // Its %CPU is a short decaying average per core, as in Activity Monitor.
    static func byCPU(completion: @escaping @MainActor @Sendable ([ProcessRow]) -> Void) {
        run("/bin/ps", ["-Ao", "pid=,pcpu=,comm=", "-r"]) { output in
            let rows = output.split(whereSeparator: \.isNewline).prefix(limit).compactMap { line in
                let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard fields.count == 3, let pid = pid_t(fields[0]), let cpu = Double(fields[1])
                else { return nil as ProcessRow? }
                let name = (String(fields[2]) as NSString).lastPathComponent
                return ProcessRow(pid: pid, name: name, cpu: cpu, received: 0, sent: 0)
            }
            deliver(rows, to: completion)
        }
    }

    // No public API reports per-process traffic, but `nettop` does. In delta mode its second sample
    // is the traffic over the one second between samples. Only Wi-Fi and wired traffic counts, to
    // match the menu bar total.
    static func byNetwork(completion: @escaping @MainActor @Sendable ([ProcessRow]) -> Void) {
        let arguments = ["-P", "-x", "-d", "-L", "2", "-s", "1", "-t", "wifi", "-t", "wired",
                         "-J", "bytes_in,bytes_out"]
        run("/usr/bin/nettop", arguments) { output in
            // Each sample starts with a header line of column names, which begins with a comma.
            let lines = output.split(whereSeparator: \.isNewline)
            guard let header = lines.lastIndex(where: { $0.hasPrefix(",") }) else {
                deliver([], to: completion)
                return
            }
            let rows = lines[(header + 1)...].compactMap { line -> ProcessRow? in
                // Rows are "name.pid,bytes_in,bytes_out,"; the name itself may contain dots.
                let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                guard fields.count >= 3, let dot = fields[0].lastIndex(of: "."),
                      let pid = pid_t(fields[0][fields[0].index(after: dot)...]),
                      let received = Double(fields[1]), let sent = Double(fields[2]),
                      received + sent > 0
                else { return nil }
                return ProcessRow(pid: pid, name: String(fields[0][..<dot]), cpu: 0,
                                  received: received, sent: sent)
            }
            let top = rows.sorted { $0.received + $0.sent > $1.received + $1.sent }.prefix(limit)
            deliver(Array(top), to: completion)
        }
    }

    // An app's own name where it has one; `nettop` cuts names short.
    @MainActor
    static func displayName(of row: ProcessRow) -> String {
        if let app = NSRunningApplication(processIdentifier: row.pid), let name = app.localizedName {
            return name
        }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(row.pid, &path, UInt32(path.count))
        if length > 0 {
            let bytes = path.prefix(Int(length)).map { UInt8(bitPattern: $0) }
            return (String(decoding: bytes, as: UTF8.self) as NSString).lastPathComponent
        }
        return row.name
    }

    // An open menu runs the main run loop in a mode the main dispatch queue is not served in, so
    // results are queued for the run loop's common modes instead.
    private static func deliver(_ rows: [ProcessRow],
                                to completion: @escaping @MainActor @Sendable ([ProcessRow]) -> Void) {
        let mainLoop = CFRunLoopGetMain()
        CFRunLoopPerformBlock(mainLoop, CFRunLoopMode.commonModes.rawValue) {
            MainActor.assumeIsolated { completion(rows) }
        }
        CFRunLoopWakeUp(mainLoop)
    }

    private static func run(_ path: String, _ arguments: [String],
                            completion: @escaping @Sendable (String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return completion("") }
            // Reading to the end before waiting stops a full pipe from blocking the tool.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            completion(String(decoding: data, as: UTF8.self))
        }
    }
}
