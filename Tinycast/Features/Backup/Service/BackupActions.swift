import AppKit
import UniformTypeIdentifiers

extension UTType {
    /// Not per-channel: a UTI names an interchange format, so Dev must read stable's exports.
    static let tinycastBackup = UTType(exportedAs: "com.tinycast.backup")
}

/// The backup flows' entry points, shared by the Settings pane and the commands.
@MainActor
enum BackupActions {
    // MARK: - File panels (dialogs come from `AppCore`)

    /// An accessory app must activate first, or the panel opens behind.
    private static func chooseSaveLocation() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.tinycastBackup]
        let ext = UTType.tinycastBackup.preferredFilenameExtension ?? "json"
        panel.nameFieldStringValue = "Tinycast-\(dateStamp()).\(ext)"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func chooseBackupFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.tinycastBackup]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    // MARK: - Tinycast backups

    /// Composes off-main, then seals — a clipboard history runs to gigabytes.
    static func exportBackup(
        core: AppCore, categories: Set<BackupCategory>
    ) async throws
        -> BackupComposer.Result
    {
        guard let destination = chooseSaveLocation() else {
            throw CancellationError()
        }
        let plan = BackupComposer.plan(categories, from: core)
        return try await Task.detached(priority: .userInitiated) {
            let staging = try BackupStaging()
            defer { staging.discard() }
            let result = try BackupComposer.write(plan, into: staging.bundle)
            try BackupArchive.seal(directory: staging.root, into: destination)
            return result
        }.value
    }

    /// Opens the archive and reads its manifest, leaving staging for the caller to apply and discard.
    static func openBackup(at file: URL) async throws -> (BackupStaging, BackupManifest) {
        try await Task.detached(priority: .userInitiated) {
            let staging = try BackupStaging()
            do {
                try BackupArchive.open(file: file, into: staging.root)
                return (staging, try staging.bundle.readManifest())
            } catch {
                staging.discard()
                throw error
            }
        }.value
    }

    static func applyBackup(
        _ categories: Set<BackupCategory>, from staging: BackupStaging, to core: AppCore
    ) async -> BackupApplier.Summary {
        await BackupApplier.apply(categories, from: staging.bundle, to: core)
    }

    /// The launcher has no picker, so its commands take everything; the pane is where you choose.
    static func runExportCommand(core: AppCore) async {
        do {
            let result = try await exportBackup(core: core, categories: BackupCategory.all)
            await present(
                core: core, title: "Backup Exported", message: exportText(result),
                symbol: exportSymbol, tone: .success)
        } catch is CancellationError {
        } catch {
            await present(
                core: core, title: "Export Failed", message: error.localizedDescription,
                symbol: exportSymbol)
        }
    }

    static func runImportCommand(core: AppCore) async {
        guard let file = chooseBackupFile() else { return }
        do {
            let (staging, manifest) = try await openBackup(at: file)
            defer { staging.discard() }
            let summary = await applyBackup(manifest.categories, from: staging, to: core)
            await present(
                core: core, title: "Backup Imported", message: summaryText(summary),
                symbol: importSymbol, tone: .success)
        } catch {
            await present(
                core: core, title: "Import Failed", message: error.localizedDescription,
                symbol: importSymbol)
        }
    }

    // MARK: - Helpers

    /// One sentence per category that actually moved, so an import is never silent.
    static func summaryText(_ summary: BackupApplier.Summary) -> String {
        var parts: [String] = []
        if let settings = summary.settings, let applied = appliedText(settings) {
            parts.append(applied)
        }
        var imported: [String] = []
        if summary.clipboard > 0 { imported.append("\(summary.clipboard) clips") }
        if summary.learning > 0 { imported.append("\(summary.learning) learning records") }
        if !imported.isEmpty {
            parts.append("Imported " + imported.joined(separator: ", ") + ".")
        }
        return parts.isEmpty ? nothingImportedText : parts.joined(separator: " ")
    }

    static func exportText(_ result: BackupComposer.Result) -> String {
        let categories = BackupCategory.ordered(result.manifest.categories)
        var text =
            categories.isEmpty
            ? "Nothing was selected."
            : "Saved "
                + categories.map(\.descriptor.label)
                .joined(separator: ", ") + "."
        if result.missingImages > 0 {
            text += " \(result.missingImages) images were unavailable and skipped."
        }
        return text
    }

    static let nothingImportedText = "Nothing to import from this file."

    /// nil when no settings applied, so a caller can compose one combined sentence.
    static func appliedText(_ s: SettingsBackup.ApplySummary) -> String? {
        var parts: [String] = []
        if s.settingsFields > 0 { parts.append("\(s.settingsFields) settings") }
        if s.hotkeys > 0 { parts.append("\(s.hotkeys) shortcuts") }
        if s.favorites > 0 { parts.append("\(s.favorites) favorites") }
        if s.hiddenItems > 0 { parts.append("\(s.hiddenItems) hidden items") }
        if s.aliases > 0 { parts.append("\(s.aliases) aliases") }
        if s.pinnedEmoji > 0 { parts.append("\(s.pinnedEmoji) pinned emoji and symbols") }
        guard !parts.isEmpty else { return nil }
        return "Applied " + parts.joined(separator: ", ") + "."
    }

    // MARK: - Settings file

    /// Where settings.json lives for this channel, as the pane and its dialog spell it.
    static var settingsFilePath: String {
        (AppPaths.settingsFile().path as NSString).abbreviatingWithTildeInPath
    }

    /// Turning the mirror on over a file that already exists asks which side wins.
    static func setSettingsFileEnabled(_ enabled: Bool, core: AppCore) async {
        guard enabled else { return core.stopSettingsFile() }
        guard FileManager.default.fileExists(atPath: AppPaths.settingsFile().path) else {
            return core.startSettingsFile(importing: false)
        }
        let choice = await core.choose(
            title: "Import the existing settings file?",
            message:
                "\(settingsFilePath) already exists. Import applies its settings here; Replace "
                + "overwrites it with the current ones.",
            symbol: importSymbol,
            options: [
                DialogAction(title: "Import"),
                DialogAction(title: "Replace", role: .destructive),
                DialogAction(title: "Cancel", role: .cancel)
            ],
            defaultIndex: 0)
        switch choice {
        case 0: core.startSettingsFile(importing: true)
        case 1: core.startSettingsFile(importing: false)
        default: break
        }
    }

    static func revealSettingsFile() {
        AppLauncher.showInFinder(AppPaths.settingsFile())
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Every import dialog carries the same glyph, so the flow reads as one thing.
    private static let importSymbol = "square.and.arrow.down"
    private static let exportSymbol = "square.and.arrow.up"

    private static func present(
        core: AppCore, title: String, message: String, symbol: String, tone: DialogTone = .danger
    ) async {
        await core.showNotice(title: title, message: message, symbol: symbol, tone: tone)
    }
}
