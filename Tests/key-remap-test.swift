import Foundation

/// Expected bytes are written by hand from pqrs's packed structs, never produced by the encoder.
@main
struct KeyRemapTests {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        expect(actual == expected, "\(message) — got \(actual), want \(expected)")
    }

    static func main() {
        wireFrames()
        frameDecoding()
        reportPacking()
        topRowParsing()
        engineChords()
        engineQuickPress()
        engineTopRow()
        engineRelease()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Wire format

    static func wireFrames() {
        expect(VirtualHIDWireFormat.heartbeat, [0, 0, 0, 1, 0], "a heartbeat is a bare kind byte")
        expect(
            VirtualHIDWireFormat.response(id: 0x0102_0304_0506_0708),
            [0, 0, 0, 9, 5, 1, 2, 3, 4, 5, 6, 7, 8],
            "a response carries a big-endian request id and no body")

        let hyper = VirtualHIDReport.keyboard(modifiers: 0x0F, keys: [0x1A])
        let frame = VirtualHIDWireFormat.request(.postKeyboard, id: 1, payload: hyper.bytes)
        expect(frame.count, 4 + 1 + 8 + 2 + 1 + 67, "a keyboard post is header, id, version, kind, report")
        expect(
            Array(frame.prefix(17)), [0, 0, 0, 79, 4, 0, 0, 0, 0, 0, 0, 0, 1, 7, 0, 6, 1],
            "length and id are big-endian; protocol version 7 is little-endian")
        expect(Array(frame[17..<21]), [0x0F, 0, 0x1A, 0], "modifiers, reserved, then a 16-bit usage")

        expect(
            VirtualHIDWireFormat.keyboardParameters(vendorID: 0x05AC, productID: 0x024F, countryCode: 0),
            [0xAC, 0x05, 0, 0, 0, 0, 0, 0, 0x4F, 0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            "keyboard parameters are three native 64-bit fields")
    }

    static func frameDecoding() {
        let push: [UInt8] = [0, 0, 0, 15, 4, 0, 0, 0, 0, 0, 0, 0, 7, 1, 1, 2, 0, 4, 1]
        var decoder = VirtualHIDWireFormat.FrameDecoder()
        let first = (try? decoder.append(push.prefix(6))) ?? []
        expect(first.isEmpty, "a split frame waits for the rest")
        let rest = (try? decoder.append(push.dropFirst(6) + VirtualHIDWireFormat.heartbeat)) ?? []
        expect(rest.map(\.kind), [.request, .heartbeat], "a joined frame and heartbeat both come out")
        expect(rest.first?.requestID, 7, "the status push keeps its request id for the reply")

        let statuses = VirtualHIDWireFormat.statuses(in: rest.first?.body ?? [])
        expect(statuses.map(\.0), [.driverActivated, .driverConnected, .keyboardReady], "status kinds")
        expect(statuses.map(\.1), [true, false, true], "status values")

        var broken = VirtualHIDWireFormat.FrameDecoder()
        expect(
            (try? broken.append([0, 0, 0, 0])) == nil,
            "a zero-length frame is a desync, not something to skip")
    }

    static func reportPacking() {
        let sizes = VirtualHIDReport.Kind.allCases.map { VirtualHIDReport.empty($0).bytes.count }
        expect(sizes, [67, 65, 65, 65, 65], "each report matches its packed struct's size")
        let ids = VirtualHIDReport.Kind.allCases.map { VirtualHIDReport.empty($0).bytes[0] }
        expect(ids, [1, 2, 3, 4, 7], "report ids match the driver's descriptor")
        expect(
            Array(VirtualHIDReport.consumer([0x221]).bytes.prefix(5)), [2, 0x21, 0x02, 0, 0],
            "consumer usages above 0xFF keep their high byte")
    }

    // MARK: - Top row

    static let builtInMap =
        "0x0007003a,0x00ff0005,0x0007003b,0x00ff0004,0x0007003c,0xff010010,0x0007003d,0x000c0221,"
        + "0x0007003e,0x000c00cf,0x0007003f,0x0001009b,0x00070040,0x000c00b4,0x00070041,0x000c00cd,"
        + "0x00070042,0x000c00b3,0x00070043,0x000c00e2,0x00070044,0x000c00ea,0x00070045,0x000c00e9"

    static func topRowParsing() {
        let map = TopRowMap(registryValue: builtInMap)
        expect(map.actions.count, 12, "all twelve F-keys parse")
        expect(map.actions[0x3A], HIDUsage(page: 0xFF, usage: 0x05), "F1 dims through the top case")
        expect(map.actions[0x3D], HIDUsage(page: 0x0C, usage: 0x221), "F4 is Spotlight")
        expect(map.actions[0x3F], HIDUsage(page: 0x01, usage: 0x9B), "F6 is Do Not Disturb")
        expect(TopRowMap(registryValue: "0x0007003a,garbage").actions.isEmpty, "a broken pair is skipped")
    }

    // MARK: - Engine

    static let rightCommand: UInt16 = 0xE7
    static let rightOption: UInt16 = 0xE6
    static let leftShift: UInt16 = 0xE1
    static let w: UInt16 = 0x1A
    static let f12: UInt16 = 0x45

    static func engine(functionKeysAreStandard: Bool = false) -> KeyRemapEngine {
        let configuration = KeyRemapConfiguration(
            bindings: [
                .init(usage: rightCommand, modifiers: 0x0F, quickPress: .none),
                .init(usage: rightOption, modifiers: 0x07, quickPress: .none),
                .init(usage: HIDUsage.capsLock.usage, modifiers: 0x0D, quickPress: .escape),
            ],
            functionKeysAreStandard: functionKeysAreStandard)
        return KeyRemapEngine(configuration: configuration, topRow: TopRowMap(registryValue: builtInMap))
    }

    static func key(_ usage: UInt16, _ isPressed: Bool, at time: TimeInterval = 0)
        -> KeyRemapEngine.Input
    {
        .init(usage: .key(usage), isPressed: isPressed, time: time)
    }

    static func engineChords() {
        var e = engine()
        expect(e.handle(key(rightCommand, true)), [.keyboard(modifiers: 0x0F, keys: [])], "Hyper holds ⌃⌥⇧⌘")
        expect(e.handle(key(w, true)), [.keyboard(modifiers: 0x0F, keys: [w])], "Hyper+W")
        expect(e.handle(key(w, false)), [.keyboard(modifiers: 0x0F, keys: [])], "W lifts alone")
        expect(e.handle(key(rightCommand, false)), [.keyboard(modifiers: 0, keys: [])], "Hyper lifts")

        expect(e.handle(key(rightOption, true)), [.keyboard(modifiers: 0x07, keys: [])], "Meh is ⌃⌥⇧")
        expect(e.handle(key(leftShift, true)), [], "a physical modifier already held changes nothing")
        expect(e.handle(key(rightOption, false)), [.keyboard(modifiers: 0x02, keys: [])], "Left ⇧ stays")
        expect(e.handle(key(leftShift, false)), [.keyboard(modifiers: 0, keys: [])], "and then lifts")

        expect(e.handle(key(0x01, true)), [], "rollover codes are not keys")
        expect(e.handle(.init(usage: .init(page: 0xFF00, usage: 3), isPressed: true, time: 0)), [], "unknown page")
    }

    static func engineQuickPress() {
        let caps = HIDUsage.capsLock.usage
        var e = engine()
        _ = e.handle(key(caps, true, at: 0))
        expect(
            e.handle(key(caps, false, at: 0.1)),
            [
                .keyboard(modifiers: 0, keys: []), .keyboard(modifiers: 0, keys: [0x29]),
                .keyboard(modifiers: 0, keys: []),
            ],
            "a lone quick press lifts the chord, then taps Escape")

        _ = e.handle(key(caps, true, at: 1))
        expect(e.handle(key(caps, false, at: 1.3)), [.keyboard(modifiers: 0, keys: [])], "a long hold is not a tap")

        _ = e.handle(key(caps, true, at: 2))
        _ = e.handle(key(w, true, at: 2.05))
        _ = e.handle(key(w, false, at: 2.08))
        expect(e.handle(key(caps, false, at: 2.1)), [.keyboard(modifiers: 0, keys: [])], "a chord is not a tap")

        _ = e.handle(key(0xE0, true, at: 3))
        _ = e.handle(key(caps, true, at: 3.05))
        expect(
            e.handle(key(caps, false, at: 3.1)), [.keyboard(modifiers: 0x01, keys: [])],
            "a tap made while Control was already down sends no ⌃Escape")
        _ = e.handle(key(0xE0, false, at: 3.2))

        _ = e.handle(key(0x29, true, at: 4))
        _ = e.handle(key(caps, true, at: 4.05))
        expect(
            e.handle(key(caps, false, at: 4.1)), [.keyboard(modifiers: 0, keys: [0x29])],
            "a tap made while Escape is held leaves Escape held")
    }

    static func engineTopRow() {
        var media = engine()
        expect(media.handle(key(f12, true)), [.consumer([0xE9])], "F12 alone turns the volume up")
        expect(media.handle(key(f12, false)), [.consumer([])], "and releases as volume")

        let globe = KeyRemapEngine.Input(usage: .globe, isPressed: true, time: 0)
        let globeUp = KeyRemapEngine.Input(usage: .globe, isPressed: false, time: 0)
        expect(media.handle(globe), [.appleVendorTopCase([3])], "Globe passes through")
        expect(media.handle(key(f12, true)), [.keyboard(modifiers: 0, keys: [f12])], "fn+F12 is F12")
        _ = media.handle(globeUp)
        expect(media.handle(key(f12, false)), [.keyboard(modifiers: 0, keys: [])], "release matches the press")

        var standard = engine(functionKeysAreStandard: true)
        expect(standard.handle(key(f12, true)), [.keyboard(modifiers: 0, keys: [f12])], "standard F-keys")
        _ = standard.handle(key(f12, false))
        _ = standard.handle(globe)
        expect(standard.handle(key(f12, true)), [.consumer([0xE9])], "fn flips to volume")
    }

    static func engineRelease() {
        var e = engine()
        _ = e.handle(key(rightCommand, true))
        _ = e.handle(key(w, true))
        expect(e.releaseAll(), [.keyboard(modifiers: 0, keys: [])], "releasing lifts the chord and the key")
        expect(e.handle(key(w, false)), [], "a key lifted after the release is ignored")
        expect(e.handle(key(rightCommand, false)), [], "so is the bound key")
    }
}
