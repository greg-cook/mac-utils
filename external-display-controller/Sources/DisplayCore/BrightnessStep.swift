public enum Direction: Sendable {
    case up, down
}

public enum BrightnessStep {
    /// One key press moves the value by 1/16 of the range, and by at least 1.
    public static func next(current: Int, maximum: Int, direction: Direction) -> Int {
        let step = max(1, maximum / 16)
        switch direction {
        case .up: return min(maximum, current + step)
        case .down: return max(0, current - step)
        }
    }
}
