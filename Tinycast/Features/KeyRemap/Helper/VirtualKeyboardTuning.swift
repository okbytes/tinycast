import Foundation
import IOKit.hid
import IOKit.hidsystem

/// Event-system properties of pqrs's virtual keyboard, which only take once it exists.
enum VirtualKeyboardTuning {
    private static let productPrefix = "Karabiner DriverKit VirtualHIDKeyboard"

    /// Apple keyboards ignore a brief Caps Lock press, and a Quick Press tap is exactly that brief.
    static func disableCapsLockDelay() {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient]
        else { return }
        for service in services where isVirtualKeyboard(service) {
            IOHIDServiceClientSetProperty(
                service, kIOHIDKeyboardCapsLockDelayOverrideKey as CFString, 0 as CFNumber)
        }
    }

    private static func isVirtualKeyboard(_ service: IOHIDServiceClient) -> Bool {
        let product = IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString)
        return (product as? String)?.hasPrefix(productPrefix) == true
    }
}
