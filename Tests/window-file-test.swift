// Window commands' shortcuts and aliases as settings.json spells them: round trips, bad entries.

import Foundation

@main
@MainActor
struct WindowFileTest {
    static var failures = 0

    static func main() {
        testCommandShortcuts()
        testCommandAliases()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private static func testCommandShortcuts() {
        let json = WindowManagementFileFormat.json(commandShortcuts: [.half: "ctrl+option+left"])
        let members = json.members ?? []
        check("every command is listed", members.count == WindowCommand.ID.allCases.count)
        check("in catalog order", members.first?.key == WindowCommand.ID.allCases.first?.rawValue)
        check("a bound one carries its chord", json["half"] == "ctrl+option+left")
        check("an unbound one is null", json["quarter"] == .null)

        let decoded = WindowManagementFileFormat.commandShortcuts(from: json)
        check(
            "the list reads back",
            decoded?.texts[.half] == "ctrl+option+left" && decoded?.texts[.quarter] == .some(nil))
        check("with nothing to report", decoded?.problems == [])

        let edited = WindowManagementFileFormat.commandShortcuts(
            from: .object(["half": 1, "no-such-command": "cmd+k"]))
        check(
            "a number is not a chord, so that command keeps its own",
            edited?.texts.keys.contains(.half) == false)
        check("one left out is unbound", edited?.texts[.quarter] == .some(nil))
        check("both mistakes are reported", edited?.problems.count == 2)
        check("a list is not an object", WindowManagementFileFormat.commandShortcuts(from: .array([])) == nil)
    }

    private static func testCommandAliases() {
        let json = WindowManagementFileFormat.json(commandAliases: [.half: "lh"])
        check("only a command with an alias is listed", json.members?.map(\.key) == ["half"])

        let decoded = WindowManagementFileFormat.commandAliases(from: json)
        check("the aliases read back", decoded?.texts[.half] == "lh")

        let edited = WindowManagementFileFormat.commandAliases(from: .object(["half": true]))
        check(
            "a flag is not an alias, so the command keeps its own, and is reported",
            edited?.texts.keys.contains(.half) == false && edited?.problems.count == 1)
    }

    private static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }
}
