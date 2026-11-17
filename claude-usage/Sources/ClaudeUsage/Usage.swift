import Foundation

// One rate limit window as Claude Code reports it: how much is used and when it resets.
struct LimitWindow: Equatable {
    let usedPercentage: Double
    let resetsAt: Date

    // Once the reset time has passed, the window is empty again even though no new reading has
    // arrived yet, because the reading only refreshes when Claude Code next talks to the API.
    func remainingPercentage(at now: Date) -> Int {
        guard resetsAt > now else { return 100 }
        return Int((100 - usedPercentage).rounded()).clamped(to: 0...100)
    }
}

struct Usage: Equatable {
    enum Source { case anthropic, claudeCode }

    let fiveHour: LimitWindow?
    let sevenDay: LimitWindow?
    let receivedAt: Date
    var source: Source = .claudeCode

    // The file the capture command writes and the app reads.
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/claude-usage/rate-limits.json")

    static func load(from url: URL = fileURL) -> Usage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    // Reads Claude Code's statusLine JSON, or the file written from it. Both carry `rate_limits`;
    // the file adds `received_at`. Returns nil when there is no rate limit data, which is the case
    // for accounts without subscription limits and before a session's first API response.
    static func decode(_ data: Data, now: Date = Date()) -> Usage? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["rate_limits"] as? [String: Any] else { return nil }
        let fiveHour = window(limits["five_hour"])
        let sevenDay = window(limits["seven_day"])
        guard fiveHour != nil || sevenDay != nil else { return nil }
        let received = (root["received_at"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? now
        return Usage(fiveHour: fiveHour, sevenDay: sevenDay, receivedAt: received)
    }

    // Reads Anthropic's /api/oauth/usage response: `utilization` is the percentage used and
    // `resets_at` an ISO 8601 time.
    static func decodeEndpoint(_ data: Data, now: Date = Date()) -> Usage? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func window(_ value: Any?) -> LimitWindow? {
            guard let dict = value as? [String: Any],
                  let used = dict["utilization"] as? Double,
                  let reset = (dict["resets_at"] as? String).flatMap(parseDate) else { return nil }
            return LimitWindow(usedPercentage: used, resetsAt: reset)
        }
        let fiveHour = window(root["five_hour"])
        let sevenDay = window(root["seven_day"])
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return Usage(fiveHour: fiveHour, sevenDay: sevenDay, receivedAt: now, source: .anthropic)
    }

    private static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func window(_ value: Any?) -> LimitWindow? {
        guard let dict = value as? [String: Any],
              let used = dict["used_percentage"] as? Double,
              let reset = dict["resets_at"] as? Double else { return nil }
        return LimitWindow(usedPercentage: used, resetsAt: Date(timeIntervalSince1970: reset))
    }

    // Writes the file atomically, so the app never reads a half-written one.
    func save(to url: URL = fileURL) throws {
        func object(_ window: LimitWindow?) -> Any {
            guard let window else { return NSNull() }
            return ["used_percentage": window.usedPercentage,
                    "resets_at": window.resetsAt.timeIntervalSince1970]
        }
        let root: [String: Any] = [
            "received_at": receivedAt.timeIntervalSince1970,
            "rate_limits": ["five_hour": object(fiveHour), "seven_day": object(sevenDay)],
        ]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
            .write(to: url, options: .atomic)
    }
}

// `ClaudeUsage capture`, run as Claude Code's statusLine command. Claude Code pipes its status JSON
// to stdin on every update. This keeps the rate limits for the app and prints nothing, so the
// status line stays empty. Anything unexpected is ignored: a status line command must never fail.
func runCapture() {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    try? Usage.decode(input)?.save()
}

enum Format {
    // "2h 14m", "3d 4h", "35m". Days and hours once a window is a day or more away, since minutes
    // mean nothing at that range.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded(.down)))
        let (days, hours, mins) = (minutes / 1440, minutes % 1440 / 60, minutes % 60)
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
