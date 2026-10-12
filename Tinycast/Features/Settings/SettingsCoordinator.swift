import SwiftUI

/// Settings' lifecycle, independent of the palette: neither surface opens or closes the other.
@MainActor
final class SettingsCoordinator {
    private let window: AppWindowController
    /// Environment injection only — never for state this type owns.
    private unowned let core: AppCore
    /// The open window's session; the window's chrome and view tree own it, so this self-nils.
    private weak var navigation: SettingsNavigationState?

    init(core: AppCore) {
        self.core = core
        window = AppWindowController(
            title: "Settings", contentSize: Theme.Size.settingsWindow, resizable: true,
            autosaveName: "SettingsWindow", activation: core.activationPolicy)
    }

    /// A fresh window mounts on `tab`; an open one navigates to it, recording the jump in history.
    /// A nil `tab` only reveals the window, so re-opening a minimised one keeps the pane it was on.
    func showSettings(tab: SettingsTab? = nil, revealing target: SettingsTarget? = nil) {
        if window.focus() {
            if let tab { navigation?.select(tab, revealing: target) }
            return
        }
        let navigation = SettingsNavigationState(tab: tab ?? .general)
        navigation.select(navigation.tab, revealing: target)
        self.navigation = navigation
        let hosting = NSHostingController(
            rootView: SettingsRootView().settingsEnvironment(core: core, navigation: navigation))
        // Keep the window's size authoritative: an unconstrained fill would drive the frame.
        hosting.sizingOptions = []
        // The back/forward chevrons, the pane title and the sidebar's search field all ride on it.
        hosting.sceneBridgingOptions = [.toolbars, .title]
        window.show(chrome: SettingsWindowChrome()) { hosting }
    }

    /// ⌘Q and the window's close button land here; the app itself keeps running.
    func closeSettings() {
        window.close()
    }

    func focusExisting() -> Bool {
        window.focus()
    }
}

extension View {
    func settingsEnvironment(core: AppCore, navigation: SettingsNavigationState) -> some View {
        environment(navigation)
            .environment(core)
            .environment(core.settings)
            .environment(core.appIndex)
            .environment(core.hotKeys)
            .environment(core.visibility)
            .environment(core.aliases)
            .environment(core.calendarStore)
            .scrollContentBackground(.hidden)
    }
}
