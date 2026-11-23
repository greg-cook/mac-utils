public struct MediaKeyEvent: Equatable, Sendable {
    public let key: Direction
    public let isDown: Bool
    public let isRepeat: Bool

    public init(key: Direction, isDown: Bool, isRepeat: Bool) {
        self.key = key
        self.isDown = isDown
        self.isRepeat = isRepeat
    }
}

public enum MediaKeyDecoder {
    // NX_KEYTYPE_BRIGHTNESS_UP and NX_KEYTYPE_BRIGHTNESS_DOWN from IOKit's ev_keymap.h.
    private static let brightnessUp = 2
    private static let brightnessDown = 3

    /// Decodes the `data1` field of a system-defined media key event. Returns nil for any other key.
    public static func decode(data1: Int) -> MediaKeyEvent? {
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let flags = data1 & 0x0000FFFF
        let key: Direction
        switch keyCode {
        case brightnessUp: key = .up
        case brightnessDown: key = .down
        default: return nil
        }
        return MediaKeyEvent(key: key, isDown: (flags & 0xFF00) >> 8 == 0xA, isRepeat: flags & 0x1 == 1)
    }
}
