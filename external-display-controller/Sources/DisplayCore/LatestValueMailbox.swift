import Foundation

/// Holds only the newest value, so a held key or a dragged slider sends the latest value and not a queue.
public final class LatestValueMailbox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: Value?
    private var draining = false

    public init() {}

    /// Stores the value. Returns true if the caller must now start draining the mailbox.
    public func put(_ value: Value) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pending = value
        if draining { return false }
        draining = true
        return true
    }

    /// Returns the newest value, or nil and ends the drain if there is none.
    public func take() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let value = pending else {
            draining = false
            return nil
        }
        pending = nil
        return value
    }
}
