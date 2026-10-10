import Foundation
import os

/// Owns the whole keyboard path on one dedicated thread, so the hot path takes no lock and no hop.
final class RemapWorker {
    private static let tickInterval: TimeInterval = 0.25
    private static let seizeRetryInterval: TimeInterval = 1
    /// launchd starts the helper again on Tinycast's next message, so an idle one need not linger.
    private static let idleExitDelay: TimeInterval = 30

    private let mailbox: HelperMailbox
    private let client: VirtualHIDClient
    private let seizer = KeyboardSeizer()
    private var engine: KeyRemapEngine?
    private var configuration = KeyRemapConfiguration.off
    private var generation: UInt64 = 0
    private var lastSeizeAttempt: TimeInterval = -.infinity
    private var idleSince: TimeInterval?
    /// The executable as it was at launch; an app update replaces it, and this copy must go.
    private let launchedExecutable = RemapWorker.executableIdentity()
    private let logger = Logger(subsystem: KeyboardHelper.subsystem, category: "worker")

    init(mailbox: HelperMailbox) {
        self.mailbox = mailbox
        client = VirtualHIDClient(
            keyboardProductID: VirtualHIDWireFormat.appleKeyboardProductID(
                standardType: KeyboardSeizer.builtInStandardType()))
    }

    func run() -> Never {
        seizer.onInput = { [unowned self] input in
            guard let reports = engine?.handle(input) else { return }
            post(reports)
        }
        let timer = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault, CFAbsoluteTimeGetCurrent(), Self.tickInterval, 0, 0
        ) { [unowned self] _ in tick() }
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
        publishStatus()
        while true { CFRunLoopRun() }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        mailbox.lastTick.store(clock_gettime_nsec_np(CLOCK_UPTIME_RAW), ordering: .relaxed)
        client.tick(at: now)
        if seizer.takeRemoval() { releaseKeyboard() }
        var needsReconcile = client.takeChange()
        if let update = mailbox.desired(after: generation) {
            generation = update.generation
            configuration = update.configuration
            needsReconcile = true
        }
        if needsReconcile || (wantsKeyboard && !seizer.isSeized) { reconcile() }
        exitIfIdleOrReplaced(at: now)
    }

    /// Only hold the keyboard while every report can reach the virtual one; otherwise it is dead.
    private var wantsKeyboard: Bool {
        !configuration.bindings.isEmpty && client.isKeyboardReady
    }

    private func reconcile() {
        defer { publishStatus() }
        guard wantsKeyboard else {
            releaseKeyboard()
            return
        }
        if seizer.isSeized {
            guard engine?.configuration != configuration, let reports = engine?.reconfigure(configuration)
            else { return }
            post(reports)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSeizeAttempt >= Self.seizeRetryInterval else { return }
        lastSeizeAttempt = now
        // Armed before the device is opened, so a stall anywhere in acquisition is still caught.
        mailbox.isSeized.store(true, ordering: .relaxed)
        client.reset()
        guard let topRow = seizer.seize() else { return }
        VirtualKeyboardTuning.disableCapsLockDelay()
        engine = KeyRemapEngine(configuration: configuration, topRow: topRow)
    }

    /// Hands the physical keyboard back first, then lifts whatever the virtual one still holds.
    private func releaseKeyboard() {
        guard seizer.isSeized || engine != nil else { return }
        mailbox.isSeized.store(true, ordering: .relaxed)
        seizer.release()
        if let reports = engine?.releaseAll() { post(reports) }
        client.reset()
        engine = nil
        publishStatus()
    }

    private func post(_ reports: [VirtualHIDReport]) {
        for report in reports { client.post(report) }
    }

    private func exitIfIdleOrReplaced(at now: TimeInterval) {
        if Self.executableIdentity() != launchedExecutable {
            logger.info("the helper was replaced; exiting so launchd starts the new one")
            releaseKeyboard()
            exit(EXIT_SUCCESS)
        }
        guard configuration.bindings.isEmpty, !seizer.isSeized else {
            idleSince = nil
            return
        }
        let since = idleSince ?? now
        idleSince = since
        guard now - since >= Self.idleExitDelay else { return }
        logger.info("idle; exiting until Tinycast needs the keyboard again")
        exit(EXIT_SUCCESS)
    }

    /// Inode and modification time, which an app update or rebuild changes.
    private static func executableIdentity() -> [Int] {
        guard let path = Bundle.main.executablePath,
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        else { return [] }
        let inode = (attributes[.systemFileNumber] as? NSNumber)?.intValue ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return [inode, Int(modified)]
    }

    private func publishStatus() {
        mailbox.publish(
            KeyRemapHelperInterface.Status(
                driverInstalled: VirtualHIDClient.isDriverInstalled,
                daemonReachable: client.isConnected,
                driverActivated: client.statuses[.driverActivated] == true,
                driverConnected: client.statuses[.driverConnected] == true,
                driverVersionMismatched: client.statuses[.driverVersionMismatched] == true,
                clientProtocolRejected: client.clientProtocolRejected,
                virtualKeyboardReady: client.isKeyboardReady,
                builtInKeyboards: seizer.builtInCount,
                seizedKeyboards: seizer.seizedCount,
                seizeFailure: seizer.lastFailure))
    }
}
