import Foundation

/// Which adjacent Space a switch command moves to.
enum SpaceDirection: Sendable {
    case previous
    case next

    init?(_ command: WindowCommand.ID) {
        switch command {
        case .previousSpace: self = .previous
        case .nextSpace: self = .next
        default: return nil
        }
    }

    var reversed: SpaceDirection {
        self == .next ? .previous : .next
    }
}

/// The synthetic Dock swipe macOS switches Spaces with, as data rather than events.
enum SpaceGesture {
    /// The Dock ignores a gesture that skips a phase, so all three are always posted.
    enum Phase: Int64, CaseIterable, Sendable {
        case began = 1
        case changed = 2
        case ended = 4
    }

    enum FieldValue: Equatable, Sendable {
        case integer(Int64)
        case double(Double)
    }

    /// One `CGEvent` field write, keyed by raw number so this file needs no CoreGraphics.
    struct Field: Equatable, Sendable {
        let raw: UInt32
        let value: FieldValue
    }

    /// Momentum, not speed: 2000 overshoots by two Spaces, and lowering it costs no latency.
    static let velocity = 1000.0

    /// Phases posted back-to-back coalesce, which lands as a double move.
    static let phaseDelay = Duration.milliseconds(10)

    /// The serialization version `CGEventCreateData` emits; the splice only knows this layout.
    static let dataVersion: [UInt8] = [0, 0, 0, 2]

    // MARK: - Fields

    /// The gesture fields for one phase; the payload carries the rest.
    static func fields(phase: Phase, direction: SpaceDirection, timestamp: UInt64) -> [Field] {
        let sign = direction == .next ? 1.0 : -1.0
        var fields = [
            Field(raw: eventTypeField, value: .integer(dockControlEventType)),
            Field(raw: hidTypeField, value: .integer(dockSwipeHIDType)),
            Field(raw: phaseField, value: .integer(phase.rawValue)),
            Field(raw: progressField, value: .double(sign * progressMagnitude)),
            Field(raw: motionField, value: .integer(horizontalMotion)),
            Field(raw: phaseAliasField, value: .integer(phase.rawValue)),
            Field(raw: zoomDeltaYField, value: .double(zoomDeltaY)),
            Field(raw: processAliasField, value: .double(Double(timestamp))),
            Field(raw: positionXField, value: .double(positionX))
        ]
        // Velocity on any phase but the last makes the Space slide back before it settles.
        if phase == .ended {
            fields.append(Field(raw: velocityXField, value: .double(sign * velocity)))
        }
        return fields
    }

    // MARK: - IOHID payload

    /// The record header `CGEventCreateData` frames a field with: big-endian size, then tag and id.
    static func payloadRecordHeader(payloadCount: Int) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: payloadCount >> 8), UInt8(truncatingIfNeeded: payloadCount),
            UInt8(truncatingIfNeeded: payloadField >> 8), UInt8(truncatingIfNeeded: payloadField)
        ]
    }

    /// The IOHID queue element the Dock validates the gesture against, for `payloadField`.
    static func payload(phase: Phase, direction: SpaceDirection, timestamp: UInt64) -> Data {
        let sign = direction == .next ? 1.0 : -1.0
        let carriesVelocity = phase == .ended

        var payload = queueHeader(
            timestamp: timestamp, eventCount: carriesVelocity ? 2 : 1)
        payload.append(fluidRecord(phase: phase, progress: sign * progressMagnitude))
        guard carriesVelocity else { return payload }
        payload.append(velocityRecord(x: sign * velocity))
        return payload
    }

    /// 16.16 fixed point, floored to ±1 so a value too small to encode never lands on zero.
    static func fixed1616(_ value: Double) -> Int32 {
        let fixed = Int32(value * 65536)
        if fixed == 0, value != 0 { return value > 0 ? 1 : -1 }
        return fixed
    }

    /// `IOHIDSystemQueueElementHeader`: timestamp, sender id, options, attribute length, count.
    private static func queueHeader(timestamp: UInt64, eventCount: UInt32) -> Data {
        var header = Data()
        header.append(littleEndian: timestamp)
        header.append(littleEndian: UInt64(0))
        header.append(littleEndian: UInt32(0))
        header.append(littleEndian: UInt32(0))
        header.append(littleEndian: eventCount)
        return header
    }

    /// `IOHIDFluidTouchGestureData`: position x/y/z, swipe mask, motion, flavour, progress.
    private static func fluidRecord(phase: Phase, progress: Double) -> Data {
        var record = eventBase(
            size: fluidRecordSize, type: fluidTouchGestureType,
            options: UInt32(truncatingIfNeeded: phase.rawValue & 0xFF) << 24, depth: 0)
        record.append(littleEndian: fixed1616(positionX))
        record.append(littleEndian: Int32(0))
        record.append(littleEndian: Int32(0))
        record.append(littleEndian: UInt32(0))
        record.append(littleEndian: UInt16(truncatingIfNeeded: horizontalMotion))
        record.append(littleEndian: dockPrimaryFlavor)
        record.append(littleEndian: fixed1616(progress))
        return record
    }

    /// `IOHIDVelocityEventData`: velocity x/y/z.
    private static func velocityRecord(x: Double) -> Data {
        var record = eventBase(size: velocityRecordSize, type: velocityType, options: 0, depth: 1)
        record.append(littleEndian: fixed1616(x))
        record.append(littleEndian: Int32(0))
        record.append(littleEndian: Int32(0))
        return record
    }

    /// `IOHIDEventBase`: size, type, options, depth, then three reserved bytes.
    private static func eventBase(
        size: UInt32, type: UInt32, options: UInt32, depth: UInt8
    ) -> Data {
        var base = Data()
        base.append(littleEndian: size)
        base.append(littleEndian: type)
        base.append(littleEndian: options)
        base.append(littleEndian: depth)
        base.append(contentsOf: [0, 0, 0])
        return base
    }

    /// One 16.16 step: a real distance makes the WindowServer draw the slide.
    private static let progressMagnitude = 0.000016

    // MARK: - Undocumented constants

    static let payloadField: UInt32 = 4205

    private static let eventTypeField: UInt32 = 55
    private static let hidTypeField: UInt32 = 110
    private static let motionField: UInt32 = 123
    private static let progressField: UInt32 = 124
    private static let positionXField: UInt32 = 125
    private static let velocityXField: UInt32 = 129
    private static let phaseField: UInt32 = 132
    private static let phaseAliasField: UInt32 = 134
    private static let zoomDeltaYField: UInt32 = 138
    private static let processAliasField: UInt32 = 169

    private static let dockControlEventType: Int64 = 30
    private static let dockSwipeHIDType: Int64 = 23
    private static let horizontalMotion: Int64 = 1

    private static let fluidRecordSize: UInt32 = 40
    private static let velocityRecordSize: UInt32 = 28
    private static let fluidTouchGestureType: UInt32 = 23
    private static let velocityType: UInt32 = 9
    private static let dockPrimaryFlavor: UInt16 = 3

    private static let positionX = 0.1
    private static let zoomDeltaY = 3.0
}

extension Data {
    /// The IOHID queue is a packed little-endian layout, so every scalar goes in as raw bytes.
    fileprivate mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
