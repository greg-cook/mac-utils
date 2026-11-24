/// Counts failed writes in a row, so a display that stopped answering can be dropped.
public struct FailureTracker: Sendable {
    private let limit: Int
    private var failures = 0

    public init(limit: Int = 2) {
        self.limit = limit
    }

    /// Returns true when the failures in a row reach the limit.
    public mutating func record(success: Bool) -> Bool {
        if success {
            failures = 0
            return false
        }
        failures += 1
        return failures >= limit
    }
}
