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

    struct Input: Equatable, Sendable {
        var command: WindowCommand.ID
        var windowFrame: CGRect
        var screens: [Screen]
        var gap: CGFloat
        /// Cycle position, supplied by `WindowActionMemory` so the geometry itself stays stateless.
        var step: Int
        /// What the step means: the mode the user picked for a repeat press.
        var cycle: WindowCycle
        /// The display the chain started on; `nil`, or one since unplugged, means the host.
        var originScreenID: Int?

        init(
            command: WindowCommand.ID, windowFrame: CGRect, screens: [Screen], gap: CGFloat = 0,
            step: Int = 0, cycle: WindowCycle = .off, originScreenID: Int? = nil
        ) {
            self.command = command
            self.windowFrame = windowFrame
            self.screens = screens
            self.gap = gap
            self.step = step
            self.cycle = cycle
            self.originScreenID = originScreenID
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
        let step = wrapped(
            input.step,
            into: cycleLength(for: input.command, screens: input.screens, cycle: input.cycle))

        if let half = Half.of(input.command) {
            return halfPlacement(input, half: half, host: host, step: step)
        }
        if let fractions = tileFractions(input.command) {
            return tilePlacement(fractions, on: host, gap: input.gap)
        }

        let canvas = canvas(
            host.usableFrame, gap: sanitizedGap(input.gap, in: host.usableFrame))
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        let current = input.windowFrame

        switch input.command {
        case .maximize:
            return Placement(
                frame: canvas, screenID: host.id, anchor: .topLeading, resizes: true)

        // Horizontal only: the window keeps its vertical position, clamped back onto the display.
        case .center:
            let size = CGSize(
                width: min(current.width, canvas.width), height: min(current.height, canvas.height))
            let frame = CGRect(
                x: canvas.midX - size.width / 2, y: current.minY, width: size.width,
                height: size.height)
            return Placement(
                frame: rounded(clamped(frame, into: canvas)), screenID: host.id,
                anchor: Anchor(horizontal: .center, vertical: .min), resizes: true)

        case .moveLeft, .moveRight, .moveUp, .moveDown:
            return Placement(
                frame: pushed(current, in: canvas, command: input.command), screenID: host.id,
                anchor: .topLeading, resizes: false)

        default:
            return nil
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

    /// Left-to-right, then top-to-bottom: stable however `NSScreen.screens` is sorted.
    static func ordered(_ screens: [Screen]) -> [Screen] {
        screens.sorted {
            $0.frame.minX != $1.frame.minX
                ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY
        }
    }

    // MARK: - Tiles

    private struct Fractions {
        var x0: CGFloat
        var x1: CGFloat
        var y0: CGFloat
        var y1: CGFloat
        var anchor: Anchor
    }

    /// Left or Right Half, named by the screen edge it hugs.
    private enum Half {
        case leading, trailing

        static func of(_ command: WindowCommand.ID) -> Half? {
            switch command {
            case .leftHalf: .leading
            case .rightHalf: .trailing
            default: nil
            }
        }

        /// Full height, covering `fraction` of the width from this edge.
        func fractions(_ fraction: CGFloat) -> Fractions {
            switch self {
            case .leading:
                Fractions(x0: 0, x1: fraction, y0: 0, y1: 1, anchor: .topLeading)
            case .trailing:
                Fractions(
                    x0: 1 - fraction, x1: 1, y0: 0, y1: 1,
                    anchor: Anchor(horizontal: .max, vertical: .min))
            }
        }
    }

    /// The sizes a half steps through when size cycling is on.
    private static let sizeCycle: [CGFloat] = [0.5, 1.0 / 3.0, 2.0 / 3.0]

    /// Presses before the chain wraps; 1 means this command doesn't cycle at all.
    static func cycleLength(
        for command: WindowCommand.ID, screens: [Screen], cycle: WindowCycle
    ) -> Int {
        guard WindowCommandCatalog.command(id: command)?.cyclesOnRepeat == true else { return 1 }
        switch cycle {
        case .off: return 1
        case .sizes: return sizeCycle.count
        // One display is a no-op, not an in-place flip.
        case .displays: return screens.count > 1 ? screens.count * 2 : 1
        }
    }

    /// A half's slot this press: its own edge on the host, or one walked along the display strip.
    private static func halfPlacement(
        _ input: Input, half: Half, host: Screen, step: Int
    ) -> Placement {
        guard input.cycle == .displays else {
            return tilePlacement(half.fractions(sizeCycle[step]), on: host, gap: input.gap)
        }
        let strip = ordered(input.screens)
        // Mid-chain the window already sits on another display, so counting from it would overshoot.
        guard strip.count > 1,
            let originIndex = strip.firstIndex(where: { $0.id == input.originScreenID })
                ?? strip.firstIndex(where: { $0.id == host.id })
        else {
            return tilePlacement(half.fractions(0.5), on: host, gap: input.gap)
        }
        // Left walks backwards, so one shortcut sweeps the whole desktop in one direction.
        let leads = half == .leading
        let slot = wrapped(
            originIndex * 2 + (leads ? 0 : 1) + (leads ? -step : step), into: strip.count * 2)
        let edge: Half = slot.isMultiple(of: 2) ? .leading : .trailing
        return tilePlacement(edge.fractions(0.5), on: strip[slot / 2], gap: input.gap)
    }

    private static func tilePlacement(
        _ fractions: Fractions, on screen: Screen, gap: CGFloat
    ) -> Placement {
        let frame = tile(
            screen.usableFrame, x0: fractions.x0, x1: fractions.x1, y0: fractions.y0,
            y1: fractions.y1, gap: sanitizedGap(gap, in: screen.usableFrame))
        return Placement(
            frame: frame, screenID: screen.id, anchor: fractions.anchor, resizes: true)
    }

    /// Fractional bounds of a tile command that isn't a half, or `nil` if it isn't one.
    private static func tileFractions(_ command: WindowCommand.ID) -> Fractions? {
        switch command {
        case .topLeftQuarter:
            return Fractions(x0: 0, x1: 0.5, y0: 0, y1: 0.5, anchor: .topLeading)
        case .topRightQuarter:
            return Fractions(
                x0: 0.5, x1: 1, y0: 0, y1: 0.5, anchor: Anchor(horizontal: .max, vertical: .min))
        case .bottomLeftQuarter:
            return Fractions(
                x0: 0, x1: 0.5, y0: 0.5, y1: 1, anchor: Anchor(horizontal: .min, vertical: .max))
        case .bottomRightQuarter:
            return Fractions(
                x0: 0.5, x1: 1, y0: 0.5, y1: 1, anchor: Anchor(horizontal: .max, vertical: .max))

        case .firstThreeFourths:
            return Fractions(x0: 0, x1: 0.75, y0: 0, y1: 1, anchor: .topLeading)
        case .centerThreeFourths:
            return Fractions(
                x0: 0.125, x1: 0.875, y0: 0, y1: 1,
                anchor: Anchor(horizontal: .center, vertical: .min))
        case .lastThreeFourths:
            return Fractions(
                x0: 0.25, x1: 1, y0: 0, y1: 1, anchor: Anchor(horizontal: .max, vertical: .min))

        default:
            return nil
        }
    }

    /// A tile from fractional bounds of `visible`. See docs/features/window-management.md#geometry.
    static func tile(
        _ visible: CGRect, x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat, gap: CGFloat
    ) -> CGRect {
        let left = visible.minX + x0 * visible.width + (x0 == 0 ? gap : gap / 2)
        let right = visible.minX + x1 * visible.width - (x1 == 1 ? gap : gap / 2)
        let top = visible.minY + y0 * visible.height + (y0 == 0 ? gap : gap / 2)
        let bottom = visible.minY + y1 * visible.height - (y1 == 1 ? gap : gap / 2)
        return rounded(
            CGRect(
                x: left, y: top, width: max(1, right - left), height: max(1, bottom - top)))
    }

    /// The box free-floating commands work in: full gap on every side, not the grid's halves.
    static func canvas(_ visible: CGRect, gap: CGFloat) -> CGRect {
        rounded(visible.insetBy(dx: gap, dy: gap))
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

    /// The gaps Settings offers, in points; the file is held to the same range.
    static let gapRange = 0...64

    /// A gap wider than the screen would produce zero-width tiles, so cap it before any math.
    static func sanitizedGap(_ gap: CGFloat, in visible: CGRect) -> CGFloat {
        guard gap.isFinite, gap > 0, visible.width > 0, visible.height > 0 else { return 0 }
        return min(gap, min(visible.width, visible.height) / 10)
    }

    /// Wraps into `0..<length`, so neither a negative nor an overrun step escapes the cycle.
    private static func wrapped(_ value: Int, into length: Int) -> Int {
        ((value % length) + length) % length
    }
}
