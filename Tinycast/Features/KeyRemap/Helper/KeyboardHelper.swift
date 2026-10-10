import Foundation
import XPC
import os

/// Tinycast's root LaunchDaemon. See docs/features/key-remap.md#the-helper.
@main
enum KeyboardHelper {
    static let subsystem = "com.tinycast.keyboard-helper"

    static func main() {
        let logger = Logger(subsystem: subsystem, category: "lifecycle")
        // Seizing and the driver's socket both need root; run as anyone else, it would only spin.
        guard geteuid() == 0 else {
            logger.fault("must run as root")
            exit(EX_NOPERM)
        }
        guard let appBundleIdentifier = appBundle()?.bundleIdentifier else {
            logger.fault("not inside an app bundle")
            exit(EX_CONFIG)
        }
        let label = KeyRemapHelperInterface.label(appBundleIdentifier: appBundleIdentifier)
        let mailbox = HelperMailbox()

        let worker = Thread { RemapWorker(mailbox: mailbox).run() }
        worker.name = "keyboard"
        worker.qualityOfService = .userInteractive
        worker.start()
        HelperWatchdog.start(mailbox: mailbox)

        let listener: XPCListener
        do {
            listener = try XPCListener(
                service: label,
                requirement: .isFromSameTeam(andMatchesSigningIdentifier: appBundleIdentifier)
            ) { request in
                let session = mailbox.openSession()
                return request.accept { (configuration: KeyRemapConfiguration) -> (any Encodable)? in
                    mailbox.apply(configuration, session: session)
                    return mailbox.status
                } cancellationHandler: { _ in
                    mailbox.closeSession(session)
                }
            }
        } catch {
            logger.fault("could not listen on \(label): \(error.localizedDescription)")
            exit(EX_UNAVAILABLE)
        }
        logger.info("listening on \(label)")
        withExtendedLifetime(listener) { dispatchMain() }
    }

    /// launchd passes a bundle-relative argv[0], so the real executable path is the one to walk up.
    private static func appBundle() -> Bundle? {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        let app = executable.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return app.pathExtension == "app" ? Bundle(url: app) : nil
    }
}
