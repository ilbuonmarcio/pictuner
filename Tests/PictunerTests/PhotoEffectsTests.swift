import XCTest
import CoreImage
@testable import Pictuner

final class PhotoEffectsTests: XCTestCase {
    private let renderer = Renderer()
    private var root: URL!
    private let newKeys = ["vibrance", "clarity", "texture", "sharpening", "sharpeningRadius", "noiseReduction", "glow", "glowRadius", "shadowHue", "shadowTint", "highlightHue", "highlightTint", "gradingBalance", "grain", "grainSize"]

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PicTunerEffects-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func fixture(noiseOnly: Bool = false) -> CIImage {
        let width = 512, height = 384
        var data = [UInt8](repeating: 255, count: width*height*4)
        var seed: UInt32 = 42
        for y in 0..<height {
            for x in 0..<width {
                seed = 1664525 &* seed &+ 1013904223
                let noise = Int(seed >> 24)%21-10
                let level = noiseOnly ? 125 : 45+x/4+(x/12%2)*20
                let bright = !noiseOnly && (235..<255).contains(x) && (100..<280).contains(y)
                for c in 0..<3 {
                    data[(y*width+x)*4+c] = UInt8(clamping: bright ? 245 : level+noise+(noiseOnly ? 0 : c*12))
                }
            }
        }
        return CIImage(bitmapData: Data(data), bytesPerRow: width*4, size: CGSize(width: width, height: height), format: .RGBA8, colorSpace: renderer.colorSpace)
    }
    private func bytes(_ image: CIImage) -> [UInt8] {
        let width = Int(image.extent.width), height = Int(image.extent.height)
        var data = [UInt8](repeating: 0, count: width*height*4)
        renderer.context.render(image, toBitmap: &data, rowBytes: width*4, bounds: image.extent, format: .RGBA8, colorSpace: renderer.colorSpace)
        return data
    }
    private func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        Double(zip(a,b).map { abs(Int($0)-Int($1)) }.reduce(0,+))/Double(a.count)
    }
    private func allEffects() -> Adjustments {
        var a = Adjustments()
        a.vibrance = 0.6; a.noiseReduction = 0.45
        a.clarity = 0.4; a.texture = 0.5; a.sharpening = 0.8; a.sharpeningRadius = 2.1
        a.shadowTint = 0.3; a.highlightTint = 0.25; a.gradingBalance = -0.1
        a.glow = 0.35; a.glowRadius = 0.035
        a.grain = 0.5; a.grainSize = 2.7
        return a
    }

    func testLegacySettingsKeepExistingEditsAndMigrateWithNeutralEffects() throws {
        var existing = Adjustments(); existing.exposure = 0.7; existing.sepia = 0.2
        existing.geometry.rotate(clockwise: true)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(existing)) as? [String: Any])
        for key in newKeys { json.removeValue(forKey: key) }
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Adjustments.self, from: data)
        XCTAssertEqual(decoded, existing)
        XCTAssertEqual(bytes(try renderer.render(fixture(), adjustments: decoded)), bytes(try renderer.render(fixture(), adjustments: existing)))
        let directory = root.appendingPathComponent(".pictuner")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let document: [String: Any] = ["schemaVersion": 3, "renderVersion": 1, "workspaceID": UUID().uuidString,
            "images": ["missing.nef": ["favorite": true, "rejected": false, "exportReady": true, "adjustments": json]]]
        let original = try JSONSerialization.data(withJSONObject: document)
        let url = directory.appendingPathComponent("workspace.json")
        try original.write(to: url)
        let store = WorkspaceStore(root: root)
        XCTAssertNil(store.failure)
        XCTAssertEqual(try Data(contentsOf: url), original, "Migration must not save until a normal write")
        XCTAssertEqual(store.settings(for: "missing.nef").adjustments, existing)
        XCTAssertTrue(store.save())
        let reopened = WorkspaceStore(root: root)
        XCTAssertEqual(reopened.document.schemaVersion, 4)
        XCTAssertEqual(reopened.document.renderVersion, 2)
        XCTAssertTrue(reopened.settings(for: "missing.nef").exportReady)
    }

    func testEveryNewEffectChangesPixelsAndZeroAmountsBypassEverything() throws {
        let image = fixture()
        let baseline = bytes(image)
        XCTAssertEqual(bytes(try renderer.render(image, adjustments: Adjustments())), baseline)
        let cases: [(String, (inout Adjustments) -> Void)] = [
            ("Vibrance", { $0.vibrance = 1 }), ("Clarity", { $0.clarity = 1 }),
            ("Texture", { $0.texture = 1 }), ("Sharpening", { $0.sharpening = 2 }),
            ("Noise reduction", { $0.noiseReduction = 1 }), ("Glow", { $0.glow = 1 }),
            ("Color grading", { $0.shadowTint = 1; $0.highlightTint = 1 }), ("Film grain", { $0.grain = 1 })
        ]
        for (name, change) in cases {
            var a = Adjustments(); change(&a)
            let output = try renderer.render(image, adjustments: a)
            XCTAssertEqual(output.extent, image.extent)
            XCTAssertGreaterThan(difference(bytes(output), baseline), 0.05, "\(name) must have a visible effect")
        }
        var inactive = Adjustments()
        inactive.glowRadius = 0.06; inactive.grainSize = 8; inactive.sharpeningRadius = 5
        inactive.shadowHue = 120; inactive.highlightHue = 280; inactive.gradingBalance = 1
        XCTAssertEqual(bytes(try renderer.render(image, adjustments: inactive)), baseline)
    }

    func testInvalidEffectMetadataIsRejectedAndPreserved() throws {
        let store = WorkspaceStore(root: root)
        var settings = ImageSettings(); settings.adjustments = allEffects()
        store.update(settings, for: "photo.png")
        XCTAssertTrue(store.save())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.metadataURL)) as? [String: Any])
        var images = try XCTUnwrap(json["images"] as? [String: [String: Any]])
        var entry = try XCTUnwrap(images["photo.png"])
        var adjustments = try XCTUnwrap(entry["adjustments"] as? [String: Any])
        adjustments["grainSize"] = 0
        entry["adjustments"] = adjustments; images["photo.png"] = entry; json["images"] = images
        let corrupt = try JSONSerialization.data(withJSONObject: json)
        try corrupt.write(to: store.metadataURL)
        let reopened = WorkspaceStore(root: root)
        XCTAssertNotNil(reopened.failure)
        XCTAssertFalse(reopened.save())
        XCTAssertEqual(try Data(contentsOf: store.metadataURL), corrupt)
    }

    func testDenoiseSmoothsNoiseAndGradingSeparatesDarkAndLightTones() throws {
        let image = fixture(noiseOnly: true)
        var denoise = Adjustments(); denoise.noiseReduction = 1
        func roughness(_ data: [UInt8]) -> Double {
            Double(stride(from: 4, to: data.count, by: 4).map { abs(Int(data[$0])-Int(data[$0-4])) }.reduce(0,+))
        }
        XCTAssertLessThan(roughness(bytes(try renderer.render(image, adjustments: denoise))), roughness(bytes(image)))
        var grading = Adjustments(); grading.shadowHue = 240; grading.highlightHue = 30
        grading.shadowTint = 0.9; grading.highlightTint = 0.9
        for (level, blueShadow) in [(0.2, true), (0.8, false)] {
            let solid = CIImage(color: CIColor(red: level, green: level, blue: level)).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
            let output = bytes(try renderer.render(solid, adjustments: grading))
            if blueShadow { XCTAssertGreaterThan(output[2], output[0]) }
            else { XCTAssertGreaterThan(output[0], output[2]) }
        }
    }

    func testNeighborhoodEffectsAndFixedGrainMatchFullImageAtCropEdgesAndAfterPanning() throws {
        let url = root.appendingPathComponent("photo.png")
        try renderer.context.writePNGRepresentation(of: fixture(), to: url, format: .RGBA8, colorSpace: renderer.colorSpace)
        let sourceBytes = try Data(contentsOf: url)
        let a = allEffects()
        let source = try renderer.load(url)
        for scale in [1.0, 0.5] {
            let full = try renderer.render(source.transformed(by: CGAffineTransform(scaleX: scale, y: scale)), adjustments: a, sourceScale: scale)
            for region in [CGRect(x: 0.5, y: 0.3, width: 0.2, height: 0.4), CGRect(x: 0.45, y: 0.2, width: 0.3, height: 0.5)] {
                let preview = try renderer.preview(url: url, adjustments: a, detailViewport: DetailViewport(region: region, scale: scale))
                let detail = try XCTUnwrap(preview.detail)
                let bounds = CGRect(x: detail.region.minX*512*scale, y: detail.region.minY*384*scale, width: Double(detail.edited.width), height: Double(detail.edited.height))
                let expected = bytes(full.cropped(to: bounds))
                XCTAssertLessThan(difference(bytes(CIImage(cgImage: detail.edited)), expected), 1.5, "Zoom crops need filter halos and global grain coordinates, including their boundary pixels")
                XCTAssertEqual(bytes(CIImage(cgImage: preview.edited)), bytes(CIImage(cgImage: try renderer.preview(url: url, adjustments: a).edited)), "Grain must not change on each render")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), sourceBytes)
    }

    func testEffectsPreviewHistogramAndPNGExportShareSettingsAndPreserveOriginalComparison() throws {
        let workspace = root.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let url = workspace.appendingPathComponent("photo.png")
        try renderer.context.writePNGRepresentation(of: fixture(), to: url, format: .RGBA8, colorSpace: renderer.colorSpace)
        let original = try Data(contentsOf: url)
        var a = allEffects(); a.geometry.rotate(clockwise: true)
        a.geometry.crop = CropRegion(CGRect(x: 0.1, y: 0.1, width: 0.7, height: 0.8))
        let preview = try renderer.preview(url: url, adjustments: a)
        let histogram = renderer.histogram(CIImage(cgImage: preview.edited))
        XCTAssertEqual(preview.histogram.red, histogram.red)
        let baseline = try renderer.cgImage(renderer.geometry(renderer.load(url), a.geometry))
        XCTAssertEqual(bytes(CIImage(cgImage: preview.original)), bytes(CIImage(cgImage: baseline)))
        var options = ExportOptions(); options.format = .png
        let result = Exporter.run(items: [ExportItem(photo: Photo(relativePath: "photo.png", url: url), adjustments: a)], destination: root.appendingPathComponent("export"), roots: [workspace], options: options, cancellation: ExportCancellation()) { _, _ in }
        XCTAssertEqual(result.completed, 1); XCTAssertEqual(result.errors, [])
        let exported = try XCTUnwrap(CIImage(contentsOf: root.appendingPathComponent("export/photo.png")))
        XCTAssertLessThan(difference(bytes(exported), bytes(CIImage(cgImage: preview.edited))), 1.5)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    @MainActor func testEffectSliderUndoResetPersistenceAndPresets() async throws {
        let url = root.appendingPathComponent("photo.png")
        try renderer.context.writePNGRepresentation(of: fixture(), to: url, format: .RGBA8, colorSpace: renderer.colorSpace)
        let model = AppModel(restoringSession: false, supportDirectory: root.appendingPathComponent("support"))
        model.open(WorkspaceReference(path: root.path))
        for _ in 0..<200 where model.preview == nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(model.preview)
        let a = allEffects()
        model.setAdjustments(a)
        for _ in 0..<200 where model.isRendering { try await Task.sleep(for: .milliseconds(20)) }
        model.editingGesture(true)
        for value in [0.1, 0.3, 0.7] {
            let previous = try XCTUnwrap(model.preview?.edited)
            model.adjustmentBinding(\.grain).wrappedValue = value
            for _ in 0..<200 where model.preview?.edited === previous { try await Task.sleep(for: .milliseconds(20)) }
            let live = try XCTUnwrap(model.preview?.edited)
            XCTAssertGreaterThan(difference(bytes(CIImage(cgImage: live)), bytes(CIImage(cgImage: previous))), 0.01, "All effects must publish changed frames before the drag ends")
        }
        model.editingGesture(false)
        model.undo(); XCTAssertEqual(model.settings.adjustments, a)
        model.redo(); XCTAssertEqual(model.settings.adjustments.grain, 0.7)
        ResetValueButton(title: "Film grain", value: model.adjustmentBinding(\.grain), defaultValue: 0).reset()
        XCTAssertEqual(model.settings.adjustments.glow, a.glow)
        XCTAssertEqual(model.settings.adjustments.grain, 0)
        model.undo(); XCTAssertEqual(model.settings.adjustments.grain, 0.7)
        model.savePreset(name: "All effects")
        let saved = try JSONDecoder().decode([UserPreset].self, from: Data(contentsOf: root.appendingPathComponent("support/presets.json")))
        XCTAssertEqual(saved.first?.adjustments, model.settings.adjustments)
        XCTAssertTrue(model.flush())
        XCTAssertEqual(WorkspaceStore(root: root).settings(for: "photo.png").adjustments, model.settings.adjustments)
        for _ in 0..<200 where model.isRendering { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(model.preview)
        XCTAssertTrue(model.prepareToQuit())
    }

    func testRealRAWWithAllNewEffects() throws {
        guard let path = ProcessInfo.processInfo.environment["PICTUNER_RAW_FIXTURE"] else {
            throw XCTSkip("Set PICTUNER_RAW_FIXTURE to test a real camera RAW image.")
        }
        let url = URL(fileURLWithPath: path)
        let original = try Data(contentsOf: url)
        let preview = try renderer.preview(url: url, adjustments: allEffects(), longEdge: 640)
        XCTAssertGreaterThan(difference(bytes(CIImage(cgImage: preview.original)), bytes(CIImage(cgImage: preview.edited))), 0.5)
        var options = ExportOptions(); options.longEdge = 640
        let result = Exporter.run(items: [ExportItem(photo: Photo(relativePath: url.lastPathComponent, url: url), adjustments: allEffects())], destination: root.appendingPathComponent("raw-export"), roots: [url.deletingLastPathComponent()], options: options, cancellation: ExportCancellation()) { _, _ in }
        XCTAssertEqual(result.completed, 1); XCTAssertEqual(result.errors, [])
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
