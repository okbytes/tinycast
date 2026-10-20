import AppKit
import UniformTypeIdentifiers

/// Writes the last days of the `dock-watch` and `window-management` log to a file the user picks.
/// See docs/features/window-management.md#recording-dock-episodes.
enum DockLogExport {
    static let days = 3
    private static let predicate =
        "subsystem == \"com.tinycast.app\" AND "
        + "(category == \"dock-watch\" OR category == \"window-management\")"

    /// Nil when the save panel is dismissed; the file is revealed once written.
    @MainActor
    static func run() async throws -> URL? {
        guard let destination = chooseSaveLocation() else { return nil }
        let result = try await ToolRunner.run(
            URL(fileURLWithPath: "/usr/bin/log"),
            ["show", "--style", "compact", "--last", "\(days)d", "--predicate", predicate])
        guard result.succeeded else {
            throw ExportFailure(reason: result.tail)
        }
        let text = header() + result.output
        try text.write(to: destination, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([destination])
        return destination
    }

    struct ExportFailure: LocalizedError {
        let reason: String
        var errorDescription: String? { "log show failed: \(reason)" }
    }

    /// The facts a reader needs beside the lines: build, OS, Dock settings and the screens now.
    @MainActor
    private static func header() -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let dock = UserDefaults(suiteName: "com.apple.dock")
        let dockSettings = [
            "autohide \(dock?.bool(forKey: "autohide") ?? false)",
            "orientation \(dock?.string(forKey: "orientation") ?? "bottom")",
            "tilesize \(dock?.integer(forKey: "tilesize") ?? 0)",
            "magnification \(dock?.bool(forKey: "magnification") ?? false)",
        ].joined(separator: ", ")
        let screens = NSScreen.screens.map { screen in
            "\(screen.localizedName) frame \(screen.frame) visible \(screen.visibleFrame)"
        }.joined(separator: "; ")
        return """
            Tinycast \(version) (\(build)) on \(os), exported \(Date().ISO8601Format())
            Dock: \(dockSettings)
            Screens: \(screens)

            """
    }

    /// An accessory app must activate first, or the panel opens behind.
    @MainActor
    private static func chooseSaveLocation() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Tinycast Dock Log \(dateStamp()).txt"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
