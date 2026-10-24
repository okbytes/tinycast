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

    /// The reference display: origin at the AX origin, evenly divisible by halves and quarters.
    static let mainScreen = WindowPlacementEngine.Screen(
        id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        usableFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))

    static func screens(_ list: WindowPlacementEngine.Screen...) -> [WindowPlacementEngine.Screen] { list }

    static func preferences(
        half: WindowCommand.HalfSide = .left, quarter: WindowCommand.QuarterCorner = .topLeft,
        centerWidth: Int = 75
    ) -> WindowPlacementEngine.Preferences {
        WindowPlacementEngine.Preferences(
            halfStart: half, quarterStart: quarter, centerWidth: centerWidth)
    }

    static func placement(
        _ command: WindowCommand.ID, on screen: WindowPlacementEngine.Screen = mainScreen,
        window: CGRect = CGRect(x: 100, y: 100, width: 600, height: 400), step: Int = 0,
        centerWidth: Int = 75
    ) -> WindowPlacementEngine.Placement? {
        WindowPlacementEngine.placement(
            for: WindowPlacementEngine.Input(
                command: command, windowFrame: window, screens: [screen], step: step,
                centerWidth: centerWidth))
    }

    static func frame(
        _ command: WindowCommand.ID, on screen: WindowPlacementEngine.Screen = mainScreen,
        window: CGRect = CGRect(x: 100, y: 100, width: 600, height: 400), step: Int = 0,
        centerWidth: Int = 75
    ) -> CGRect? {
        placement(command, on: screen, window: window, step: step, centerWidth: centerWidth)?.frame
    }

    static func quarter(_ corner: WindowCommand.QuarterCorner) -> CGRect {
        frame(.quarter, step: WindowCommand.QuarterCorner.cycle.firstIndex(of: corner)!)!
    }

    static func half(_ side: WindowCommand.HalfSide) -> CGRect {
        frame(.half, step: WindowCommand.HalfSide.cycle.firstIndex(of: side)!)!
    }

    /// Presses `command` like `WindowMover`; `land` stands in for an app that bends the frame asked for.
    static func presses(
        _ command: WindowCommand.ID, _ count: Int, from window: CGRect,
        preferences: WindowPlacementEngine.Preferences = .standard,
        land: (CGRect) -> CGRect = { $0 }, memory: inout WindowActionMemory<Int>
    ) -> [CGRect] {
        let clock = Date(timeIntervalSince1970: 1_000_000)
        let length = WindowCommandCatalog.cycleLength(for: command)
        var current = window
        var landed: [CGRect] = []
        for _ in 0..<count {
            let continued = memory.decide(
                key: 1, command: command, currentFrame: current, currentScreenID: mainScreen.id,
                cycleLength: length, now: clock)
            var step =
                continued ?? WindowPlacementEngine.firstStep(for: command, preferences: preferences)
            var landing = land(
                frame(command, window: current, step: step, centerWidth: preferences.centerWidth)!)
            if continued == nil, length > 1,
                landing.approximatelyEquals(current, tolerance: WindowActionMemory<Int>.tolerance)
            {
                step = (step + 1) % length
                landing = land(
                    frame(command, window: landing, step: step, centerWidth: preferences.centerWidth)!)
            }
            memory.commit(
                key: 1, command: command, step: step, appliedFrame: landing,
                screenID: mainScreen.id, now: clock)
            current = landing
            landed.append(landing)
        }
        return landed
    }

    static func presses(
        _ command: WindowCommand.ID, _ count: Int, from window: CGRect,
        preferences: WindowPlacementEngine.Preferences = .standard,
        land: (CGRect) -> CGRect = { $0 }
    ) -> [CGRect] {
        var memory = WindowActionMemory<Int>()
        return presses(
            command, count, from: window, preferences: preferences, land: land, memory: &memory)
    }

    static func main() {
        testCatalog()
        testConventionLock()
        testTiling()
        testNonDivisible()
        testOffOriginScreens()
        testSizing()
        testMoves()
        testScreens()
        testCycling()
        testMemory()
        testFuzz()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Catalog

    static func testCatalog() {
        let commands = WindowCommandCatalog.all
        expect(commands.count == 8, "catalog contains all 8 agreed commands")
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

        let cycling = Dictionary(
            uniqueKeysWithValues: WindowCommand.ID.allCases.compactMap { id in
                let length = WindowCommandCatalog.cycleLength(for: id)
                return length > 1 ? (id, length) : nil
            })
        expect(cycling == [.half: 2, .quarter: 4], "Half cycles two sides, Quarter four corners")
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
        expect(grouped.first { $0.group == .sizing }?.commands.count == 4, "four sizing commands")
        expect(grouped.first { $0.group == .moving }?.commands.count == 4, "four moving commands")

        expect(
            Set(WindowCommand.QuarterCorner.cycle) == Set(WindowCommand.QuarterCorner.allCases)
                && WindowCommand.QuarterCorner.cycle.count == WindowCommand.QuarterCorner.allCases.count,
            "Quarter's cycle visits every corner once")
        expect(
            Set(WindowCommand.HalfSide.cycle) == Set(WindowCommand.HalfSide.allCases)
                && WindowCommand.HalfSide.cycle.count == WindowCommand.HalfSide.allCases.count,
            "Half's cycle visits every side once")
    }

    // MARK: - Convention lock

    static func testConventionLock() {
        // AX space: +Y points down, so a top quarter starts at the usable frame's minY.
        expect(
            quarter(.topLeft).minY == mainScreen.usableFrame.minY,
            "top left quarter is anchored at usableFrame.minY (AX space, +Y down)")
        expect(
            quarter(.bottomLeft).maxY == mainScreen.usableFrame.maxY,
            "bottom left quarter is anchored at usableFrame.maxY")
    }

    // MARK: - Tiling

    static func testTiling() {
        expectRect(half(.left), CGRect(x: 0, y: 0, width: 720, height: 900), "left half")
        expectRect(half(.right), CGRect(x: 720, y: 0, width: 720, height: 900), "right half")
        expectRect(frame(.half)!, half(.left), "Half starts on the left by default")

        expectRect(
            quarter(.topLeft), CGRect(x: 0, y: 0, width: 720, height: 450), "top left quarter")
        expectRect(
            quarter(.topRight), CGRect(x: 720, y: 0, width: 720, height: 450), "top right quarter")
        expectRect(
            quarter(.bottomLeft), CGRect(x: 0, y: 450, width: 720, height: 450),
            "bottom left quarter")
        expectRect(
            quarter(.bottomRight), CGRect(x: 720, y: 450, width: 720, height: 450),
            "bottom right quarter")
        expectRect(frame(.quarter)!, quarter(.topLeft), "Quarter starts top left by default")

        let quarters = WindowCommand.QuarterCorner.allCases.map(quarter)
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

        // A step is a slot in the cycle, whatever Settings says to start on.
        expectRect(frame(.half, step: 1)!, half(.right), "half step 1 is the right half")
        expectRect(frame(.half, step: 2)!, half(.left), "half step 2 wraps to the left half")
        expectRect(frame(.half, step: -1)!, half(.right), "a negative half step normalizes")
        let corners = WindowCommand.QuarterCorner.cycle
        for step in 0..<6 {
            expectRect(
                frame(.quarter, step: step)!, quarter(corners[step % corners.count]),
                "quarter step \(step) is \(corners[step % corners.count])")
        }
        expect(
            corners == [.topLeft, .topRight, .bottomRight, .bottomLeft],
            "Quarter's cycle runs clockwise")

        // The starting position names the first slot and nothing else.
        for side in WindowCommand.HalfSide.allCases {
            let first = WindowPlacementEngine.firstStep(for: .half, preferences: preferences(half: side))
            expectRect(frame(.half, step: first)!, half(side), "Half starting \(side) lands \(side)")
        }
        for corner in WindowCommand.QuarterCorner.allCases {
            let first = WindowPlacementEngine.firstStep(
                for: .quarter, preferences: preferences(quarter: corner))
            expectRect(
                frame(.quarter, step: first)!, quarter(corner), "Quarter starting \(corner) lands there")
        }
        for command in WindowCommand.ID.allCases where WindowCommandCatalog.cycleLength(for: command) == 1 {
            expect(
                WindowPlacementEngine.firstStep(for: command, preferences: .standard) == 0,
                "\(command.rawValue) starts at slot 0")
        }

        // A step handed to a command that doesn't cycle must be ignored outright.
        for step in 0...5 {
            expectRect(
                frame(.maximize, step: step)!, frame(.maximize)!, "maximize ignores step \(step)")
            expectRect(frame(.center, step: step)!, frame(.center)!, "center ignores step \(step)")
        }
    }

    // MARK: - Non-divisible widths

    static func testNonDivisible() {
        for width in [1441, 1000, 1367, 1366] as [CGFloat] {
            let screen = WindowPlacementEngine.Screen(
                id: 9, frame: CGRect(x: 0, y: 0, width: width, height: 901),
                usableFrame: CGRect(x: 0, y: 0, width: width, height: 901))

            let left = frame(.half, on: screen)!
            let right = frame(.half, on: screen, step: 1)!
            expect(left.maxX == right.minX, "\(width): halves share an edge exactly")
            expect(left.union(right) == screen.usableFrame, "\(width): halves cover the screen")
            expect(abs(left.width - right.width) <= 1, "\(width): halves differ by at most a point")

            let corners = (0..<4).map { frame(.quarter, on: screen, step: $0)! }
            expect(
                corners.reduce(CGRect.null) { $0.union($1) } == screen.usableFrame,
                "\(width)×901: quarters still cover the screen")
            expect(corners[0].maxX == corners[1].minX, "\(width): top quarters share an edge")
            expect(corners[1].maxY == corners[2].minY, "\(width)×901: right quarters share an edge")

            let centred = frame(.center, on: screen)!
            expect(
                abs((centred.minX - screen.usableFrame.minX) - (screen.usableFrame.maxX - centred.maxX))
                    <= 1, "\(width): center leaves equal margins to within a point")
            expect(
                abs(centred.width - width * 0.75) <= 1, "\(width): center is 75% of the screen")
        }
    }

    // MARK: - Off-origin displays

    static func testOffOriginScreens() {
        // A display up and to the right of the primary — negative Y in AX space.
        let high = WindowPlacementEngine.Screen(
            id: 2, frame: CGRect(x: 1920, y: -300, width: 2560, height: 1440),
            usableFrame: CGRect(x: 1920, y: -300, width: 2560, height: 1440))
        let onHigh = CGRect(x: 2000, y: 0, width: 400, height: 300)
        expectRect(
            frame(.half, on: high, window: onHigh)!,
            CGRect(x: 1920, y: -300, width: 1280, height: 1440), "left half on an off-origin display")
        expect(
            frame(.quarter, on: high, window: onHigh)!.minY == -300,
            "top left quarter honours a negative minY")

        // A display left of and below the primary.
        let low = WindowPlacementEngine.Screen(
            id: 3, frame: CGRect(x: -1440, y: 200, width: 1440, height: 900),
            usableFrame: CGRect(x: -1440, y: 200, width: 1440, height: 900))
        let onLow = CGRect(x: -1000, y: 300, width: 400, height: 300)
        expectRect(
            frame(.half, on: low, window: onLow, step: 1)!,
            CGRect(x: -720, y: 200, width: 720, height: 900), "right half on a negative-X display")
        expectRect(
            frame(.maximize, on: low, window: onLow)!, low.usableFrame,
            "maximize on a negative-X display")
        expectRect(
            frame(.center, on: low, window: onLow)!,
            CGRect(x: -1260, y: 200, width: 1080, height: 900), "center on a negative-X display")

        // A usable frame smaller than the full frame, with the menu bar reserved.
        let reserved = WindowPlacementEngine.Screen(
            id: 4, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            usableFrame: CGRect(x: 0, y: 25, width: 1440, height: 800))
        expectRect(
            frame(.quarter, on: reserved)!, CGRect(x: 0, y: 25, width: 720, height: 400),
            "tiles respect a reserved usable frame")
        expectRect(
            frame(.maximize, on: reserved)!, reserved.usableFrame, "maximize never covers the menu bar")
        expectRect(
            frame(.center, on: reserved)!, CGRect(x: 180, y: 25, width: 1080, height: 800),
            "center is full height below the menu bar")
    }

    // MARK: - Sizing

    static func testSizing() {
        expectRect(frame(.maximize)!, mainScreen.usableFrame, "maximize fills the usable frame")

        let window = CGRect(x: 100, y: 200, width: 300, height: 400)
        expectRect(
            frame(.center, window: window)!, CGRect(x: 180, y: 0, width: 1080, height: 900),
            "center is 75% wide by default, full height, centred horizontally")
        expectRect(
            frame(.center, window: frame(.center, window: window)!)!,
            frame(.center, window: window)!, "center is idempotent")
        expectRect(
            frame(.center, centerWidth: 50)!,
            CGRect(x: 360, y: 0, width: 720, height: 900), "center honours the width it is given")
        expectRect(
            frame(.center, centerWidth: 100)!, frame(.maximize)!,
            "a full-width center is a maximize")

        // A width from outside the range is pulled back to its nearest end.
        expectRect(
            frame(.center, centerWidth: 5)!,
            frame(.center, centerWidth: 20)!,
            "too narrow a width clamps to the smallest")
        expectRect(
            frame(.center, centerWidth: 400)!, frame(.maximize)!,
            "too wide a width clamps to full width")
        expect(
            WindowPlacementEngine.clampedCenterWidth(-3) == 20
                && WindowPlacementEngine.clampedCenterWidth(60) == 60
                && WindowPlacementEngine.clampedCenterWidth(101) == 100,
            "the clamp keeps a width inside 20…100")
        expect(
            placement(.center)!.anchor
                == WindowPlacementEngine.Anchor(horizontal: .center, vertical: .center),
            "a window that can't take Center's size sits centred on both axes")
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
        let both = screens(right, mainScreen)

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

    // MARK: - Cycling

    static func testCycling() {
        let loose = CGRect(x: 100, y: 100, width: 600, height: 400)

        expect(
            presses(.half, 3, from: loose) == [half(.left), half(.right), half(.left)],
            "Half goes left, then right, then left again")
        expect(
            presses(.half, 3, from: loose, preferences: preferences(half: .right))
                == [half(.right), half(.left), half(.right)],
            "Half starting on the right goes right, then left")
        expect(
            presses(.quarter, 5, from: loose)
                == [
                    quarter(.topLeft), quarter(.topRight), quarter(.bottomRight),
                    quarter(.bottomLeft), quarter(.topLeft)
                ],
            "Quarter walks clockwise from the top left and wraps")
        expect(
            presses(.quarter, 2, from: loose, preferences: preferences(quarter: .bottomLeft))
                == [quarter(.bottomLeft), quarter(.topLeft)],
            "Quarter starting bottom left moves on to the top left")

        // With nothing remembered, a window already on its first slot moves on rather than staying.
        expect(
            presses(.half, 1, from: half(.left)) == [half(.right)],
            "Half on a window already at the left half flips it right")
        expect(
            presses(.quarter, 1, from: quarter(.topLeft)) == [quarter(.topRight)],
            "Quarter on a window already top left moves it on")
        expect(
            presses(.half, 1, from: half(.right)) == [half(.left)],
            "a window on the other half lands on the starting side")
        let nearlyLeft = CGRect(x: 1, y: 0, width: 719, height: 900)
        expect(
            presses(.half, 1, from: nearlyLeft) == [half(.right)],
            "a window within tolerance of its first slot counts as already there")
        expect(
            presses(.maximize, 2, from: mainScreen.usableFrame)
                == [mainScreen.usableFrame, mainScreen.usableFrame],
            "a command that doesn't cycle stays put on a repeat")

        // An app that never takes the slot exactly still moves on: the landing decides, not the slot.
        let snapsNarrower: (CGRect) -> CGRect = {
            CGRect(x: $0.minX, y: $0.minY, width: $0.width - 5, height: $0.height)
        }
        let snappedLeft = snapsNarrower(half(.left))
        expect(
            presses(.half, 1, from: snappedLeft, land: snapsNarrower)
                == [snapsNarrower(half(.right))],
            "Half on a window that snapped into the left half still flips it right")

        // A changed starting position never reinterprets a chain already under way.
        var restarted = WindowActionMemory<Int>()
        _ = presses(.quarter, 1, from: loose, memory: &restarted)
        expect(
            presses(
                .quarter, 1, from: quarter(.topLeft), preferences: preferences(quarter: .topRight),
                memory: &restarted) == [quarter(.topRight)],
            "a new Quarter start mid-chain still moves clockwise from where the window is")
        var flipped = WindowActionMemory<Int>()
        _ = presses(.half, 1, from: loose, memory: &flipped)
        expect(
            presses(
                .half, 1, from: half(.left), preferences: preferences(half: .right),
                memory: &flipped) == [half(.right)],
            "a new Half start mid-chain still flips the window")

        // A drag or another command between presses starts the chain over.
        var memory = WindowActionMemory<Int>()
        _ = presses(.half, 1, from: loose, memory: &memory)
        expect(
            presses(.half, 1, from: loose, memory: &memory) == [half(.left)],
            "a window dragged off its half starts again on the left")
        _ = presses(.quarter, 1, from: loose, memory: &memory)
        expect(
            presses(.half, 1, from: quarter(.topLeft), memory: &memory) == [half(.left)],
            "Half after a Quarter starts on the left")
    }

    // MARK: - Action memory

    static func testMemory() {
        let clock = Date(timeIntervalSince1970: 1_000_000)
        let left = half(.left)
        let original = CGRect(x: 100, y: 100, width: 600, height: 400)

        // A fresh window starts its chain at step 0.
        var memory = WindowActionMemory<Int>()
        var step = memory.decide(
            key: 1, command: .quarter, currentFrame: original, currentScreenID: 1, cycleLength: 4,
            now: clock)
        expect(step == nil, "a first press starts a new chain")
        memory.commit(
            key: 1, command: .quarter, step: 0, appliedFrame: quarter(.topLeft), screenID: 1,
            now: clock)

        // Repeats advance the cycle.
        for expected in [1, 2, 3, 0, 1] {
            step = memory.decide(
                key: 1, command: .quarter, currentFrame: memory.record(for: 1)!.appliedFrame,
                currentScreenID: 1, cycleLength: 4, now: clock)
            expect(step == expected, "the cycle advances to step \(expected)")
            memory.commit(
                key: 1, command: .quarter, step: expected,
                appliedFrame: frame(.quarter, step: expected)!, screenID: 1, now: clock)
        }

        // A different command, screen, or window resets the cycle.
        step = memory.decide(
            key: 1, command: .half, currentFrame: memory.record(for: 1)!.appliedFrame,
            currentScreenID: 1, cycleLength: 2, now: clock)
        expect(step == nil, "a different command restarts the cycle")
        step = memory.decide(
            key: 1, command: .quarter, currentFrame: memory.record(for: 1)!.appliedFrame,
            currentScreenID: 2, cycleLength: 4, now: clock)
        expect(step == nil, "a different display restarts the cycle")
        step = memory.decide(
            key: 99, command: .quarter, currentFrame: original, currentScreenID: 1,
            cycleLength: 4, now: clock)
        expect(step == nil, "another window has its own chain")

        // A user drag resets the cycle.
        var dragged = WindowActionMemory<Int>()
        dragged.commit(key: 1, command: .half, step: 0, appliedFrame: left, screenID: 1, now: clock)
        let movedByUser = CGRect(x: 400, y: 400, width: 500, height: 300)
        step = dragged.decide(
            key: 1, command: .half, currentFrame: movedByUser, currentScreenID: 1, cycleLength: 2,
            now: clock)
        expect(step == nil, "a user drag restarts the cycle")

        // A quantising app that lands a point off its target must NOT read as a user drag.
        let quantised = CGRect(x: left.minX + 1, y: left.minY, width: left.width - 1, height: left.height)
        step = dragged.decide(
            key: 1, command: .half, currentFrame: quantised, currentScreenID: 1, cycleLength: 2,
            now: clock)
        expect(step == 1, "a sub-tolerance difference keeps the cycle running")

        // A non-cycling command never advances.
        var nonCycling = WindowActionMemory<Int>()
        let maximized = mainScreen.usableFrame
        for _ in 0..<5 {
            let nonStep = nonCycling.decide(
                key: 1, command: .maximize, currentFrame: maximized, currentScreenID: 1,
                cycleLength: WindowCommandCatalog.cycleLength(for: .maximize), now: clock)
            expect(nonStep == nil, "a non-cycling command never advances")
            nonCycling.commit(
                key: 1, command: .maximize, step: 0, appliedFrame: maximized, screenID: 1,
                now: clock)
        }

        var timed = WindowActionMemory<Int>(cycleTimeout: 60)
        timed.commit(key: 1, command: .half, step: 0, appliedFrame: left, screenID: 1, now: clock)
        expect(
            timed.decide(
                key: 1, command: .half, currentFrame: left, currentScreenID: 1, cycleLength: 2,
                now: clock.addingTimeInterval(30)) == 1, "a cycle inside the timeout continues")
        expect(
            timed.decide(
                key: 1, command: .half, currentFrame: left, currentScreenID: 1, cycleLength: 2,
                now: clock.addingTimeInterval(120)) == nil, "a cycle past the timeout restarts")

        // Bounded growth, most-recently-used retained.
        var bounded = WindowActionMemory<Int>(capacity: 64)
        for key in 0..<100 {
            bounded.commit(
                key: key, command: .half, step: 0, appliedFrame: left, screenID: 1, now: clock)
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
        let centerWidths = [75, 20, 100, -40, 9_000]
        let steps = [0, 1, 5, -3]

        var checked = 0
        var problems: [String] = []
        for screens in displays {
            for window in windows {
                for centerWidth in centerWidths {
                    for step in steps {
                        for command in WindowCommand.ID.allCases {
                            let input = WindowPlacementEngine.Input(
                                command: command, windowFrame: window, screens: screens, step: step,
                                centerWidth: centerWidth)
                            // A nil placement is a legitimate quiet no-op, not a failure.
                            guard let placement = WindowPlacementEngine.placement(for: input) else {
                                continue
                            }
                            checked += 1
                            let rect = placement.frame
                            let label = "\(command.rawValue) width \(centerWidth) step \(step) window \(window)"

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
                            // Determinism, and no drift when a command is applied twice at one step.
                            if WindowPlacementEngine.placement(for: input)?.frame != rect {
                                problems.append("non-deterministic: \(label)")
                            }
                            var repeated = input
                            repeated.windowFrame = rect
                            if let again = WindowPlacementEngine.placement(for: repeated)?.frame,
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
        expect(checked > 1000, "the fuzz sweep exercised a meaningful number of placements")
        expect(problems.isEmpty, "fuzz sweep found no violations")
        for problem in problems.prefix(10) { print("      \(problem)") }
    }
}
