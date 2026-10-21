import Foundation

/// What Tinycast was launched with and must not pass on. docs/architecture.md#entry-points-and-windows
enum InheritedEnvironment {
    /// What launchd gives a Dock-launched app. Anything else came from a shell or a Shortcut.
    private static let launchdVariables: Set<String> = [
        "HOME", "USER", "LOGNAME", "SHELL", "SSH_AUTH_SOCK", "COMMAND_MODE", "OSLogRateLimit",
        "XPC_FLAGS", "XPC_SERVICE_NAME", "__CFBundleIdentifier", "__CF_USER_TEXT_ENCODING",
    ]
    private static let launchdPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// Apps opened from Tinycast inherit its environment, so it is made the Dock's before any opens.
    static func adoptLaunchdEnvironment() {
        for name in variableNames() where !launchdVariables.contains(name) {
            unsetenv(name)
        }
        setenv("PATH", launchdPath, 1)
        // Read after DIRHELPER_USER_DIR_SUFFIX is gone, or Shortcuts' suffix is still in the path.
        if let temp = userTemporaryDirectory() { setenv("TMPDIR", temp, 1) }
    }

    private static func variableNames() -> [String] {
        var names: [String] = []
        var entry = environ
        while let pointer = entry.pointee {
            let variable = String(cString: pointer)
            if let equals = variable.firstIndex(of: "=") {
                names.append(String(variable[..<equals]))
            }
            entry += 1
        }
        return names
    }

    private static func userTemporaryDirectory() -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX))
        let length = buffer.withUnsafeMutableBufferPointer { raw in
            raw.withMemoryRebound(to: CChar.self) {
                confstr(_CS_DARWIN_USER_TEMP_DIR, $0.baseAddress, $0.count)
            }
        }
        guard length > 1, length <= buffer.count else { return nil }
        return String(bytes: buffer.prefix(length - 1), encoding: .utf8)
    }
}
