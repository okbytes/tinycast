import AppKit
import Darwin

struct SystemActionFeedback: Sendable {
    let title: String
    /// Set when there was nothing to do, so it reads as information, not a change.
    let isNoOp: Bool

    init(_ title: String, isNoOp: Bool = false) {
        self.title = title
        self.isNoOp = isNoOp
    }
}

@MainActor
enum SystemActionRunner {
    /// Failures raised after `run` returned; the runner owns effects, never UI. Set in `start()`.
    static var onAsyncFailure: ((SystemAction.ID, SystemActionFailure) -> Void)?

    private struct ProcessOutput: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// What an action reports on success; only the ones whose effect is invisible do.
    static func run(
        _ id: SystemAction.ID, previousApp: NSRunningApplication?
    ) async throws
        -> SystemActionFeedback?
    {
        switch id {
        case .lockScreen:
            try lockScreen()
        case .sleep:
            try await runProcess("/usr/bin/pmset", arguments: ["sleepnow"])
        case .sleepDisplays:
            try await runProcess("/usr/bin/pmset", arguments: ["displaysleepnow"])
        case .restart:
            try await runAppleScript(
                "tell application \"System Events\" to restart with state saving preference")
        case .shutDown:
            try await runAppleScript(
                "tell application \"System Events\" to shut down with state saving preference")
        case .logOut:
            try await runAppleScript("tell application \"System Events\" to log out")
        case .showScreenSaver:
            let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SystemActionFailure("The macOS screen saver could not be found.")
            }
            NSWorkspace.shared.openApplication(
                at: url, configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                guard let error else { return }
                Task { @MainActor in
                    onAsyncFailure?(
                        .showScreenSaver, SystemActionFailure(error.localizedDescription))
                }
            }
        case .showDesktop:
            // Executing the binary directly is SIGKILLed; only a LaunchServices launch is allowed.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = ["1"]
            _ = try await NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/System/Applications/Mission Control.app"),
                configuration: configuration)
        case .toggleAppearance:
            // The script returns the resulting state, so the confirmation can name it.
            let result = try await runAppleScript(
                "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
            )
            let dark = result.flag
            return SystemActionFeedback(dark ? "Dark Appearance" : "Light Appearance")
        case .toggleStageManager:
            let on = try await toggleDefault(
                domain: "com.apple.WindowManager", key: "GloballyEnabled")
            return SystemActionFeedback(on ? "Stage Manager On" : "Stage Manager Off")
        case .openTrash:
            let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            guard NSWorkspace.shared.open(trash) else {
                throw SystemActionFailure("Finder could not open the Trash.")
            }
        case .emptyTrash:
            // Count first: Finder errors on an empty Trash, and `~/.Trash` is TCC-protected.
            let items =
                try await runAppleScript("tell application \"Finder\" to count items of trash")
                .number
            guard items > 0 else {
                return SystemActionFeedback("Trash Is Already Empty", isNoOp: true)
            }
            try await runAppleScript("tell application \"Finder\" to empty trash")
            return SystemActionFeedback("Trash Emptied")
        case .ejectAllDisks:
            let ejected = try ejectAllDisks()
            guard ejected > 0 else {
                return SystemActionFeedback("No Disks to Eject", isNoOp: true)
            }
            return SystemActionFeedback(ejected == 1 ? "1 Disk Ejected" : "\(ejected) Disks Ejected")
        case .toggleHiddenFiles:
            let shown = try await toggleDefault(
                domain: "com.apple.finder", key: "AppleShowAllFiles")
            let output = try await process("/usr/bin/killall", arguments: ["Finder"])
            if output.status != 0 && output.status != 1 {
                throw processFailure(output, executable: "killall")
            }
            return SystemActionFeedback(shown ? "Hidden Files Shown" : "Hidden Files Hidden")
        case .hideOtherApps:
            hideOtherApps(except: previousApp)
        case .unhideAllApps:
            let hidden = NSWorkspace.shared.runningApplications.filter(\.isHidden)
            for app in hidden { app.unhide() }
            guard !hidden.isEmpty else {
                return SystemActionFeedback("Nothing Was Hidden", isNoOp: true)
            }
            return SystemActionFeedback("All Apps Unhidden")
        case .quitAllApps:
            for app in AppLauncher.quitAllTargets() { app.terminate() }
        case .dismissNotifications:
            let dismissed = try await dismissNotifications()
            guard dismissed > 0 else {
                return SystemActionFeedback("No Notifications", isNoOp: true)
            }
            return SystemActionFeedback("Notifications Dismissed")
        case .toggleBluetooth:
            let on = try await toggleBluetooth()
            return SystemActionFeedback(on ? "Bluetooth On" : "Bluetooth Off")
        }
        return nil
    }

    /// Finder writes the key only once the box is changed, so an absent key is its default: on.
    static var finderWarnsBeforeEmptyingTrash: Bool {
        let key = "WarnOnEmptyTrash"
        guard let finder = UserDefaults(suiteName: "com.apple.finder"),
            finder.object(forKey: key) != nil
        else { return true }
        return finder.bool(forKey: key)
    }

    private static func lockScreen() throws {
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        guard let handle = dlopen(path, RTLD_NOW) else {
            throw SystemActionFailure("Screen locking is unavailable on this Mac.")
        }
        defer { dlclose(handle) }
        typealias LockScreen = @convention(c) () -> Int32
        guard let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            throw SystemActionFailure("This macOS version does not expose screen locking.")
        }
        _ = unsafeBitCast(symbol, to: LockScreen.self)()
    }

    private static func hideOtherApps(except previousApp: NSRunningApplication?) {
        let ownPID = NSRunningApplication.current.processIdentifier
        let keptPID = previousApp?.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular
            && app.processIdentifier != ownPID
            && app.processIdentifier != keptPID
        {
            app.hide()
        }
        previousApp?.unhide()
        previousApp?.activate()
    }

    @discardableResult
    private static func ejectAllDisks() throws -> Int {
        let keys: Set<URLResourceKey> = [
            .volumeIsEjectableKey, .volumeIsInternalKey, .volumeIsLocalKey,
            .volumeIsRootFileSystemKey
        ]
        let urls =
            FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        let ejectable = urls.filter { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return false }
            guard values.volumeIsLocal != false,
                values.volumeIsInternal != true,
                values.volumeIsRootFileSystem != true
            else { return false }
            // A dock's fixed-media HDD is external but not ejectable, so external alone qualifies.
            return values.volumeIsEjectable == true || values.volumeIsInternal == false
        }
        var failures: [String] = []
        var ejected = 0
        for url in ejectable {
            // Ejecting one volume takes the device, so a vanished sibling is done.
            guard mountedVolumeExists(url) else { continue }
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                ejected += 1
            } catch {
                // An eject that errors yet leaves no mount behind still took the volume offline.
                guard mountedVolumeExists(url) else {
                    ejected += 1
                    continue
                }
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        guard failures.isEmpty else {
            throw SystemActionFailure(
                "Some disks could not be ejected:\n\n" + failures.joined(separator: "\n"))
        }
        return ejected
    }

    private static func mountedVolumeExists(_ url: URL) -> Bool {
        let mounted =
            FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        return mounted.contains { $0.standardizedFileURL == url.standardizedFileURL }
    }

    /// Returns the state it landed in, so the caller needn't re-read the preference.
    @discardableResult
    private static func toggleDefault(domain: String, key: String) async throws -> Bool {
        let read = try await process("/usr/bin/defaults", arguments: ["read", domain, key])
        let normalized = read.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let current: Bool
        if read.status == 0 {
            guard let parsed = booleanDefault(normalized) else {
                throw SystemActionFailure("macOS reported an unexpected value for this setting.")
            }
            current = parsed
        } else if read.stderr.contains("does not exist") {
            // Unset is genuinely off; any other failure is unknown and stays untouched.
            current = false
        } else {
            throw processFailure(read, executable: "defaults")
        }
        let requested = !current
        try await runProcess(
            "/usr/bin/defaults",
            arguments: ["write", domain, key, "-bool", requested ? "true" : "false"])
        let verify = try await process("/usr/bin/defaults", arguments: ["read", domain, key])
        let verified = verify.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard verify.status == 0, booleanDefault(verified) == requested else {
            throw SystemActionFailure("macOS did not save the requested setting.")
        }
        return requested
    }

    private static func booleanDefault(_ value: String) -> Bool? {
        switch value {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }

    /// Returns how many were dismissed, so an empty screen reads as information.
    private static func dismissNotifications() async throws -> Int {
        guard Permissions.ensureAccessibility() else {
            throw SystemActionFailure(
                "Allow Tinycast to control your Mac in Accessibility settings, then try again.",
                settings: .accessibility)
        }
        guard
            let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.notificationcenterui"
            ).first
        else { return 0 }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var dismissed = 0
        for _ in 0..<100 {
            // The tree is rebuilt every pass: dismissing one notification invalidates its siblings.
            guard let notification = firstNotification(in: root, depth: 0) else { return dismissed }
            guard let action = dismissAction(of: notification) else {
                throw SystemActionFailure(
                    "This version of Notification Center exposes no dismiss control Tinycast can use.")
            }
            let result = AXUIElementPerformAction(notification, action as CFString)
            guard result == .success || result == .invalidUIElement else {
                throw SystemActionFailure("Notification Center did not allow a notification to be dismissed.")
            }
            dismissed += 1
            try await Task.sleep(for: .milliseconds(150))
        }
        throw SystemActionFailure("Some notifications remain after the safety limit was reached.")
    }

    /// Matched on AX subrole, so the search never depends on the UI language.
    private static func firstNotification(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 20 else { return nil }
        let subrole = axString(element, attribute: kAXSubroleAttribute as CFString)?.lowercased()
        if let subrole, subrole.contains("notificationcenter") { return element }
        for child in axChildren(element) {
            if let found = firstNotification(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    /// A banner offers "Close" and a stack "Clear All" as custom actions; neither has a button.
    private static func dismissAction(of notification: AXUIElement) -> String? {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(notification, &actions) == .success,
            let names = actions as? [String]
        else { return nil }
        return names.first { $0.hasPrefix("Name:Close\n") || $0.hasPrefix("Name:Clear All\n") }
    }

    private static func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
                == .success,
            let children = value as? [AXUIElement]
        else { return [] }
        return children
    }

    private static func axString(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    /// Returns the state it settled into; the setter is void, so polling is the only way.
    private static func toggleBluetooth() async throws -> Bool {
        let path = "/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth"
        guard let handle = dlopen(path, RTLD_NOW) else {
            throw SystemActionFailure("Bluetooth control is unavailable on this Mac.")
        }
        defer { dlclose(handle) }
        typealias Available = @convention(c) () -> Int32
        typealias GetPower = @convention(c) () -> Int32
        typealias SetPower = @convention(c) (Int32) -> Void
        guard let availableSymbol = dlsym(handle, "IOBluetoothPreferencesAvailable"),
            let getSymbol = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState"),
            let setSymbol = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState")
        else { throw SystemActionFailure("This macOS version does not expose Bluetooth power control.") }
        let available = unsafeBitCast(availableSymbol, to: Available.self)
        let getPower = unsafeBitCast(getSymbol, to: GetPower.self)
        let setPower = unsafeBitCast(setSymbol, to: SetPower.self)
        guard available() != 0 else {
            throw SystemActionFailure("No Bluetooth controller is available.", settings: .bluetooth)
        }
        let requested: Int32 = getPower() == 0 ? 1 : 0
        setPower(requested)
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            if getPower() == requested { return requested == 1 }
        }
        throw SystemActionFailure(
            "Bluetooth did not change state. Check Tinycast’s Bluetooth permission.",
            settings: .bluetooth)
    }

    /// `NSAppleEventDescriptor` isn't `Sendable`, so the two fields callers read cross instead.
    private struct AppleScriptResult: Sendable {
        let number: Int32
        let flag: Bool
    }

    /// A cold Finder answers in seconds, so the send never happens on the main actor.
    @discardableResult
    private static func runAppleScript(_ source: String) async throws -> AppleScriptResult {
        try await Task.detached(priority: .userInitiated) {
            guard let script = NSAppleScript(source: source) else {
                throw SystemActionFailure("The system automation could not be prepared.")
            }
            var errorInfo: NSDictionary?
            let result = script.executeAndReturnError(&errorInfo)
            guard let errorInfo else {
                return AppleScriptResult(number: result.int32Value, flag: result.booleanValue)
            }
            let number = errorInfo[NSAppleScript.errorNumber] as? Int
            let detail =
                errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown automation error."
            if number == -1743 {
                throw SystemActionFailure(
                    "Allow Tinycast to control the requested app in Automation settings, then try again.",
                    settings: .automation)
            }
            throw SystemActionFailure(detail)
        }.value
    }

    private static func runProcess(_ executable: String, arguments: [String]) async throws {
        let output = try await process(executable, arguments: arguments)
        guard output.status == 0 else { throw processFailure(output, executable: executable) }
    }

    private static func process(_ executable: String, arguments: [String]) async throws -> ProcessOutput {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdout
            process.standardError = stderr
            do { try process.runObservingExit().wait() } catch {
                throw SystemActionFailure(
                    "\(URL(fileURLWithPath: executable).lastPathComponent) could not start: \(error.localizedDescription)"
                )
            }
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            return ProcessOutput(
                status: process.terminationStatus,
                stdout: String(data: outData, encoding: .utf8) ?? "",
                stderr: String(data: errorData, encoding: .utf8) ?? "")
        }.value
    }

    private static func processFailure(_ output: ProcessOutput, executable: String) -> SystemActionFailure {
        let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = URL(fileURLWithPath: executable).lastPathComponent
        return SystemActionFailure(
            detail.isEmpty ? "\(name) exited with status \(output.status)." : detail)
    }
}
