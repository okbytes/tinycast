import SwiftUI

/// The folder's commands, each with the launcher controls any item carries.
struct CommandFolderSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppIndex.self) private var appIndex
    @State private var query = ""

    private var entries: [AppEntry] {
        let entries = core.folderCommandCoordinator.entries
        guard !query.isEmpty else { return entries }
        // Membership only: score order would move the row being edited out from under the caret.
        let matched = Set(appIndex.matches(query).map(\.id))
        return entries.filter { matched.contains($0.id) }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button("Choose…") { core.folderCommandCoordinator.chooseFolder() }
                        Button("Show in Finder") { core.folderCommandCoordinator.revealFolder() }
                    }
                } label: {
                    SettingsRowTitle(.commandFolderFolder, "Folder")
                    Text(
                        (core.folderCommandCoordinator.folder.path(percentEncoded: false) as NSString)
                            .abbreviatingWithTildeInPath)
                }
            } header: {
                SettingsSectionHeader(.commandFolderFolder)
            } footer: {
                Text(
                    """
                    A shell script or any executable is a command that runs it in a login shell. \
                    A .url or .link file holding one link is a command that opens it. \
                    Untick a row to keep it out of the launcher.
                    """)
            }

            Section {
                SettingsFilterField(prompt: "Search commands…", query: $query)
                LauncherItemsList(entries: entries, query: query, isEnabled: true)
            } header: {
                SettingsSectionHeader(.commandFolderCommands)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.commandFolder)
        .releasesFocusOnOutsideClick()
        // The folder can change while Settings sits closed, so the pane reads it fresh.
        .task { core.folderCommandCoordinator.refresh() }
    }
}
