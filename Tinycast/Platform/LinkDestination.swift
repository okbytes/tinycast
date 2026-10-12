import Foundation

/// What a link points at, detected by shape alone; a local path is not a link.
enum LinkDestination: Sendable {
    case web(URL)
    /// Any other scheme — `spotify://`, `smb://`, `shortcuts://`, `mailto:`.
    case deeplink(URL)

    static func detect(_ link: String) -> Self? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let scheme = scheme(of: trimmed) {
            guard scheme != "file", let url = url(from: trimmed) else { return nil }
            return scheme == "http" || scheme == "https" ? .web(url) : .deeplink(url)
        }
        // A bare host is how people write a website down, so it reads as https.
        guard looksLikeBareHost(trimmed), let url = url(from: "https://" + trimmed) else {
            return nil
        }
        return .web(url)
    }

    /// The lowercased scheme when the value starts with an RFC 3986 `scheme:`.
    private static func scheme(of value: String) -> String? {
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let candidate = value[value.startIndex..<colon]
        guard let first = candidate.first, first.isLetter else { return nil }
        guard candidate.dropFirst().allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" })
        else { return nil }
        // Excludes a Windows drive letter and a host:port, both commoner than what they shadow.
        guard candidate.count > 1 else { return nil }
        let remainder = value[value.index(after: colon)...]
        guard !remainder.isEmpty, !remainder.allSatisfy(\.isNumber) else { return nil }
        return candidate.lowercased()
    }

    /// A space is the one mistake worth rescuing; re-encoding would corrupt existing `%xx`.
    private static func url(from value: String) -> URL? {
        URL(string: value) ?? URL(string: value.replacingOccurrences(of: " ", with: "%20"))
    }

    private static func looksLikeBareHost(_ value: String) -> Bool {
        guard !value.contains(where: \.isWhitespace) else { return false }
        var host = value.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        if let colon = host.firstIndex(of: ":") {
            let port = host[host.index(after: colon)...]
            guard !port.isEmpty, port.allSatisfy(\.isNumber) else { return false }
            host = host[host.startIndex..<colon]
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        // Requiring a letter-led final label keeps version numbers and decimals out.
        guard let tld = labels.last, tld.count >= 2, tld.first?.isLetter == true else { return false }
        return tld.allSatisfy(\.isLetter)
    }
}
