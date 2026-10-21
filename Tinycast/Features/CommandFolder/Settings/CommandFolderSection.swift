import SwiftUI

/// The folder row on the Commands pane; the folder's commands list under it as any category does.
struct CommandFolderSection: View {
    @Environment(AppCore.self) private var core

    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    Button("Choose…") { core.folderCommandCoordinator.chooseFolder() }
                    Button("Show in Finder") { core.folderCommandCoordinator.revealFolder() }
                }
            } label: {
                SettingsRowTitle(.commandsCommandFolder, "Folder")
                Text(
                    (core.folderCommandCoordinator.folder.path(percentEncoded: false) as NSString)
                        .abbreviatingWithTildeInPath)
            }
            // The folder can change while Settings sits closed, so the pane reads it fresh.
            .task { core.folderCommandCoordinator.refresh() }
        } header: {
            SettingsSectionHeader(.commandsCommandFolder)
        } footer: {
            Text(
                """
                A shell script or any executable is a command that runs it in a login shell. \
                A .url or .link file holding one link is a command that opens it. \
                Untick a row to keep it out of the launcher.
                """)
        }
    }
}
