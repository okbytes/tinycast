import Foundation

/// The built-in keyboard's F-key → system-action table. See docs/features/key-remap.md#the-top-row.
struct TopRowMap: Equatable, Sendable {
    /// Keyboard-page F-key usage → the usage it sends as a system action (brightness, media, …).
    let actions: [UInt16: HIDUsage]

    static let registryKey = "FnFunctionUsageMap"

    init(actions: [UInt16: HIDUsage]) {
        self.actions = actions
    }

    /// Parses the registry's comma-separated `0xPPPPUUUU` pairs; a malformed pair is skipped.
    init(registryValue: String) {
        let numbers = registryValue.split(separator: ",").map {
            UInt32($0.trimmingCharacters(in: .whitespaces).dropFirst(2), radix: 16)
        }
        var actions: [UInt16: HIDUsage] = [:]
        for index in stride(from: 0, to: numbers.count - 1, by: 2) {
            guard let source = numbers[index].map(HIDUsage.init(packed:)),
                let target = numbers[index + 1].map(HIDUsage.init(packed:)),
                source.page == HIDUsage.keyboardPage
            else { continue }
            actions[source.usage] = target
        }
        self.actions = actions
    }
}
