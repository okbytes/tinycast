import CoreGraphics
import Foundation

/// Pure geometry, entirely in AX space. See docs/features/window-management.md#coordinate-space.
enum WindowPlacementEngine {
    /// A display, already converted to AX space by the caller.
    struct Screen: Equatable, Sendable {
        /// `CGDirectDisplayID` in the app; any stable value in tests.
        let id: Int
        let frame: CGRect
        /// Everything below the menu bar; the Dock is deliberately not subtracted.
        let usableFrame: CGRect
    }

    /// Where a window that refused to shrink sits in its slot; a left half stays left-aligned.
    struct Anchor: Equatable, Sendable {
        /// `min` is left / top, since +Y points down here.
        enum Axis: Equatable, Sendable { case min, center, max }

        var horizontal: Axis
        var vertical: Axis

        static let topLeading = Anchor(horizontal: .min, vertical: .min)

        /// Places `size` inside `slot` per the anchor, when an app clamped itself larger.
        func place(_ size: CGSize, in slot: CGRect) -> CGRect {
            func origin(
                _ axis: Axis, slotMin: CGFloat, slotLength: CGFloat, length: CGFloat
            )
                -> CGFloat
            {
                switch axis {
                case .min: return slotMin
                case .center: return slotMin + (slotLength - length) / 2
                case .max: return slotMin + slotLength - length
                }
            }
            return CGRect(
                x: origin(
                    horizontal, slotMin: slot.minX, slotLength: slot.width, length: size.width),
                y: origin(vertical, slotMin: slot.minY, slotLength: slot.height, length: size.height),
                width: size.width, height: size.height)
        }
    }

    /// The three commands the user tunes in Settings; `standard` is also every setting's default.
    struct Preferences: Equatable, Sendable {
        var halfStart: WindowCommand.HalfSide
        var quarterStart: WindowCommand.QuarterCorner
        /// Center's width, as a percentage of the display.
        var centerWidth: Int

        static let standard = Preferences(halfStart: .left, quarterStart: .topLeft, centerWidth: 75)
    }

    /// The widths Center offers, in percent; the file is held to the same range.
    static let centerWidthRange = 20...100

    struct Input: Equatable, Sendable {
        var command: WindowCommand.ID
        var windowFrame: CGRect
        var screens: [Screen]
        /// The slot in the command's cycle, chosen by the mover so the geometry stays stateless.
        var step: Int
        /// Center's width, as a percentage of the display.
        var centerWidth: Int

        init(
            command: WindowCommand.ID, windowFrame: CGRect, screens: [Screen], step: Int = 0,
            centerWidth: Int = Preferences.standard.centerWidth
        ) {
            self.command = command
            self.windowFrame = windowFrame
            self.screens = screens
            self.step = step
            self.centerWidth = centerWidth
        }
    }

    struct Placement: Equatable, Sendable {
        var frame: CGRect
        var screenID: Int
        var anchor: Anchor
        var resizes: Bool
    }

    // MARK: - Entry point

    /// The target placement, or `nil` when the mover should write nothing at all.
    static func placement(for input: Input) -> Placement? {
        guard let host = screen(containing: input.windowFrame, in: input.screens),
            host.usableFrame.width > 0, host.usableFrame.height > 0
        else { return nil }

        // `cycleLength` is 1 for a non-cycling command, so a stale step can never leak in.
        let step = wrapped(input.step, into: WindowCommandCatalog.cycleLength(for: input.command))
        let canvas = canvas(host.usableFrame)
        let current = input.windowFrame

        switch input.command {
        case .half:
            return tilePlacement(WindowCommand.HalfSide.cycle[step].fractions, on: host)

        case .quarter:
            return tilePlacement(WindowCommand.QuarterCorner.cycle[step].fractions, on: host)

        case .maximize:
            return Placement(
                frame: canvas, screenID: host.id, anchor: .topLeading, resizes: true)

        // A window that can't take this size sits centred on both axes, not pinned to the top.
        case .center:
            let width = CGFloat(clampedCenterWidth(input.centerWidth)) / 100
            return tilePlacement(
                Fractions(
                    x0: (1 - width) / 2, x1: (1 + width) / 2, y0: 0, y1: 1,
                    anchor: Anchor(horizontal: .center, vertical: .center)),
                on: host)

        case .moveLeft, .moveRight, .moveUp, .moveDown:
            return Placement(
                frame: pushed(current, in: canvas, command: input.command), screenID: host.id,
                anchor: .topLeading, resizes: false)
        }
    }

    /// The slot a press that starts a new chain lands on: the starting position Settings names.
    static func firstStep(for command: WindowCommand.ID, preferences: Preferences) -> Int {
        switch command {
        case .half: return WindowCommand.HalfSide.cycle.firstIndex(of: preferences.halfStart) ?? 0
        case .quarter:
            return WindowCommand.QuarterCorner.cycle.firstIndex(of: preferences.quarterStart) ?? 0
        case .maximize, .center, .moveLeft, .moveRight, .moveUp, .moveDown: return 0
        }
    }

    // MARK: - Screens

    /// The display a window lives on: most overlapping area wins, else the one holding its centre.
    static func screen(containing frame: CGRect, in screens: [Screen]) -> Screen? {
        guard !screens.isEmpty else { return nil }
        var best: (screen: Screen, area: CGFloat)?
        for screen in screens {
            let overlap = screen.frame.intersection(frame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (screen, area) }
        }
        if let best, best.area > 0 { return best.screen }
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        return screens.first { $0.frame.contains(centre) } ?? screens.first
    }

    // MARK: - Tiles

    fileprivate struct Fractions {
        var x0: CGFloat
        var x1: CGFloat
        var y0: CGFloat
        var y1: CGFloat
        var anchor: Anchor
    }

    private static func tilePlacement(_ fractions: Fractions, on screen: Screen) -> Placement {
        let frame = tile(
            screen.usableFrame, x0: fractions.x0, x1: fractions.x1, y0: fractions.y0,
            y1: fractions.y1)
        return Placement(
            frame: frame, screenID: screen.id, anchor: fractions.anchor, resizes: true)
    }

    /// A tile from fractional bounds of `visible`. See docs/features/window-management.md#geometry.
    static func tile(
        _ visible: CGRect, x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat
    ) -> CGRect {
        let left = visible.minX + x0 * visible.width
        let right = visible.minX + x1 * visible.width
        let top = visible.minY + y0 * visible.height
        let bottom = visible.minY + y1 * visible.height
        return rounded(
            CGRect(
                x: left, y: top, width: max(1, right - left), height: max(1, bottom - top)))
    }

    /// The box free-floating commands work in.
    static func canvas(_ visible: CGRect) -> CGRect {
        rounded(visible)
    }

    /// settings.json and backups refuse a width outside the range; this catches a defaults write.
    static func clampedCenterWidth(_ percent: Int) -> Int {
        min(max(percent, centerWidthRange.lowerBound), centerWidthRange.upperBound)
    }

    // MARK: - Moves

    /// Flush against one canvas edge; the size and the other axis's position stay put.
    private static func pushed(
        _ frame: CGRect, in canvas: CGRect, command: WindowCommand.ID
    )
        -> CGRect
    {
        var moved = frame
        switch command {
        case .moveLeft: moved.origin.x = canvas.minX
        case .moveRight: moved.origin.x = canvas.maxX - frame.width
        case .moveUp: moved.origin.y = canvas.minY
        case .moveDown: moved.origin.y = canvas.maxY - frame.height
        default: break
        }
        return rounded(clamped(moved, into: canvas))
    }

    // MARK: - Held frames

    /// What happened to a frame we placed since we placed it.
    enum HeldFrameChange: Equatable, Sendable {
        case unchanged
        /// Only the bottom edge rose, by at most a Dock: macOS or the app fitting it above one.
        case dockShrink
        case other
    }

    /// A Dock at its largest tile size plus its padding; a deeper lift is not the Dock's doing.
    static let dockReserveLimit: CGFloat = 160

    static func heldFrameChange(
        from held: CGRect, to current: CGRect, tolerance: CGFloat
    ) -> HeldFrameChange {
        let keepsTopLeftAndWidth =
            abs(current.minX - held.minX) <= tolerance && abs(current.minY - held.minY) <= tolerance
            && abs(current.width - held.width) <= tolerance
        guard keepsTopLeftAndWidth else { return .other }
        let lift = held.maxY - current.maxY
        if abs(lift) <= tolerance { return .unchanged }
        return lift > 0 && lift <= dockReserveLimit ? .dockShrink : .other
    }

    // MARK: - Primitives

    /// Rounds the four edges, so two tiles sharing a boundary round it identically.
    static func rounded(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded()
        let minY = rect.minY.rounded()
        let maxX = rect.maxX.rounded()
        let maxY = rect.maxY.rounded()
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    /// Keeps `frame` inside `box` unresized; an oversized window pins its leading edge.
    static func clamped(_ frame: CGRect, into box: CGRect) -> CGRect {
        let x = min(max(frame.minX, box.minX), max(box.minX, box.maxX - frame.width))
        let y = min(max(frame.minY, box.minY), max(box.minY, box.maxY - frame.height))
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    /// Wraps into `0..<length`, so neither a negative nor an overrun step escapes the cycle.
    private static func wrapped(_ value: Int, into length: Int) -> Int {
        ((value % length) + length) % length
    }
}

extension CGRect {
    /// Every edge within `tolerance`: what "the window is still where it was" means here.
    func approximatelyEquals(_ other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

extension WindowCommand.HalfSide {
    fileprivate var fractions: WindowPlacementEngine.Fractions {
        switch self {
        case .left:
            WindowPlacementEngine.Fractions(x0: 0, x1: 0.5, y0: 0, y1: 1, anchor: .topLeading)
        case .right:
            WindowPlacementEngine.Fractions(
                x0: 0.5, x1: 1, y0: 0, y1: 1,
                anchor: WindowPlacementEngine.Anchor(horizontal: .max, vertical: .min))
        }
    }
}

extension WindowCommand.QuarterCorner {
    fileprivate var fractions: WindowPlacementEngine.Fractions {
        typealias Anchor = WindowPlacementEngine.Anchor
        return switch self {
        case .topLeft:
            WindowPlacementEngine.Fractions(x0: 0, x1: 0.5, y0: 0, y1: 0.5, anchor: .topLeading)
        case .topRight:
            WindowPlacementEngine.Fractions(
                x0: 0.5, x1: 1, y0: 0, y1: 0.5, anchor: Anchor(horizontal: .max, vertical: .min))
        case .bottomLeft:
            WindowPlacementEngine.Fractions(
                x0: 0, x1: 0.5, y0: 0.5, y1: 1, anchor: Anchor(horizontal: .min, vertical: .max))
        case .bottomRight:
            WindowPlacementEngine.Fractions(
                x0: 0.5, x1: 1, y0: 0.5, y1: 1, anchor: Anchor(horizontal: .max, vertical: .max))
        }
    }
}
