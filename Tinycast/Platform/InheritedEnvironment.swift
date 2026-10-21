import Foundation

/// What Tinycast was launched with and must not pass on. docs/architecture.md#entry-points-and-windows
enum InheritedEnvironment {
    /// Shortcuts' shell actions export this, and a Shortcut relaunching Tinycast hands it down.
    private static let tempDirSuffixKey = "DIRHELPER_USER_DIR_SUFFIX"

    /// With the suffix set, every opened app gets a temp folder too long for a Unix socket path.
    static func clearTempDirSuffix() {
        guard getenv(tempDirSuffixKey) != nil else { return }
        unsetenv(tempDirSuffixKey)
        var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX))
        // Unsuffixed once the variable is gone; TMPDIR still carries the long path until reset.
        let length = buffer.withUnsafeMutableBufferPointer { raw in
            raw.withMemoryRebound(to: CChar.self) {
                confstr(_CS_DARWIN_USER_TEMP_DIR, $0.baseAddress, $0.count)
            }
        }
        guard length > 1, length <= buffer.count else { return }
        setenv("TMPDIR", String(decoding: buffer.prefix(length - 1), as: UTF8.self), 1)
    }
}
