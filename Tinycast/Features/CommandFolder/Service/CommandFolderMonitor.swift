import Darwin
import Foundation

/// Reports a file added, removed or renamed in the command folder, once the writes settle.
@MainActor
final class CommandFolderMonitor {
    var onChange: (() -> Void)?

    private let folder: URL
    private var source: DispatchSourceFileSystemObject?
    private var settleTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    private static let settleDelay = Duration.milliseconds(300)
    private static let retryDelay = Duration.seconds(2)

    init(folder: URL) {
        self.folder = folder
    }

    isolated deinit {
        settleTask?.cancel()
        retryTask?.cancel()
        source?.cancel()
    }

    func start() {
        arm()
    }

    /// Reopened after every event: a folder deleted and recreated is a new inode.
    private func arm() {
        source?.cancel()
        source = nil
        let descriptor = Darwin.open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return scheduleRetry() }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .revoke],
            queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.sourceDidFire() }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        self.source = source
    }

    private func sourceDidFire() {
        arm()
        settle()
    }

    private func settle() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            guard (try? await Task.sleep(for: Self.settleDelay)) != nil else { return }
            self?.onChange?()
        }
    }

    /// Polls only while the folder is missing; Show in Finder or the user creates it.
    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            guard (try? await Task.sleep(for: Self.retryDelay)) != nil else { return }
            guard let self else { return }
            retryTask = nil
            arm()
            if source != nil { settle() }
        }
    }
}
