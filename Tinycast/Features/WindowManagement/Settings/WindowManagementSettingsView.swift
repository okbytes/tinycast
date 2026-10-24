import SwiftUI

struct WindowManagementSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppCore.self) private var core
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
                commands
                options
            }
            .settingsEnabled(settings.windowManagementEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.windowManagement)
    }

    /// One section per catalog group, each command followed by the setting that tunes it.
    private var commands: some View {
        ForEach(WindowCommandCatalog.grouped(), id: \.group) { section in
            Section {
                ForEach(section.commands) { command in
                    WindowCommandSettingsRow(
                        command: command, showsInLauncher: settings.windowManagementShowInLauncher)
                    preference(for: command.id)
                }
            } header: {
                header(for: section.group)
            }
        }
    }

    @ViewBuilder
    private func header(for group: WindowCommand.Group) -> some View {
        switch group {
        case .sizing: SettingsSectionHeader(.windowManagementSizing)
        case .moving: SettingsSectionHeader(.windowManagementMoving)
        }
    }

    @ViewBuilder
    private func preference(for id: WindowCommand.ID) -> some View {
        @Bindable var settings = settings
        switch id {
        case .half:
            Picker(selection: $settings.windowHalfStart) {
                ForEach(WindowCommand.HalfSide.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowTitle(.windowManagementSizing, "Half starts on")
                Text("Pressing Half again moves it to the other side.")
            }
        case .quarter:
            Picker(selection: $settings.windowQuarterStart) {
                ForEach(WindowCommand.QuarterCorner.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowTitle(.windowManagementSizing, "Quarter starts at")
                Text("Pressing Quarter again moves it clockwise.")
            }
        case .center:
            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("Center width", value: centerWidth, format: .number)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: Theme.Size.settingsNumberField)
                    Text("%").foregroundStyle(.secondary)
                    Stepper(
                        "Center width", value: centerWidth,
                        in: WindowPlacementEngine.centerWidthRange, step: 5
                    )
                    .labelsHidden()
                }
            } label: {
                SettingsRowTitle(.windowManagementSizing, "Center width")
                Text("Of the screen, always at full height.")
            }
        default:
            EmptyView()
        }
    }

    /// A typed value outside the range snaps to its nearest end rather than being refused.
    private var centerWidth: Binding<Int> {
        Binding(
            get: { settings.windowCenterWidth },
            set: { settings.windowCenterWidth = WindowPlacementEngine.clampedCenterWidth($0) })
    }

    private var options: some View {
        Section {
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
