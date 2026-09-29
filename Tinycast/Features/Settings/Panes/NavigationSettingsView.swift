import SwiftUI

/// Moving somewhere — a window — rather than changing something.
struct NavigationSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.navigationEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .navigationNavigation, title: "Enable navigation",
                        subtitle: "Switch windows from the palette.")
                }
            }
            .settingsAnchor(.navigationNavigation)

            // No "show in launcher" switch: the per-command checkboxes below already are one.
            FeatureCommandsSection(owner: .navigation, anchor: .navigationCommands)
                .settingsEnabled(settings.navigationEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.navigation)
    }
}
