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
enum PNGBitDepth: String, CaseIterable { case eight = "8-bit", sixteen = "16-bit" }
enum CollisionPolicy: String, CaseIterable { case rename = "Add a number", skip = "Skip existing" }
enum ExportRecipe: String, CaseIterable, Identifiable {
    case webPage = "Web Page"
    case instagram = "Instagram"
    case fullResolution = "Full Resolution"
    case lossless = "Lossless"
    var id: String { rawValue }
    var quality: Double {
        switch self { case .webPage: return 0.8; case .fullResolution: return 0.95; case .instagram, .lossless: return 1 }
    }
    var summary: String {
        switch self {
        case .webPage: return "Full resolution · JPEG 80%"
        case .instagram: return "Full resolution · JPEG 100%"
        case .fullResolution: return "Full resolution · JPEG 95%"
        case .lossless: return "Full resolution · 16-bit PNG"
        }
    }
    var help: String {
        switch self {
        case .instagram: return "\(summary). Full resolution is retained without a forced crop or resize; upload processing is controlled by Instagram."
        case .lossless: return "\(summary). Lossless compression of the rendered sRGB image; source RAW data is not embedded."
        case .webPage, .fullResolution: return "\(summary). Keeps the current crop and orientation without downsizing."
        }
    }
    func apply(to options: inout ExportOptions) {
        // Recipes affect encoding only. Keep the user's scope, folder and collision choices.
        options.format = self == .lossless ? .png : .jpeg
        options.quality = quality
        options.longEdge = 0
        options.pngBitDepth = self == .lossless ? .sixteen : .eight
    }
    func matches(_ options: ExportOptions) -> Bool {
        guard options.longEdge == 0 else { return false }
        if self == .lossless { return options.format == .png && options.pngBitDepth == .sixteen }
        return options.format == .jpeg && abs(options.quality-quality) < 0.000001
    }
}
struct ExportOptions: Equatable {
    var scope = ExportScope.ready
    var format = OutputFormat.jpeg
    var quality = 0.9
    var pngBitDepth = PNGBitDepth.eight
    var longEdge = 0.0
    var preserveFolders = true
    var collision = CollisionPolicy.rename
    var recipe: ExportRecipe? { ExportRecipe.allCases.first { $0.matches(self) } }
    var encodingIsDefault: Bool {
        let defaults = ExportOptions()
        return format == defaults.format && quality == defaults.quality && longEdge == defaults.longEdge && pngBitDepth == defaults.pngBitDepth
    }

    mutating func resetEncoding() {
        let defaults = ExportOptions()
        format = defaults.format; quality = defaults.quality
        longEdge = defaults.longEdge; pngBitDepth = defaults.pngBitDepth
    }
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
                    var image = try renderer.render(source, adjustments: item.adjustments, metadata: renderer.metadata)
                    if options.longEdge > 0 { image = renderer.resize(image, longEdge: options.longEdge) }
                    let cgImage = try renderer.cgImage(image, format: options.format == .png && options.pngBitDepth == .sixteen ? .RGBA16 : .RGBA8)
                    let data = NSMutableData()
                    let type = options.format == .jpeg ? UTType.jpeg.identifier : UTType.png.identifier
                    guard let target = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else {
                        throw PictunerError.message("Could not create the output encoder.")
                    }
                    // Deliberately do not copy EXIF/GPS in this first version. The rendered CGImage carries sRGB.
                    let properties: [CFString: Any] = options.format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: options.quality] : [:]
                    CGImageDestinationAddImage(target, cgImage, properties as CFDictionary)
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
