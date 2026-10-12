import Foundation

/// The dictionary's action surface: open the screen, and act on the entry it shows.
@MainActor
final class DictionaryCoordinator {
    private let paletteCoordinator: PaletteCoordinator

    init(paletteCoordinator: PaletteCoordinator) {
        self.paletteCoordinator = paletteCoordinator
    }

    func show() {
        paletteCoordinator.togglePalette(mode: .dictionary)
    }

    func copy(_ entry: DictionaryEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(entry.text)
    }

    /// Dictionary.app shows the full entry, with every dictionary the reader has enabled.
    func openInDictionary(_ entry: DictionaryEntry) {
        guard let term = entry.term.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
            let url = URL(string: "dict://" + term)
        else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.open(url)
    }
}
