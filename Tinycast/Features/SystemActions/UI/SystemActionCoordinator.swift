import AppKit

/// The one dispatch funnel for system actions, its gates and their feedback.
@MainActor
final class SystemActionCoordinator {
    private let paletteCoordinator: PaletteCoordinator
    /// Dialog and message-HUD presentation only — never for state this type owns.
    private unowned let core: AppCore

    init(paletteCoordinator: PaletteCoordinator, core: AppCore) {
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// The one funnel for every activation route, so no gate can be bypassed.
    func runSystemAction(id: SystemAction.ID) {
        let target = paletteCoordinator.targetApp
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        Task { await perform(SystemActionCatalog.action(id: id), previousApp: target) }
    }

    private func perform(_ action: SystemAction, previousApp: NSRunningApplication?) async {
        switch action.confirmation {
        case .computed:
            await quitAllApps()
            return
        case .followsFinder where !SystemActionRunner.finderWarnsBeforeEmptyingTrash:
            break
        case .required(let title, let message), .followsFinder(let title, let message):
            guard
                await core.confirm(
                    title: title, message: message, symbol: action.sfSymbol,
                    confirmTitle: action.name)
            else { return }
        case .none:
            break
        }
        do {
            if let feedback = try await SystemActionRunner.run(action.id, previousApp: previousApp) {
                core.showMessage(feedback.title, tone: feedback.isNoOp ? .neutral : .success)
            }
        } catch let failure as SystemActionFailure {
            await presentFailure(action: action, failure: failure)
        } catch {
            await presentFailure(
                action: action, failure: SystemActionFailure(error.localizedDescription))
        }
    }

    /// Sync entry point for the runner's own async completion handlers, which can't await.
    func presentSystemActionFailure(id: SystemAction.ID, failure: SystemActionFailure) {
        Task { await presentFailure(action: SystemActionCatalog.action(id: id), failure: failure) }
    }

    private func presentFailure(action: SystemAction, failure: SystemActionFailure) async {
        guard
            await core.reportFailure(
                title: "“\(action.name)” Failed", message: failure.message,
                symbol: action.sfSymbol,
                recovery: failure.settings == nil ? nil : "Open System Settings…"),
            let settings = failure.settings
        else { return }
        let pane: String
        switch settings {
        case .accessibility: pane = "Privacy_Accessibility"
        case .automation: pane = "Privacy_Automation"
        case .bluetooth: pane = "Privacy_Bluetooth"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Quit All confirms first, and the resolved list is both counted and terminated.
    private func quitAllApps() async {
        let targets = AppLauncher.quitAllTargets()
        guard !targets.isEmpty,
            await core.confirm(
                title: targets.count == 1
                    ? "Quit 1 application?" : "Quit \(targets.count) applications?",
                message: "Applications with unsaved changes will ask you to save.",
                symbol: SystemActionCatalog.action(id: .quitAllApps).sfSymbol,
                confirmTitle: "Quit All")
        else { return }
        for app in targets { app.terminate() }
    }
}
