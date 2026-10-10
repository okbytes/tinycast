import Foundation

/// Built-in keyboard input → virtual keyboard reports. See docs/features/key-remap.md#the-engine.
struct KeyRemapEngine {
    /// Longest a bound key may be held alone and still count as a quick press.
    static let quickPressWindow: TimeInterval = 0.25

    struct Input: Sendable {
        let usage: HIDUsage
        let isPressed: Bool
        /// Monotonic seconds; only differences are read.
        let time: TimeInterval
    }

    private struct Hold {
        let since: TimeInterval
        var interrupted = false
    }

    private(set) var configuration: KeyRemapConfiguration
    private let topRow: TopRowMap

    private var physicalModifiers: UInt8 = 0
    private var held: [UInt16: Hold] = [:]
    private var pressed: [VirtualHIDReport.Kind: [UInt16]] = [:]
    /// What each top-row key went out as, so its release matches its press if fn moves in between.
    private var sentTopRow: [UInt16: HIDUsage] = [:]
    private var globeHeld = false
    private var lastSent: [VirtualHIDReport.Kind: VirtualHIDReport] = [:]

    init(configuration: KeyRemapConfiguration, topRow: TopRowMap) {
        self.configuration = configuration
        self.topRow = topRow
    }

    /// The reports to post, in order; empty when the input changes nothing the system can see.
    mutating func handle(_ input: Input) -> [VirtualHIDReport] {
        let usage = input.usage
        if usage.page == HIDUsage.keyboardPage {
            guard usage.usage >= HIDUsage.firstKeyUsage else { return [] }
            if let binding = configuration.binding(for: usage.usage) {
                return handleBound(binding, isPressed: input.isPressed, at: input.time)
            }
        }
        guard let kind = Self.kind(forPage: usage.page) else { return [] }
        if input.isPressed { interruptHeld() }
        if usage == .globe { globeHeld = input.isPressed }
        if let bit = usage.modifierBit {
            physicalModifiers = input.isPressed ? physicalModifiers | bit : physicalModifiers & ~bit
        } else if kind == .keyboard, let action = topRow.actions[usage.usage] {
            handleTopRow(usage.usage, action: action, isPressed: input.isPressed)
        } else {
            update(kind, usage.usage, isPressed: input.isPressed)
        }
        return changedReports()
    }

    /// Lifts everything as a seize ends; keys still physically down are ignored on release.
    mutating func releaseAll() -> [VirtualHIDReport] {
        physicalModifiers = 0
        held = [:]
        pressed = [:]
        sentTopRow = [:]
        globeHeld = false
        return changedReports()
    }

    mutating func reconfigure(_ configuration: KeyRemapConfiguration) -> [VirtualHIDReport] {
        let reports = releaseAll()
        self.configuration = configuration
        return reports
    }

    // MARK: - Bound keys

    private mutating func handleBound(
        _ binding: KeyRemapConfiguration.Binding, isPressed: Bool, at time: TimeInterval
    ) -> [VirtualHIDReport] {
        if isPressed {
            guard held[binding.usage] == nil else { return [] }
            let startsAlone = !isOtherInputHeld
            interruptHeld()
            held[binding.usage] = Hold(since: time, interrupted: !startsAlone)
            return changedReports()
        }
        guard let hold = held.removeValue(forKey: binding.usage) else { return [] }
        let reports = changedReports()
        guard !hold.interrupted, time - hold.since < Self.quickPressWindow else { return reports }
        return reports + quickPress(binding.quickPress)
    }

    /// A quick press means the bound key alone, so anything already down rules one out.
    private var isOtherInputHeld: Bool {
        physicalModifiers != 0 || !held.isEmpty || pressed.values.contains { !$0.isEmpty }
    }

    private mutating func interruptHeld() {
        for usage in held.keys { held[usage]?.interrupted = true }
    }

    private mutating func quickPress(_ action: KeyRemapConfiguration.QuickPress) -> [VirtualHIDReport] {
        let usage: HIDUsage
        switch action {
        case .none: return []
        case .escape: usage = .escape
        case .capsLock: usage = .capsLock
        }
        // A tap of a key the user is holding would release it out from under them.
        guard !(pressed[.keyboard] ?? []).contains(usage.usage) else { return [] }
        update(.keyboard, usage.usage, isPressed: true)
        let down = changedReports()
        update(.keyboard, usage.usage, isPressed: false)
        return down + changedReports()
    }

    // MARK: - Top row

    private mutating func handleTopRow(_ key: UInt16, action: HIDUsage, isPressed: Bool) {
        if isPressed {
            // Act where the built-in keyboard's driver would, so the virtual one's never does.
            let sendsAction = globeHeld == configuration.functionKeysAreStandard
            let sent = sendsAction ? action : .key(key)
            sentTopRow[key] = sent
            update(sent, isPressed: true)
        } else {
            update(sentTopRow.removeValue(forKey: key) ?? .key(key), isPressed: false)
        }
    }

    // MARK: - Reports

    private static func kind(forPage page: UInt16) -> VirtualHIDReport.Kind? {
        switch page {
        case HIDUsage.keyboardPage: .keyboard
        case HIDUsage.consumerPage: .consumer
        case HIDUsage.appleVendorTopCasePage: .appleVendorTopCase
        case HIDUsage.appleVendorKeyboardPage: .appleVendorKeyboard
        case HIDUsage.genericDesktopPage: .genericDesktop
        default: nil
        }
    }

    private mutating func update(_ usage: HIDUsage, isPressed: Bool) {
        guard let kind = Self.kind(forPage: usage.page) else { return }
        update(kind, usage.usage, isPressed: isPressed)
    }

    private mutating func update(_ kind: VirtualHIDReport.Kind, _ usage: UInt16, isPressed: Bool) {
        var usages = pressed[kind] ?? []
        if isPressed {
            guard !usages.contains(usage), usages.count < VirtualHIDReport.keyCapacity else { return }
            usages.append(usage)
        } else {
            usages.removeAll { $0 == usage }
        }
        pressed[kind] = usages
    }

    private var outputModifiers: UInt8 {
        held.keys.reduce(physicalModifiers) { bits, usage in
            bits | (configuration.binding(for: usage)?.modifiers ?? 0)
        }
    }

    private func report(_ kind: VirtualHIDReport.Kind) -> VirtualHIDReport {
        let usages = pressed[kind] ?? []
        switch kind {
        case .keyboard: return .keyboard(modifiers: outputModifiers, keys: usages)
        case .consumer: return .consumer(usages)
        case .appleVendorTopCase: return .appleVendorTopCase(usages)
        case .appleVendorKeyboard: return .appleVendorKeyboard(usages)
        case .genericDesktop: return .genericDesktop(usages)
        }
    }

    private mutating func changedReports() -> [VirtualHIDReport] {
        VirtualHIDReport.Kind.allCases.compactMap { kind in
            let current = report(kind)
            guard current != (lastSent[kind] ?? .empty(kind)) else { return nil }
            lastSent[kind] = current
            return current
        }
    }
}
