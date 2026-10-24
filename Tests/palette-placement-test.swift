import CoreGraphics
import Foundation

/// Against the real `Theme`, so retuning cannot restore the palette off-display.
@main
@MainActor
struct PalettePlacementTests {
    static var failures = 0
    static var passes = 0

    // Exactly what `PaletteWindowController` passes.
    static let width = Theme.Size.panelWidth
    static let topFraction = Theme.Size.paletteTopMarginFraction

    /// A 1440p display with the menu bar taken off the top.
    static let laptop = CGRect(x: 0, y: 0, width: 2560, height: 1415)
    /// A second display stacked to the right, as `NSScreen.screens` would report it.
    static let external = CGRect(x: 2560, y: 0, width: 1920, height: 1055)

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expect(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
        expect(abs(actual - expected) < 0.001, "\(message) — got \(actual), want \(expected)")
    }

    static func home(_ screen: CGRect) -> CGPoint {
        PalettePlacement.defaultAnchor(
            in: screen, width: width, topMarginFraction: topFraction)
    }

    static func main() {
        theDefaultPlacement()
        menuPanelAnchors()
        tokenGrammar()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - The untouched placement

    static func theDefaultPlacement() {
        let anchor = home(laptop)
        expect(anchor.x, laptop.midX - width / 2, "the panel centres horizontally")
        expect(
            anchor.y, laptop.maxY - laptop.height * topFraction,
            "its top edge sits the margin fraction below the top of the visible area")
        expect(anchor.y < laptop.maxY, "the top edge is inside the screen, not on its edge")

        // The panel grows downward from the anchor, so a full-height list must still fit.
        expect(
            anchor.y - Theme.Size.panelHeight > laptop.minY,
            "an expanded palette clears the bottom of the screen it opened on")

        // A screen offset from the origin must not shift the panel off it.
        let offset = home(external)
        expect(offset.x, external.midX - width / 2, "a non-origin display centres the same way")
        expect(
            offset.y, external.maxY - external.height * topFraction,
            "and its top edge is measured from its own maxY")
    }

    // MARK: - Menu panels

    static func menuPanelAnchors() {
        let parent = CGRect(x: 100, y: 200, width: 750, height: 475)
        let content = CGSize(width: 276, height: 240)
        let inset = Theme.Spacing.md
        let headerExtent = Theme.Size.headerPadding + Theme.Size.headerHeight

        let trailing = MenuPanelCorner.bottomTrailing.frame(
            contentSize: content, parentFrame: parent, inset: inset,
            headerExtent: headerExtent)
        expect(trailing.maxX, parent.maxX - inset, "the action menu follows the trailing button")
        expect(trailing.minY, parent.minY + inset, "the action menu follows the footer's bottom edge")

        let header = MenuPanelCorner.belowHeaderTrailing.frame(
            contentSize: content, parentFrame: parent, inset: inset,
            headerExtent: headerExtent)
        expect(header.maxX, parent.maxX - inset * 2, "a header menu follows its trailing control")
        expect(header.maxY, parent.maxY - headerExtent, "a header menu opens below the field")

        let scale = Theme.MenuMotion.maximumScale
        let trailingCanvas = MenuPanelCorner.bottomTrailing.scaledFrame(trailing, by: scale)
        let headerCanvas = MenuPanelCorner.belowHeaderTrailing.scaledFrame(header, by: scale)
        expect(trailingCanvas.maxX, trailing.maxX, "right expansion keeps its trailing edge fixed")
        expect(trailingCanvas.minY, trailing.minY, "right expansion keeps its bottom edge fixed")
        expect(headerCanvas.maxX, header.maxX, "header expansion keeps its trailing edge fixed")
        expect(headerCanvas.maxY, header.maxY, "header expansion keeps its top edge fixed")
    }

    // MARK: - The tokens these rules depend on

    static func tokenGrammar() {
        expect(topFraction > 0 && topFraction < 1, "the top margin is a real fraction of the screen")
    }
}
