import SwiftUI
import UniformTypeIdentifiers

/// The editable list of folders (and individual `.app` bundles) the launcher indexes.
struct SearchScopesSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SettingsNavigationState.self) private var navigation
    /// Recomputed only on change: a `fileExists` per row is too much per body render.
    @State private var missing: Set<String> = []
    /// Collapsed by default: it is set once and would otherwise push the app list off screen.
    @State private var isExpanded = false

    private var isDefault: Bool { settings.searchScopes == SearchScopes.defaults }

    var body: some View {
        Section(isExpanded: $isExpanded) {
            ForEach(settings.searchScopes, id: \.self) { scope in
                SettingsScopeRow(
                    scope: scope, path: SearchScopes.expand(scope),
                    isMissing: missing.contains(scope)
                ) {
                    settings.searchScopes.removeAll { $0 == scope }
                }
            }

            HStack(spacing: Theme.Spacing.lg) {
                Button("Add…", action: addScopes)
                    .help("Add a folder or application to search.")
                if !isDefault {
                    Button("Restore Defaults") { settings.searchScopes = SearchScopes.defaults }
                }
            }
        } header: {
            SettingsSectionHeader(.applicationsSearchScopes)
        }
        .onAppear(perform: refreshMissing)
        .onChange(of: settings.searchScopes) { _, _ in refreshMissing() }
        .onChange(of: navigation.scrollRequest, initial: true) { _, request in
            if request?.target.anchor == .applicationsSearchScopes { isExpanded = true }
        }
    }

    private func refreshMissing() {
        let fm = FileManager.default
        missing = Set(
            settings.searchScopes.filter { !fm.fileExists(atPath: SearchScopes.expand($0)) })
    }

    private func addScopes() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        // Otherwise an .app is navigated into rather than selected.
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders or applications to include in the launcher."
        // Tinycast is an accessory app, so the panel opens behind the frontmost app without this.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        settings.searchScopes = SearchScopes.normalize(
            settings.searchScopes + panel.urls.map(\.path))
    }
}
