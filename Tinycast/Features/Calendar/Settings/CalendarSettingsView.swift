import SwiftUI

struct CalendarSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @Environment(CalendarStore.self) private var store

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    SettingsFeatureToggleLabel(
                        anchor: .calendarCalendar, title: "Enable calendar",
                        subtitle:
                            "Reads \(settings.calendarSpan.possessivePhrase) events "
                            + "for the menu bar. Nothing leaves this Mac.")
                }
            }
            .settingsAnchor(.calendarCalendar)

            if settings.calendarEnabled, store.access == .notDetermined {
                Section {
                    SettingsRow(
                        title: "Calendar access is needed",
                        subtitle: "Needed to read events for the menu bar."
                    ) {
                        Button("Allow Calendar Access…") {
                            core.calendarCoordinator.setCalendarEnabled(true)
                        }
                    }
                }
            } else if store.access == .denied {
                Section {
                    SettingsRow(
                        title: "Calendar access is off",
                        subtitle: "Allow it in Privacy & Security ▸ Calendars."
                    ) {
                        Button("Open System Settings…") { Permissions.openCalendarSettings() }
                    }
                }
            }

            Section {
                Picker(selection: $settings.calendarMenuBarDisplay) {
                    ForEach(CalendarMenuBarDisplay.allCases) { display in
                        Text(display.title).tag(display)
                    }
                } label: {
                    SettingsRowTitle(.calendarMenuBar, "Calendar in Menu Bar")
                    Text("Separate from the Tinycast icon.")
                }
                Picker(selection: $settings.calendarSpan) {
                    ForEach(MeetingSpan.allCases) { span in
                        Text(span.title).tag(span)
                    }
                } label: {
                    SettingsRowTitle(.calendarMenuBar, "Days to Show")
                    Text("Listed in the menu.")
                }
                Picker(selection: $settings.menuBarEvents) {
                    ForEach(MenuBarEvents.allCases) { lead in
                        Text(lead.title).tag(lead)
                    }
                } label: {
                    SettingsRowTitle(.calendarMenuBar, "Show Upcoming Events")
                    Text("When the next event appears.")
                }
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
                Toggle(isOn: $settings.menuBarLinkedEventsOnly) {
                    SettingsRowTitle(.calendarMenuBar, "Only show events with meetings")
                }
                .toggleStyle(.checkbox)
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
                Toggle(isOn: $settings.calendarMenuBarHidesWhenEmpty) {
                    SettingsRowTitle(.calendarMenuBar, "Hide when there are no upcoming events")
                }
                .toggleStyle(.checkbox)
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
                Picker(selection: $settings.hideCurrentEvent) {
                    ForEach(HideCurrentEvent.allCases) { hide in
                        Text(hide.title).tag(hide)
                    }
                } label: {
                    SettingsRowTitle(.calendarMenuBar, "Hide Current Event")
                    Text("Once it has started.")
                }
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
            } header: {
                SettingsSectionHeader(.calendarMenuBar)
            }
            .settingsEnabled(settings.calendarEnabled)

            CalendarPickerSection()
                .settingsEnabled(settings.calendarEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.calendar)
        .releasesFocusOnOutsideClick()
        // The snapshot is only reloaded while the feature runs, so a grant made in Settings lands here.
        .onAppear { store.refreshAccess() }
    }

    /// Routed through the coordinator so enabling, which is also consent, confirms first.
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.calendarEnabled },
            set: { core.calendarCoordinator.setCalendarEnabled($0) }
        )
    }
}

/// Machine-local by nature, so these live on the store and never travel in a backup.
private struct CalendarPickerSection: View {
    @Environment(CalendarStore.self) private var store
    @State private var query = ""

    private var calendars: [MeetingCalendar] {
        guard !query.isEmpty else { return store.calendars }
        return store.calendars.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.accountName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Section {
            SettingsFilterField(prompt: "Search calendars…", query: $query)

            if calendars.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(calendars) { calendar in
                    CalendarRow(calendar: calendar)
                }
            }
        } header: {
            SettingsSectionHeader(.calendarCalendars)
        }
    }

    private var emptyMessage: String {
        if !query.isEmpty { return "No matches for “\(query)”." }
        return store.access == .granted ? "No calendars on this Mac." : "Nothing to show yet."
    }
}

private struct CalendarRow: View {
    let calendar: MeetingCalendar
    @Environment(CalendarStore.self) private var store

    var body: some View {
        SettingsRow(title: calendar.title, subtitle: calendar.accountName) {
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel("Include \(calendar.title) in meetings")
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { store.isEnabled(calendar) },
            set: { store.setEnabled($0, for: calendar) }
        )
    }
}
