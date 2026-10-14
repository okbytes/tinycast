import AppKit
import SwiftUI

/// Against the real `Theme`, so `.standard` can never drift from what the app ships today.
@main
@MainActor
struct InterfaceSizeTests {
    static var failures = 0
    static var passes = 0

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

    static func main() {
        theDefaultIsThemeVerbatim()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Identity at the default size

    /// Every member, so a mistyped `Theme` reference in `InterfaceMetrics` cannot ship silently.
    static func theDefaultIsThemeVerbatim() {
        let m = InterfaceMetrics.standard
        expect(m.scale, 1, "the default scale is 1")

        expect(m.spacing.xxs, Theme.Spacing.xxs, "spacing.xxs")
        expect(m.spacing.xs, Theme.Spacing.xs, "spacing.xs")
        expect(m.spacing.sm, Theme.Spacing.sm, "spacing.sm")
        expect(m.spacing.md, Theme.Spacing.md, "spacing.md")
        expect(m.spacing.lg, Theme.Spacing.lg, "spacing.lg")
        expect(m.spacing.xl, Theme.Spacing.xl, "spacing.xl")
        expect(m.spacing.dialogInset, Theme.Spacing.dialogInset, "spacing.dialogInset")
        expect(m.spacing.xxl, Theme.Spacing.xxl, "spacing.xxl")
        expect(m.spacing.xxxl, Theme.Spacing.xxxl, "spacing.xxxl")
        expect(
            m.spacing.sectionHeaderBottom, Theme.Spacing.sectionHeaderBottom,
            "spacing.sectionHeaderBottom")
        expect(m.spacing.sectionSpacing, Theme.Spacing.sectionSpacing, "spacing.sectionSpacing")
        expect(
            m.spacing.emojiSectionSpacing, Theme.Spacing.emojiSectionSpacing,
            "spacing.emojiSectionSpacing")

        expect(m.radius.panel, Theme.Radius.panel, "radius.panel")
        expect(m.radius.row, Theme.Radius.row, "radius.row")
        expect(m.radius.emojiCell, Theme.Radius.emojiCell, "radius.emojiCell")
        expect(m.radius.menu, Theme.Radius.menu, "radius.menu")
        expect(m.radius.menuRow, Theme.Radius.menuRow, "radius.menuRow")
        expect(m.radius.barControl, Theme.Radius.barControl, "radius.barControl")
        expect(m.radius.menuPanel, Theme.Radius.menuPanel, "radius.menuPanel")
        expect(m.radius.dialogSymbol, Theme.Radius.dialogSymbol, "radius.dialogSymbol")
        expect(m.radius.dialog, Theme.Radius.dialog, "radius.dialog")
        expect(m.radius.thumbnail, Theme.Radius.thumbnail, "radius.thumbnail")
        expect(m.radius.card, Theme.Radius.card, "radius.card")
        expect(m.radius.keyCap, Theme.Radius.keyCap, "radius.keyCap")
        expect(m.radius.tooltip, Theme.Radius.tooltip, "radius.tooltip")

        expect(m.size.panelWidth, Theme.Size.panelWidth, "size.panelWidth")
        expect(m.size.panelHeight, Theme.Size.panelHeight, "size.panelHeight")
        expect(m.size.headerHeight, Theme.Size.headerHeight, "size.headerHeight")
        expect(m.size.headerIconSlot, Theme.Size.headerIconSlot, "size.headerIconSlot")
        expect(m.size.headerPadding, Theme.Size.headerPadding, "size.headerPadding")
        expect(m.size.compactHeight, Theme.Size.compactHeight, "size.compactHeight")
        expect(m.size.bottomBarHeight, Theme.Size.bottomBarHeight, "size.bottomBarHeight")
        expect(m.size.barButtonHeight, Theme.Size.barButtonHeight, "size.barButtonHeight")
        expect(m.size.rowIcon, Theme.Size.rowIcon, "size.rowIcon")
        expect(m.size.resultRowIcon, Theme.Size.resultRowIcon, "size.resultRowIcon")
        expect(m.size.keyCap, Theme.Size.keyCap, "size.keyCap")
        expect(m.size.compactKeyCap, Theme.Size.compactKeyCap, "size.compactKeyCap")
        expect(m.size.heroKeyCap, Theme.Size.heroKeyCap, "size.heroKeyCap")
        expect(m.size.menuButton, Theme.Size.menuButton, "size.menuButton")
        expect(m.size.checkbox, Theme.Size.checkbox, "size.checkbox")
        expect(
            m.size.clipboardFilterMenuWidth, Theme.Size.clipboardFilterMenuWidth,
            "size.clipboardFilterMenuWidth")
        expect(
            m.size.emojiCategoryMenuWidth, Theme.Size.emojiCategoryMenuWidth,
            "size.emojiCategoryMenuWidth")
        expect(m.size.menuIcon, Theme.Size.menuIcon, "size.menuIcon")
        expect(m.size.menuRowSpacing, Theme.Size.menuRowSpacing, "size.menuRowSpacing")
        expect(m.size.menuSectionHeader, Theme.Size.menuSectionHeader, "size.menuSectionHeader")
        expect(m.size.menuRowHeight, Theme.Size.menuRowHeight, "size.menuRowHeight")
        expect(m.size.menuRowsMaxHeight, Theme.Size.menuRowsMaxHeight, "size.menuRowsMaxHeight")
        expect(m.size.clipboardListWidth, Theme.Size.clipboardListWidth, "size.clipboardListWidth")
        expect(
            m.size.clipboardMediaHeight, Theme.Size.clipboardMediaHeight, "size.clipboardMediaHeight")
        expect(
            m.size.clipboardPreviewPixel, Theme.Size.clipboardPreviewPixel,
            "size.clipboardPreviewPixel")
        expect(m.size.emojiGridInset, Theme.Size.emojiGridInset, "size.emojiGridInset")
        expect(m.size.dialogWidth, Theme.Size.dialogWidth, "size.dialogWidth")
        expect(
            m.size.dialogButtonHeight, Theme.Size.dialogButtonHeight,
            "size.dialogButtonHeight")
        expect(m.size.dialogSymbol, Theme.Size.dialogSymbol, "size.dialogSymbol")
        expect(
            m.size.dialogSymbolContainer, Theme.Size.dialogSymbolContainer,
            "size.dialogSymbolContainer")
        expect(m.size.dialogIcon, Theme.Size.dialogIcon, "size.dialogIcon")
        expect(m.size.hudMaxWidth, Theme.Size.hudMaxWidth, "size.hudMaxWidth")
        expect(m.size.hudWidth, Theme.Size.hudWidth, "size.hudWidth")
        expect(m.size.hudHeight, Theme.Size.hudHeight, "size.hudHeight")
        expect(m.size.volumeTrackHeight, Theme.Size.volumeTrackHeight, "size.volumeTrackHeight")
        expect(m.size.volumeReadout, Theme.Size.volumeReadout, "size.volumeReadout")

        expect(m.typography.searchFieldSize, Theme.Typography.searchFieldSize, "typography.searchField")
    }
}
