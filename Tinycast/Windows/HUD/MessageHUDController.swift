import AppKit
import SwiftUI

/// The message pill, shared by every feature that reports a transient confirmation.
@MainActor
final class MessageHUDController {
    private let presenter = HUDPresenter(
        edgeInset: Theme.Size.hudEdgeOffset, dwell: Theme.Duration.messageHUD,
        screen: { .underCursor })

    func show(message: String, tone: DialogTone = .success) {
        presenter.show(MessageHUDView(message: message, accessory: .tone(tone)))
    }

    /// Stays up until the work it reports ends and something replaces it.
    func showProgress(message: String) {
        presenter.show(MessageHUDView(message: message, accessory: .progress), dwells: false)
    }
}
