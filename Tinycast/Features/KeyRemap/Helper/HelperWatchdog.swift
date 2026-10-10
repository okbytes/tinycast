import Foundation
import os

/// Exits if the keyboard thread stalls while holding the keyboard; the kernel then gives it back.
enum HelperWatchdog {
    private static let stallLimit: UInt64 = 2_000_000_000
    private static let checkInterval: TimeInterval = 0.5

    static func start(mailbox: HelperMailbox) {
        let thread = Thread {
            let logger = Logger(subsystem: KeyboardHelper.subsystem, category: "watchdog")
            while true {
                Thread.sleep(forTimeInterval: checkInterval)
                guard mailbox.isSeized.load(ordering: .relaxed) else { continue }
                let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                let last = mailbox.lastTick.load(ordering: .relaxed)
                guard now > last, now - last > stallLimit else { continue }
                logger.fault("keyboard thread stalled while seized; exiting to release the keyboard")
                // `_exit`: atexit teardown could block on a lock the stalled thread holds.
                _exit(EX_SOFTWARE)
            }
        }
        thread.name = "watchdog"
        thread.start()
    }
}
