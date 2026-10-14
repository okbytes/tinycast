import Foundation

struct WindowCommand: Identifiable, Hashable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case leftHalf = "left-half"
        case rightHalf = "right-half"
        case topLeftQuarter = "top-left-quarter"
        case topRightQuarter = "top-right-quarter"
        case bottomLeftQuarter = "bottom-left-quarter"
        case bottomRightQuarter = "bottom-right-quarter"
        case firstThreeFourths = "first-three-fourths"
        case centerThreeFourths = "center-three-fourths"
        case lastThreeFourths = "last-three-fourths"
        case maximize
        case center
        case moveLeft = "move-left"
        case moveRight = "move-right"
        case moveUp = "move-up"
        case moveDown = "move-down"
    }

    /// The launcher section a command belongs to, and the order the Settings panel lists them in.
    enum Group: String, CaseIterable, Sendable {
        case halves
        case quarters
        case fourths
        case sizing
        case moving

        var title: String {
            switch self {
            case .halves: return "Halves"
            case .quarters: return "Quarters"
            case .fourths: return "Fourths"
            case .sizing: return "Sizing"
            case .moving: return "Moving"
            }
        }
    }

    let id: ID
    let name: String
    let sfSymbol: String
    let group: Group
    /// Only the two halves honour `WindowCycle`; the rest ignore the step they are handed.
    let cyclesOnRepeat: Bool
    /// False for the four moves, so the mover never writes `kAXSizeAttribute` for them.
    let resizes: Bool

    var entryID: String { "window-command:" + id.rawValue }
}

enum WindowCommandCatalog {
    static let all: [WindowCommand] = WindowCommand.ID.allCases.map { id in
        WindowCommand(
            id: id, name: name(for: id), sfSymbol: symbol(for: id), group: group(for: id),
            cyclesOnRepeat: cyclesOnRepeat.contains(id),
            resizes: !movesOnly.contains(id))
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

    static let cyclesOnRepeat: Set<WindowCommand.ID> = [.leftHalf, .rightHalf]

    /// The four moves reposition without ever touching the size.
    static let movesOnly: Set<WindowCommand.ID> = [.moveLeft, .moveRight, .moveUp, .moveDown]

    private static func name(for id: WindowCommand.ID) -> String {
        switch id {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topLeftQuarter: return "Top Left Quarter"
        case .topRightQuarter: return "Top Right Quarter"
        case .bottomLeftQuarter: return "Bottom Left Quarter"
        case .bottomRightQuarter: return "Bottom Right Quarter"
        case .firstThreeFourths: return "First Three Fourths"
        case .centerThreeFourths: return "Center Three Fourths"
        case .lastThreeFourths: return "Last Three Fourths"
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
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topLeftQuarter: return "rectangle.inset.topleading.filled"
        case .topRightQuarter: return "rectangle.inset.toptrailing.filled"
        case .bottomLeftQuarter: return "rectangle.inset.bottomleading.filled"
        case .bottomRightQuarter: return "rectangle.inset.bottomtrailing.filled"
        case .firstThreeFourths: return "rectangle.lefthalf.inset.filled"
        case .centerThreeFourths: return "inset.filled.center.rectangle"
        case .lastThreeFourths: return "rectangle.righthalf.inset.filled"
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
        case .leftHalf, .rightHalf:
            return .halves
        case .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            return .quarters
        case .firstThreeFourths, .centerThreeFourths, .lastThreeFourths:
            return .fourths
        case .maximize, .center:
            return .sizing
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            return .moving
        }
    }
}
