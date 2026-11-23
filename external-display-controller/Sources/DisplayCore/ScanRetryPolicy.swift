public enum ScanRetryPolicy {
    /// Seconds to wait before each retry of a display that gave no DDC answer. Displays are often not ready just after a wake.
    public static let delays: [Double] = [2, 6]
}
