// Standalone contract tests for the pure window-management geometry and action memory.
import CoreGraphics
import Foundation

@main
@MainActor
struct WindowCommandTests {
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

    static func expectRect(_ actual: CGRect, _ expected: CGRect, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), expected \(expected)")
        }
    }

    // MARK: - Fixtures

    /// The reference display: origin at the AX origin, evenly divisible by halves and thirds.
    static let mainScreen = WindowPlacementEngine.Screen(
        id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        usableFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))

    static func screens(_ list: WindowPlacementEngine.Screen...) -> [WindowPlacementEngine.Screen] { list }

    static func placement(
        _ command: WindowCommand.ID, on screen: WindowPlacementEngine.Screen = mainScreen,
        window: CGRect = CGRect(x: 100, y: 100, width: 600, height: 400), gap: CGFloat = 0,
        step: Int = 0, cycle: WindowCycle = .off,
        allScreens: [WindowPlacementEngine.Screen]? = nil
    ) -> WindowPlacementEngine.Placement? {
        WindowPlacementEngine.placement(
            for: WindowPlacementEngine.Input(
                command: command, windowFrame: window, screens: allScreens ?? [screen], gap: gap,
                step: step, cycle: cycle))
    }

    static func frame(
        _ command: WindowCommand.ID, on screen: WindowPlacementEngine.Screen = mainScreen,
        window: CGRect = CGRect(x: 100, y: 100, width: 600, height: 400), gap: CGFloat = 0,
        step: Int = 0, cycle: WindowCycle = .off,
        allScreens: [WindowPlacementEngine.Screen]? = nil
    ) -> CGRect? {
        placement(
            command, on: screen, window: window, gap: gap, step: step, cycle: cycle,
            allScreens: allScreens)?.frame
    }

    /// Presses `command` like `WindowMover`: each press starts from where the last one landed.
    static func presses(
        _ command: WindowCommand.ID, _ count: Int, from window: CGRect,
        on list: [WindowPlacementEngine.Screen]
    ) -> [WindowPlacementEngine.Placement] {
        let clock = Date(timeIntervalSince1970: 1_000_000)
        var memory = WindowActionMemory<Int>()
        var current = window
        var landed: [WindowPlacementEngine.Placement] = []
        for _ in 0..<count {
            let host = WindowPlacementEngine.screen(containing: current, in: list)!
            let decision = memory.decide(
                key: 1, command: command, currentFrame: current, currentScreenID: host.id,
                cycleLength: length(command, .displays, list), now: clock)
            let placement = WindowPlacementEngine.placement(
                for: WindowPlacementEngine.Input(
                    command: command, windowFrame: current, screens: list, step: decision.step,
                    cycle: .displays, originScreenID: decision.originScreenID))!
            memory.commit(
                key: 1, command: command, decision: decision, appliedFrame: placement.frame,
                screenID: placement.screenID, now: clock)
            current = placement.frame
            landed.append(placement)
        }
        return landed
    }

    static func length(
        _ command: WindowCommand.ID, _ cycle: WindowCycle,
        _ list: [WindowPlacementEngine.Screen] = [mainScreen]
    ) -> Int {
        WindowPlacementEngine.cycleLength(for: command, screens: list, cycle: cycle)
    }

    static func main() {
        testCatalog()
        testConventionLock()
        testTiling()
        testNonDivisible()
        testOffOriginScreens()
        testGaps()
        testSizing()
        testMoves()
        testScreens()
        testDisplayCycle()
        testMemory()
        testFuzz()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Catalog

    static func testCatalog() {
        let commands = WindowCommandCatalog.all
        expect(commands.count == 15, "catalog contains all 15 agreed commands")
        expect(commands.map(\.id) == WindowCommand.ID.allCases, "catalog covers every ID once")
        expect(
            Set(commands.map { $0.name.lowercased() }).count == commands.count, "names are unique")
        expect(commands.allSatisfy { !$0.name.isEmpty }, "names are non-empty")
        expect(commands.allSatisfy { !$0.sfSymbol.isEmpty }, "symbols are non-empty")

        for command in commands {
            expect(
                WindowCommandCatalog.command(forEntryID: command.entryID) == command,
                "\(command.id.rawValue) round-trips through its entry ID")
            expect(
                WindowCommandCatalog.command(id: command.id) == command,
                "\(command.id.rawValue) round-trips through its ID")
            expect(
                command.entryID.hasPrefix("window-command:"),
                "\(command.id.rawValue) is namespaced")
        }
        expect(
            WindowCommandCatalog.command(forEntryID: "window-command:unknown") == nil,
            "unknown entry IDs are rejected")
        expect(
            WindowCommandCatalog.command(forEntryID: "system-action:sleep") == nil,
            "system-action entry IDs are not claimed")

        let cycling = Set(commands.filter(\.cyclesOnRepeat).map(\.id))
        expect(cycling == [.leftHalf, .rightHalf], "only the two halves cycle on repeat")
        let moveOnly = Set(commands.filter { !$0.resizes }.map(\.id))
        expect(
            moveOnly == [.moveLeft, .moveRight, .moveUp, .moveDown],
            "only the four moves leave the size alone")

        // Grouping drives the Settings list; every command must land in exactly one group.
        let grouped = WindowCommandCatalog.grouped()
        expect(
            grouped.flatMap(\.commands).count == commands.count, "grouping loses no command")
        expect(
            grouped.map(\.group) == WindowCommand.Group.allCases,
            "every group is represented, in declaration order")
        expect(grouped.first { $0.group == .halves }?.commands.count == 2, "two halves")
        expect(grouped.first { $0.group == .quarters }?.commands.count == 4, "four quarters")
        expect(grouped.first { $0.group == .fourths }?.commands.count == 3, "three fourths commands")
        expect(grouped.first { $0.group == .sizing }?.commands.count == 2, "two sizing commands")
        expect(grouped.first { $0.group == .moving }?.commands.count == 4, "four moving commands")
    }

    // MARK: - Convention lock

    static func testConventionLock() {
        // AX space: +Y points down, so a top quarter starts at the usable frame's minY.
        expect(
            frame(.topLeftQuarter)?.minY == mainScreen.usableFrame.minY,
            "top left quarter is anchored at usableFrame.minY (AX space, +Y down)")
        expect(
            frame(.bottomLeftQuarter)?.maxY == mainScreen.usableFrame.maxY,
            "bottom left quarter is anchored at usableFrame.maxY")
    }

    // MARK: - Tiling

    static func testTiling() {
        expectRect(frame(.leftHalf)!, CGRect(x: 0, y: 0, width: 720, height: 900), "left half")
        expectRect(frame(.rightHalf)!, CGRect(x: 720, y: 0, width: 720, height: 900), "right half")

        expectRect(
            frame(.topLeftQuarter)!, CGRect(x: 0, y: 0, width: 720, height: 450), "top left quarter")
        expectRect(
            frame(.topRightQuarter)!, CGRect(x: 720, y: 0, width: 720, height: 450),
            "top right quarter")
        expectRect(
            frame(.bottomLeftQuarter)!, CGRect(x: 0, y: 450, width: 720, height: 450),
            "bottom left quarter")
        expectRect(
            frame(.bottomRightQuarter)!, CGRect(x: 720, y: 450, width: 720, height: 450),
            "bottom right quarter")

        let quarters = [
            frame(.topLeftQuarter)!, frame(.topRightQuarter)!, frame(.bottomLeftQuarter)!,
            frame(.bottomRightQuarter)!
        ]
        expect(
            quarters.reduce(CGRect.null) { $0.union($1) } == mainScreen.usableFrame,
            "the four quarters union to the visible frame")
        var overlapping = false
        for i in quarters.indices {
            for j in quarters.indices where j > i {
                if !quarters[i].intersection(quarters[j]).isEmpty { overlapping = true }
            }
        }
        expect(!overlapping, "quarters never overlap")

        expectRect(
            frame(.firstThreeFourths)!, CGRect(x: 0, y: 0, width: 1080, height: 900),
            "first three fourths")
        expectRect(
            frame(.lastThreeFourths)!, CGRect(x: 360, y: 0, width: 1080, height: 900),
            "last three fourths")
        expect(
            frame(.firstThreeFourths)!.union(frame(.lastThreeFourths)!) == mainScreen.usableFrame,
            "the two three-fourths cover the screen between them")
        expect(
            frame(.firstThreeFourths)!.intersection(frame(.lastThreeFourths)!)
                == CGRect(x: 360, y: 0, width: 720, height: 900),
            "they overlap on exactly the centre half, so all three share the quarter grid")

        // Size cycling: the two halves only, ½ → ⅓ → ⅔, wrapping.
        let firstThird = CGRect(x: 0, y: 0, width: 480, height: 900)
        let firstTwoThirds = CGRect(x: 0, y: 0, width: 960, height: 900)
        expectRect(
            frame(.leftHalf, step: 1, cycle: .sizes)!, firstThird, "left half step 1 is a third")
        expectRect(
            frame(.leftHalf, step: 2, cycle: .sizes)!, firstTwoThirds,
            "left half step 2 is two thirds")
        expectRect(
            frame(.leftHalf, step: 3, cycle: .sizes)!, frame(.leftHalf)!,
            "left half step 3 wraps to the half")
        expectRect(
            frame(.rightHalf, step: 1, cycle: .sizes)!,
            CGRect(x: 960, y: 0, width: 480, height: 900), "right half step 1 is a third")
        expectRect(
            frame(.rightHalf, step: 2, cycle: .sizes)!,
            CGRect(x: 480, y: 0, width: 960, height: 900), "right half step 2 is two thirds")

        // A step handed to a command that doesn't cycle must be ignored outright.
        for step in 0...5 {
            expectRect(
                frame(.firstThreeFourths, step: step, cycle: .sizes)!, frame(.firstThreeFourths)!,
                "non-cycling commands ignore step \(step)")
            expectRect(
                frame(.maximize, step: step, cycle: .sizes)!, frame(.maximize)!,
                "maximize ignores step \(step)")
            expectRect(
                frame(.leftHalf, step: step)!, frame(.leftHalf)!,
                "cycling switched off ignores step \(step)")
        }
        // Negative steps can't crash or escape the cycle.
        expectRect(
            frame(.leftHalf, step: -1, cycle: .sizes)!, firstTwoThirds, "negative steps normalize")
    }

    // MARK: - Non-divisible widths

    static func testNonDivisible() {
        // 1366 is the tie case for fourths: a quarter of it lands exactly on .5.
        for width in [1441, 1000, 1367, 1366] as [CGFloat] {
            let screen = WindowPlacementEngine.Screen(
                id: 9, frame: CGRect(x: 0, y: 0, width: width, height: 901),
                usableFrame: CGRect(x: 0, y: 0, width: width, height: 901))
            let third = frame(.leftHalf, on: screen, step: 1, cycle: .sizes)!
            let twoThirds = frame(.rightHalf, on: screen, step: 2, cycle: .sizes)!
            expect(third.maxX == twoThirds.minX, "\(width): a third and two thirds share an edge exactly")
            expect(
                third.union(twoThirds) == screen.usableFrame,
                "\(width): a third and two thirds still cover the whole screen")

            let left = frame(.leftHalf, on: screen)!
            let right = frame(.rightHalf, on: screen)!
            expect(left.maxX == right.minX, "\(width): halves share an edge exactly")
            expect(left.union(right) == screen.usableFrame, "\(width): halves cover the screen")
            expect(abs(left.width - right.width) <= 1, "\(width): halves differ by at most a point")

            let firstFourths = frame(.firstThreeFourths, on: screen)!
            let lastFourths = frame(.lastThreeFourths, on: screen)!
            expect(
                abs(firstFourths.width - lastFourths.width) <= 1,
                "\(width): the two three-fourths differ by at most a point")
            expect(
                abs(firstFourths.width - width * 0.75) <= 1,
                "\(width): three fourths is three quarters of the screen")
            expect(
                firstFourths.union(lastFourths) == screen.usableFrame,
                "\(width): the two three-fourths still cover the screen")
        }
    }

    // MARK: - Off-origin displays

    static func testOffOriginScreens() {
        // A display up and to the right of the primary — negative Y in AX space.
        let high = WindowPlacementEngine.Screen(
            id: 2, frame: CGRect(x: 1920, y: -300, width: 2560, height: 1440),
            usableFrame: CGRect(x: 1920, y: -300, width: 2560, height: 1440))
        expectRect(
            frame(.leftHalf, on: high, window: CGRect(x: 2000, y: 0, width: 400, height: 300))!,
            CGRect(x: 1920, y: -300, width: 1280, height: 1440), "left half on an off-origin display")
        expect(
            frame(.topLeftQuarter, on: high, window: CGRect(x: 2000, y: 0, width: 400, height: 300))!
                .minY == -300, "top left quarter honours a negative minY")

        // A display left of and below the primary.
        let low = WindowPlacementEngine.Screen(
            id: 3, frame: CGRect(x: -1440, y: 200, width: 1440, height: 900),
            usableFrame: CGRect(x: -1440, y: 200, width: 1440, height: 900))
        expectRect(
            frame(.rightHalf, on: low, window: CGRect(x: -1000, y: 300, width: 400, height: 300))!,
            CGRect(x: -720, y: 200, width: 720, height: 900), "right half on a negative-X display")
        expectRect(
            frame(.maximize, on: low, window: CGRect(x: -1000, y: 300, width: 400, height: 300))!,
            low.usableFrame, "maximize on a negative-X display")

        // A usable frame smaller than the full frame, with the menu bar reserved.
        let reserved = WindowPlacementEngine.Screen(
            id: 4, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            usableFrame: CGRect(x: 0, y: 25, width: 1440, height: 800))
        expectRect(
            frame(.topLeftQuarter, on: reserved)!, CGRect(x: 0, y: 25, width: 720, height: 400),
            "tiles respect a reserved usable frame")
        expectRect(
            frame(.maximize, on: reserved)!, reserved.usableFrame, "maximize never covers the menu bar")
    }

    // MARK: - Gaps

    static func testGaps() {
        expectRect(
            frame(.leftHalf, gap: 10)!, CGRect(x: 10, y: 10, width: 705, height: 880),
            "left half with a 10pt gap")
        expectRect(
            frame(.rightHalf, gap: 10)!, CGRect(x: 725, y: 10, width: 705, height: 880),
            "right half with a 10pt gap")
        expect(
            frame(.leftHalf, gap: 10)!.maxX + 10 == frame(.rightHalf, gap: 10)!.minX,
            "the gutter between halves is exactly the gap")

        // Every outer edge is inset by the full gap, every gutter is exactly one gap.
        let quarters = [
            frame(.topLeftQuarter, gap: 10)!, frame(.topRightQuarter, gap: 10)!,
            frame(.bottomLeftQuarter, gap: 10)!, frame(.bottomRightQuarter, gap: 10)!
        ]
        expect(quarters[0].maxX + 10 == quarters[1].minX, "quarters: vertical gutter is the gap")
        expect(quarters[0].maxY + 10 == quarters[2].minY, "quarters: horizontal gutter is the gap")
        expect(
            quarters.allSatisfy {
                $0.minX >= 10 && $0.minY >= 10 && $0.maxX <= 1430 && $0.maxY <= 890
            }, "quarters stay inset from every screen edge")

        // Fourths: the outer edge takes the full gap, the interior one half of it.
        expectRect(
            frame(.firstThreeFourths, gap: 10)!, CGRect(x: 10, y: 10, width: 1065, height: 880),
            "first three fourths with a 10pt gap")
        expectRect(
            frame(.lastThreeFourths, gap: 10)!, CGRect(x: 365, y: 10, width: 1065, height: 880),
            "last three fourths with a 10pt gap")

        // A third's fractional boundary still leaves an exact gutter.
        expect(
            frame(.leftHalf, gap: 10, step: 1, cycle: .sizes)!.maxX + 10
                == frame(.rightHalf, gap: 10, step: 2, cycle: .sizes)!.minX,
            "a cycled third and two thirds leave an exact gutter")

        // An odd gap must not drift when halved and rounded.
        expect(
            frame(.leftHalf, gap: 9)!.maxX + 9 == frame(.rightHalf, gap: 9)!.minX,
            "an odd gap still produces an exact gutter")

        expectRect(
            frame(.maximize, gap: 12)!, CGRect(x: 12, y: 12, width: 1416, height: 876),
            "maximize honours the gap")

        // Degenerate gaps must never produce an unusable window.
        for gap in [-5, 0, 10_000] as [CGFloat] {
            let rect = frame(.leftHalf, gap: gap)!
            expect(rect.width > 0 && rect.height > 0, "gap \(gap) still yields a positive tile")
            expect(
                mainScreen.usableFrame.contains(rect), "gap \(gap) keeps the tile on screen")
        }
        expectRect(frame(.leftHalf, gap: -5)!, frame(.leftHalf)!, "a negative gap reads as zero")
        // Every non-finite value reads as zero, so NaN and infinity behave alike.
        expectRect(frame(.leftHalf, gap: .nan)!, frame(.leftHalf)!, "a NaN gap reads as zero")
        expectRect(
            frame(.leftHalf, gap: .infinity)!, frame(.leftHalf)!, "an infinite gap reads as zero")
        // A merely oversized (but finite) gap is capped rather than zeroed.
        expectRect(
            frame(.leftHalf, gap: 10_000)!, frame(.leftHalf, gap: 90)!,
            "an oversized finite gap is capped to a tenth of the smaller dimension")
    }

    // MARK: - Sizing

    static func testSizing() {
        expectRect(frame(.maximize)!, mainScreen.usableFrame, "maximize fills the usable frame")

        let window = CGRect(x: 100, y: 200, width: 300, height: 400)
        expectRect(
            frame(.center, window: window)!, CGRect(x: 570, y: 200, width: 300, height: 400),
            "center preserves the size and vertical position and centres it horizontally")
        expectRect(
            frame(.center, window: frame(.center, window: window)!)!,
            frame(.center, window: window)!, "center is idempotent")

        // A window larger than the screen must be clamped down, not centred off-screen.
        let huge = CGRect(x: -500, y: -500, width: 3000, height: 2000)
        let centred = frame(.center, window: huge)!
        expect(
            centred.width <= 1440 && centred.height <= 900, "center clamps an oversized window")
        expect(mainScreen.usableFrame.contains(centred), "a clamped center stays on screen")
    }

    // MARK: - Moves

    static func testMoves() {
        let start = CGRect(x: 300, y: 300, width: 600, height: 400)
        expectRect(
            frame(.moveLeft, window: start)!, CGRect(x: 0, y: 300, width: 600, height: 400),
            "move left pushes flush left and keeps the vertical position")
        expectRect(
            frame(.moveRight, window: start)!, CGRect(x: 840, y: 300, width: 600, height: 400),
            "move right pushes flush right and keeps the vertical position")
        expectRect(
            frame(.moveUp, window: start)!, CGRect(x: 300, y: 0, width: 600, height: 400),
            "move up pushes flush to the top and keeps the horizontal position")
        expectRect(
            frame(.moveDown, window: start)!, CGRect(x: 300, y: 500, width: 600, height: 400),
            "move down pushes flush to the bottom and keeps the horizontal position")

        // A window wider than the canvas pins its leading edge rather than sliding off.
        let overWide = CGRect(x: 100, y: 100, width: 2000, height: 400)
        expectRect(
            frame(.moveRight, window: overWide)!, CGRect(x: 0, y: 100, width: 2000, height: 400),
            "an oversized window pins to the leading edge without resizing")
    }

    // MARK: - Screens

    static func testScreens() {
        let right = WindowPlacementEngine.Screen(
            id: 2, frame: CGRect(x: 1440, y: 0, width: 2560, height: 1440),
            usableFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1440))
        // Deliberately out of order, to prove the ordering is derived and not inherited.
        let both = screens(right, mainScreen)
        expect(WindowPlacementEngine.ordered(both).map(\.id) == [1, 2], "displays order left-to-right")

        // Screen resolution by overlap.
        expect(
            WindowPlacementEngine.screen(
                containing: CGRect(x: 1150, y: 0, width: 500, height: 100), in: both)?.id == 1,
            "a straddling window belongs to the display showing more of it")
        expect(
            WindowPlacementEngine.screen(
                containing: CGRect(x: 1300, y: 0, width: 500, height: 100), in: both)?.id == 2,
            "the overlap majority flips with the window")
        expect(
            WindowPlacementEngine.screen(
                containing: CGRect(x: -5000, y: -5000, width: 100, height: 100), in: both) != nil,
            "a window off every display still resolves to one")
    }

    // MARK: - Cycling across displays

    static func testDisplayCycle() {
        let left = mainScreen
        let right = WindowPlacementEngine.Screen(
            id: 2, frame: CGRect(x: 1440, y: 0, width: 1440, height: 900),
            usableFrame: CGRect(x: 1440, y: 0, width: 1440, height: 900))
        let both = screens(right, left)
        let onLeft = CGRect(x: 100, y: 100, width: 600, height: 400)

        // The strip is two half-slots per display, so the length is a plain product.
        expect(length(.leftHalf, .off, both) == 1, "cycling off is a length of one")
        expect(length(.leftHalf, .sizes, both) == 3, "the size cycle is three steps")
        expect(length(.leftHalf, .displays, both) == 4, "two displays give four slots")
        expect(length(.maximize, .displays, both) == 1, "a non-cycling command never cycles")
        expect(
            length(.leftHalf, .displays) == 1,
            "one display makes the display leg a no-op")

        // The sequence the issue asks for: Left walks the strip backwards, wrapping.
        let expected: [CGRect] = [
            frame(.leftHalf, on: left)!, frame(.rightHalf, on: right)!,
            frame(.leftHalf, on: right)!, frame(.rightHalf, on: left)!
        ]
        for (step, want) in expected.enumerated() {
            expectRect(
                frame(.leftHalf, window: onLeft, step: step, cycle: .displays, allScreens: both)!,
                want, "left half display step \(step)")
        }
        expectRect(
            frame(.leftHalf, window: onLeft, step: 4, cycle: .displays, allScreens: both)!,
            expected[0], "the display cycle wraps")
        expectRect(
            frame(.leftHalf, window: onLeft, step: -1, cycle: .displays, allScreens: both)!,
            expected[3], "a negative display step normalises")

        // Right is the exact mirror, so the two shortcuts sweep the strip in opposite directions.
        for (step, want) in [
            frame(.rightHalf, on: left)!, frame(.leftHalf, on: right)!,
            frame(.rightHalf, on: right)!, frame(.leftHalf, on: left)!
        ].enumerated() {
            expectRect(
                frame(.rightHalf, window: onLeft, step: step, cycle: .displays, allScreens: both)!,
                want, "right half display step \(step)")
        }

        // The size cycle stays on the host display, whatever else is plugged in.
        for step in 0..<3 {
            expectRect(
                frame(.leftHalf, window: onLeft, step: step, cycle: .sizes, allScreens: both)!,
                frame(.leftHalf, on: left, step: step, cycle: .sizes)!,
                "the size cycle ignores the other display at step \(step)")
        }

        // Real presses: from the second one on, the window sits on a display it was just moved to.
        let onRight = CGRect(x: 1540, y: 100, width: 600, height: 400)
        let walked = presses(.leftHalf, 5, from: onRight, on: both).map(\.frame)
        let walk: [CGRect] = [
            frame(.leftHalf, on: right)!, frame(.rightHalf, on: left)!,
            frame(.leftHalf, on: left)!, frame(.rightHalf, on: right)!,
            frame(.leftHalf, on: right)!
        ]
        for (press, want) in walk.enumerated() {
            expectRect(walked[press], want, "left half from the right display, press \(press + 1)")
        }

        // An origin that is no longer plugged in falls back to the window's own display.
        expectRect(
            WindowPlacementEngine.placement(
                for: WindowPlacementEngine.Input(
                    command: .leftHalf, windowFrame: onLeft, screens: both, step: 1,
                    cycle: .displays, originScreenID: 99))!.frame,
            expected[1], "an unplugged origin counts from the host")

        // One full lap of real presses visits every slot exactly once, from either starting display.
        for start in [onLeft, onRight] {
            for command in [WindowCommand.ID.leftHalf, .rightHalf] {
                let lap = presses(command, length(command, .displays, both), from: start, on: both)
                expect(
                    Set(lap.map(\.frame)).count == lap.count,
                    "\(command.rawValue) visits four distinct slots")
                expect(
                    Set(lap.map(\.screenID)) == [1, 2],
                    "\(command.rawValue) reaches both displays")
            }
        }

        // The gap belongs to the destination, not to the display the window started on.
        let narrow = WindowPlacementEngine.Screen(
            id: 3, frame: CGRect(x: 1440, y: 0, width: 200, height: 900),
            usableFrame: CGRect(x: 1440, y: 0, width: 200, height: 900))
        expectRect(
            frame(
                .leftHalf, window: onLeft, gap: 100, step: 2, cycle: .displays,
                allScreens: screens(left, narrow))!,
            frame(.leftHalf, on: narrow, gap: 100)!,
            "the destination display sanitises the gap")

        // No mode ever gives a non-cycling command a chain to walk.
        for command in WindowCommand.ID.allCases
        where !WindowCommandCatalog.cyclesOnRepeat.contains(command) {
            for cycle in WindowCycle.allCases {
                expect(
                    length(command, cycle, both) == 1,
                    "\(command.rawValue) has no cycle to walk under \(cycle.rawValue)")
            }
        }
    }

    // MARK: - Action memory

    static func testMemory() {
        let clock = Date(timeIntervalSince1970: 1_000_000)
        let half = CGRect(x: 0, y: 0, width: 720, height: 900)
        let original = CGRect(x: 100, y: 100, width: 600, height: 400)

        // A fresh window starts its chain at step 0 on its own display.
        var memory = WindowActionMemory<Int>()
        var decision = memory.decide(
            key: 1, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleLength: 3, now: clock)
        expect(decision.step == 0, "a first press starts at step 0")
        expect(decision.originScreenID == 1, "a first press starts its chain on its own display")
        memory.commit(
            key: 1, command: .leftHalf, decision: decision, appliedFrame: half, screenID: 1,
            now: clock)

        // Repeats advance the cycle.
        for expected in [1, 2, 0, 1] {
            let applied = frame(.leftHalf, step: expected)!
            decision = memory.decide(
                key: 1, command: .leftHalf, currentFrame: memory.record(for: 1)!.appliedFrame,
                currentScreenID: 1, cycleLength: 3, now: clock)
            expect(decision.step == expected, "the cycle advances to step \(expected)")
            memory.commit(
                key: 1, command: .leftHalf, decision: decision, appliedFrame: applied, screenID: 1,
                now: clock)
        }

        // A different command, screen, or window resets the cycle.
        decision = memory.decide(
            key: 1, command: .rightHalf, currentFrame: memory.record(for: 1)!.appliedFrame,
            currentScreenID: 1, cycleLength: 3, now: clock)
        expect(decision.step == 0, "a different command restarts the cycle")
        decision = memory.decide(
            key: 1, command: .leftHalf, currentFrame: memory.record(for: 1)!.appliedFrame,
            currentScreenID: 2, cycleLength: 3, now: clock)
        expect(decision.step == 0, "a different display restarts the cycle")
        expect(decision.originScreenID == 2, "a restarted chain starts on the current display")
        decision = memory.decide(
            key: 99, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleLength: 3, now: clock)
        expect(decision.step == 0, "another window has its own chain")

        // A chain the display cycle carried elsewhere keeps counting from where it started.
        var crossing = WindowActionMemory<Int>()
        let crossingSeed = crossing.decide(
            key: 1, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleLength: 4, now: clock)
        crossing.commit(
            key: 1, command: .leftHalf, decision: crossingSeed, appliedFrame: half, screenID: 2,
            now: clock)
        decision = crossing.decide(
            key: 1, command: .leftHalf, currentFrame: half, currentScreenID: 2, cycleLength: 4,
            now: clock)
        expect(decision.step == 1, "a press on the display the chain landed on continues it")
        expect(decision.originScreenID == 1, "a continued chain keeps its origin display")

        // A user drag resets the cycle.
        var dragged = WindowActionMemory<Int>()
        let seed = dragged.decide(
            key: 1, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleLength: 3, now: clock)
        dragged.commit(
            key: 1, command: .leftHalf, decision: seed, appliedFrame: half, screenID: 1, now: clock)
        let movedByUser = CGRect(x: 400, y: 400, width: 500, height: 300)
        decision = dragged.decide(
            key: 1, command: .leftHalf, currentFrame: movedByUser, currentScreenID: 1,
            cycleLength: 3, now: clock)
        expect(decision.step == 0, "a user drag restarts the cycle")

        // A quantising app that lands a point off its target must NOT read as a user drag.
        let quantised = CGRect(x: half.minX + 1, y: half.minY, width: half.width - 1, height: half.height)
        decision = dragged.decide(
            key: 1, command: .leftHalf, currentFrame: quantised, currentScreenID: 1,
            cycleLength: 3, now: clock)
        expect(decision.step == 1, "a sub-tolerance difference keeps the cycle running")

        // The cycle switch pins everything to step 0.
        var pinned = WindowActionMemory<Int>()
        var pinnedDecision = pinned.decide(
            key: 1, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleLength: 1, now: clock)
        for _ in 0..<5 {
            pinned.commit(
                key: 1, command: .leftHalf, decision: pinnedDecision, appliedFrame: half,
                screenID: 1, now: clock)
            pinnedDecision = pinned.decide(
                key: 1, command: .leftHalf, currentFrame: half, currentScreenID: 1,
                cycleLength: 1, now: clock)
            expect(pinnedDecision.step == 0, "cycling off pins every repeat to step 0")
        }

        // A non-cycling command never advances even with cycling on.
        var nonCycling = WindowActionMemory<Int>()
        let maximized = mainScreen.usableFrame
        var nonDecision = nonCycling.decide(
            key: 1, command: .maximize, currentFrame: original, currentScreenID: 1,
            cycleLength: length(.maximize, .sizes), now: clock)
        for _ in 0..<5 {
            nonCycling.commit(
                key: 1, command: .maximize, decision: nonDecision, appliedFrame: maximized,
                screenID: 1, now: clock)
            nonDecision = nonCycling.decide(
                key: 1, command: .maximize, currentFrame: maximized, currentScreenID: 1,
                cycleLength: length(.maximize, .sizes), now: clock)
            expect(nonDecision.step == 0, "a non-cycling command never advances")
        }

        var timed = WindowActionMemory<Int>(cycleTimeout: 60)
        let timedSeed = timed.decide(
            key: 1, command: .leftHalf, currentFrame: original, currentScreenID: 1,
            cycleLength: 3, now: clock)
        timed.commit(
            key: 1, command: .leftHalf, decision: timedSeed, appliedFrame: half, screenID: 1,
            now: clock)
        expect(
            timed.decide(
                key: 1, command: .leftHalf, currentFrame: half, currentScreenID: 1,
                cycleLength: 3, now: clock.addingTimeInterval(30)
            ).step == 1, "a cycle inside the timeout continues")
        expect(
            timed.decide(
                key: 1, command: .leftHalf, currentFrame: half, currentScreenID: 1,
                cycleLength: 3, now: clock.addingTimeInterval(120)
            ).step == 0, "a cycle past the timeout restarts")

        // Bounded growth, most-recently-used retained.
        var bounded = WindowActionMemory<Int>(capacity: 64)
        for key in 0..<100 {
            let boundedDecision = bounded.decide(
                key: key, command: .leftHalf, currentFrame: original, currentScreenID: 1,
                cycleLength: 3, now: clock)
            bounded.commit(
                key: key, command: .leftHalf, decision: boundedDecision, appliedFrame: half,
                screenID: 1, now: clock)
        }
        expect(bounded.count == 64, "the memory is bounded at its capacity")
        expect(bounded.record(for: 99) != nil, "the most recent key survives eviction")
        expect(bounded.record(for: 0) == nil, "the oldest key is evicted")
        expect(bounded.record(for: 36) != nil, "the 64 most recent keys survive")

        bounded.forget { $0 % 2 == 0 }
        expect(bounded.record(for: 99) != nil, "forget(where:) keeps non-matching keys")
        expect(bounded.record(for: 98) == nil, "forget(where:) drops matching keys")
        bounded.forget(key: 99)
        expect(bounded.record(for: 99) == nil, "forget(key:) drops that key")
    }

    // MARK: - Fuzz

    static func testFuzz() {
        let displays: [[WindowPlacementEngine.Screen]] = [
            [mainScreen],
            [
                mainScreen,
                WindowPlacementEngine.Screen(
                    id: 2, frame: CGRect(x: 1440, y: -200, width: 2560, height: 1440),
                    usableFrame: CGRect(x: 1440, y: -175, width: 2560, height: 1390))
            ],
            [
                WindowPlacementEngine.Screen(
                    id: 5, frame: CGRect(x: 0, y: 0, width: 1024, height: 640),
                    usableFrame: CGRect(x: 0, y: 25, width: 1024, height: 590)),
                WindowPlacementEngine.Screen(
                    id: 6, frame: CGRect(x: -3840, y: 0, width: 3840, height: 2160),
                    usableFrame: CGRect(x: -3840, y: 25, width: 3840, height: 2060))
            ]
        ]
        let windows: [CGRect] = [
            CGRect(x: 100, y: 100, width: 600, height: 400),
            CGRect(x: 0, y: 0, width: 0, height: 0),
            CGRect(x: -900, y: -900, width: 200, height: 150),
            CGRect(x: 200, y: 200, width: 5000, height: 4000),
            CGRect(x: 1439, y: 899, width: 1, height: 1)
        ]
        let gaps: [CGFloat] = [0, 1, 8, 25, 200]
        let cycles: [WindowCycle] = WindowCycle.allCases
        let steps = [0, 1, 5, -3]

        var checked = 0
        var problems: [String] = []
        for screens in displays {
            for window in windows {
                for gap in gaps {
                    for cycle in cycles {
                        for step in steps {
                            for command in WindowCommand.ID.allCases {
                                let input = WindowPlacementEngine.Input(
                                    command: command, windowFrame: window, screens: screens, gap: gap,
                                    step: step, cycle: cycle)
                                // A nil placement is a legitimate quiet no-op, not a failure.
                                guard let placement = WindowPlacementEngine.placement(for: input) else {
                                    continue
                                }
                                checked += 1
                                let rect = placement.frame
                                let label = "\(command.rawValue) gap \(gap) step \(step) window \(window)"

                                if !(rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite
                                    && rect.height.isFinite)
                                {
                                    problems.append("non-finite frame: \(label)")
                                }
                                if rect.width < 0 || rect.height < 0 {
                                    problems.append("negative size: \(label)")
                                }
                                guard let host = screens.first(where: { $0.id == placement.screenID })
                                else {
                                    problems.append("unknown screen id: \(label)")
                                    continue
                                }
                                if rect.intersection(host.usableFrame).isNull {
                                    problems.append("off-screen frame: \(label)")
                                }
                                // Determinism, and no drift when a command is applied twice at step 0.
                                if WindowPlacementEngine.placement(for: input)?.frame != rect {
                                    problems.append("non-deterministic: \(label)")
                                }
                                var repeated = input
                                repeated.windowFrame = rect
                                // Only step 0 is meant to be idempotent: a cycle exists to move the window.
                                if step == 0,
                                    let again = WindowPlacementEngine.placement(for: repeated)?.frame,
                                    command != .moveLeft, command != .moveRight, command != .moveUp,
                                    command != .moveDown,
                                    again != rect
                                {
                                    problems.append("drifts on repeat: \(label) — \(rect) then \(again)")
                                }
                            }
                        }
                    }
                }
            }
        }
        expect(checked > 1000, "the fuzz sweep exercised a meaningful number of placements")
        expect(problems.isEmpty, "fuzz sweep found no violations")
        for problem in problems.prefix(10) { print("      \(problem)") }
    }
}
