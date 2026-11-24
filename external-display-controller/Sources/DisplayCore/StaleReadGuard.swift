/// Drops a read result that arrives after the user changed the value, so it cannot undo the change.
public struct StaleReadGuard {
    private var revisions: [UInt32: Int] = [:]

    public init() {}

    public mutating func markChanged(_ id: UInt32) {
        revisions[id, default: 0] += 1
    }

    public func token(for id: UInt32) -> Int {
        revisions[id, default: 0]
    }

    public func isCurrent(_ token: Int, for id: UInt32) -> Bool {
        revisions[id, default: 0] == token
    }
}
