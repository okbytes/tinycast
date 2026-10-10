import Foundation

/// A report for the pqrs virtual keyboard, packed exactly as the driver's C++ structs lay it out.
enum VirtualHIDReport: Hashable, Sendable {
    case keyboard(modifiers: UInt8, keys: [UInt16])
    case consumer([UInt16])
    case appleVendorTopCase([UInt16])
    case appleVendorKeyboard([UInt16])
    case genericDesktop([UInt16])

    /// Every report carries a fixed array of this many usages; extra presses are dropped.
    static let keyCapacity = 32

    enum Kind: CaseIterable, Sendable {
        case keyboard, consumer, appleVendorTopCase, appleVendorKeyboard, genericDesktop
    }

    var kind: Kind {
        switch self {
        case .keyboard: .keyboard
        case .consumer: .consumer
        case .appleVendorTopCase: .appleVendorTopCase
        case .appleVendorKeyboard: .appleVendorKeyboard
        case .genericDesktop: .genericDesktop
        }
    }

    static func empty(_ kind: Kind) -> VirtualHIDReport {
        switch kind {
        case .keyboard: .keyboard(modifiers: 0, keys: [])
        case .consumer: .consumer([])
        case .appleVendorTopCase: .appleVendorTopCase([])
        case .appleVendorKeyboard: .appleVendorKeyboard([])
        case .genericDesktop: .genericDesktop([])
        }
    }

    var request: VirtualHIDWireFormat.Request {
        switch self {
        case .keyboard: .postKeyboard
        case .consumer: .postConsumer
        case .appleVendorTopCase: .postAppleVendorTopCase
        case .appleVendorKeyboard: .postAppleVendorKeyboard
        case .genericDesktop: .postGenericDesktop
        }
    }

    /// Report ID, then for the keyboard a modifier byte and a reserved byte, then the usage array.
    var bytes: [UInt8] {
        switch self {
        case .keyboard(let modifiers, let keys): [1, modifiers, 0] + Self.usageArray(keys)
        case .consumer(let usages): [2] + Self.usageArray(usages)
        case .appleVendorTopCase(let usages): [3] + Self.usageArray(usages)
        case .appleVendorKeyboard(let usages): [4] + Self.usageArray(usages)
        case .genericDesktop(let usages): [7] + Self.usageArray(usages)
        }
    }

    private static func usageArray(_ usages: [UInt16]) -> [UInt8] {
        (0..<keyCapacity).flatMap { index -> [UInt8] in
            let usage = index < usages.count ? usages[index] : 0
            return [UInt8(usage & 0xFF), UInt8(usage >> 8)]
        }
    }
}
