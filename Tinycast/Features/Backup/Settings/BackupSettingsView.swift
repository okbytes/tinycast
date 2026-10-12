import AppKit
import SwiftUI

struct BackupSettingsView: View {
    @Environment(AppCore.self) private var core
    @State private var exportSelection = BackupCategory.all
    @State private var importSelection: Set<BackupCategory> = []
    @State private var exporting = false
    @State private var importingBackup = false
    @State private var backupStatus: Status?
    @State private var backupFile: URL?
    @State private var openedManifest: BackupManifest?
    /// Held between opening the file and applying it, so the extracted tree survives the picker.
    @State private var openedStaging: BackupStaging?

    private enum Status {
        case success(String)
        case failure(String)
    }

    /// Turning it on may ask first, so the switch follows the setting rather than the click.
    private var settingsFileSync: Binding<Bool> {
        Binding(
            get: { core.settings.settingsFileEnabled },
            set: { enabled in Task { await BackupActions.setSettingsFileEnabled(enabled, core: core) } })
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if exporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Export…") { runExport() }.disabled(exportSelection.isEmpty)
                    }
                } label: {
                    SettingsRowTitle(.backupExport, "Export Backup")
                    Text("The ticked items, as one .tinycast file.")
                }
                BackupCategorySelection(selection: $exportSelection)
                if let backupStatus { statusRow(backupStatus) }
            } header: {
                SettingsSectionHeader(.backupExport)
            }

            Section {
                LabeledContent {
                    Button("Choose…") { chooseBackupFile() }
                } label: {
                    SettingsRowTitle(.backupImport, "Backup File")
                    Text(backupFileSubtitle)
                }
                if let manifest = openedManifest {
                    BackupCategorySelection(
                        selection: $importSelection, available: manifest.available)
                    LabeledContent {
                        if importingBackup {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Import") { runBackupImport() }
                                .disabled(importSelection.isEmpty)
                        }
                    } label: {
                        Text("Import")
                    }
                }
            } header: {
                SettingsSectionHeader(.backupImport)
            }

            Section {
                Toggle(isOn: settingsFileSync) {
                    SettingsRowTitle(.backupSettingsFile, "Sync settings file")
                    Text(BackupActions.settingsFilePath)
                }
                if core.settings.settingsFileEnabled {
                    LabeledContent {
                        Button("Show in Finder", action: BackupActions.revealSettingsFile)
                    } label: {
                        Text("Settings changed here are written to the file, and edits to it apply here.")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                SettingsSectionHeader(.backupSettingsFile)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.backup)
        .onDisappear { if !importingBackup { discardStagedBackup() } }
    }

    @ViewBuilder
    private func statusRow(_ status: Status) -> some View {
        switch status {
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var backupFileSubtitle: String {
        guard let name = backupFile?.lastPathComponent else {
            return "A .tinycast file exported from Tinycast."
        }
        return openedManifest == nil ? "\(name) — couldn't be read" : name
    }

    private func runExport() {
        guard !exporting else { return }
        exporting = true
        backupStatus = nil
        let categories = exportSelection
        Task {
            defer { exporting = false }
            do {
                let result = try await BackupActions.exportBackup(
                    core: core, categories: categories)
                backupStatus = .success(BackupActions.exportText(result))
            } catch is CancellationError {
                // The user closed the save panel; nothing to report.
            } catch {
                backupStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func chooseBackupFile() {
        guard let url = BackupActions.chooseBackupFile() else { return }
        discardStagedBackup()
        backupFile = url
        backupStatus = nil
        Task {
            do {
                let (staging, manifest) = try await BackupActions.openBackup(at: url)
                openedStaging = staging
                openedManifest = manifest
                importSelection = manifest.categories
            } catch {
                backupStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func runBackupImport() {
        guard let staging = openedStaging, !importingBackup, !importSelection.isEmpty else {
            return
        }
        importingBackup = true
        let categories = importSelection
        Task {
            defer { importingBackup = false }
            let summary = await BackupActions.applyBackup(
                categories, from: staging, to: core)
            // Staged files are adopted by the stores during apply, so the tree goes either way.
            discardStagedBackup()
            backupFile = nil
            backupStatus = .success(BackupActions.summaryText(summary))
        }
    }

    /// The extracted tree can run to gigabytes, so leaving the pane must not strand it.
    private func discardStagedBackup() {
        openedStaging?.discard()
        openedStaging = nil
        openedManifest = nil
    }
}
