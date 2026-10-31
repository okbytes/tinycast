import Foundation

/// Which directory entries belong to an app, from names alone. See docs/features/uninstall.md.
enum UninstallRules {
    /// Stripped before matching, so `com.foo.Bar.plist` compares as `com.foo.Bar`.
    static let strippedExtensions: Set<String> = [
        "plist", "savedstate", "binarycookies", "lockfile", "lock", "sfl", "sfl2", "sfl3",
        "ips", "diag", "crash", "spin",
        // Plug-in wrappers, named after the product that installed them.
        "qlgenerator", "saver", "prefpane", "service", "workflow", "mdimporter", "appex",
        "component", "wdgt", "dext", "driver", "osax", "colorpicker", "plugin", "bundle",
        "vst", "vst3", "clap"
    ]

    /// The name plus each stripped form; stripping only adds comparisons, never removes one.
    static func matchableForms(_ name: String) -> [String] {
        var forms = [name]
        var current = name
        for _ in 0..<3 {
            let ext = (current as NSString).pathExtension.lowercased()
            guard !ext.isEmpty, strippedExtensions.contains(ext) else { break }
            let stripped = (current as NSString).deletingPathExtension
            guard !stripped.isEmpty else { break }
            forms.append(stripped)
            current = stripped
        }
        return forms
    }

    /// `-` counts: vendors name variants that way, unless the variant is itself installed.
    private static let namespaceSeparators: Set<Character> = [".", "-"]

    /// The bundle ID itself, or a namespaced child of it.
    static func matchesBundleID(_ component: String, identity: UninstallIdentity) -> Bool {
        guard let id = identity.bundleID else { return false }
        return matchableForms(component).contains { form in
            let folded = UninstallIdentity.folded(form)
            guard owns(folded, id: id, allowingPrefix: identity.allowsBundleIDPrefixMatch)
            else { return false }
            // A longer-ID sibling owns its own artifacts, so channels can't claim each other.
            return !identity.otherBundleIDs.contains { other in
                other.count > id.count && owns(folded, id: other, allowingPrefix: true)
            }
        }
    }

    private static func owns(_ folded: String, id: String, allowingPrefix: Bool) -> Bool {
        if folded == id { return true }
        guard allowingPrefix, folded.count > id.count, folded.hasPrefix(id) else { return false }
        // The separator stops `com.apple.SafariTechnologyPreview` reading as Safari's child.
        return namespaceSeparators.contains(folded[folded.index(folded.startIndex, offsetBy: id.count)])
    }

    /// Attribution by link target, never by name — the name is whatever the vendor chose.
    static func isBundleSymlink(target: String, bundlePath: String) -> Bool {
        let target = (target as NSString).standardizingPath
        let bundlePath = (bundlePath as NSString).standardizingPath
        return target == bundlePath || isDescendant(target, of: bundlePath)
    }

    /// Strips a leading `group.` and/or Team ID; the strict 10-char shape stops false hits.
    static func groupContainerBase(_ component: String) -> String {
        var base = component
        for _ in 0..<2 {
            if base.lowercased().hasPrefix("group.") {
                base = String(base.dropFirst("group.".count))
                continue
            }
            guard let dot = base.firstIndex(of: "."), isTeamID(String(base[base.startIndex..<dot]))
            else { break }
            base = String(base[base.index(after: dot)...])
        }
        return base
    }

    static func isTeamID(_ value: String) -> Bool {
        value.count == 10
            && value.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) && !$0.isLowercase }
    }

    static func matchesGroupContainer(_ component: String, identity: UninstallIdentity) -> Bool {
        matchesBundleID(groupContainerBase(component), identity: identity)
    }

    /// The company folder itself (`Google`), which holds every product from that company.
    static func isSharedVendorFolder(_ name: String, identity: UninstallIdentity) -> Bool {
        guard let vendor = vendorParts(identity) else { return false }
        let folder = UninstallIdentity.folded(name)
        return folder == vendor.token || folder == vendor.prefixed || folder == vendor.token + "software"
    }

    /// `Apple` under Library is the system's shared folder, not one company's.
    private static func vendorParts(
        _ identity: UninstallIdentity
    ) -> (token: String, prefixed: String)? {
        guard let id = identity.bundleID else { return nil }
        let parts = id.split(separator: ".").map(String.init)
        guard parts.count >= 3 else { return nil }
        let token = parts[1]
        guard token != "apple", token.count >= 3 else { return nil }
        return (token, parts[0] + "." + token)
    }

    /// Exact folded equality: no prefix, no substring, so "Books" can't claim "Books Reader".
    static func matchesDisplayName(_ component: String, identity: UninstallIdentity) -> Bool {
        guard !identity.names.isEmpty else { return false }
        return matchableForms(component).contains { form in
            identity.names.contains(UninstallIdentity.folded(form))
        }
    }

    static func evidence(
        for name: String, in root: UninstallSearchRoot, identity: UninstallIdentity
    ) -> UninstallEvidence? {
        if root.styles.contains(.report), let evidence = reportEvidence(for: name, identity: identity) {
            return evidence
        }
        if root.styles.contains(.bundleID), matchesBundleID(name, identity: identity) {
            return .bundleID
        }
        if root.styles.contains(.groupContainer), matchesGroupContainer(name, identity: identity) {
            return .groupContainer
        }
        if root.styles.contains(.displayName), matchesDisplayName(name, identity: identity) {
            return .displayName
        }
        return nil
    }

    /// Crash reports put the app name, then `_` or `-`, then a timestamp or UUID.
    static func reportEvidence(
        for name: String, identity: UninstallIdentity
    ) -> UninstallEvidence? {
        for form in matchableForms(name) {
            let folded = UninstallIdentity.folded(form)
            if identity.otherBundleIDs.contains(where: {
                folded == $0 || isReportName(folded, token: $0)
            }) { return nil }
        }
        if matchesBundleID(name, identity: identity) { return .bundleID }
        for form in matchableForms(name) {
            let folded = UninstallIdentity.folded(form)
            if let id = identity.bundleID, isReportName(folded, token: id) { return .bundleID }
            if identity.names.contains(where: { folded == $0 || isReportName(folded, token: $0) }) {
                return .displayName
            }
        }
        return nil
    }

    /// A launch-job program that resolves inside the bundle. The name of the plist is irrelevant.
    static func referencesBundle(
        program: String?, arguments: [String], bundlePath: String
    ) -> Bool {
        guard let executable = program ?? arguments.first, executable.hasPrefix("/") else {
            return false
        }
        return isBundleSymlink(target: executable, bundlePath: bundlePath)
    }

    static func matches(
        childNames: [String], nestedNames: [String: [String]] = [:], in root: UninstallSearchRoot,
        identity: UninstallIdentity
    ) -> [(name: String, evidence: UninstallEvidence)] {
        var claimed = Set<String>()
        var results: [(name: String, evidence: UninstallEvidence)] = []
        for name in childNames {
            guard let evidence = evidence(for: name, in: root, identity: identity) else { continue }
            // The company folder stays; the candidate is the product directory inside it.
            if root.depth >= 2, isSharedVendorFolder(name, identity: identity) { continue }
            results.append((name, evidence))
            claimed.insert(name)
        }
        guard root.depth >= 2 else { return results }
        for parent in nestedNames.keys.sorted() where !claimed.contains(parent) {
            let vendor = isSharedVendorFolder(parent, identity: identity)
            guard vendor || UninstallIdentity.folded(parent) == "cloudkit" else { continue }
            for child in nestedNames[parent] ?? [] {
                guard let evidence = evidence(for: child, in: root, identity: identity)
                else { continue }
                if evidence == .displayName, !vendor { continue }
                results.append((parent + "/" + child, evidence))
            }
        }
        return results
    }

    /// Belt and braces on every produced path, whatever matched it.
    static func isAcceptableCandidate(
        path: String, rootPath: String, home: String, bundlePath: String, maxDepth: Int = 1
    ) -> Bool {
        let rawComponents = path.split(separator: "/")
        guard !rawComponents.contains("."), !rawComponents.contains("..") else { return false }
        let path = (path as NSString).standardizingPath
        let rootPath = (rootPath as NSString).standardizingPath
        let home = (home as NSString).standardizingPath
        let bundlePath = (bundlePath as NSString).standardizingPath
        guard path.hasPrefix("/"), path != "/", path != home, path != rootPath else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty, !components.contains("."), !components.contains("..")
        else { return false }
        guard path.hasPrefix(rootPath + "/") else { return false }
        let relative = path.dropFirst(rootPath.count + 1)
        let depth = relative.split(separator: "/", omittingEmptySubsequences: false).count
        guard depth >= 1, depth <= max(maxDepth, 1) else { return false }
        guard path != bundlePath, !isDescendant(path, of: bundlePath),
            !isDescendant(bundlePath, of: path)
        else { return false }
        return true
    }

    /// `_` or `-` after the token, so Helium does not claim `Helium Helper_…`.
    private static func isReportName(_ name: String, token: String) -> Bool {
        guard name.count > token.count, name.hasPrefix(token) else { return false }
        let separator = name.index(name.startIndex, offsetBy: token.count)
        guard name[separator] == "_" || name[separator] == "-" else { return false }
        let suffix = String(name[name.index(after: separator)...])
        if UUID(uuidString: suffix) != nil { return true }
        return suffix.range(
            of: #"^\d{4}-\d{2}-\d{2}(?:[-_].*)?$"#, options: .regularExpression) != nil
    }

    static func isDescendant(_ path: String, of ancestor: String) -> Bool {
        path.hasPrefix(ancestor + "/")
    }

    /// Takes `home` rather than reading it, so it stays pure.
    static func abbreviate(_ path: String, home: String) -> String {
        if path == home { return "~" }
        guard isDescendant(path, of: home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
