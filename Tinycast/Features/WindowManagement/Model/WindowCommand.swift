import Foundation

struct WindowCommand: Identifiable, Hashable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case half
        case quarter
        case maximize
        case center
        case moveLeft = "move-left"
        case moveRight = "move-right"
        case moveUp = "move-up"
        case moveDown = "move-down"
    }

    /// The launcher section a command belongs to, and the order the Settings panel lists them in.
    enum Group: String, CaseIterable, Sendable {
        case sizing
        case moving

        var title: String {
            switch self {
            case .sizing: return "Sizing"
            case .moving: return "Moving"
            }
        }
    }

    /// The side Half lands on first; pressing it again flips to the other.
    enum HalfSide: String, CaseIterable, Identifiable, Sendable {
        case left
        case right

        var id: Self { self }

        var title: String {
            switch self {
            case .left: return "Left"
            case .right: return "Right"
            }
        }
    }

    /// The corner Quarter lands on first; pressing it again walks the others clockwise.
    enum QuarterCorner: String, CaseIterable, Identifiable, Sendable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        var id: Self { self }

        var title: String {
            switch self {
            case .topLeft: return "Top Left"
            case .topRight: return "Top Right"
            case .bottomLeft: return "Bottom Left"
            case .bottomRight: return "Bottom Right"
            }
        }

        /// Repeat-press order: each step moves to an adjacent corner, never across the diagonal.
        static let clockwise: [Self] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
    }

    let id: ID
    let name: String
    let sfSymbol: String
    let group: Group
    /// Slots a repeat press walks through; 1 for a command that lands in the same place again.
    let cycleLength: Int
    /// False for the four moves, so the mover never writes `kAXSizeAttribute` for them.
    let resizes: Bool

    var entryID: String { "window-command:" + id.rawValue }
}

enum WindowCommandCatalog {
    static let all: [WindowCommand] = WindowCommand.ID.allCases.map { id in
        WindowCommand(
            id: id, name: name(for: id), sfSymbol: symbol(for: id), group: group(for: id),
            cycleLength: cycleLength(for: id), resizes: !movesOnly.contains(id))
    }

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    private static let byEntryID = Dictionary(uniqueKeysWithValues: all.map { ($0.entryID, $0) })

    static func command(id: WindowCommand.ID) -> WindowCommand? { byID[id] }

    static func command(forEntryID entryID: String) -> WindowCommand? { byEntryID[entryID] }

    /// Catalog order grouped for Settings; `ID.allCases` is in group order, so this partitions.
    static func grouped() -> [(group: WindowCommand.Group, commands: [WindowCommand])] {
        WindowCommand.Group.allCases.compactMap { group in
            let commands = all.filter { $0.group == group }
            return commands.isEmpty ? nil : (group, commands)
        }
    }

    static func cycleLength(for id: WindowCommand.ID) -> Int {
        switch id {
        case .half: return WindowCommand.HalfSide.allCases.count
        case .quarter: return WindowCommand.QuarterCorner.clockwise.count
        default: return 1
        }
    }

    /// The four moves reposition without ever touching the size.
    static let movesOnly: Set<WindowCommand.ID> = [.moveLeft, .moveRight, .moveUp, .moveDown]

    private static func name(for id: WindowCommand.ID) -> String {
        switch id {
        case .half: return "Half"
        case .quarter: return "Quarter"
        case .maximize: return "Maximize"
        case .center: return "Center"
        case .moveLeft: return "Move Left"
        case .moveRight: return "Move Right"
        case .moveUp: return "Move Up"
        case .moveDown: return "Move Down"
        }
    }

    private static func symbol(for id: WindowCommand.ID) -> String {
        switch id {
        case .half: return "rectangle.split.2x1"
        case .quarter: return "rectangle.split.2x2"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .center: return "rectangle.center.inset.filled"
        case .moveLeft: return "arrow.left"
        case .moveRight: return "arrow.right"
        case .moveUp: return "arrow.up"
        case .moveDown: return "arrow.down"
        }
    }

    private static func group(for id: WindowCommand.ID) -> WindowCommand.Group {
        switch id {
        case .half, .quarter, .maximize, .center:
            return .sizing
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            return .moving
        }
    }
}
