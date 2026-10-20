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
    var vibrance = 0.0
    var clarity = 0.0
    var texture = 0.0
    var sharpening = 0.0
    var sharpeningRadius = 1.2
    var noiseReduction = 0.0
    var glow = 0.0
    var glowRadius = 0.02
    var shadowHue = 220.0
    var shadowTint = 0.0
    var highlightHue = 40.0
    var highlightTint = 0.0
    var gradingBalance = 0.0
    var grain = 0.0
    var grainSize = 2.0
    var monochrome = 0.0
    var sepia = 0.0
    var vignette = 0.0
    var vignetteRadius = 0.65
    var vignetteSoftness = 0.5
    var selective = SelectiveColor()
    var geometry = ImageGeometry()
    var metadataOverlay = MetadataOverlay()
    var isEdited: Bool { self != Adjustments() }

    init() {}
    private enum CodingKeys: String, CodingKey {
        case exposure, brightness, contrast, highlights, shadows, temperature, tint, saturation, hue
        case vibrance, clarity, texture, sharpening, sharpeningRadius, noiseReduction, glow, glowRadius
        case shadowHue, shadowTint, highlightHue, highlightTint, gradingBalance, grain, grainSize
        case monochrome, sepia, vignette, vignetteRadius, vignetteSoftness, selective, geometry, metadataOverlay
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
        metadataOverlay = try values.decodeIfPresent(MetadataOverlay.self, forKey: .metadataOverlay) ?? MetadataOverlay()
        vibrance = try values.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0
        clarity = try values.decodeIfPresent(Double.self, forKey: .clarity) ?? 0
        texture = try values.decodeIfPresent(Double.self, forKey: .texture) ?? 0
        sharpening = try values.decodeIfPresent(Double.self, forKey: .sharpening) ?? 0
        sharpeningRadius = try values.decodeIfPresent(Double.self, forKey: .sharpeningRadius) ?? 1.2
        noiseReduction = try values.decodeIfPresent(Double.self, forKey: .noiseReduction) ?? 0
        glow = try values.decodeIfPresent(Double.self, forKey: .glow) ?? 0
        glowRadius = try values.decodeIfPresent(Double.self, forKey: .glowRadius) ?? 0.02
        shadowHue = try values.decodeIfPresent(Double.self, forKey: .shadowHue) ?? 220
        shadowTint = try values.decodeIfPresent(Double.self, forKey: .shadowTint) ?? 0
        highlightHue = try values.decodeIfPresent(Double.self, forKey: .highlightHue) ?? 40
        highlightTint = try values.decodeIfPresent(Double.self, forKey: .highlightTint) ?? 0
        gradingBalance = try values.decodeIfPresent(Double.self, forKey: .gradingBalance) ?? 0
        grain = try values.decodeIfPresent(Double.self, forKey: .grain) ?? 0
        grainSize = try values.decodeIfPresent(Double.self, forKey: .grainSize) ?? 2
        let effectRanges: [(CodingKeys, Double, ClosedRange<Double>)] = [
            (.vibrance, vibrance, -1...1), (.clarity, clarity, -1...1), (.texture, texture, -1...1),
            (.sharpening, sharpening, 0...2), (.sharpeningRadius, sharpeningRadius, 0.3...5),
            (.noiseReduction, noiseReduction, 0...1), (.glow, glow, 0...1), (.glowRadius, glowRadius, 0.002...0.06),
            (.shadowHue, shadowHue, 0...360), (.shadowTint, shadowTint, 0...1),
            (.highlightHue, highlightHue, 0...360), (.highlightTint, highlightTint, 0...1),
            (.gradingBalance, gradingBalance, -1...1), (.grain, grain, 0...1), (.grainSize, grainSize, 0.5...8)
        ]
        for (key, value, range) in effectRanges where !value.isFinite || !range.contains(value) {
            throw DecodingError.dataCorruptedError(forKey: key, in: values, debugDescription: "Invalid photo effect value.")
        }
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
    var schemaVersion = 6
    var renderVersion = 4
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
