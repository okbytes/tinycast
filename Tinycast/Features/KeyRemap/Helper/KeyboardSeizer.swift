import Foundation
import IOKit
import IOKit.hid
import os

/// Holds the built-in keyboard exclusively and hands on its input. See docs/features/key-remap.md.
final class KeyboardSeizer {
    var onInput: ((KeyRemapEngine.Input) -> Void)?
    /// The `IOReturn` of the last refused seize, cleared by the next one that succeeds.
    private(set) var lastFailure: IOReturn?
    /// Built-in keyboards the last scan found, so "none to hold" reads apart from "refused".
    private(set) var builtInCount = 0
    /// Set from the removal callout and acted on by the worker's tick, outside any IOKit callout.
    private var removalPending = false

    private var held: [(device: IOHIDDevice, queue: IOHIDQueue)] = []
    private let logger = Logger(subsystem: KeyboardHelper.subsystem, category: "keyboard")
    private static let secondsPerTick: Double = {
        var timebase = mach_timebase_info()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }()

    init() {
        let services = Self.builtInKeyboards()
        services.forEach { IOObjectRelease($0) }
        builtInCount = services.count
    }

    var seizedCount: Int { held.count }
    var isSeized: Bool { !held.isEmpty }

    /// Seizes every built-in keyboard; the first one's top-row map, or nil when none was seized.
    func seize() -> TopRowMap? {
        var topRow: TopRowMap?
        let context = Unmanaged.passUnretained(self).toOpaque()
        let services = Self.builtInKeyboards()
        builtInCount = services.count
        for service in services {
            defer { IOObjectRelease(service) }
            guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { continue }
            let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            guard result == kIOReturnSuccess else {
                lastFailure = result
                logger.error("seize refused: \(String(UInt32(bitPattern: result), radix: 16))")
                continue
            }
            guard let queue = Self.inputQueue(for: device, context: context) else {
                logger.error("the built-in keyboard exposed no keys to read")
                IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
                continue
            }
            IOHIDDeviceRegisterRemovalCallback(device, removalCallback, context)
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            held.append((device, queue))
            topRow = topRow ?? Self.topRowMap(below: service)
            lastFailure = nil
        }
        guard isSeized else { return nil }
        logger.info("seized \(self.held.count) built-in keyboard(s)")
        return topRow ?? TopRowMap(actions: [:])
    }

    func release() {
        guard isSeized else { return }
        let runLoop: CFRunLoop = CFRunLoopGetCurrent()
        for (device, queue) in held {
            IOHIDQueueStop(queue)
            IOHIDQueueUnscheduleFromRunLoop(queue, runLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        }
        held = []
        logger.info("released the built-in keyboard")
    }

    /// Whether a device went away since the last call; the worker then releases and seizes afresh.
    func takeRemoval() -> Bool {
        defer { removalPending = false }
        return removalPending
    }

    /// The built-in keyboard's ANSI (0), ISO (1) or JIS (2) type, which the virtual one must match.
    static func builtInStandardType() -> Int {
        let services = builtInKeyboards()
        defer { services.forEach { IOObjectRelease($0) } }
        guard let service = services.first else { return 0 }
        let value = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, kIOHIDStandardTypeKey as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively))
        return value as? Int ?? 0
    }

    fileprivate func drain(_ queue: IOHIDQueue) {
        while isSeized, let value = IOHIDQueueCopyNextValueWithTimeout(queue, 0) {
            let element = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            // Each report also delivers a page-0 placeholder that is no key at all.
            guard page != 0, page <= UInt16.max, usage <= UInt16.max else { continue }
            onInput?(
                KeyRemapEngine.Input(
                    usage: HIDUsage(page: UInt16(page), usage: UInt16(usage)),
                    isPressed: IOHIDValueGetIntegerValue(value) != 0,
                    time: Double(IOHIDValueGetTimeStamp(value)) * Self.secondsPerTick))
        }
    }

    fileprivate func deviceRemoved() {
        removalPending = true
    }

    // MARK: - Discovery

    private static func builtInKeyboards() -> [io_service_t] {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOHIDDeviceKey), &iterator)
                == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var services: [io_service_t] = []
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            if isBuiltInKeyboard(service) {
                services.append(service)
            } else {
                IOObjectRelease(service)
            }
        }
        return services
    }

    private static func isBuiltInKeyboard(_ service: io_service_t) -> Bool {
        guard property(kIOHIDBuiltInKey, of: service) as? Bool == true else { return false }
        let pairs = property(kIOHIDDeviceUsagePairsKey, of: service) as? [[String: Any]] ?? []
        return pairs.contains {
            $0[kIOHIDDeviceUsagePageKey] as? Int == kHIDPage_GenericDesktop
                && $0[kIOHIDDeviceUsageKey] as? Int == kHIDUsage_GD_Keyboard
        }
    }

    private static func property(_ key: String, of service: io_service_t) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }

    /// The map lives on the keyboard's event driver, a few registry levels below the device.
    private static func topRowMap(below service: io_service_t) -> TopRowMap? {
        let value = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, TopRowMap.registryKey as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively))
        return (value as? String).map(TopRowMap.init(registryValue:))
    }

    /// Queues every input element, nil without a key; a seized device's value callback got nothing.
    private static func inputQueue(for device: IOHIDDevice, context: UnsafeMutableRawPointer)
        -> IOHIDQueue?
    {
        let inputs = (IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone))
            as? [IOHIDElement] ?? [])
            .filter { IOHIDElementGetType($0).rawValue < kIOHIDElementTypeOutput.rawValue }
        guard inputs.contains(where: { IOHIDElementGetUsagePage($0) == UInt32(HIDUsage.keyboardPage) }),
            let queue = IOHIDQueueCreate(
                kCFAllocatorDefault, device, 1024, IOOptionBits(kIOHIDOptionsTypeNone))
        else { return nil }
        for element in inputs { IOHIDQueueAddElement(queue, element) }
        IOHIDQueueRegisterValueAvailableCallback(queue, queueCallback, context)
        IOHIDQueueScheduleWithRunLoop(queue, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDQueueStart(queue)
        return queue
    }
}

private let queueCallback: IOHIDCallback = { context, _, sender in
    guard let context, let sender else { return }
    let queue = Unmanaged<IOHIDQueue>.fromOpaque(sender).takeUnretainedValue()
    Unmanaged<KeyboardSeizer>.fromOpaque(context).takeUnretainedValue().drain(queue)
}

private let removalCallback: IOHIDCallback = { context, _, _ in
    guard let context else { return }
    Unmanaged<KeyboardSeizer>.fromOpaque(context).takeUnretainedValue().deviceRemoved()
}
