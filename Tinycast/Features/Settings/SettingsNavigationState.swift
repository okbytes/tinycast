import Observation

/// Not on `AppCore`: one window's session, released in `windowWillClose` so history never survives.
@MainActor
@Observable
final class SettingsNavigationState {
    private var history: SettingsHistory
    private var requests = 0

    init(tab: SettingsTab) {
        history = SettingsHistory(current: tab)
    }

    var tab: SettingsTab { history.current }
    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    /// Set by a search result, consumed by the pane that scrolls to it.
    private(set) var scrollRequest: SettingsScrollRequest?
    /// The section lit right now. One source for the whole window, so a pane swap can't lose it.
    private(set) var flashing: SettingsTarget?

    /// A search result navigates and asks the pane to reveal one section; a sidebar row just navigates.
    func select(_ tab: SettingsTab, revealing target: SettingsTarget? = nil) {
        history.select(tab)
        endReveal()
        guard let target else { return }
        requests += 1
        scrollRequest = SettingsScrollRequest(target: target, token: requests)
    }

    func beginFlash(_ target: SettingsTarget) {
        flashing = target
    }

    /// Ends the pulse, unless a later jump has already lit something else.
    func endFlash(_ target: SettingsTarget) {
        guard flashing == target else { return }
        flashing = nil
    }

    /// Released only once the pulse is over: it keys the pane's task, so clearing it early would
    /// cancel the very task doing the revealing.
    func clear(_ request: SettingsScrollRequest) {
        guard scrollRequest == request else { return }
        scrollRequest = nil
    }

    func goBack() {
        history.goBack()
        endReveal()
    }

    func goForward() {
        history.goForward()
        endReveal()
    }

    /// Any navigation puts the last reveal out, so neither its light nor its request outlives it.
    private func endReveal() {
        flashing = nil
        scrollRequest = nil
    }
}
