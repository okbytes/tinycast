import SwiftUI

struct WindowManagementSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppCore.self) private var core
    @State private var chosenPreset: WindowShortcutPreset?
    @State private var savingDockLog = false

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.windowManagementEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .windowManagementWindowManagement, title: "Enable window management",
                        subtitle: "Moves the last window you used. Needs Accessibility.")
                }
                Toggle("Show in launcher", isOn: $settings.windowManagementShowInLauncher)
                    // The switch above stays live so the feature can always be turned back on.
                    .settingsEnabled(settings.windowManagementEnabled)
            }
            .settingsAnchor(.windowManagementWindowManagement)

            Group {
                options
                commands
            }
            .settingsEnabled(settings.windowManagementEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.windowManagement)
    }

    private var options: some View {
        @Bindable var settings = settings
        return Section {
            Picker(selection: $settings.windowCycle) {
                ForEach(WindowCycle.allCases) { cycle in
                    Text(cycle.title).tag(cycle)
                }
            } label: {
                SettingsRowTitle(.windowManagementOptions, "Cycling")
                Text(settings.windowCycle.detail)
            }

            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("\(settings.windowGap) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper(
                        "Gap between windows", value: $settings.windowGap,
                        in: WindowPlacementEngine.gapRange, step: 2
                    )
                    .labelsHidden()
                }
            } label: {
                SettingsRowTitle(.windowManagementOptions, "Gap between windows")
                Text("Between tiled windows and screen edges.")
            }

            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    Picker("Shortcut preset", selection: $chosenPreset) {
                        Text("Choose…").tag(WindowShortcutPreset?.none)
                        ForEach(WindowShortcutPreset.allCases) { preset in
                            Text(preset.title).tag(Optional(preset))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Apply") {
                        guard let chosenPreset else { return }
                        Task { await core.windowShortcutPresetCoordinator.apply(chosenPreset) }
                    }
                    // Live bindings decide, so one edit to an applied preset re-enables it.
                    .disabled(
                        chosenPreset == nil
                            || chosenPreset == core.windowShortcutPresetCoordinator.matchingPreset)
                }
            } label: {
                SettingsRowTitle(.windowManagementOptions, "Shortcut preset")
                Text("Fills in another app's shortcuts. Others stay as they are.")
            }

            LabeledContent {
                if savingDockLog {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Save…") { saveDockLog() }
                }
            } label: {
                SettingsRowTitle(.windowManagementOptions, "Dock log")
                Text("What Tinycast saw of the Dock and your windows, last \(DockLogExport.days) days.")
            }
        } header: {
            SettingsSectionHeader(.windowManagementOptions)
        }
    }

    private func saveDockLog() {
        guard !savingDockLog else { return }
        savingDockLog = true
        Task {
            defer { savingDockLog = false }
            do {
                _ = try await DockLogExport.run()
            } catch {
                core.showMessage(error.localizedDescription, tone: .danger)
            }
        }
    }

    /// One section per catalog group, so the sidebar's own grouping carries the headings.
    private var commands: some View {
        ForEach(WindowCommandCatalog.grouped(), id: \.group) { section in
            Section {
                ForEach(section.commands) { command in
                    WindowCommandSettingsRow(
                        command: command, showsInLauncher: settings.windowManagementShowInLauncher)
                }
            } header: {
                Text(section.group.title)
            }
        }
    }
}

/// One command's alias, shortcut recorder and visibility checkbox, shaped like the shortcuts row.
private struct WindowCommandSettingsRow: View {
    let command: WindowCommand
    let showsInLauncher: Bool
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        let entry = AppEntry(command)
        let isVisible = visibility.isItemVisible(entry)
        SettingsRow(title: command.name) {
            Image(systemName: command.sfSymbol)
        } trailing: {
            // The ranker never sees a hidden entry, so typing here would match nothing.
            AliasField(entry: entry)
                .settingsEnabled(showsInLauncher && isVisible)

            ShortcutRecorder(action: .windowCommand(id: command.id))

            Toggle(
                "", isOn: Binding(get: { isVisible }, set: { visibility.setItemVisible($0, for: entry) })
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .launcherVisibilityHelp()
            .accessibilityLabel("Show \(command.name) in launcher")
        }
    }
}
