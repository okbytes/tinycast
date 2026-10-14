import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    private var keyRemap: KeyRemapManager { core.keyRemap }
    private var launcherRanking: LauncherRankingStore { core.launcherRanking }
    @State private var confirmingRankingReset = false
    @State private var inputSources: [InputSourceSwitcher.Option] = []

    /// The Hyper modifier chord as prose glyphs, tracking the Include Shift toggle.
    private var hyperGlyphs: String { settings.hyperKeyIncludesShift ? "⌃⌥⇧⌘" : "⌃⌥⌘" }

    /// Only a choice made here resets Quick Press: settings.json may set both keys at once.
    private var hyperKeySelection: Binding<HyperKeyPhysicalKey> {
        Binding(
            get: { settings.hyperKey },
            set: { key in
                guard key != settings.hyperKey else { return }
                settings.hyperKey = key
                // A Quick Press choice is meaningless for a different key.
                settings.hyperKeyQuickPress = .none
                if key == settings.mehKey { settings.mehKey = .none }
            })
    }

    /// The Hyper key is not offered, unless an import already put it here and it must still show.
    private var mehKeyChoices: [HyperKeyPhysicalKey] {
        HyperKeyPhysicalKey.allCases.filter {
            $0 == .none || $0 != settings.hyperKey || $0 == settings.mehKey
        }
    }

    private var mehKeySelection: Binding<HyperKeyPhysicalKey> {
        Binding(
            get: { settings.mehKey },
            set: { settings.mehKey = $0 })
    }

    private var mehSubtitle: String {
        guard settings.mehKey != .none else { return "Remap one key to ⌃⌥⇧ held together." }
        return "\(settings.mehKey.title) sends ⌃⌥⇧."
    }

    /// The missing-setup half is its own row, so it can carry the button that fixes it.
    private var hyperSubtitle: String {
        guard settings.hyperKey != .none else { return "Remap one key to \(hyperGlyphs) held together." }
        return "\(settings.hyperKey.title) sends \(hyperGlyphs), shown as ✦ in shortcuts."
    }

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                SettingsRow(title: "App Launcher", anchor: .generalGlobalShortcuts) {
                    ShortcutRecorder(action: .togglePalette)
                }
            } header: {
                SettingsSectionHeader(.generalGlobalShortcuts)
            }

            Section {
                Toggle(isOn: $settings.launchAtLogin) {
                    SettingsRowTitle(.generalGeneral, "Launch at login")
                }
                Toggle(isOn: $settings.showInMenuBar) {
                    SettingsRowTitle(.generalGeneral, "Show in menu bar")
                    Text("Shortcuts still work when hidden.")
                }
                Picker(selection: $settings.popToRootTimeout) {
                    ForEach(PopToRootTimeout.allCases) { timeout in
                        Text(timeout.title).tag(timeout)
                    }
                } label: {
                    SettingsRowTitle(.generalGeneral, "Pop to Root Search")
                    Text("After the launcher closes.")
                }
                Picker(selection: $settings.escapeKeyBehavior) {
                    ForEach(EscapeKeyBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                } label: {
                    SettingsRowTitle(.generalGeneral, "Escape Key Behavior")
                    Text("When the search field is empty.")
                }
                // Empty only when TIS fails; one layout still lists, so the row stays put.
                if !inputSources.isEmpty {
                    Picker(selection: $settings.autoSwitchInputSourceID) {
                        Text("None").tag(nil as String?)
                        ForEach(inputSources) { source in
                            Text(source.title).tag(Optional(source.id))
                        }
                    } label: {
                        SettingsRowTitle(.generalGeneral, "Auto-switch input source")
                        Text("While the launcher is open.")
                    }
                }
            } header: {
                SettingsSectionHeader(.generalGeneral)
            }

            Section {
                Picker(selection: hyperKeySelection) {
                    ForEach(HyperKeyPhysicalKey.allCases) { key in
                        Text(key.title).tag(key)
                    }
                } label: {
                    SettingsRowTitle(.generalHyperKey, "Hyper Key")
                    Text(hyperSubtitle)
                }

                KeyRemapStatusRow(status: keyRemap.status)

                if settings.hyperKey.hasOriginalFunction {
                    Picker(selection: $settings.hyperKeyQuickPress) {
                        Text("Does Nothing").tag(HyperKeyQuickPress.none)
                        if let original = settings.hyperKey.quickPressOriginalTitle {
                            Text(original).tag(HyperKeyQuickPress.originalKey)
                        }
                        Text("Trigger Escape").tag(HyperKeyQuickPress.escape)
                    } label: {
                        SettingsRowTitle(.generalHyperKey, "Quick Press")
                        Text("When \(settings.hyperKey.title) is pressed alone.")
                    }
                }

                Toggle(isOn: $settings.hyperKeyIncludesShift) {
                    SettingsRowTitle(.generalHyperKey, "Include Shift (⇧)")
                }
                // Flipping it re-points recorded chords, so it needs a chord to mean.
                .settingsEnabled(settings.hyperKey != .none)

                Picker(selection: mehKeySelection) {
                    ForEach(mehKeyChoices) { key in
                        Text(key.title).tag(key)
                    }
                } label: {
                    SettingsRowTitle(.generalHyperKey, "Meh Key")
                    Text(mehSubtitle)
                }
            } header: {
                SettingsSectionHeader(.generalHyperKey)
            }

            Section {
                Picker(selection: $settings.calcNumberStyle) {
                    ForEach(CalcNumberStyle.allCases) { style in
                        let sample = core.regionNumberFormat.format(for: style).localized("1,234,567.89")
                        Text("\(style.title) (\(sample))").tag(style)
                    }
                } label: {
                    SettingsRowTitle(.generalCalculator, "Number format")
                    Text("With a decimal comma, ; separates arguments.")
                }
            } header: {
                SettingsSectionHeader(.generalCalculator)
            }

            Section {
                Toggle(isOn: $settings.launcherShowsSuggestions) {
                    SettingsRowTitle(.generalSearch, "Show suggestions")
                    Text("What you open most, while the search field is empty.")
                }
                Picker(selection: $settings.rootSearchSensitivity) {
                    ForEach(SearchSensitivity.allCases) { sensitivity in
                        Text(sensitivity.title).tag(sensitivity)
                    }
                } label: {
                    SettingsRowTitle(.generalSearch, "Search sensitivity")
                    Text("Lower finds names from scattered letters.")
                }
                LabeledContent {
                    Button("Reset…", role: .destructive) {
                        confirmingRankingReset = true
                    }
                    .disabled(launcherRanking.isEmpty)
                } label: {
                    SettingsRowTitle(.generalSearch, "Learned ranking")
                    Text("Learned privately from the results you pick.")
                }
            } header: {
                SettingsSectionHeader(.generalSearch)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.general)
        .confirmationDialog(
            "Reset learned launcher ranking?",
            isPresented: $confirmingRankingReset,
            titleVisibility: .visible
        ) {
            Button("Reset Ranking", role: .destructive) {
                launcherRanking.resetAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tinycast will relearn your preferred results as you use the launcher.")
        }
        .onAppear(perform: refreshInputSources)
        .onReceive(
            DistributedNotificationCenter.default().publisher(
                for: InputSourceSwitcher.sourcesDidChange)
        ) { _ in
            refreshInputSources()
        }
    }

    private func refreshInputSources() {
        inputSources = core.inputSourceSwitcher.options(selecting: settings.autoSwitchInputSourceID)
    }
}


/// What still stands between a bound key and a working remap, with the button that fixes it.
private struct KeyRemapStatusRow: View {
    let status: KeyRemapManager.Status
    @Environment(\.openURL) private var openURL

    private struct Problem {
        let message: String
        var action: String?
        var fix: (@MainActor @Sendable () -> Void)?
    }

    var body: some View {
        if let problem {
            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .frame(width: Theme.Size.settingsRowIcon)
                Text(problem.message)
                    .foregroundStyle(.orange)
                Spacer(minLength: Theme.Spacing.lg)
                if let action = problem.action, let fix = problem.fix {
                    Button(action, action: fix)
                }
            }
        }
    }

    private var problem: Problem? {
        let getDriver: @MainActor @Sendable () -> Void = { [openURL] in
            openURL(KeyRemapManager.driverDownloadURL)
        }
        switch status {
        case .off, .starting, .active:
            return nil
        case .driverMissing:
            return Problem(
                message: "Remapping needs the Karabiner virtual keyboard driver.",
                action: "Get Driver…", fix: getDriver)
        case .driverUnsupported:
            return Problem(
                message: "This version of the keyboard driver isn't supported.",
                action: "Get Driver…", fix: getDriver)
        case .helperUnreachable:
            return Problem(
                message: "Tinycast can't reach its keyboard helper. It needs a build signed with a team ID.")
        case .noBuiltInKeyboard:
            return Problem(message: "This Mac has no built-in keyboard to remap.")
        case .keyboardInUse:
            return Problem(message: "Another app, such as Karabiner-Elements, is holding the keyboard.")
        case .needsApproval:
            return Problem(
                message: "Allow Tinycast's keyboard helper to run.",
                action: "Open Login Items…", fix: KeyRemapManager.openLoginItemsSettings)
        case .driverNotRunning:
            return Problem(
                message: "The keyboard driver isn't running. Allow it under Driver Extensions.",
                action: "Open Settings…", fix: KeyRemapManager.openLoginItemsSettings)
        case .needsInputMonitoring:
            return Problem(
                message: "Add Tinycast's keyboard helper under Input Monitoring.",
                action: "Show Helper…", fix: KeyRemapManager.showHelperInInputMonitoring)
        }
    }
}
