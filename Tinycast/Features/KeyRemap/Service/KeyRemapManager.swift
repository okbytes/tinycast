import AppKit
import Observation
import ServiceManagement
import XPC
import os

/// Keeps the keyboard helper configured from settings and reports its health. See key-remap.md.
@MainActor
@Observable
final class KeyRemapManager: HealthCheckable {
    enum Status: Equatable {
        case off
        case driverMissing
        case needsApproval
        case helperUnreachable
        case driverNotRunning
        case driverUnsupported
        case noBuiltInKeyboard
        case keyboardInUse
        case needsAccessibility
        case starting
        case active
    }

    private typealias HelperReply = Result<KeyRemapHelperInterface.Status, any Error>

    /// Consecutive failed exchanges before the helper counts as unreachable rather than starting.
    private static let unreachableAfter = 3

    static let driverDownloadURL = URL(
        string: "https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases")!

    private(set) var status: Status = .off

    @ObservationIgnored weak var healthTicker: HealthTicker?
    @ObservationIgnored private var settings: AppSettings?
    @ObservationIgnored private var session: XPCSession?
    /// Bumped per session, so a late reply or cancellation from an old one can't touch the new one.
    @ObservationIgnored private var sessionGeneration = 0
    @ObservationIgnored private var failedExchanges = 0
    @ObservationIgnored private var userSessionTokens: [NotificationToken] = []
    /// False while fast user switching has another account at the keyboard.
    @ObservationIgnored private var userSessionActive = true
    @ObservationIgnored private let logger = Logger(subsystem: "com.tinycast.app", category: "key-remap")

    private let label = KeyRemapHelperInterface.label(
        appBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.tinycast.app")
    private var service: SMAppService {
        .daemon(plistName: label + ".plist")
    }

    /// Login Items & Extensions holds both approvals: the helper, and the driver extension.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func start(settings: AppSettings) {
        self.settings = settings
        observeSettings()
        observeUserSession()
        apply()
    }

    /// Hands the keyboard back: the helper releases it as soon as the session closes.
    func prepareForTermination() {
        closeSession()
    }

    /// Fires synchronously on main before the write lands, so the task re-arms, then applies.
    private func observeSettings() {
        withObservationTracking {
            _ = settings?.hyperKey
            _ = settings?.mehKey
            _ = settings?.hyperKeyIncludesShift
            _ = settings?.hyperKeyQuickPress
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeSettings()
                self?.apply()
            }
        }
    }

    /// The helper serves every account, so the keyboard goes back while another one is at it.
    private func observeUserSession() {
        let center = NSWorkspace.shared.notificationCenter
        let observe = { [weak self] (name: Notification.Name, active: Bool) in
            NotificationToken(
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    Task { @MainActor in self?.userSessionChanged(active: active) }
                }, center: center)
        }
        userSessionTokens = [
            observe(NSWorkspace.sessionDidResignActiveNotification, false),
            observe(NSWorkspace.sessionDidBecomeActiveNotification, true),
        ]
    }

    private func userSessionChanged(active: Bool) {
        userSessionActive = active
        apply()
    }

    private var configuration: KeyRemapConfiguration {
        guard let settings else { return .off }
        var bindings: [KeyRemapConfiguration.Binding] = []
        if let usage = settings.hyperKey.hidUsage {
            bindings.append(
                .init(
                    usage: usage,
                    modifiers: KeyRemapConfiguration.hyperModifiers(
                        includesShift: settings.hyperKeyIncludesShift),
                    quickPress: Self.quickPress(settings.hyperKeyQuickPress, for: settings.hyperKey)))
        }
        if let usage = settings.mehKey.hidUsage, settings.mehKey != settings.hyperKey {
            bindings.append(
                .init(usage: usage, modifiers: KeyRemapConfiguration.mehModifiers, quickPress: .none))
        }
        // Read per tick, so flipping it in System Settings reaches the helper within a second.
        let standard = UserDefaults.standard.bool(forKey: "com.apple.keyboard.fnState")
        return KeyRemapConfiguration(bindings: bindings, functionKeysAreStandard: standard)
    }

    /// "Original key" is offered only for Caps Lock, but settings.json can pair it with any key.
    private static func quickPress(_ choice: HyperKeyQuickPress, for key: HyperKeyPhysicalKey)
        -> KeyRemapConfiguration.QuickPress
    {
        switch choice {
        case .none: .none
        case .escape: .escape
        case .originalKey: key == .capsLock ? .capsLock : .none
        }
    }

    /// Turning both keys off only closes the session; the helper then releases and exits by itself.
    private func apply() {
        guard userSessionActive, !configuration.bindings.isEmpty else {
            healthTicker?.unsubscribe(self)
            closeSession()
            status = .off
            return
        }
        healthTicker?.subscribe(self)
        healthCheck()
    }

    /// One-second watchdog while a key is bound: registers, connects, re-sends, refreshes status.
    func healthCheck() {
        let configuration = configuration
        guard userSessionActive, !configuration.bindings.isEmpty else { return }
        guard FileManager.default.isExecutableFile(atPath: KeyRemapHelperInterface.driverDaemonPath)
        else {
            status = .driverMissing
            return
        }
        switch service.status {
        case .enabled:
            break
        case .requiresApproval:
            closeSession()
            status = .needsApproval
            return
        default:
            register()
            return
        }
        if status == .needsApproval || status == .off { status = .starting }
        guard let session = session ?? openSession() else {
            exchangeFailed()
            return
        }
        // Sent every tick, not once: a helper launchd restarted starts with nothing applied.
        send(configuration, on: session)
    }

    private func register() {
        do {
            try service.register()
        } catch {
            // Expected until the user approves it: the registration stands and awaits that.
            logger.info("helper registration pending: \(error.localizedDescription)")
        }
        status = service.status == .requiresApproval ? .needsApproval : .starting
    }

    // MARK: - Session

    private func openSession() -> XPCSession? {
        sessionGeneration += 1
        let generation = sessionGeneration
        do {
            let session = try XPCSession(
                machService: label, options: .privileged,
                requirement: .isFromSameTeam(andMatchesSigningIdentifier: label)
            ) { [weak self] _ in
                Task { @MainActor in self?.sessionEnded(generation) }
            }
            self.session = session
            return session
        } catch {
            logger.error("helper connection failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func send(_ configuration: KeyRemapConfiguration, on session: XPCSession) {
        let generation = sessionGeneration
        let reply: @Sendable (HelperReply) -> Void = { [weak self] result in
            Task { @MainActor in self?.received(result, generation: generation) }
        }
        do {
            try session.send(configuration, replyHandler: reply)
        } catch {
            closeSession()
            exchangeFailed()
        }
    }

    private func received(_ result: HelperReply, generation: Int) {
        guard generation == sessionGeneration, session != nil else { return }
        switch result {
        case .success(let helperStatus):
            failedExchanges = 0
            status = Self.status(from: helperStatus)
        case .failure(let error):
            logger.error("helper exchange failed: \(error.localizedDescription)")
            closeSession()
            exchangeFailed()
        }
    }

    /// Only a run of failures means unreachable; one is a helper launchd is still starting.
    private func exchangeFailed() {
        failedExchanges += 1
        status = failedExchanges >= Self.unreachableAfter ? .helperUnreachable : .starting
    }

    private static func status(from helper: KeyRemapHelperInterface.Status) -> Status {
        if !helper.driverInstalled { return .driverMissing }
        if helper.driverVersionMismatched || helper.clientProtocolRejected { return .driverUnsupported }
        if !helper.daemonReachable || !helper.driverActivated || !helper.driverConnected {
            return .driverNotRunning
        }
        if helper.seizedKeyboards > 0 { return .active }
        if !helper.virtualKeyboardReady { return .starting }
        switch helper.seizeFailure {
        case KeyRemapHelperInterface.seizeNotPermitted: return .needsAccessibility
        case KeyRemapHelperInterface.seizeExclusiveAccess: return .keyboardInUse
        default: return helper.builtInKeyboards == 0 ? .noBuiltInKeyboard : .starting
        }
    }

    private func sessionEnded(_ generation: Int) {
        guard generation == sessionGeneration else { return }
        session = nil
    }

    private func closeSession() {
        sessionGeneration += 1
        session?.cancel(reason: "Tinycast no longer needs the keyboard")
        session = nil
    }
}
