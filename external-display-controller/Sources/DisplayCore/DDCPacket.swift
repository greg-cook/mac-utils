/// A brightness-style reading from a display: the current value and the largest value it accepts.
public struct VCPValue: Equatable, Sendable {
    public let current: UInt16
    public let maximum: UInt16

    public init(current: UInt16, maximum: UInt16) {
        self.current = current
        self.maximum = maximum
    }
}

/// Builds and reads the DDC/CI messages sent over the display's I2C channel.
public enum DDCPacket {
    /// The display's DDC/CI address on the I2C bus.
    public static let chipAddress: UInt32 = 0x37
    /// The offset every DDC/CI message is written to. It doubles as the host's source address.
    public static let dataAddress: UInt32 = 0x51

    // The checksum starts from the destination address (0x6E, the chip address shifted left) XOR the source.
    private static let checksumSeed: UInt8 = 0x6E ^ 0x51

    private static func withChecksum(_ bytes: [UInt8]) -> [UInt8] {
        bytes + [bytes.reduce(checksumSeed, ^)]
    }

    public static func setVCP(code: UInt8, value: UInt16) -> [UInt8] {
        withChecksum([0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    public static func getVCPRequest(code: UInt8) -> [UInt8] {
        withChecksum([0x82, 0x01, code])
    }

    /// Reads a "get VCP feature" reply. Returns nil for a short reply, an error result or another feature.
    public static func parseGetReply(_ bytes: [UInt8], code: UInt8) -> VCPValue? {
        guard bytes.count >= 10, bytes[2] == 0x02, bytes[3] == 0x00, bytes[4] == code else { return nil }
        let maximum = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        let current = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
        return VCPValue(current: current, maximum: maximum)
    }
}
