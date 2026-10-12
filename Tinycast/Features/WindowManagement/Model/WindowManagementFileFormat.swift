import Foundation

/// Window commands' shortcuts and aliases as settings.json spells them.
enum WindowManagementFileFormat {
    /// Every command's chord or alias, nil for none; one of the wrong type has no entry and keeps its own.
    typealias CommandTexts = (texts: [WindowCommand.ID: String?], problems: [String])

    // MARK: - Command shortcuts

    /// Every command, unbound ones as `null`, so the file itself lists what can be bound.
    static func json(commandShortcuts: [WindowCommand.ID: String]) -> SettingsFileJSON {
        .object(
            WindowCommand.ID.allCases.map { id in
                SettingsFileJSON.Member(key: id.rawValue, value: text(commandShortcuts[id]))
            })
    }

    /// A command the object leaves out is unbound, the same as one set to `null`.
    static func commandShortcuts(from json: SettingsFileJSON) -> CommandTexts? {
        commandTexts(from: json, noun: "a shortcut")
    }

    // MARK: - Command aliases

    static func json(commandAliases: [WindowCommand.ID: String]) -> SettingsFileJSON {
        .object(
            WindowCommand.ID.allCases.compactMap { id in
                commandAliases[id].map { SettingsFileJSON.Member(key: id.rawValue, value: .string($0)) }
            })
    }

    static func commandAliases(from json: SettingsFileJSON) -> CommandTexts? {
        commandTexts(from: json, noun: "an alias")
    }

    private static func commandTexts(from json: SettingsFileJSON, noun: String) -> CommandTexts? {
        guard let members = json.members else { return nil }
        var texts = Dictionary(uniqueKeysWithValues: WindowCommand.ID.allCases.map { ($0, String?.none) })
        var problems: [String] = []
        for member in members {
            guard let id = WindowCommand.ID(rawValue: member.key) else {
                problems.append("no command is called “\(member.key)”")
                continue
            }
            switch member.value {
            case .null: continue
            case .string(let text): texts[id] = text
            default:
                texts.removeValue(forKey: id)
                problems.append("“\(member.key)” needs \(noun) in quotes, or null")
            }
        }
        return (texts, problems)
    }

    // MARK: - Fields

    private static func text(_ value: String?) -> SettingsFileJSON {
        value.map(SettingsFileJSON.string) ?? .null
    }
}
