public enum KeyAction: Equatable, Sendable {
    case passThrough
    case consume(displayID: UInt32)
}

public enum KeyRouting {
    /// A key changes the display under the pointer when that display answers DDC. Anything else passes through.
    public static func decide(pointerDisplay: UInt32?, controllable: Set<UInt32>) -> KeyAction {
        guard let display = pointerDisplay, controllable.contains(display) else { return .passThrough }
        return .consume(displayID: display)
    }
}
