import Foundation

/// A file in the command folder: an executable to run, or a `.url` file naming a link to open.
struct FolderCommand: Hashable, Identifiable, Sendable {
    enum Kind: Hashable, Sendable {
        case script
        case link(URL)
    }

    /// What the scanner reads of one file; the model decides what, if anything, it makes.
    struct File: Hashable, Sendable {
        let name: String
        let isExecutable: Bool
        /// The first line, read only for a link file.
        let firstLine: String?

        init(name: String, isExecutable: Bool, firstLine: String? = nil) {
            self.name = name
            self.isExecutable = isExecutable
            self.firstLine = firstLine
        }
    }

    static let entryIDPrefix = "folder-command:"
    static let scriptSymbol = "terminal"
    static let linkSymbol = "link"
    static let linkExtensions: Set<String> = ["url", "link"]
    /// A shell script need not be executable: the login shell runs it either way.
    static let scriptExtensions: Set<String> = ["sh", "zsh", "bash", "command"]

    /// The file name is the identity: a renamed file is a new command, as it is a new file.
    let id: String
    let name: String
    let kind: Kind

    var entryID: String { Self.entryID(for: id) }

    var symbol: String { Self.symbol(forFile: id) }

    static func entryID(for id: String) -> String { entryIDPrefix + id }

    static func id(fromEntryID entryID: String) -> String? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        let id = String(entryID.dropFirst(entryIDPrefix.count))
        return id.isEmpty ? nil : id
    }

    static func symbol(forEntryID entryID: String) -> String {
        id(fromEntryID: entryID).map(symbol(forFile:)) ?? scriptSymbol
    }

    static func isLinkFile(_ name: String) -> Bool {
        linkExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// Every file that makes a command, sorted by name. The rest of the folder is simply ignored.
    static func commands(from files: [File]) -> [FolderCommand] {
        files.compactMap(command(from:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The file name without its extension, exactly as written: `chatgpt.link` is "chatgpt".
    static func displayName(forFile name: String) -> String {
        (name as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
    }

    /// A link needs a scheme: a bare domain would open nothing, so it is not a command.
    static func link(from line: String?) -> URL? {
        guard let line = line?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty,
            let url = URL(string: line), let scheme = url.scheme, !scheme.isEmpty
        else { return nil }
        return url
    }

    /// Commands a stored preference or binding still names that the folder no longer holds.
    static func staleIDs(
        referencedBy keys: some Sequence<String>, bound: some Sequence<String>,
        live: [FolderCommand]
    ) -> Set<String> {
        let referenced = Set(keys.lazy.compactMap(id(fromEntryID:))).union(bound)
        return referenced.subtracting(live.map(\.id))
    }

    private static func command(from file: File) -> FolderCommand? {
        guard !file.name.hasPrefix(".") else { return nil }
        let name = displayName(forFile: file.name)
        guard !name.isEmpty else { return nil }
        if isLinkFile(file.name) {
            guard let url = link(from: file.firstLine) else { return nil }
            return FolderCommand(id: file.name, name: name, kind: .link(url))
        }
        guard file.isExecutable || isScriptFile(file.name) else { return nil }
        return FolderCommand(id: file.name, name: name, kind: .script)
    }

    static func isScriptFile(_ name: String) -> Bool {
        scriptExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    private static func symbol(forFile name: String) -> String {
        isLinkFile(name) ? linkSymbol : scriptSymbol
    }
}
