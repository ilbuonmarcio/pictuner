import Foundation
import Darwin

/// Main-thread owned. Keeps a byte snapshot to detect external changes before overwriting metadata.
final class WorkspaceStore {
    let root: URL
    let metadataURL: URL
    private(set) var document = WorkspaceDocument()
    private(set) var failure: String?
    private var expectedData: Data?
    private var writable = true

    init(root: URL) {
        self.root = root
        metadataURL = root.appendingPathComponent(".pictuner/workspace.json")
        do {
            try validateLocation()
            if FileManager.default.fileExists(atPath: metadataURL.path) {
                let data = try Data(contentsOf: metadataURL)
                let header = try JSONDecoder().decode(VersionHeader.self, from: data)
                guard (1...3).contains(header.schemaVersion), header.renderVersion == 1 else {
                    throw PictunerError.message("This workspace uses a newer or unsupported metadata version. Its metadata has been preserved.")
                }
                document = try JSONDecoder().decode(WorkspaceDocument.self, from: data)
                // Migrate legacy export flags and geometry with neutral defaults.
                document.schemaVersion = 3
                expectedData = data
            }
        } catch {
            failure = "Workspace metadata cannot be loaded: \(error.localizedDescription)"
            writable = false
        }
    }

    private struct VersionHeader: Decodable { let schemaVersion: Int; let renderVersion: Int }

    private func validateLocation() throws {
        for url in [metadataURL.deletingLastPathComponent(), metadataURL] {
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw PictunerError.message("Workspace metadata cannot be a symbolic link.")
            }
        }
    }

    func update(_ settings: ImageSettings, for path: String) { document.images[path] = settings }
    func setLastImage(_ path: String?) { document.lastImage = path }
    func settings(for path: String) -> ImageSettings { document.images[path] ?? ImageSettings() }

    @discardableResult func save() -> Bool {
        guard writable else { return false }
        do {
            try validateLocation()
            let directory = metadataURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let lockURL = directory.appendingPathComponent("write.lock")
            let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw PictunerError.message("Unable to lock workspace metadata.") }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                throw PictunerError.message("Another editor is saving this workspace. Try again.")
            }
            defer { flock(descriptor, LOCK_UN) }
            let current = FileManager.default.fileExists(atPath: metadataURL.path) ? try Data(contentsOf: metadataURL) : nil
            guard current == expectedData else {
                writable = false
                throw PictunerError.message("Metadata changed outside this session. Reopen the workspace before editing further; the external file has been preserved.")
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            try data.write(to: metadataURL, options: .atomic)
            expectedData = data
            failure = nil
            return true
        } catch {
            failure = "Edits are not saved: \(error.localizedDescription)"
            return false
        }
    }
}
