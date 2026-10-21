import Foundation

@main
struct FolderCommandTest {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        typealias File = FolderCommand.File
        let commands = FolderCommand.commands(from: [
            File(name: "rejoin-lines.sh", isExecutable: true),
            File(name: "hide_whitespace", isExecutable: true),
            File(name: "README.md", isExecutable: false),
            File(name: ".DS_Store", isExecutable: true),
            File(name: "Open Jira.url", isExecutable: false, firstLine: "https://jira.example.com/board"),
            File(name: "Mail Team.link", isExecutable: false, firstLine: "mailto:team@example.com"),
            File(name: "broken.url", isExecutable: false, firstLine: "jira.example.com"),
            File(name: "empty.url", isExecutable: false, firstLine: nil),
            File(name: "local.sh", isExecutable: false),
            File(name: "notes.txt", isExecutable: false),
        ])
        check("executables, shell scripts and valid link files become commands", commands.count == 5)
        check("sorted by name", commands.map(\.id) == ["hide_whitespace", "local.sh", "Mail Team.link", "Open Jira.url", "rejoin-lines.sh"])
        check("the name is the file name without its extension", commands.last?.name == "rejoin-lines")
        check("a file with no extension keeps its whole name", commands.first?.name == "hide_whitespace")
        check("a link file keeps its name", commands[3].name == "Open Jira")
        check("a link file opens its first line", commands[3].kind == .link(URL(string: "https://jira.example.com/board")!))
        check("a custom scheme is a link", commands[2].kind == .link(URL(string: "mailto:team@example.com")!))
        check("a plain .sh need not be executable", commands[1].kind == .script)
        check("an executable is a script", commands.last?.kind == .script)
        check("the name is written as the user wrote it", FolderCommand.displayName(forFile: "openJIRA board.sh") == "openJIRA board")
        check("a link needs a scheme", FolderCommand.link(from: "jira.example.com") == nil)
        check("a link is trimmed", FolderCommand.link(from: "  https://a.b/c \n") == URL(string: "https://a.b/c"))
        check("empty input is an empty folder", FolderCommand.commands(from: []).isEmpty)

        let script = commands.last!
        check("an entry id round-trips", FolderCommand.id(fromEntryID: script.entryID) == "rejoin-lines.sh")
        check("another kind's id is refused", FolderCommand.id(fromEntryID: "apple-shortcut:x") == nil)
        check("an empty id is refused", FolderCommand.id(fromEntryID: "folder-command:") == nil)
        check("a link file gets the link glyph", FolderCommand.symbol(forEntryID: commands[3].entryID) == FolderCommand.linkSymbol)
        check("a script gets the terminal glyph", script.symbol == FolderCommand.scriptSymbol)

        let stored = [script.entryID, "folder-command:gone.sh", "window-command:left-half", "com.apple.Safari"]
        let stale = FolderCommand.staleIDs(referencedBy: stored, bound: ["Open Jira.url", "also-gone.url"], live: commands)
        check("only ids the folder no longer holds are stale", stale == ["gone.sh", "also-gone.url"])
        check("an empty folder frees everything it once held", FolderCommand.staleIDs(referencedBy: stored, bound: [], live: []) == ["rejoin-lines.sh", "gone.sh"])

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) failed")
        if failures > 0 { exit(1) }
    }
}
