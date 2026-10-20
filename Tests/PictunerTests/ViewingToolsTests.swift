import XCTest
import AppKit
import CoreImage
@testable import Pictuner

final class ViewingToolsTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PicTunerViewing-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func fixture() throws -> URL {
        let width = 600, height = 400
        var bytes = [UInt8](repeating: 255, count: width*height*4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y*width+x)*4
                bytes[i] = UInt8(40+x/5)
                bytes[i+1] = UInt8(40+y/3)
                bytes[i+2] = 90
            }
        }
        let image = CIImage(bitmapData: Data(bytes), bytesPerRow: width*4, size: CGSize(width: width, height: height), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let line = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: -400, y: -4, width: 800, height: 8))
            .transformed(by: CGAffineTransform(rotationAngle: 5 * .pi/180))
            .transformed(by: CGAffineTransform(translationX: 300, y: 200))
        let source = line.composited(over: image).cropped(to: image.extent)
        let r = Renderer(), url = root.appendingPathComponent("horizon.png")
        try r.context.writePNGRepresentation(of: source, to: url, format: .RGBA8, colorSpace: r.colorSpace)
        return url
    }
    private func pixel(_ image: CIImage, x: Double, y: Double, renderer: Renderer) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        renderer.context.render(image, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: renderer.colorSpace)
        return bytes
    }
    @MainActor private func settle(_ model: AppModel) async throws {
        for _ in 0..<400 where model.isLoading || model.isRendering || model.preview == nil { try await Task.sleep(for: .milliseconds(15)) }
        XCTAssertNotNil(model.preview); XCTAssertFalse(model.isRendering)
    }

    func testStraightenLevelsAKnownHorizonAndTrimsTransparentEdges() throws {
        let r = Renderer(), image = try r.load(fixture())
        var a = Adjustments(); a.geometry.straightenAngle = 5
        let result = try r.render(image, adjustments: a)
        for fraction in [0.1, 0.3, 0.7, 0.9] {
            let p = pixel(result, x: floor(result.extent.width*fraction), y: floor(result.extent.height/2), renderer: r)
            XCTAssertGreaterThan(p[0], 240); XCTAssertLessThan(p[1], 15, "The sloping red horizon must become horizontal")
        }
        for size in [CGSize(width: 600, height: 400), CGSize(width: 400, height: 600), CGSize(width: 2000, height: 40)] {
            for angle in [-15.0, -5, 0.001, 5, 15] {
                a.geometry.straightenAngle = angle
                let solid = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.7)).cropped(to: CGRect(origin: .zero, size: size))
                let framed = try r.render(solid, adjustments: a)
                XCTAssertLessThanOrEqual(framed.extent.width, size.width)
                XCTAssertLessThanOrEqual(framed.extent.height, size.height)
                for x in [0.0, framed.extent.width-1] {
                    for y in [0.0, framed.extent.height-1] {
                        XCTAssertEqual(pixel(framed, x: x, y: y, renderer: r)[3], 255, "No transparent wedges at \(angle)°, \(size)")
                    }
                }
            }
        }
    }

    func testHorizonGuideIsDirectionIndependentAndIgnoresTinyDrags() throws {
        let start = CGPoint(x: 50, y: 50), end = CGPoint(x: 250, y: 70)
        let angle = try XCTUnwrap(ImageGeometry.horizonCorrection(from: start, to: end))
        XCTAssertEqual(angle, atan(0.1)*180 / .pi, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(ImageGeometry.horizonCorrection(from: end, to: start)), angle, accuracy: 0.0001)
        XCTAssertNil(ImageGeometry.horizonCorrection(from: start, to: CGPoint(x: 55, y: 52)))
    }

    func testLegacyGeometryDefaultsAndInvalidAnglePreservesMetadata() throws {
        let legacy = Data(#"{"quarterTurns":1,"flipHorizontal":true,"flipVertical":false}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(ImageGeometry.self, from: legacy).straightenAngle, 0)
        var document = WorkspaceDocument(), settings = ImageSettings()
        settings.adjustments.geometry.straightenAngle = 16
        document.images["missing.nef"] = settings
        let metadata = root.appendingPathComponent(".pictuner/workspace.json")
        try FileManager.default.createDirectory(at: metadata.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = try JSONEncoder().encode(document)
        try bytes.write(to: metadata)
        let store = WorkspaceStore(root: root)
        XCTAssertNotNil(store.failure); XCTAssertFalse(store.save())
        XCTAssertEqual(try Data(contentsOf: metadata), bytes)
    }

    func testStraightenPreviewDetailHistogramAndExportShareGeometry() throws {
        let url = try fixture(), sourceBytes = try Data(contentsOf: url), r = Renderer()
        var a = Adjustments(); a.geometry.straightenAngle = -8; a.exposure = 0.4
        a.geometry.crop = CropRegion(CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6))
        let full = try r.render(r.load(url), adjustments: a)
        let preview = try r.preview(url: url, adjustments: a, detailViewport: DetailViewport(region: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4), scale: 1))
        XCTAssertEqual(preview.sourceSize, full.extent.size)
        XCTAssertEqual(preview.histogram.red, r.histogram(CIImage(cgImage: preview.edited)).red)
        func mean(_ histogram: [Double]) -> Double {
            histogram.enumerated().reduce(0) { $0+Double($1.offset)*$1.element } / histogram.reduce(0, +)
        }
        XCTAssertEqual(mean(preview.histogram.red), mean(r.histogram(full).red), accuracy: 1)
        let detail = try XCTUnwrap(preview.detail)
        let x = Double(detail.edited.width/2), y = Double(detail.edited.height/2)
        let expected = pixel(full, x: floor(detail.region.minX*full.extent.width)+x, y: floor(detail.region.minY*full.extent.height)+y, renderer: r)
        let actual = pixel(CIImage(cgImage: detail.edited), x: x, y: y, renderer: r)
        for i in 0..<4 { XCTAssertEqual(Int(expected[i]), Int(actual[i]), accuracy: 2) }
        var options = ExportOptions(); options.format = .png
        let destination = root.appendingPathComponent("output")
        let result = Exporter.run(items: [ExportItem(photo: Photo(relativePath: url.lastPathComponent, url: url), adjustments: a)], destination: destination, roots: [], options: options, cancellation: ExportCancellation()) { _, _ in }
        XCTAssertEqual(result.completed, 1); XCTAssertTrue(result.errors.isEmpty)
        let output = try XCTUnwrap(CIImage(contentsOf: destination.appendingPathComponent(url.lastPathComponent)))
        XCTAssertEqual(output.extent.size, full.extent.size)
        XCTAssertEqual(try Data(contentsOf: url), sourceBytes)
        for i in 0..<4 { XCTAssertEqual(Int(pixel(output, x: 80, y: 80, renderer: r)[i]), Int(pixel(full, x: 80, y: 80, renderer: r)[i]), accuracy: 2) }
    }

    @MainActor func testStraightenDraftStreamsBeforeReleaseAndCommitsOneUndoWithCrop() async throws {
        _ = try fixture()
        let model = AppModel(restoringSession: false, supportDirectory: root.appendingPathComponent("support"))
        model.open(WorkspaceReference(path: root.path)); try await settle(model)
        let before = model.settings.adjustments
        model.beginCrop(); try await settle(model)
        let originalSize = model.preview?.sourceSize
        model.straightenEditing(true)
        model.setStraightenDraft(3); try await settle(model)
        XCTAssertNotEqual(model.preview?.sourceSize, originalSize, "A completed frame must arrive before slider release")
        model.setStraightenDraft(6); try await settle(model)
        XCTAssertEqual(model.settings.adjustments, before)
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(WorkspaceStore(root: root).settings(for: "horizon.png").adjustments, before)
        model.straightenEditing(false)
        model.setCropAspect(.square)
        model.cancelCrop(); try await settle(model)
        XCTAssertEqual(model.settings.adjustments, before); XCTAssertFalse(model.canUndo)
        model.beginCrop(); try await settle(model)
        model.levelHorizon(by: 5); try await settle(model)
        model.setCropAspect(.square)
        model.applyCrop(); try await settle(model)
        let applied = model.settings.adjustments
        XCTAssertEqual(applied.geometry.straightenAngle, 5); XCTAssertNotNil(applied.geometry.crop)
        model.undo(); try await settle(model)
        XCTAssertEqual(model.settings.adjustments, before); XCTAssertFalse(model.canUndo)
        model.redo(); try await settle(model)
        XCTAssertEqual(model.settings.adjustments, applied)
        XCTAssertTrue(model.flush())
        XCTAssertEqual(WorkspaceStore(root: root).settings(for: "horizon.png").adjustments, applied)
        XCTAssertTrue(model.prepareToQuit())
    }

    @MainActor func testViewingModesPreserveEditsViewportAndMetadata() async throws {
        let url = try fixture()
        try FileManager.default.copyItem(at: url, to: root.appendingPathComponent("second.png"))
        let model = AppModel(restoringSession: false, supportDirectory: root.appendingPathComponent("support"))
        model.open(WorkspaceReference(path: root.path)); try await settle(model)
        XCTAssertTrue(model.flush())
        let metadata = root.appendingPathComponent(".pictuner/workspace.json"), saved = try Data(contentsOf: metadata)
        model.updateCanvasGeometry(CGSize(width: 200, height: 160), backing: 2); model.setZoom(2)
        let viewport = model.viewport
        model.toggleComparisonWipe(); model.setWipePosition(0.7)
        XCTAssertEqual(model.activeWipe, 0.7)
        model.showingOriginal = true; XCTAssertNil(model.activeWipe)
        model.showingOriginal = false; XCTAssertEqual(model.activeWipe, 0.7)
        model.showMask = true; XCTAssertNil(model.activeWipe); model.showMask = false
        model.toggleDistractionFree(); XCTAssertTrue(model.distractionFree)
        XCTAssertEqual(model.viewport, viewport)
        model.escapePreview(); XCTAssertFalse(model.distractionFree); XCTAssertTrue(model.comparisonWipe)
        XCTAssertEqual(model.viewport, viewport)
        XCTAssertEqual(try Data(contentsOf: metadata), saved)
        model.setWipePosition(-4); XCTAssertEqual(model.wipePosition, 0)
        model.setWipePosition(4); XCTAssertEqual(model.wipePosition, 1)
        model.setWipePosition(.nan); XCTAssertEqual(model.wipePosition, 1)
        model.navigate(1); try await settle(model)
        XCTAssertEqual(model.wipePosition, 0.5)
        model.beginCrop(); try await settle(model)
        XCTAssertFalse(model.comparisonWipe)
        model.toggleDistractionFree(); XCTAssertFalse(model.distractionFree)
        model.setStraightenDraft(8)
        model.navigate(-1); try await settle(model)
        XCTAssertFalse(model.isCropping); XCTAssertEqual(model.settings.adjustments.geometry.straightenAngle, 0)
        XCTAssertTrue(model.prepareToQuit())
    }

    @MainActor func testWipeDrawsOriginalDetailOnlyOnLeftAndKeepsPanningAvailable() throws {
        let r = Renderer()
        func solid(_ color: CIColor) throws -> CGImage { try r.cgImage(CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))) }
        let canvas = PhotoCanvas(frame: CGRect(x: 0, y: 0, width: 280, height: 180))
        canvas.sourceSize = CGSize(width: 400, height: 240)
        canvas.image = try solid(CIColor(red: 1, green: 0, blue: 0))
        canvas.detailImage = canvas.image; canvas.detailRegion = CGRect(x: 0, y: 0, width: 1, height: 1)
        canvas.originalImage = try solid(CIColor(red: 0, green: 1, blue: 0))
        canvas.originalDetail = try solid(CIColor(red: 0, green: 0, blue: 1))
        canvas.wipe = 0.5
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 280, pixelsHigh: 180, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        canvas.draw(canvas.bounds)
        NSGraphicsContext.restoreGraphicsState()
        let left = try XCTUnwrap(bitmap.colorAt(x: 80, y: 80)?.usingColorSpace(.deviceRGB))
        let right = try XCTUnwrap(bitmap.colorAt(x: 200, y: 80)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(left.blueComponent, 0.95); XCTAssertLessThan(left.redComponent, 0.05)
        XCTAssertGreaterThan(right.redComponent, 0.95); XCTAssertLessThan(right.blueComponent, 0.05)
        canvas.viewport = PhotoViewport(scale: 2)
        var moved: Double?, panned = false
        canvas.wipeChanged = { moved = $0 }; canvas.viewportChanged = { _, _, _ in panned = true }
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let origin = CGPoint(x: canvas.wipeX, y: 80)
        canvas.mouseDown(with: mouse(.leftMouseDown, origin))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 210, y: 80)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 210, y: 80)))
        XCTAssertEqual(try XCTUnwrap(moved), 0.75, accuracy: 0.001); XCTAssertFalse(panned)
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 60, y: 60)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 80, y: 60)))
        XCTAssertTrue(panned)
    }
}
