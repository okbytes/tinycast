import Foundation
import Synchronization

/// Where XPC sessions and the keyboard thread meet; nothing else crosses between them.
final class HelperMailbox: Sendable {
    private struct State {
        var nextSession: UInt64 = 1
        var owner: UInt64?
        var desired = KeyRemapConfiguration.off
        var generation: UInt64 = 0
        var status = KeyRemapHelperInterface.Status()
    }

    private let state = Mutex(State())
    /// Uptime nanoseconds of the keyboard thread's last tick, read by `HelperWatchdog`.
    let lastTick = Atomic<UInt64>(0)
    let isSeized = Atomic<Bool>(false)

    var status: KeyRemapHelperInterface.Status { state.withLock { $0.status } }

    func openSession() -> UInt64 {
        state.withLock { state in
            defer { state.nextSession += 1 }
            return state.nextSession
        }
    }

    /// The newest session to send a configuration owns the keyboard.
    func apply(_ configuration: KeyRemapConfiguration, session: UInt64) {
        state.withLock { state in
            state.owner = session
            state.desired = configuration
            state.generation += 1
        }
    }

    /// A stale session closing after a newer one took over must not release the newer one's keys.
    func closeSession(_ session: UInt64) {
        state.withLock { state in
            guard state.owner == session else { return }
            state.owner = nil
            state.desired = .off
            state.generation += 1
        }
    }

    /// The configuration to apply, if it changed since `generation`.
    func desired(after generation: UInt64) -> (configuration: KeyRemapConfiguration, generation: UInt64)? {
        state.withLock { state in
            state.generation == generation ? nil : (state.desired, state.generation)
        }
    }

    func publish(_ status: KeyRemapHelperInterface.Status) {
        state.withLock { $0.status = status }
        isSeized.store(status.seizedKeyboards > 0, ordering: .relaxed)
    }
}
