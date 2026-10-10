import Foundation

/// What the helper applies to the built-in keyboard. Crosses XPC, so it stays plain data.
struct KeyRemapConfiguration: Codable, Equatable, Sendable {
    /// One physical key that holds a set of modifiers down instead of acting as itself.
    struct Binding: Codable, Equatable, Sendable {
        /// The key's keyboard-page usage.
        var usage: UInt16
        /// HID modifier bits, Left Control at bit 0 through Right Command at bit 7.
        var modifiers: UInt8
        var quickPress: QuickPress
    }

    /// What a lone press shorter than `KeyRemapEngine.quickPressWindow` sends after the chord.
    enum QuickPress: String, Codable, Sendable {
        case none
        case escape
        case capsLock
    }

    var bindings: [Binding]
    /// macOS's "Use F1, F2, etc. keys as standard function keys": flips the top row's fn layer.
    var functionKeysAreStandard: Bool

    static let off = KeyRemapConfiguration(bindings: [], functionKeysAreStandard: false)

    enum ModifierBit {
        static let leftControl: UInt8 = 0x01
        static let leftShift: UInt8 = 0x02
        static let leftOption: UInt8 = 0x04
        static let leftCommand: UInt8 = 0x08
    }

    /// ⌃⌥⌘, plus ⇧ when asked; the left-side bits, which every consumer reads as fully pressed.
    static func hyperModifiers(includesShift: Bool) -> UInt8 {
        ModifierBit.leftControl | ModifierBit.leftOption | ModifierBit.leftCommand
            | (includesShift ? ModifierBit.leftShift : 0)
    }

    static let mehModifiers = ModifierBit.leftControl | ModifierBit.leftOption | ModifierBit.leftShift

    func binding(for usage: UInt16) -> Binding? {
        bindings.first { $0.usage == usage }
    }
}
