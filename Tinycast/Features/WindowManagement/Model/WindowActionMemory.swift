import CoreGraphics
import Foundation

/// What Tinycast remembers per moved window. docs/features/window-management.md#cycling
struct WindowActionMemory<Key: Hashable> {
    struct Record: Equatable, Sendable {
        /// Where we *observed* it after our last write — not what we asked for. See `decide`.
        var appliedFrame: CGRect
        var command: WindowCommand.ID
        /// The slot it landed in; a chain continues from here, whatever Settings now says.
        var step: Int
        /// Where it landed; a press from any other display starts a new chain.
        var screenID: Int
        var at: Date
    }

    /// Tolerance for "still the frame we left it at": subpixel drift in, a real drag out.
    static var tolerance: CGFloat { 2 }

    /// Bounded so a long session over many windows can't grow this without limit.
    var capacity: Int
    /// When set, a cold cycle restarts from its first slot rather than continuing mid-sequence.
    var cycleTimeout: TimeInterval?

    private var records: [Key: Record] = [:]
    /// Least-recently-used first, so eviction is a `removeFirst`.
    private var order: [Key] = []

    init(capacity: Int = 64, cycleTimeout: TimeInterval? = nil) {
        self.capacity = capacity
        self.cycleTimeout = cycleTimeout
    }

    var count: Int { records.count }

    func record(for key: Key) -> Record? { records[key] }

    /// The next slot when this press continues a chain, or nil when it starts a new one.
    func decide(
        key: Key, command: WindowCommand.ID, currentFrame: CGRect, currentScreenID: Int,
        cycleLength: Int, now: Date
    ) -> Int? {
        // Against the observed frame, never the requested one. docs/features/window-management.md
        guard let record = records[key],
            currentFrame.approximatelyEquals(record.appliedFrame, tolerance: Self.tolerance)
        else { return nil }

        let expired = cycleTimeout.map { now.timeIntervalSince(record.at) > $0 } ?? false
        let continues =
            cycleLength > 1 && command == record.command
            && currentScreenID == record.screenID && !expired
        return continues ? (record.step + 1) % cycleLength : nil
    }

    /// Records what actually landed. `appliedFrame` must be read back from the window, not assumed.
    mutating func commit(
        key: Key, command: WindowCommand.ID, step: Int, appliedFrame: CGRect, screenID: Int,
        now: Date
    ) {
        records[key] = Record(
            appliedFrame: appliedFrame, command: command, step: step, screenID: screenID, at: now)
        touch(key)
    }

    mutating func forget(where predicate: (Key) -> Bool) {
        let doomed = records.keys.filter(predicate)
        guard !doomed.isEmpty else { return }
        for key in doomed { records.removeValue(forKey: key) }
        order.removeAll { doomed.contains($0) }
    }

    mutating func forget(key: Key) {
        guard records.removeValue(forKey: key) != nil else { return }
        order.removeAll { $0 == key }
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            records.removeValue(forKey: oldest)
        }
    }
}
