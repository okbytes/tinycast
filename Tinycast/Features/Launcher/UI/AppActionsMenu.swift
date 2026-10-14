import SwiftUI

/// Actions menu for a launcher app, from right-click or the Actions pill.
@MainActor
enum AppActionsMenu {
    static func content(
        app: AppEntry, searchQuery: String, core: AppCore, running: Bool,
        onResetRanking: @escaping () -> Void, onHideFromSearch: @escaping () -> Void
    ) -> PopoverMenuContent {
        var items = leadingItems(app: app, searchQuery: searchQuery, core: core)
        let preferences = items.count
        if core.launcherRanking.hasRanking(for: app.preferenceKey) {
            items.append(
                PopoverMenuItem(title: "Reset Ranking", systemImage: "arrow.counterclockwise") {
                    onResetRanking()
                })
        }
        // A query-driven row lives only for its query, so no preference could outlive it.
        if !CommandCatalog.isQueryDriven(app), app.canHideFromSearch {
            items.append(
                PopoverMenuItem(
                    title: "Hide from Search", systemImage: "eye.slash", shortcut: "⇧⌘H",
                    action: onHideFromSearch))
        }
        if items.count > preferences { items[preferences].startsSection = true }
        if running, app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: "Restart Application", systemImage: "arrow.clockwise", startsSection: true,
                    shortcut: "⌘R"
                ) {
                    core.launcherCoordinator.restart(app)
                })
            items.append(
                PopoverMenuItem(
                    title: "Quit Application", systemImage: "power", shortcut: "⌃⇧Q"
                ) {
                    core.launcherCoordinator.quit(app)
                })
            items.append(
                PopoverMenuItem(
                    title: "Force Quit Application", systemImage: "xmark.circle", shortcut: "⌃⌥⇧Q"
                ) {
                    core.launcherCoordinator.quit(app, force: true)
                })
        }
        if app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: "Uninstall Application", systemImage: "trash", startsSection: true,
                    isDestructive: true
                ) {
                    core.uninstallCoordinator.beginUninstall(app)
                })
        }
        return PopoverMenuContent(header: app.name, items: items)
    }

    private static func leadingItems(
        app: AppEntry, searchQuery: String, core: AppCore
    ) -> [PopoverMenuItem] {
        let primarySymbol =
            switch app.kind {
            case .application, .command: "list.dash.header.rectangle"
            default: "list.bullet.rectangle"
            }
        var items = [
            PopoverMenuItem(
                title: app.kind.descriptor.openVerb, systemImage: primarySymbol,
                shortcut: "↵"
            ) { core.launcherCoordinator.launch(app, searchQuery: searchQuery) }
        ]
        if app.canRevealInFinder {
            items.append(
                PopoverMenuItem(title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵") {
                    core.launcherCoordinator.showInFinder(app)
                })
        }
        return items
    }
}
