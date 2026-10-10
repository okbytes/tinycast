import Foundation

/// The XPC conversation between Tinycast and its keyboard helper; both sides compile this file.
enum KeyRemapHelperInterface {
    /// Appended to the app's bundle identifier, so Tinycast Dev runs a helper of its own.
    static let labelSuffix = ".keyboard-helper"
    /// pqrs's daemon; its presence is how both sides tell the driver package is installed.
    static let driverDaemonPath =
        "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/"
        + "Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
    /// `kIOReturnNotPermitted`: a seize with no Accessibility grant covering the helper.
    static let seizeNotPermitted = Int32(bitPattern: 0xE000_02E2)
    /// `kIOReturnExclusiveAccess`: another process, typically Karabiner-Elements, already holds it.
    static let seizeExclusiveAccess = Int32(bitPattern: 0xE000_02C5)

    static func label(appBundleIdentifier: String) -> String {
        appBundleIdentifier + labelSuffix
    }

    /// Tinycast sends its `KeyRemapConfiguration` every second; each is answered with a `Status`.
    struct Status: Codable, Equatable, Sendable {
        /// pqrs's daemon binary is on disk, i.e. the driver package is installed.
        var driverInstalled = false
        /// The daemon's socket accepted the helper.
        var daemonReachable = false
        var driverActivated = false
        var driverConnected = false
        var driverVersionMismatched = false
        /// The daemon refused the client protocol version: a driver Tinycast can't speak.
        var clientProtocolRejected = false
        var virtualKeyboardReady = false
        var builtInKeyboards = 0
        var seizedKeyboards = 0
        /// The `IOReturn` of the last refused seize, if the one after it has not succeeded.
        var seizeFailure: Int32?
    }
}
