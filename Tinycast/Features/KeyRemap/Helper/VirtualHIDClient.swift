import Foundation
import os

/// The helper's link to pqrs's daemon. See docs/features/key-remap.md#the-driver-protocol.
final class VirtualHIDClient {
    private static let reconnectInterval: TimeInterval = 1
    /// The daemon answers every request at once, so a slower answer means it has stopped working.
    private static let responseDeadline: TimeInterval = 1
    /// The daemon heartbeats every three seconds; this long without a byte means it is gone.
    private static let silenceDeadline: TimeInterval = 10
    private static let writeTimeout = timeval(tv_sec: 0, tv_usec: 500_000)

    /// The virtual keyboard's product id, matching the built-in keyboard's ANSI, ISO or JIS type.
    private let keyboardProductID: UInt64

    private(set) var isConnected = false
    private(set) var statuses: [VirtualHIDWireFormat.Status: Bool] = [:]
    private(set) var clientProtocolRejected = false
    /// Set by any connection or status change; the worker reacts next tick, never mid-callout.
    private var hasChanged = false

    private var socketDescriptor: Int32 = -1
    private var fileDescriptor: CFFileDescriptor?
    private var runLoopSource: CFRunLoopSource?
    private var decoder = VirtualHIDWireFormat.FrameDecoder()
    private var nextRequestID: UInt64 = 1
    /// Request id → when it was sent, for every request the daemon has not answered yet.
    private var unanswered: [UInt64: TimeInterval] = [:]
    private var initializeRequestID: UInt64?
    private var lastHeartbeat: TimeInterval = 0
    private var lastReceived: TimeInterval = 0
    private var lastConnectAttempt: TimeInterval = -.infinity
    /// Spawned only when no daemon answers, so a Karabiner-Elements install keeps its own.
    private var spawnedDaemon: Process?
    private let logger = Logger(subsystem: KeyboardHelper.subsystem, category: "driver")

    init(keyboardProductID: UInt64) {
        self.keyboardProductID = keyboardProductID
    }

    var isKeyboardReady: Bool { isConnected && statuses[.keyboardReady] == true }

    static var isDriverInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: KeyRemapHelperInterface.driverDaemonPath)
    }

    func takeChange() -> Bool {
        defer { hasChanged = false }
        return hasChanged
    }

    func tick(at now: TimeInterval) {
        guard isConnected else {
            guard now - lastConnectAttempt >= Self.reconnectInterval else { return }
            lastConnectAttempt = now
            connect(at: now)
            return
        }
        if let oldest = unanswered.values.min(), now - oldest > Self.responseDeadline {
            logger.error("the virtual HID daemon stopped answering")
            disconnect()
        } else if now - lastReceived > Self.silenceDeadline {
            logger.error("the virtual HID daemon went silent")
            disconnect()
        } else if now - lastHeartbeat >= VirtualHIDWireFormat.heartbeatInterval {
            lastHeartbeat = now
            send(VirtualHIDWireFormat.heartbeat)
        }
    }

    func post(_ report: VirtualHIDReport) {
        request(report.request, payload: report.bytes)
    }

    /// Lifts everything the virtual keyboard holds, whatever this side last believed it sent.
    func reset() {
        request(.keyboardReset)
    }

    // MARK: - Connection

    private func connect(at now: TimeInterval) {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return }
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = Self.writeTimeout
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        guard Self.connect(descriptor, to: VirtualHIDWireFormat.serverSocketPath) else {
            close(descriptor)
            launchDaemonIfNeeded()
            return
        }
        socketDescriptor = descriptor
        decoder = VirtualHIDWireFormat.FrameDecoder()
        statuses = [:]
        unanswered = [:]
        clientProtocolRejected = false
        lastReceived = now
        lastHeartbeat = now
        isConnected = true
        hasChanged = true
        watchSocket()
        logger.info("connected to the virtual HID daemon")
        let parameters = VirtualHIDWireFormat.keyboardParameters(
            vendorID: VirtualHIDWireFormat.appleKeyboardVendorID, productID: keyboardProductID,
            countryCode: 0)
        initializeRequestID = request(.keyboardInitialize, payload: parameters)
    }

    private static func connect(_ descriptor: Int32, to path: String) -> Bool {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }

    private func launchDaemonIfNeeded() {
        guard spawnedDaemon?.isRunning != true, Self.isDriverInstalled else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: KeyRemapHelperInterface.driverDaemonPath)
        // It keeps its own log under /var/log/karabiner; its console output would only be noise.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            spawnedDaemon = process
            logger.info("started the virtual HID daemon")
        } catch {
            logger.error("could not start the virtual HID daemon: \(error.localizedDescription)")
        }
    }

    private func watchSocket() {
        var context = CFFileDescriptorContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil,
            copyDescription: nil)
        guard
            let descriptor = CFFileDescriptorCreate(
                kCFAllocatorDefault, socketDescriptor, false, socketCallback, &context),
            let source = CFFileDescriptorCreateRunLoopSource(kCFAllocatorDefault, descriptor, 0)
        else {
            disconnect()
            return
        }
        CFFileDescriptorEnableCallBacks(descriptor, kCFFileDescriptorReadCallBack)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        fileDescriptor = descriptor
        runLoopSource = source
    }

    private func disconnect() {
        guard isConnected else { return }
        if let runLoopSource { CFRunLoopSourceInvalidate(runLoopSource) }
        if let fileDescriptor { CFFileDescriptorInvalidate(fileDescriptor) }
        runLoopSource = nil
        fileDescriptor = nil
        close(socketDescriptor)
        socketDescriptor = -1
        isConnected = false
        statuses = [:]
        unanswered = [:]
        initializeRequestID = nil
        hasChanged = true
        logger.info("lost the virtual HID daemon")
    }

    // MARK: - Traffic

    fileprivate func socketReadable() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var count: Int
        repeat {
            count = buffer.withUnsafeMutableBytes { read(socketDescriptor, $0.baseAddress, $0.count) }
        } while count < 0 && errno == EINTR
        guard count > 0 else {
            disconnect()
            return
        }
        lastReceived = ProcessInfo.processInfo.systemUptime
        do {
            for frame in try decoder.append(buffer.prefix(count)) { handle(frame) }
        } catch {
            logger.error("unreadable frame from the virtual HID daemon")
            disconnect()
            return
        }
        guard let fileDescriptor else { return }
        CFFileDescriptorEnableCallBacks(fileDescriptor, kCFFileDescriptorReadCallBack)
    }

    private func handle(_ frame: VirtualHIDWireFormat.Frame) {
        guard isConnected, frame.kind == .request || frame.kind == .response else { return }
        if frame.kind == .request, let id = frame.requestID {
            send(VirtualHIDWireFormat.response(id: id))
        } else if let id = frame.requestID {
            unanswered.removeValue(forKey: id)
            // A rejected version is answered with nothing, where initialization returns statuses.
            if id == initializeRequestID, frame.body.isEmpty {
                logger.fault("the virtual HID daemon rejected this client protocol version")
                clientProtocolRejected = true
                hasChanged = true
            }
        }
        for (status, value) in VirtualHIDWireFormat.statuses(in: frame.body)
        where statuses[status] != value {
            statuses[status] = value
            hasChanged = true
        }
    }

    @discardableResult
    private func request(_ request: VirtualHIDWireFormat.Request, payload: [UInt8] = []) -> UInt64? {
        guard isConnected else { return nil }
        let id = nextRequestID
        nextRequestID += 1
        unanswered[id] = ProcessInfo.processInfo.systemUptime
        send(VirtualHIDWireFormat.request(request, id: id, payload: payload))
        return id
    }

    /// A write that fails or times out drops the connection; the worker releases on its next tick.
    private func send(_ bytes: [UInt8]) {
        guard isConnected else { return }
        let failed = bytes.withUnsafeBytes { raw -> Bool in
            var offset = 0
            while offset < raw.count {
                let written = write(socketDescriptor, raw.baseAddress! + offset, raw.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { return true }
                offset += written
            }
            return false
        }
        if failed { disconnect() }
    }
}

private let socketCallback: CFFileDescriptorCallBack = { _, _, info in
    guard let info else { return }
    Unmanaged<VirtualHIDClient>.fromOpaque(info).takeUnretainedValue().socketReadable()
}
