import SwiftUI

struct CommandsSettingsView: View {
    var body: some View {
        Form {
            LauncherCategorySwitchSection(kind: .command, anchor: .commandsCommands)

            LauncherItemsSection(
                kind: .command,
                anchor: .commandsCommands,
                searchPrompt: "Search commands…")

            CommandFolderSection()
            LauncherItemsSection(
                kind: .folderCommand,
                anchor: .commandsFolderCommands,
                searchPrompt: "Search folder commands…")
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.commands)
        .releasesFocusOnOutsideClick()
    }
}
