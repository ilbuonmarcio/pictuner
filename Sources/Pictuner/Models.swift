import Foundation
import UniformTypeIdentifiers

struct SelectiveColor: Codable, Equatable, Sendable {
    var enabled = false
    // HSV in gamma-encoded sRGB at the selective-color input stage.
    var hue = 0.33
    var saturation = 0.8
    var brightness = 0.8
    var hueRange = 0.09
    var saturationTolerance = 0.8
    var brightnessTolerance = 0.8
    var softness = 0.15
    var selectedSaturation = 1.2
    var selectedBrightness = 0.0
    var outsideSaturation = 0.0
}

struct Adjustments: Codable, Equatable, Sendable {
    var exposure = 0.0
    var brightness = 0.0
    var contrast = 1.0
    var highlights = 1.0
    var shadows = 0.0
    var temperature = 0.0
    var tint = 0.0
    var saturation = 1.0
    var hue = 0.0
    var monochrome = 0.0
    var sepia = 0.0
    var vignette = 0.0
    var vignetteRadius = 0.65
    var vignetteSoftness = 0.5
    var selective = SelectiveColor()
    var geometry = ImageGeometry()
    var isEdited: Bool { self != Adjustments() }

    init() {}
    private enum CodingKeys: String, CodingKey {
        case exposure, brightness, contrast, highlights, shadows, temperature, tint, saturation, hue
        case monochrome, sepia, vignette, vignetteRadius, vignetteSoftness, selective, geometry
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        exposure = try values.decode(Double.self, forKey: .exposure)
        brightness = try values.decode(Double.self, forKey: .brightness)
        contrast = try values.decode(Double.self, forKey: .contrast)
        highlights = try values.decode(Double.self, forKey: .highlights)
        shadows = try values.decode(Double.self, forKey: .shadows)
        temperature = try values.decode(Double.self, forKey: .temperature)
        tint = try values.decode(Double.self, forKey: .tint)
        saturation = try values.decode(Double.self, forKey: .saturation)
        hue = try values.decode(Double.self, forKey: .hue)
        monochrome = try values.decode(Double.self, forKey: .monochrome)
        sepia = try values.decode(Double.self, forKey: .sepia)
        vignette = try values.decode(Double.self, forKey: .vignette)
        vignetteRadius = try values.decode(Double.self, forKey: .vignetteRadius)
        vignetteSoftness = try values.decode(Double.self, forKey: .vignetteSoftness)
        selective = try values.decode(SelectiveColor.self, forKey: .selective)
        geometry = try values.decodeIfPresent(ImageGeometry.self, forKey: .geometry) ?? ImageGeometry()
    }
}

struct ImageSettings: Codable, Equatable, Sendable {
    var favorite = false
    var rejected = false
    var exportReady = false
    var adjustments = Adjustments()

    init() {}
    private enum CodingKeys: String, CodingKey { case favorite, rejected, exportReady, adjustments }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        favorite = try values.decode(Bool.self, forKey: .favorite)
        rejected = try values.decode(Bool.self, forKey: .rejected)
        // Version 1 workspaces have no export flag. Never implicitly approve their images.
        exportReady = try values.decodeIfPresent(Bool.self, forKey: .exportReady) ?? false
        if rejected { exportReady = false }
        adjustments = try values.decode(Adjustments.self, forKey: .adjustments)
    }
}

struct WorkspaceDocument: Codable, Sendable {
    var schemaVersion = 3
    var renderVersion = 1
    var workspaceID = UUID()
    var images: [String: ImageSettings] = [:]
    var lastImage: String?
}

struct Photo: Identifiable, Hashable, Sendable {
    let relativePath: String
    let url: URL
    var id: String { relativePath }
    var name: String { url.lastPathComponent }
    var isRAW: Bool { ImageFiles.isRAW(url) }
}

struct WorkspaceReference: Codable, Identifiable, Hashable {
    var id: String { path }
    let path: String
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
}

struct UserPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var adjustments: Adjustments
}

enum PictunerError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

enum ImageFiles {
    static let rawExtensions: Set<String> = ["raw", "dng", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "raf", "orf", "rw2", "rwl", "pef", "ptx", "srw", "3fr", "fff", "iiq", "mos", "kdc", "dcr", "mrw", "x3f"]
    static func isRAW(_ url: URL) -> Bool {
        rawExtensions.contains(url.pathExtension.lowercased()) || UTType(filenameExtension: url.pathExtension)?.conforms(to: .rawImage) == true
    }
    static func isSupported(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) || isRAW(url)
    }
    static func scan(_ root: URL) throws -> [Photo] {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue,
              fm.isReadableFile(atPath: root.path) else {
            throw PictunerError.message("This workspace is unavailable or cannot be read.")
        }
        var scanError: Error?
        guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in
            scanError = error
            return false
        }) else { throw PictunerError.message("Unable to read this workspace.") }
        var photos: [Photo] = []
        for case let url as URL in iterator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            // Do not follow links out of the workspace or duplicate files through links.
            guard values.isRegularFile == true, values.isSymbolicLink != true, isSupported(url) else { continue }
            let normalized = url.resolvingSymlinksInPath().standardizedFileURL
            let components = normalized.pathComponents
            let rootComponents = root.pathComponents
            guard components.starts(with: rootComponents) else {
                throw PictunerError.message("A workspace entry resolved outside its root.")
            }
            let relativePath = components.dropFirst(rootComponents.count).joined(separator: "/")
            photos.append(Photo(relativePath: relativePath, url: normalized))
        }
        if let scanError { throw scanError }
        return photos.sorted {
            let result = $0.name.localizedStandardCompare($1.name)
            if result == .orderedSame { return $0.relativePath < $1.relativePath }
            return result == .orderedAscending
        }
    }
}
