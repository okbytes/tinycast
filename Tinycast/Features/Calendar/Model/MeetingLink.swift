import Foundation

/// A meeting's join link and the service behind it, read out of the event's own text.
struct MeetingLink: Hashable, Sendable {
    let provider: Provider
    let url: URL

    /// Fields in precedence order; a named provider anywhere beats a bare link found earlier.
    static func detect(fields: [String?]) -> MeetingLink? {
        var fallback: MeetingLink?
        for field in fields.compactMap({ $0 }) {
            for url in webURLs(in: field) {
                guard let provider = classify(url) else { continue }
                let link = MeetingLink(provider: provider, url: url)
                if provider != .generic { return link }
                if fallback == nil { fallback = link }
            }
        }
        return fallback
    }

    static func detect(in text: String) -> MeetingLink? {
        detect(fields: [text])
    }

    /// A known host failing its path rule is rejected, never demoted to `.generic`.
    private static func classify(_ url: URL) -> Provider? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host()?.lowercased()
        else { return nil }
        guard let provider = Provider(host: host) else { return .generic }
        return provider.admits(path: url.path()) ? provider : nil
    }

    private static let terminators: Set<Character> = [
        " ", "\t", "\n", "\r", "\r\n", "\"", "'", "<", ">", "«", "»", "\u{00A0}"
    ]
    private static let trailingNoise: Set<Character> = [".", ",", ";", ":", ")", "]", "}", "!", "?"]

    /// Hand-rolled: `NSDataDetector` is not `Sendable` and costs more than the scan.
    private static func webURLs(in text: String) -> [URL] {
        var found: [URL] = []
        var cursor = text.startIndex
        while cursor < text.endIndex,
            let start = text.range(
                of: "http", options: .caseInsensitive, range: cursor..<text.endIndex)?.lowerBound
        {
            let end = text[start...].firstIndex(where: terminators.contains) ?? text.endIndex
            var candidate = text[start..<end]
            while let last = candidate.last, trailingNoise.contains(last) {
                candidate = candidate.dropLast()
            }
            let lowered = candidate.lowercased()
            if lowered.hasPrefix("http://") || lowered.hasPrefix("https://"),
                let url = URL(string: String(candidate))
            {
                found.append(url)
            }
            cursor = end > start ? end : text.index(after: start)
        }
        return found
    }
}

extension MeetingLink {
    enum Provider: String, CaseIterable, Sendable {
        case zoom
        case googleMeet
        case teams
        case webex
        case jitsi
        case whereby
        case chime
        case gotoMeeting
        case blueJeans
        case skype
        /// Any other http(s) link the event carries — joinable, just not identifiable.
        case generic

        /// No brand artwork ships, so the glyph says only what kind of thing this is.
        var sfSymbol: String { self == .generic ? "link" : "video.fill" }

        /// Host suffixes, matched whole or as a subdomain. Disjoint by construction.
        private static let hostSuffixes: [Provider: [String]] = [
            .zoom: ["zoom.us", "zoom.com", "zoomgov.com"],
            .googleMeet: ["meet.google.com"],
            .teams: ["teams.microsoft.com", "teams.microsoft.us", "teams.live.com"],
            .webex: ["webex.com", "webex.com.cn"],
            .jitsi: ["meet.jit.si", "8x8.vc"],
            .whereby: ["whereby.com"],
            .chime: ["chime.aws"],
            .gotoMeeting: ["gotomeeting.com", "gotomeet.me", "app.goto.com"],
            .blueJeans: ["bluejeans.com"],
            .skype: ["join.skype.com"]
        ]

        init?(host: String) {
            let match = Self.hostSuffixes.first { _, suffixes in
                suffixes.contains { host == $0 || host.hasSuffix("." + $0) }
            }
            guard let match else { return nil }
            self = match.key
        }

        /// Whether the path shape is a meeting rather than a download page or a dial-in helper.
        func admits(path: String) -> Bool {
            let segments = path.split(separator: "/").map { $0.lowercased() }
            switch self {
            case .zoom:
                return segments.contains { ["j", "w", "s", "my"].contains($0) }
            case .googleMeet:
                return segments.count == 1 && segments[0] != "tel"
            case .teams:
                return segments.contains("meetup-join") || segments.contains("meet")
            case .webex, .jitsi, .whereby, .chime, .gotoMeeting, .blueJeans, .skype, .generic:
                return !segments.isEmpty
            }
        }
    }
}
