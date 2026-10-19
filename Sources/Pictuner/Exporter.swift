import Foundation
import ImageIO
import UniformTypeIdentifiers
import Darwin

enum ExportScope: String, CaseIterable {
    case ready = "Marked in Workspace"
    case currentFolder = "Marked in Folder"
    case selected = "Marked in Selection"
    case favorites = "Marked Favorites"
}
enum OutputFormat: String, CaseIterable { case jpeg = "JPEG", png = "PNG" }
enum CollisionPolicy: String, CaseIterable { case rename = "Add a number", skip = "Skip existing" }
struct ExportOptions {
    var scope = ExportScope.ready
    var format = OutputFormat.jpeg
    var quality = 0.9
    var longEdge = 0.0
    var preserveFolders = true
    var collision = CollisionPolicy.rename
}
struct ExportItem { let photo: Photo; let adjustments: Adjustments }

/// Cancellation is checked between images; the in-flight render may finish first.
final class ExportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}

enum Exporter {
    static func isWithin(_ candidate: URL, root: URL) -> Bool {
        let path = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        return path == base || path.hasPrefix(base + "/")
    }

    static func validateDestination(_ destination: URL, roots: [URL]) throws {
        guard !roots.contains(where: { isWithin(destination, root: $0) }) else {
            throw PictunerError.message("Choose an export folder outside your workspaces.")
        }
    }

    /// Publish using link(2): it atomically refuses an existing path, including a symlink/hard link.
    /// No source or pre-existing file can be overwritten even if a collision appears during export.
    static func publish(_ data: Data, to proposed: URL, collision: CollisionPolicy, protectedRoots: [URL]) throws -> URL? {
        let fm = FileManager.default
        let parent = proposed.deletingLastPathComponent()
        try validateDestination(parent, roots: protectedRoots)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try validateDestination(parent, roots: protectedRoots)
        let temporary = parent.appendingPathComponent(".pictuner-export-\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .withoutOverwriting)
        defer { try? fm.removeItem(at: temporary) }
        var candidate = proposed
        for index in 0..<10000 {
            if index > 0 {
                candidate = parent.appendingPathComponent(proposed.deletingPathExtension().lastPathComponent + "-\(index)").appendingPathExtension(proposed.pathExtension)
            }
            // Existing leaf symlinks are collisions, never followed or replaced.
            try validateDestination(candidate.deletingLastPathComponent(), roots: protectedRoots)
            if link(temporary.path, candidate.path) == 0 { return candidate }
            let code = errno
            guard code == EEXIST else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
            if collision == .skip { return nil }
        }
        throw PictunerError.message("Too many filename collisions for \(proposed.lastPathComponent).")
    }

    static func run(items: [ExportItem], destination: URL, roots: [URL], options: ExportOptions, cancellation: ExportCancellation, progress: @escaping (Int, String) -> Void) -> (completed: Int, skipped: Int, errors: [String]) {
        let renderer = Renderer()
        var completed = 0, skipped = 0
        var errors: [String] = []
        for (index, item) in items.enumerated() {
            if cancellation.cancelled { break }
            autoreleasepool {
                do {
                    let source = try renderer.load(item.photo.url)
                    var image = try renderer.render(source, adjustments: item.adjustments)
                    if options.longEdge > 0 { image = renderer.resize(image, longEdge: options.longEdge) }
                    let cgImage = try renderer.cgImage(image)
                    let data = NSMutableData()
                    let type = options.format == .jpeg ? UTType.jpeg.identifier : UTType.png.identifier
                    guard let target = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else {
                        throw PictunerError.message("Could not create the output encoder.")
                    }
                    // Deliberately do not copy EXIF/GPS in this first version. The rendered CGImage carries sRGB.
                    CGImageDestinationAddImage(target, cgImage, [kCGImageDestinationLossyCompressionQuality: options.quality] as CFDictionary)
                    guard CGImageDestinationFinalize(target) else { throw PictunerError.message("The output encoder failed.") }
                    if cancellation.cancelled { return }
                    let relative = options.preserveFolders ? item.photo.relativePath : item.photo.name
                    let output = destination.appendingPathComponent(relative).deletingPathExtension().appendingPathExtension(options.format == .jpeg ? "jpg" : "png")
                    if try publish(data as Data, to: output, collision: options.collision, protectedRoots: roots) != nil { completed += 1 }
                    else { skipped += 1 }
                } catch { errors.append("\(item.photo.relativePath): \(error.localizedDescription)") }
            }
            progress(index + 1, item.photo.name)
        }
        return (completed, skipped, errors)
    }
}
