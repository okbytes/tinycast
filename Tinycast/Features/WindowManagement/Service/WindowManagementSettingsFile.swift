import Foundation

/// Window management's shortcuts and aliases in settings.json.
@MainActor
struct WindowManagementSettingsFile {
    let aliases: AliasStore
    let shortcuts: HotKeySettingsFile

    func commandShortcutsBinding(for key: SettingsFileKey) -> SettingsFileBinding {
        SettingsFileBinding(
            key,
            read: {
                let spelling = shortcuts.spelling
                var texts: [WindowCommand.ID: String] = [:]
                for id in WindowCommand.ID.allCases {
                    texts[id] = shortcuts.text(for: .windowCommand(id: id), spelling)
                }
                return WindowManagementFileFormat.json(commandShortcuts: texts)
            },
            write: { json in
                guard let decoded = WindowManagementFileFormat.commandShortcuts(from: json) else {
                    return [.invalidValue(key)]
                }
                let wanted = WindowCommand.ID.allCases.compactMap { id in
                    decoded.texts[id].map { text in
                        HotKeySettingsFile.Wanted(
                            action: .windowCommand(id: id), text: text, label: "“\(id.rawValue)”")
                    }
                }
                return decoded.problems.map { .invalidEntry(key, $0) }
                    + shortcuts.apply(wanted, key: key)
            })
    }

    func commandAliasesBinding(for key: SettingsFileKey) -> SettingsFileBinding {
        SettingsFileBinding(
            key,
            read: {
                var texts: [WindowCommand.ID: String] = [:]
                for command in WindowCommandCatalog.all {
                    texts[command.id] = aliases.alias(for: command.entryID)
                }
                return WindowManagementFileFormat.json(commandAliases: texts)
            },
            write: { json in
                guard let decoded = WindowManagementFileFormat.commandAliases(from: json) else {
                    return [.invalidValue(key)]
                }
                for command in WindowCommandCatalog.all {
                    guard let alias = decoded.texts[command.id] else { continue }
                    aliases.setAlias(alias ?? "", for: command.entryID)
                }
                return decoded.problems.map { .invalidEntry(key, $0) }
            })
    }
}
