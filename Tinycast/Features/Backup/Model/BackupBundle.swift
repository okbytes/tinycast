import Foundation

/// The payload a `.tinycast` seals; pure, so the harness drives the real layout.
struct BackupBundle: Sendable {
    enum LearningPart: String, CaseIterable, Sendable {
        case ranking
        case emoji
        case calculator
    }

    let root: URL

    init(root: URL) {
        self.root = root
    }

    // MARK: - Layout

    var manifestURL: URL { root.appendingPathComponent("manifest.json") }
    var settingsURL: URL { root.appendingPathComponent("settings.json") }

    private func directory(for category: BackupCategory) -> URL {
        let subpath = category.descriptor.subpath
        guard !subpath.isEmpty else { return root }
        return root.appendingPathComponent(subpath, isDirectory: true)
    }

    var clipboardItemsURL: URL { directory(for: .clipboard).appendingPathComponent("items.jsonl") }
    var clipboardImagesDirectory: URL {
        directory(for: .clipboard).appendingPathComponent("images", isDirectory: true)
    }

    func learningURL(_ part: LearningPart) -> URL {
        directory(for: .learning).appendingPathComponent("\(part.rawValue).json")
    }

    // MARK: - Writing

    /// Called once before composing; the archive carries no directory a category didn't ask for.
    func prepare(_ categories: Set<BackupCategory>) throws {
        try create(root)
        if categories.contains(.clipboard) { try create(clipboardImagesDirectory) }
        if categories.contains(.learning) { try create(directory(for: .learning)) }
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func writeManifest(_ manifest: BackupManifest) throws {
        try write(try Self.encoder.encode(manifest), to: manifestURL)
    }

    func encode<Value: Encodable>(_ value: Value, to url: URL) throws {
        try write(try Self.encoder.encode(value), to: url)
    }

    // MARK: - Clipboard, a line at a time

    /// One clip per line; a newline inside a clip is escaped, so `\n` only ever separates.
    struct ClipboardWriter: ~Copyable {
        private let handle: FileHandle
        /// Compact, not pretty-printed: a pretty object spans lines and breaks the separator.
        private let encoder: JSONEncoder

        init(url: URL) throws {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
            encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
        }

        func write(_ item: BackupClipboardItem) throws {
            var line = try encoder.encode(item)
            line.append(0x0A)
            try handle.write(contentsOf: line)
        }

        deinit { try? handle.close() }
    }

    func clipboardWriter() throws -> ClipboardWriter {
        try ClipboardWriter(url: clipboardItemsURL)
    }

    /// Mapped and decoded lazily, so a gigabyte of history costs one clip of resident memory.
    func clipboardItems() -> some Sequence<BackupClipboardItem> {
        let data = (try? Data(contentsOf: clipboardItemsURL, options: .mappedIfSafe)) ?? Data()
        return data.split(separator: 0x0A, omittingEmptySubsequences: true)
            .lazy
            .compactMap { try? Self.decoder.decode(BackupClipboardItem.self, from: Data($0)) }
    }

    // MARK: - Reading

    func readManifest() throws(BackupFormatError) -> BackupManifest {
        guard let data = try? Data(contentsOf: manifestURL),
            let manifest = try? Self.decoder.decode(BackupManifest.self, from: data)
        else { throw .unreadable }
        guard manifest.format == BackupManifest.currentFormat else {
            throw .unsupportedFormat(found: manifest.format)
        }
        return manifest
    }

    /// nil rather than a throw: a clip whose image the archive lost is skipped and counted.
    func clipboardImageURL(named name: String) -> URL? {
        guard Self.isSafeName(name) else { return nil }
        let url = clipboardImagesDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func decodeLearning<Value: Decodable>(_ part: LearningPart, as type: Value.Type) -> Value? {
        guard let data = try? Data(contentsOf: learningURL(part)) else { return nil }
        return try? Self.decoder.decode(Value.self, from: data)
    }

    // MARK: - Coding

    /// ISO-8601 dates, so a backup stays readable by eye and by anything but this decoder.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Names

    static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && name.rangeOfCharacter(from: Self.forbidden) == nil
    }

    private static let forbidden = CharacterSet(charactersIn: "/:\\\0")

    private func create(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
