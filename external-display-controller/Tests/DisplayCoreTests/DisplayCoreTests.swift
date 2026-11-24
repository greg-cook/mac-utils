import Testing
import DisplayCore

@Suite struct DDCPacketTests {
    @Test func setVCPBuildsPacketWithChecksum() {
        // Checksum is 0x6E ^ 0x51 XOR every earlier byte.
        #expect(DDCPacket.setVCP(code: 0x10, value: 50) == [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
    }

    @Test func getRequestBuildsPacketWithChecksum() {
        #expect(DDCPacket.getVCPRequest(code: 0x10) == [0x82, 0x01, 0x10, 0xAC])
    }

    @Test func parsesGoodReply() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00]
        #expect(DDCPacket.parseGetReply(reply, code: 0x10) == VCPValue(current: 50, maximum: 100))
    }

    @Test func rejectsReplyWithErrorResult() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x01, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00]
        #expect(DDCPacket.parseGetReply(reply, code: 0x10) == nil)
    }

    @Test func rejectsReplyForOtherCode() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00]
        #expect(DDCPacket.parseGetReply(reply, code: 0x10) == nil)
    }

    @Test func rejectsShortReply() {
        #expect(DDCPacket.parseGetReply([0x6E, 0x88], code: 0x10) == nil)
    }
}

@Suite struct BrightnessStepTests {
    @Test func stepsUpByOneSixteenth() {
        #expect(BrightnessStep.next(current: 50, maximum: 100, direction: .up) == 56)
    }

    @Test func clampsAtMaximum() {
        #expect(BrightnessStep.next(current: 98, maximum: 100, direction: .up) == 100)
    }

    @Test func clampsAtZero() {
        #expect(BrightnessStep.next(current: 3, maximum: 100, direction: .down) == 0)
    }

    @Test func stepsByAtLeastOne() {
        #expect(BrightnessStep.next(current: 7, maximum: 15, direction: .up) == 8)
    }
}

@Suite struct LatestValueMailboxTests {
    @Test func coalescesToLatestValue() {
        let mailbox = LatestValueMailbox<Int>()
        #expect(mailbox.put(1) == true)
        #expect(mailbox.put(2) == false)
        #expect(mailbox.take() == 2)
        #expect(mailbox.take() == nil)
        #expect(mailbox.put(3) == true)
    }
}

@Suite struct MediaKeyDecoderTests {
    @Test func decodesBrightnessUpPress() {
        let event = MediaKeyDecoder.decode(data1: (2 << 16) | (0xA << 8))
        #expect(event == MediaKeyEvent(key: .up, isDown: true, isRepeat: false))
    }

    @Test func decodesBrightnessDownRelease() {
        let event = MediaKeyDecoder.decode(data1: (3 << 16) | (0xB << 8))
        #expect(event == MediaKeyEvent(key: .down, isDown: false, isRepeat: false))
    }

    @Test func decodesRepeatFlag() {
        let event = MediaKeyDecoder.decode(data1: (3 << 16) | (0xA << 8) | 0x1)
        #expect(event?.isRepeat == true)
    }

    @Test func ignoresOtherKeys() {
        // Key code 0 is sound up.
        #expect(MediaKeyDecoder.decode(data1: (0 << 16) | (0xA << 8)) == nil)
    }
}

@Suite struct KeyRoutingTests {
    @Test func consumesOnControllableDisplay() {
        #expect(KeyRouting.decide(pointerDisplay: 7, controllable: [7, 9]) == .consume(displayID: 7))
    }

    @Test func passesThroughOnOtherDisplay() {
        #expect(KeyRouting.decide(pointerDisplay: 3, controllable: [7]) == .passThrough)
    }

    @Test func passesThroughWithNoPointerDisplay() {
        #expect(KeyRouting.decide(pointerDisplay: nil, controllable: [7]) == .passThrough)
    }

    @Test func passesThroughWithNoControllableDisplay() {
        #expect(KeyRouting.decide(pointerDisplay: 7, controllable: []) == .passThrough)
    }
}

@Suite struct ScanRetryPolicyTests {
    @Test func retriesAfterTwoAndSixSeconds() {
        #expect(ScanRetryPolicy.delays == [2, 6])
    }
}

@Suite struct ServicePairingTests {
    @Test func pairsByPositionWhenCountsMatch() {
        let pairs = ServicePairing.pair(serviceCount: 2, screenIDs: [9, 4])
        #expect(pairs == [ServicePair(service: 0, screen: 4), ServicePair(service: 1, screen: 9)])
    }

    @Test func pairsNothingWhenThereAreMoreScreensThanServices() {
        // One DDC display plus a Sidecar or AirPlay screen: the match would be a guess.
        #expect(ServicePairing.pair(serviceCount: 1, screenIDs: [3, 5]) == [])
    }

    @Test func pairsNothingWhenThereAreMoreServicesThanScreens() {
        #expect(ServicePairing.pair(serviceCount: 2, screenIDs: [3]) == [])
    }

    @Test func pairsNothingWithNoServices() {
        #expect(ServicePairing.pair(serviceCount: 0, screenIDs: []) == [])
    }
}

@Suite struct StaleReadGuardTests {
    @Test func readStartedBeforeAChangeIsStale() {
        var guardian = StaleReadGuard()
        let token = guardian.token(for: 7)
        guardian.markChanged(7)
        #expect(guardian.isCurrent(token, for: 7) == false)
    }

    @Test func readWithNoChangeIsCurrent() {
        var guardian = StaleReadGuard()
        let token = guardian.token(for: 7)
        guardian.markChanged(8)
        #expect(guardian.isCurrent(token, for: 7) == true)
    }
}

@Suite struct FailureTrackerTests {
    @Test func reportsAfterTwoFailuresInARow() {
        var tracker = FailureTracker()
        #expect(tracker.record(success: false) == false)
        #expect(tracker.record(success: false) == true)
    }

    @Test func aSuccessResetsTheCount() {
        var tracker = FailureTracker()
        _ = tracker.record(success: false)
        _ = tracker.record(success: true)
        #expect(tracker.record(success: false) == false)
    }
}
