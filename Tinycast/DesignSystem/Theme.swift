import QuartzCore
import SwiftUI

/// Central design tokens; every dark colour is the literal the forced-dark build shipped.
enum Theme {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        /// Outer inset of Tinycast's dialog content.
        static let dialogInset: CGFloat = 18
        static let xxl: CGFloat = 20
        /// Calculator answer card's roomier vertical breathing room.
        static let xxxl: CGFloat = 28
        /// Gap under a category header, shared by every palette list's `SectionHeader`.
        static let sectionHeaderBottom: CGFloat = 4
        /// Space above every header but the first, reading as the previous section's close.
        static let sectionSpacing: CGFloat = 12
        /// Emoji tiles need a little more separation so adjacent category grids stay distinct.
        static let emojiSectionSpacing: CGFloat = 14
        /// The Settings sidebar list's section-header inset, so its footer lines up beneath them.
        static let settingsSidebarInset: CGFloat = 14
    }

    enum Radius {
        static let panel: CGFloat = 26
        static let row: CGFloat = 10
        /// Emoji tiles are roomier than list rows, so their corners take one larger step.
        static let emojiCell: CGFloat = 12
        static let menu: CGFloat = 6
        /// Hover highlight behind a popover menu row.
        static let menuRow: CGFloat = 10
        /// A header pop-up button; the footer's action pills stay capsules.
        static let barControl: CGFloat = 8
        static let menuPanel: CGFloat = 16
        /// A footer menu's attached corner, concentric with the panel corner an inset away.
        static let menuAttached: CGFloat = panel - Spacing.md
        /// Subject tile inside the more rounded dialog panel.
        static let dialogSymbol: CGFloat = 16
        /// The dialog and HUD surface, so a dialog reads as a sibling of the palette.
        static let dialog: CGFloat = 20
        static let thumbnail: CGFloat = 6
        static let card: CGFloat = 10
        static let keyCap: CGFloat = 6
        /// Settings shortcut-recorder keycap — smaller than the palette's `keyCap` chip.
        static let recorderKeyCap: CGFloat = 4
        static let tooltip: CGFloat = 8
    }

    enum Size {
        static let panelWidth: CGFloat = 750
        static let panelHeight: CGFloat = 475
        /// Fraction of visible height above the palette's top edge; it grows downward.
        static let paletteTopMarginFraction: CGFloat = 0.18
        static let headerHeight: CGFloat = 44
        /// Fixed slot for the header glyph, so the field starts at one x in every mode.
        static let headerIconSlot: CGFloat = 22
        /// Room above the search row, constant so typing never shifts the bar.
        static let headerPadding: CGFloat = 10
        /// Collapsed compact bar: the search row centered in symmetric `headerPadding` slack.
        static let compactHeight: CGFloat = headerHeight + headerPadding * 2
        static let bottomBarHeight: CGFloat = 52
        /// A `BarButton`'s hover capsule, shared by the footer group and the header's filter.
        static let barButtonHeight: CGFloat = 28
        static let rowIcon: CGFloat = 24
        static let resultRowIcon: CGFloat = 26
        /// Colour-codes a secondary label, as Calendar.app marks an event's calendar.
        static let colorDot: CGFloat = 8
        static let keyCap: CGFloat = 18
        /// Settings shortcut-recorder keycap — smaller than the palette's `keyCap` chip.
        static let recorderKeyCap: CGFloat = 16
        /// Fixed so the recorder can't resize as its binding changes.
        static let shortcutRecorder: CGFloat = 120
        /// One text line in the recorder callout.
        static let shortcutPopoverLine: CGFloat = 14
        /// Summed from the laid-out bands; the width is pinned by `callout-test`.
        static let shortcutPopover = CGSize(
            width: 132,
            height: Spacing.sm * 2 + heroKeyCap + Spacing.sm + shortcutPopoverLine + Spacing.sm
                + compactKeyCap + calloutCaretHeight)
        /// The callout's pointer: a triangle with a rounded tip.
        static let calloutCaretWidth: CGFloat = 15
        static let calloutCaretHeight: CGFloat = 7
        static let calloutCaretTip: CGFloat = 2.5
        /// Keycaps: `compact` hints, `keyCap` is standard, `hero` where the cap is content.
        static let compactKeyCap: CGFloat = 15
        static let heroKeyCap: CGFloat = 22
        /// A one-pixel rule or stroke.
        static let hairline: CGFloat = 1
        /// The uninstall list's leading checkbox / lock glyph.
        static let checkbox: CGFloat = 16
        static let clipboardListWidth: CGFloat = 290
        /// Symmetric clearance between the emoji grid and both panel edges.
        static let emojiGridInset: CGFloat = 16
        static let actionMenuWidth: CGFloat = 320
        static let clipboardFilterMenuWidth: CGFloat = 200
        /// Fits "Shapes & Punctuation", the longest category title.
        static let emojiCategoryMenuWidth: CGFloat = 220
        /// Stated, not padded: the cap below counts rows, so a capped menu would land mid-row.
        static let menuRowHeight: CGFloat = menuIcon + Spacing.md * 2
        static let menuRowSpacing: CGFloat = 1
        /// Stated, not measured: `viewportHeight` counts headers, so a capped menu lands on a row.
        static let menuSectionHeader: CGFloat = 16
        /// Five rows and half of the sixth, so a capped menu reads as scrollable, not clipped.
        static let menuVisibleRows: CGFloat = 5.5
        /// Rounded: a half-row of an odd pitch lands the glass edge on a half pixel.
        static var menuRowsMaxHeight: CGFloat {
            (menuVisibleRows * (menuRowHeight + menuRowSpacing)).rounded()
        }
        /// A menu row's glyph slot, sized so symbol and app-icon rows read the same.
        static let menuIcon: CGFloat = 20
        /// The clipboard preview's player; `VideoPlayer` expands unbounded without a height.
        static let clipboardMediaHeight: CGFloat = 260
        /// The preview pane is ~460pt wide, so 900px stays crisp at 2× without over-decoding.
        static let clipboardPreviewPixel: CGFloat = 900
        /// Opening size and resize floor; the height fits the sidebar in full.
        static let settingsWindow = CGSize(width: 900, height: 700)
        /// Settings sidebar: a fixed column, wide enough for "Window Management".
        static let settingsSidebar: CGFloat = 215
        /// The narrowest the pane column may get before a grouped row's control starts colliding.
        static let settingsDetailMinimum: CGFloat = 420
        static let settingsRowIcon: CGFloat = 20
        /// A Settings number field, wide enough for three digits.
        static let settingsNumberField: CGFloat = 44
        /// A sidebar glyph inside its tinted tile; the tile's inset brings it to the row icon's size.
        static let settingsSidebarGlyph: CGFloat = 14
        /// The confirmation HUD's width ceiling, and its distance above the screen bottom.
        static let hudMaxWidth: CGFloat = 420
        static let hudEdgeOffset: CGFloat = 48
        /// Room for `featheredBlur`'s blur to fade out: twice its radius.
        static let blurFeather: CGFloat = Spacing.md * 2
        static let dialogWidth: CGFloat = 290
        static let dialogButtonHeight: CGFloat = 34
        /// Subject glyph and its fixed tile at the top of a dialog.
        static let dialogSymbol: CGFloat = 28
        static let dialogSymbolContainer: CGFloat = 52
        /// The camera's no-video glyph.
        static let dialogIcon: CGFloat = 32
        /// 16:9 and wider than a dialog: the camera is the surface itself.
        static let cameraStage = CGSize(width: 560, height: 315)
    }

    enum Duration {
        /// How long the message HUD stays up.
        static let messageHUD: TimeInterval = 2.4
        /// How a borderless surface arrives and leaves; the exit is shorter, so it feels quick.
        static let enter: TimeInterval = 0.18
        static let exit: TimeInterval = 0.12
        /// A dialog moves with its launcher dimming; its fade-in is a shorter sub-beat.
        static let dialogEnter: TimeInterval = 0.12
        static let dialogExit: TimeInterval = 0.10
        /// Fade-in/out for a hover `Tooltip`, after a wait only a deliberate hover outlasts.
        static let tooltip: TimeInterval = 0.15
        static let tooltipDelay: TimeInterval = 0.4
        /// A control lighting up under the pointer; short enough to feel like a response.
        static let hover: TimeInterval = 0.12
        /// A pop-up chevron turning between its closed and open directions.
        static let menuChevron: TimeInterval = 0.34
        /// A Settings search result scrolling its section into view, then the pulse that marks it.
        static let settingsReveal: TimeInterval = 0.28
        static let settingsFlash: TimeInterval = 2.0
        static let settingsFlashOut: TimeInterval = 0.6
    }

    enum DialogMotion {
        static let offset: CGFloat = 3
        static let initialOpacity: CGFloat = 0.08
    }

    @MainActor
    enum MenuMotion {
        static let entryScale: CGFloat = 0.94
        static let maximumScale: CGFloat = 1.003
        static let exitScaleDelta: CGFloat = 0.04
        static let expansionDuration: TimeInterval = 0.10
        static let settleDuration: TimeInterval = 0.05
        static let exitDuration: TimeInterval = 0.18
        static let expansionTiming = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.2, 1)
        static let settleTiming = CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1)
        static let exitTiming = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
        /// Starts promptly and eases gently into the chevron's final direction.
        static let chevronAnimation = Animation.timingCurve(
            0.16, 1, 0.3, 1, duration: Theme.Duration.menuChevron)
    }

    /// System text styles (not hardcoded sizes) so the UI honors Dynamic Type.
    enum Typography {
        static let searchFieldSize: CGFloat = 20
        static let searchField = Font.system(size: searchFieldSize, weight: .regular)
        static let headerIcon = Font.system(size: 18, weight: .medium)
        static let rowTitle = Font.body
        static let rowTrailing = Font.callout
        static let sectionHeader = Font.subheadline.weight(.medium)
        /// A borderless panel's own title, which names the surface rather than a section inside it.
        static let panelTitle = Font.headline
        /// The big value line on the calculator answer card (both source and target sides).
        static let calcResult = Font.title
        static let keyCap = Font.caption
        /// Pair with the matching `Size` for `KeyCapChip.Scale`.
        static let compactKeyCap = Font.caption2
        static let heroKeyCap = Font.body
        static let bar = Font.callout.weight(.medium)
        /// A dropdown control's trailing chevron, deliberately smaller than the label it follows.
        static let disclosure = Font.caption.weight(.semibold)
        static let menuRow = Font.body
        static let menuIcon = Font.body
        static let menuSymbolSize: CGFloat = 14
        static let menuSymbolWeight = Font.Weight.medium
    }

    enum Colors {
        /// Resolves against the window's `effectiveAppearance`, so a token repaints on its own.
        static func adaptive(dark: NSColor, light: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { $0.isDark ? dark : light })
        }

        /// The alpha ramp, inverted: white ink over the dark surface, black ink over the light one.
        static func ramp(dark: Double, light: Double) -> Color {
            adaptive(dark: .srgbInk(1, alpha: dark), light: .srgbInk(0, alpha: light))
        }

        /// The ramp's inverse: the scrim darkens the dark surface and lightens the light one.
        static let panelScrim = adaptive(dark: .srgbInk(0, alpha: 0.40), light: .srgbInk(1, alpha: 0.55))
        /// Modal separation inside Tinycast: the launcher recedes while its dialog is in front.
        static let dialogDimming = adaptive(
            dark: .srgbInk(0, alpha: 0.34), light: .srgbInk(0, alpha: 0.34))
        static let tooltipShadow = adaptive(
            dark: .srgbInk(0, alpha: 0.18), light: .srgbInk(0, alpha: 0.18))

        /// Selection fill, shared by every list so they look identical.
        static let selection = ramp(dark: 0.10, light: 0.09)
        /// Mouse hover: a fainter layer, visually distinct from selection.
        static let rowHover = ramp(dark: 0.05, light: 0.045)
        /// Emoji grid chrome: a quiet tile at rest, with two legible rings on interaction.
        static let emojiCell = ramp(dark: 0.045, light: 0.04)
        static let emojiHoverBorder = ramp(dark: 0.42, light: 0.34)
        static let emojiSelectionBorder = ramp(dark: 0.92, light: 0.72)
        static let emojiInnerBorder = adaptive(
            dark: .srgbInk(0, alpha: 0.72), light: .srgbInk(1, alpha: 0.72))
        static let menuHover = ramp(dark: 0.10, light: 0.09)
        static let separator = ramp(dark: 0.10, light: 0.12)
        /// Small control surfaces: kbd chips, glyph tiles.
        static let controlSurface = ramp(dark: 0.10, light: 0.08)
        /// A pointer over a control should lift it above its resting surface.
        static let controlHover = ramp(dark: 0.16, light: 0.14)
        /// A held control is stronger than hover, so mouse-down always reads.
        static let controlPressed = ramp(dark: 0.24, light: 0.20)
        /// Control borders: outlined kbd chips.
        static let border = ramp(dark: 0.20, light: 0.18)
        /// Alpha 1, so a call site can dim it with `.opacity` and land on the value it replaced.
        static let textPrimary = ramp(dark: 1.0, light: 1.0)
        static let textSecondary = ramp(dark: 0.60, light: 0.60)
        static let textTertiary = ramp(dark: 0.40, light: 0.42)
        static let menuSymbol = ramp(dark: 0.70, light: 0.70)
        static let iconPlaceholder = ramp(dark: 0.06, light: 0.06)
        /// The faint wash behind the Onboarding header.
        static let sheen = ramp(dark: 0.04, light: 0.04)
        /// The Settings card: a faint surface whose border doubles as the row divider.
        static let cardFill = ramp(dark: 0.05, light: 0.04)
        static let cardStroke = ramp(dark: 0.10, light: 0.10)
        /// The pill behind the header of the section a Settings search jumped to.
        static let searchFlash = Color.accentColor.opacity(0.35)
        /// The two squares of a checkerboard, behind a colour with alpha to show.
        static let checkerLight = Color(nsColor: .srgbInk(1, alpha: 0.22))
        static let checkerDark = Color(nsColor: .srgbInk(0, alpha: 0.22))
        /// A dialog's standard default action; destructive defaults keep their semantic red.
        static let primaryAction = Color.blue
        /// Destructive tint: a destructive label, and a `.danger` dialog's glyph.
        static let destructive = Color.red
        /// Success tint: the leading glyph of a `.success` dialog.
        static let success = Color.green
        /// Progress tint: the message pill's spinner while the work behind it is still running.
        static let progress = Color.blue
    }
}

extension View {
    /// Lighter than glass: blurs what passes beneath, faded out at the edges so no outline shows.
    func featheredBlur() -> some View {
        background {
            Rectangle()
                .fill(.ultraThinMaterial)
                // Inset by twice the blur radius, so the mask reaches zero before the frame does.
                .mask {
                    Capsule()
                        .padding(Theme.Size.blurFeather)
                        .blur(radius: Theme.Spacing.md)
                }
                .padding(-(Theme.Spacing.md + Theme.Size.blurFeather))
                // It reaches past the bar into the list, where rows keep their clicks and hover.
                .allowsHitTesting(false)
        }
    }
}
