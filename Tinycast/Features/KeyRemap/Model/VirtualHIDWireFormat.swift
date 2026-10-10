import Foundation

/// pqrs's daemon client protocol. See docs/features/key-remap.md#the-driver-protocol.
enum VirtualHIDWireFormat {
    /// The daemon answers a request carrying any other version with an empty reply and ignores it.
    static let clientProtocolVersion: UInt16 = 7
    /// pqrs's ids for an Apple Aluminum keyboard of each `StandardType`: ANSI, ISO, JIS.
    static let appleKeyboardVendorID: UInt64 = 0x05AC
    static func appleKeyboardProductID(standardType: Int) -> UInt64 {
        switch standardType {
        case 1: 0x0250
        case 2: 0x0251
        default: 0x024F
        }
    }
    static let serverSocketPath =
        "/Library/Application Support/org.pqrs/tmp/rootonly/karabiner_virtual_hid_device_service.sock"
    /// The daemon closes a peer it has not heard from for longer than its read timeout.
    static let heartbeatInterval: TimeInterval = 3
    private static let maxPayloadSize = 1024
    private static let headerSize = 4
    private static let requestIDSize = 8

    enum Request: UInt8, Sendable {
        case keyboardInitialize = 0
        case keyboardTerminate = 1
        case keyboardReset = 2
        case postKeyboard = 6
        case postConsumer = 7
        case postAppleVendorKeyboard = 8
        case postAppleVendorTopCase = 9
        case postGenericDesktop = 10
    }

    /// What the daemon reports, as `(status, value)` byte pairs in pushes and responses.
    enum Status: UInt8, Sendable {
        case driverActivated = 1
        case driverConnected = 2
        case driverVersionMismatched = 3
        case keyboardReady = 4
    }

    enum FrameKind: UInt8, Sendable {
        case heartbeat = 0
        case userData = 1
        case healthCheck = 2
        case healthCheckResponse = 3
        case request = 4
        case response = 5
    }

    struct Frame: Equatable, Sendable {
        let kind: FrameKind
        let requestID: UInt64?
        let body: [UInt8]
    }

    enum DecodeError: Error, Equatable {
        case badLength(Int)
        case unknownKind(UInt8)
    }

    static let heartbeat: [UInt8] = bigEndian(UInt32(1)) + [FrameKind.heartbeat.rawValue]

    static func request(_ request: Request, id: UInt64, payload: [UInt8] = []) -> [UInt8] {
        let body = littleEndian(clientProtocolVersion) + [request.rawValue] + payload
        return requestResponseFrame(.request, id: id, body: body)
    }

    /// The empty acknowledgement every status push from the daemon expects.
    static func response(id: UInt64) -> [UInt8] {
        requestResponseFrame(.response, id: id, body: [])
    }

    /// The driver's `virtual_hid_keyboard_parameters`: three 64-bit fields in native order.
    static func keyboardParameters(vendorID: UInt64, productID: UInt64, countryCode: UInt64)
        -> [UInt8]
    {
        littleEndian(vendorID) + littleEndian(productID) + littleEndian(countryCode)
    }

    /// Known statuses in a response or push body; unknown status bytes are skipped, not fatal.
    static func statuses(in body: [UInt8]) -> [(Status, Bool)] {
        stride(from: 0, to: body.count - 1, by: 2).compactMap { index in
            Status(rawValue: body[index]).map { ($0, body[index + 1] != 0) }
        }
    }

    /// Reassembles frames from a stream socket, which may split or join them arbitrarily.
    struct FrameDecoder: Sendable {
        private var buffer: [UInt8] = []

        mutating func append(_ bytes: some Sequence<UInt8>) throws(DecodeError) -> [Frame] {
            buffer.append(contentsOf: bytes)
            var frames: [Frame] = []
            while buffer.count >= headerSize {
                let length = buffer[0..<headerSize].reduce(0) { $0 << 8 | Int($1) }
                guard length >= 1, length <= maxPayloadSize + 1 + requestIDSize else {
                    throw .badLength(length)
                }
                guard buffer.count >= headerSize + length else { break }
                let body = Array(buffer[headerSize..<headerSize + length])
                buffer.removeFirst(headerSize + length)
                frames.append(try Self.frame(from: body))
            }
            return frames
        }

        private static func frame(from body: [UInt8]) throws(DecodeError) -> Frame {
            guard let kind = FrameKind(rawValue: body[0]) else { throw .unknownKind(body[0]) }
            guard kind == .request || kind == .response else {
                return Frame(kind: kind, requestID: nil, body: Array(body.dropFirst()))
            }
            guard body.count >= 1 + requestIDSize else { throw .badLength(body.count) }
            let id = body[1...requestIDSize].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            return Frame(kind: kind, requestID: id, body: Array(body.dropFirst(1 + requestIDSize)))
        }
    }

    private static func requestResponseFrame(_ kind: FrameKind, id: UInt64, body: [UInt8])
        -> [UInt8]
    {
        let frameBody = [kind.rawValue] + bigEndian(id) + body
        return bigEndian(UInt32(frameBody.count)) + frameBody
    }

    private static func bigEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian, Array.init)
    }

    private static func littleEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }
}
