import SwiftUI

/// The pane column: whichever pane the history currently points at.
struct SettingsDetailView: View {
    @Environment(SettingsNavigationState.self) private var navigation

    var body: some View {
        // Not a `TabView`: `NSTabView` re-hosts on selection and breaks the recorder.
        Group {
            switch navigation.tab {
            case .general: GeneralSettingsView()
            case .applications: ApplicationsSettingsView()
            case .systemActions: SystemActionsSettingsView()
            case .commands: CommandsSettingsView()
            case .appleShortcuts: AppleShortcutsSettingsView()
            case .snippets: SnippetsSettingsView()
            case .windowManagement: WindowManagementSettingsView()
            case .clipboard: ClipboardSettingsView()
            case .emoji: EmojiSettingsView()
            case .calendar: CalendarSettingsView()
            case .permissions: PermissionsSettingsView()
            case .backup: BackupSettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // One host for every pane, above their scroll views so a callout is never clipped.
        .shortcutRecorderPopoverHost()
    }
}
