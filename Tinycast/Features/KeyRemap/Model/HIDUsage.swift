import Foundation

/// One HID usage: a page and a usage on it, as a seized keyboard reports them.
struct HIDUsage: Hashable, Sendable, CustomStringConvertible {
    let page: UInt16
    let usage: UInt16

    static let keyboardPage: UInt16 = 0x07
    static let consumerPage: UInt16 = 0x0C
    static let genericDesktopPage: UInt16 = 0x01
    static let appleVendorTopCasePage: UInt16 = 0x00FF
    static let appleVendorKeyboardPage: UInt16 = 0xFF01

    /// The top-case usage Apple keyboards report for fn / Globe.
    static let globe = HIDUsage(page: appleVendorTopCasePage, usage: 0x03)
    static let escape = HIDUsage(page: keyboardPage, usage: 0x29)
    static let capsLock = HIDUsage(page: keyboardPage, usage: 0x39)

    /// Keyboard-page usages below this are error and rollover codes, never keys.
    static let firstKeyUsage: UInt16 = 0x04
    /// Left Control through Right Command, reported as bits rather than array entries.
    static let modifierUsages: ClosedRange<UInt16> = 0xE0...0xE7

    init(page: UInt16, usage: UInt16) {
        self.page = page
        self.usage = usage
    }

    /// Apple's registry maps pack a usage as `page << 16 | usage`.
    init(packed: UInt32) {
        self.init(page: UInt16(packed >> 16), usage: UInt16(packed & 0xFFFF))
    }

    static func key(_ usage: UInt16) -> HIDUsage { HIDUsage(page: keyboardPage, usage: usage) }

    /// The HID modifier bit for Left Control (bit 0) through Right Command (bit 7), if this is one.
    var modifierBit: UInt8? {
        guard page == Self.keyboardPage, Self.modifierUsages.contains(usage) else { return nil }
        return 1 << UInt8(usage - Self.modifierUsages.lowerBound)
    }

    var description: String {
        "0x\(String(page, radix: 16))/0x\(String(usage, radix: 16))"
    }
}
