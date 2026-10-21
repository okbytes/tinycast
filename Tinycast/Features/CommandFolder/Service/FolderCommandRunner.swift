import Foundation

/// Runs a script from the command folder in a login shell, so it sees the user's PATH.
enum FolderCommandRunner {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private static let shell = URL(fileURLWithPath: "/bin/zsh")

    /// Never timed out: a script may wait on a dialog of its own. Silent unless it fails.
    static func run(script: URL, isExecutable: Bool, in directory: URL) async throws(Failure) {
        // An executable keeps its shebang through `exec`; anything else is zsh's to read.
        let arguments =
            isExecutable ? ["-lc", "exec \"$0\"", script.path] : ["-l", script.path]
        let result: ToolRunner.Result
        do {
            result = try await ToolRunner.run(
                shell, arguments, timeout: nil, currentDirectory: directory)
        } catch {
            throw Failure(errorDescription: error.localizedDescription)
        }
        guard result.succeeded else { throw Failure(errorDescription: result.tail) }
    }
}
