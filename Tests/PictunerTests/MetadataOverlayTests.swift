import XCTest
import CoreImage
import ImageIO
@testable import Pictuner

final class MetadataOverlayTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PicTunerEXIF-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private var properties: [String: Any] { [
        kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifDateTimeOriginal as String: "2024:10:20 17:02:03",
                                                  kCGImagePropertyExifOffsetTimeOriginal as String: "+09:00"],
        kCGImagePropertyGPSDictionary as String: [kCGImagePropertyGPSLatitude as String: 48.82761,
                                                 kCGImagePropertyGPSLatitudeRef as String: "N",
                                                 kCGImagePropertyGPSLongitude as String: 2.28896,
                                                 kCGImagePropertyGPSLongitudeRef as String: "E"]
    ] }
    private func fixture(_ name: String = "photo.jpg", metadata: Bool = true) throws -> URL {
        let url = root.appendingPathComponent(name), renderer = Renderer()
        let image = try renderer.cgImage(CIImage(color: CIColor(red: 0.45, green: 0.5, blue: 0.55)).cropped(to: CGRect(x: 0, y: 0, width: 1200, height: 800)))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, metadata ? properties as CFDictionary : nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
    private func bytes(_ image: CIImage, renderer: Renderer) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: Int(image.extent.width*image.extent.height)*4)
        renderer.context.render(image, toBitmap: &result, rowBytes: Int(image.extent.width)*4, bounds: image.extent, format: .RGBA8, colorSpace: renderer.colorSpace)
        return result
    }
    @MainActor private func settle(_ model: AppModel) async throws {
        for _ in 0..<400 where model.isLoading || model.isRendering || model.preview == nil { try await Task.sleep(for: .milliseconds(15)) }
        XCTAssertNotNil(model.preview); XCTAssertFalse(model.isRendering)
    }

    func testReadsRecordedClockAndCoordinatesWithoutGuessingMissingValues() throws {
        let metadata = PhotoMetadata.read(try fixture())
        XCTAssertEqual(metadata.captureDate, "20 Oct 2024 · 17:02:03 +09:00")
        XCTAssertEqual(metadata.coordinates, "48.82761° N   2.28896° E")
        XCTAssertEqual(PhotoMetadata.read(try fixture("missing.jpg", metadata: false)), PhotoMetadata())
        XCTAssertEqual(PhotoMetadata(properties: [:]), PhotoMetadata())
        var p = properties
        p[kCGImagePropertyExifDictionary as String] = [kCGImagePropertyExifDateTimeOriginal as String: "2024:02:30 17:02:03"]
        XCTAssertNil(PhotoMetadata(properties: p).captureDate)
        p[kCGImagePropertyGPSDictionary as String] = [kCGImagePropertyGPSLatitude as String: 0, kCGImagePropertyGPSLatitudeRef as String: "S", kCGImagePropertyGPSLongitude as String: 0, kCGImagePropertyGPSLongitudeRef as String: "W"]
        XCTAssertEqual(PhotoMetadata(properties: p).coordinates, "0.00000° S   0.00000° W")
        p[kCGImagePropertyGPSDictionary as String] = [kCGImagePropertyGPSLatitude as String: 91, kCGImagePropertyGPSLatitudeRef as String: "N", kCGImagePropertyGPSLongitude as String: 0, kCGImagePropertyGPSLongitudeRef as String: "E"]
        XCTAssertNil(PhotoMetadata(properties: p).coordinates)
        p[kCGImagePropertyExifDictionary as String] = [kCGImagePropertyExifDateTimeOriginal as String: "2024:10:20 17:02:03"]
        XCTAssertEqual(PhotoMetadata(properties: p).captureDate, "20 Oct 2024 · 17:02:03", "Do not assign this Mac's time zone to an unspecified camera clock")
    }

    func testAllPositionsKeepPlateInsideMarginsIncludingTinyAndNarrowImages() throws {
        var settings = MetadataOverlay(); settings.enabled = true
        for size in [CGSize(width: 1200, height: 800), CGSize(width: 400, height: 1200), CGSize(width: 32, height: 2)] {
            for position in OverlayPosition.allCases {
                settings.position = position
                let margin = min(size.width, size.height)*settings.margin
                let frame = MetadataStamp.frame(labelSize: CGSize(width: 600, height: 100), in: size, settings: settings)
                XCTAssertGreaterThanOrEqual(frame.minX+0.00001, margin)
                XCTAssertGreaterThanOrEqual(frame.minY+0.00001, margin)
                XCTAssertLessThanOrEqual(frame.maxX, size.width-margin+0.00001)
                XCTAssertLessThanOrEqual(frame.maxY, size.height-margin+0.00001)
                if position == .bottomLeft { XCTAssertEqual(frame.minX, margin); XCTAssertEqual(frame.minY, margin) }
                if position == .topRight { XCTAssertEqual(frame.maxX, size.width-margin, accuracy: 0.00001); XCTAssertEqual(frame.maxY, size.height-margin, accuracy: 0.00001) }
            }
        }
        let renderer = Renderer(), image = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 2))
        var a = Adjustments(); a.metadataOverlay = settings
        XCTAssertEqual(try renderer.render(image, adjustments: a, metadata: PhotoMetadata(properties: properties)).extent, image.extent)
    }

    func testPreviewDetailExportAndHistogramIncludeTheSameStampButOriginalAndSamplingDoNot() throws {
        let url = try fixture(), originalBytes = try Data(contentsOf: url), renderer = Renderer()
        var a = Adjustments(); a.metadataOverlay.enabled = true; a.metadataOverlay.textSize = 0.05
        a.geometry.rotate(clockwise: true)
        a.geometry.crop = CropRegion(CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))
        let source = try renderer.load(url)
        let full = try renderer.render(source, adjustments: a, metadata: renderer.metadata)
        let preview = try renderer.preview(url: url, adjustments: a, detailViewport: DetailViewport(region: CGRect(x: 0, y: 0, width: 0.8, height: 0.3), scale: 1))
        XCTAssertEqual(preview.metadata, PhotoMetadata(properties: properties))
        XCTAssertNotEqual(bytes(CIImage(cgImage: preview.edited), renderer: renderer), bytes(CIImage(cgImage: preview.original), renderer: renderer))
        XCTAssertEqual(bytes(CIImage(cgImage: preview.samplingImage), renderer: renderer), bytes(CIImage(cgImage: preview.original), renderer: renderer))
        XCTAssertEqual(preview.histogram.red, renderer.histogram(CIImage(cgImage: preview.edited)).red)
        let detail = try XCTUnwrap(preview.detail)
        let bounds = CGRect(x: round(detail.region.minX*full.extent.width), y: round(detail.region.minY*full.extent.height), width: Double(detail.edited.width), height: Double(detail.edited.height))
        let expected = bytes(full.cropped(to: bounds), renderer: renderer)
        let actual = bytes(CIImage(cgImage: detail.edited), renderer: renderer)
        XCTAssertEqual(expected.count, actual.count)
        XCTAssertLessThanOrEqual(zip(expected, actual).map { abs(Int($0)-Int($1)) }.max() ?? 0, 2, "Zoom detail must not move or clip the caption")
        var options = ExportOptions(); ExportRecipe.lossless.apply(to: &options)
        let destination = root.appendingPathComponent("output")
        let result = Exporter.run(items: [ExportItem(photo: Photo(relativePath: "photo.jpg", url: url), adjustments: a)], destination: destination, roots: [], options: options, cancellation: ExportCancellation()) { _, _ in }
        XCTAssertEqual(result.completed, 1); XCTAssertEqual(result.errors, [])
        let output = try XCTUnwrap(CGImageSourceCreateWithURL(destination.appendingPathComponent("photo.png") as CFURL, nil))
        let tags = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [String: Any])
        XCTAssertNil(tags[kCGImagePropertyGPSDictionary as String])
        let exif = tags[kCGImagePropertyExifDictionary as String] as? [String: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal as String])
        XCTAssertEqual((tags[kCGImagePropertyDepth as String] as? NSNumber)?.intValue, 16)
        let exported = try XCTUnwrap(CGImageSourceCreateImageAtIndex(output, 0, nil))
        let exportedBytes = bytes(CIImage(cgImage: exported), renderer: renderer), fullBytes = bytes(full, renderer: renderer)
        XCTAssertLessThanOrEqual(zip(exportedBytes, fullBytes).map { abs(Int($0)-Int($1)) }.max() ?? 0, 2)
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
        var missing = a; missing.metadataOverlay.showsGPS = false; missing.metadataOverlay.showsDate = false
        XCTAssertEqual(bytes(try renderer.render(source, adjustments: missing, metadata: renderer.metadata), renderer: renderer), bytes(renderer.geometry(source, a.geometry), renderer: renderer))
    }

    @MainActor func testSettingsPersistAndUndoWithoutLeakingThroughPresetsCopyOrBatch() async throws {
        _ = try fixture("1.jpg"); _ = try fixture("2.jpg")
        let model = AppModel(restoringSession: false, supportDirectory: root.appendingPathComponent("support"))
        model.open(WorkspaceReference(path: root.path)); try await settle(model)
        var a = model.settings.adjustments; a.metadataOverlay.enabled = true; a.metadataOverlay.position = .topRight
        model.setAdjustments(a); model.editingGesture(true)
        a.metadataOverlay.margin = 0.06; model.setAdjustments(a); try await settle(model)
        XCTAssertEqual(model.preview?.metadata.captureDate, "20 Oct 2024 · 17:02:03 +09:00")
        a.metadataOverlay.margin = 0.09; model.setAdjustments(a); model.editingGesture(false)
        model.undo(); XCTAssertEqual(model.settings.adjustments.metadataOverlay.margin, MetadataOverlay().margin)
        model.redo(); XCTAssertEqual(model.settings.adjustments.metadataOverlay.margin, 0.09)
        model.copyAdjustments(); model.savePreset(name: "Color only")
        XCTAssertEqual(model.presets.last?.adjustments.metadataOverlay, MetadataOverlay())
        model.selectedIDs = Set(model.photos.map(\.id)); model.applyToSelection()
        XCTAssertFalse(model.savedSettings(for: model.photos[1]).adjustments.metadataOverlay.enabled)
        model.select(model.photos[1]); model.pasteAdjustments()
        XCTAssertFalse(model.settings.adjustments.metadataOverlay.enabled)
        model.select(model.photos[0]); model.applyColorAdjustments(Adjustments())
        XCTAssertEqual(model.settings.adjustments.metadataOverlay.position, .topRight)
        XCTAssertTrue(model.flush())
        let reopened = WorkspaceStore(root: root)
        XCTAssertNil(reopened.failure); XCTAssertEqual(reopened.document.schemaVersion, 6); XCTAssertEqual(reopened.document.renderVersion, 4)
        XCTAssertEqual(reopened.settings(for: "1.jpg").adjustments.metadataOverlay, model.settings.adjustments.metadataOverlay)
        XCTAssertTrue(model.prepareToQuit())
    }

    func testLegacySettingsStartDisabledAndInvalidMetadataIsPreserved() throws {
        let data = try JSONEncoder().encode(Adjustments())
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]); legacy.removeValue(forKey: "metadataOverlay")
        XCTAssertEqual(try JSONDecoder().decode(Adjustments.self, from: JSONSerialization.data(withJSONObject: legacy)).metadataOverlay, MetadataOverlay())
        var document = WorkspaceDocument(), entry = ImageSettings()
        entry.adjustments.metadataOverlay.margin = 0.9; document.images["missing.nef"] = entry
        let url = root.appendingPathComponent(".pictuner/workspace.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let invalid = try JSONEncoder().encode(document); try invalid.write(to: url)
        let store = WorkspaceStore(root: root)
        XCTAssertNotNil(store.failure); XCTAssertFalse(store.save()); XCTAssertEqual(try Data(contentsOf: url), invalid)
    }

    func testRenderedLabelMovesToEachAnchorAndKeepsItsMargin() throws {
        let renderer = Renderer(), source = try renderer.load(fixture())
        let original = bytes(source, renderer: renderer), metadata = renderer.metadata
        for position in OverlayPosition.allCases {
            var a = Adjustments(); a.metadataOverlay.enabled = true; a.metadataOverlay.position = position
            let rendered = bytes(try renderer.render(source, adjustments: a, metadata: metadata), renderer: renderer)
            var minX = 1200, minY = 800, maxX = 0, maxY = 0
            for y in 0..<800 {
                for x in 0..<1200 {
                    let offset = (y*1200+x)*4
                    if abs(Int(rendered[offset])-Int(original[offset])) > 10 {
                        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
            }
            XCTAssertLessThan(minX, maxX); XCTAssertLessThan(minY, maxY)
            let margin = 800*a.metadataOverlay.margin
            // Bitmap rows run from top to bottom; placement uses image-space coordinates.
            if [.topLeft, .bottomLeft].contains(position) { XCTAssertEqual(Double(minX), margin, accuracy: 2) }
            if [.topRight, .bottomRight].contains(position) { XCTAssertEqual(Double(1200-maxX-1), margin, accuracy: 2) }
            if [.topCenter, .bottomCenter].contains(position) { XCTAssertEqual(Double(minX+maxX)/2, 600, accuracy: 2) }
            if [.topLeft, .topCenter, .topRight].contains(position) { XCTAssertEqual(Double(minY), margin, accuracy: 2) }
            else { XCTAssertEqual(Double(800-maxY-1), margin, accuracy: 2) }
        }
    }

    func testRAWCaptureDateCanBeRenderedWithoutChangingTheSource() throws {
        guard let path = ProcessInfo.processInfo.environment["PICTUNER_RAW_FIXTURE"] else { throw XCTSkip("Set PICTUNER_RAW_FIXTURE to test real camera metadata.") }
        let url = URL(fileURLWithPath: path), original = try Data(contentsOf: url), renderer = Renderer()
        var a = Adjustments(); a.metadataOverlay.enabled = true
        let preview = try renderer.preview(url: url, adjustments: a, longEdge: 600)
        XCTAssertNotNil(preview.metadata.captureDate, "The selected Nikon integration fixture contains DateTimeOriginal")
        XCTAssertNotEqual(bytes(CIImage(cgImage: preview.edited), renderer: renderer), bytes(CIImage(cgImage: preview.original), renderer: renderer))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
