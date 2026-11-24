public struct ServicePair: Equatable, Sendable {
    public let service: Int
    public let screen: UInt32

    public init(service: Int, screen: UInt32) {
        self.service = service
        self.screen = screen
    }
}

public enum ServicePairing {
    /// No property links a DDC service to its screen, so they pair by position. A pair is a guess unless the
    /// counts are equal, so any other count pairs nothing. Sidecar and AirPlay screens have no DDC service.
    public static func pair(serviceCount: Int, screenIDs: [UInt32]) -> [ServicePair] {
        guard serviceCount == screenIDs.count else { return [] }
        return screenIDs.sorted().enumerated().map { ServicePair(service: $0.offset, screen: $0.element) }
    }
}
