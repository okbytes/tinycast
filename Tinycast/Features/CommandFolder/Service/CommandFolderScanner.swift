import Foundation

/// Reads the command folder into the listing the model turns into commands.
enum CommandFolderScanner {
    /// Nil when the folder is missing or unreadable, which must never read as an empty folder.
    nonisolated static func scan(_ folder: URL) -> [FolderCommand]? {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: folder.path) else { return nil }
        let files = names.compactMap { name -> FolderCommand.File? in
            let url = folder.appending(path: name)
            var isDirectory: ObjCBool = false
            // Follows a symlink, so a linked script counts and a linked folder does not.
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                !isDirectory.boolValue
            else { return nil }
            return FolderCommand.File(
                name: name, isExecutable: manager.isExecutableFile(atPath: url.path),
                firstLine: FolderCommand.isLinkFile(name) ? firstLine(of: url) : nil)
        }
        return FolderCommand.commands(from: files)
    }

    private nonisolated static func firstLine(of url: URL) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return contents.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
