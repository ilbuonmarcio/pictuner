import XCTest
import CoreImage
import AppKit
@testable import Pictuner

final class GeometryTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PictunerGeometry-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func fixture() throws -> URL {
        let r = Renderer()
        var image = CIImage.empty()
        for (rect, color) in [
            (CGRect(x: 0, y: 0, width: 200, height: 120), CIColor(red: 1, green: 0, blue: 0)),
            (CGRect(x: 200, y: 0, width: 200, height: 120), CIColor(red: 0, green: 0, blue: 1)),
            (CGRect(x: 0, y: 120, width: 200, height: 120), CIColor(red: 0, green: 1, blue: 0)),
            (CGRect(x: 200, y: 120, width: 200, height: 120), CIColor(red: 1, green: 1, blue: 0))
        ] { image = CIImage(color: color).cropped(to: rect).composited(over: image) }
        let url = root.appendingPathComponent("quadrants.png")
        try r.context.writePNGRepresentation(of: image, to: url, format: .RGBA8, colorSpace: r.colorSpace)
        return url
    }
    private func pixel(_ image: CIImage, _ x: Double, _ y: Double, _ r: Renderer) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        r.context.render(image, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: r.colorSpace)
        return bytes
    }
    private func assertMatches(_ actual: CIImage, _ expected: CIImage, _ r: Renderer, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.extent.size, expected.extent.size, file: file, line: line)
        for (x, y) in [(0.2,0.2), (0.8,0.2), (0.2,0.8), (0.8,0.8)] {
            let p = pixel(actual, floor(x*actual.extent.width), floor(y*actual.extent.height), r)
            let e = pixel(expected, floor(x*expected.extent.width), floor(y*expected.extent.height), r)
            for i in 0..<4 { XCTAssertEqual(Int(p[i]), Int(e[i]), accuracy: 2, file: file, line: line) }
        }
    }

    func testRotateAndFlipPreserveVisibleCropForEveryOrientation() throws {
        let r = Renderer(), source = try r.load(fixture())
        for turns in 0..<4 {
            for h in [false, true] {
                for v in [false, true] {
                    var a = Adjustments()
                    a.geometry = ImageGeometry(quarterTurns: turns, flipHorizontal: h, flipVertical: v, crop: CropRegion(CGRect(x: 0.1, y: 0.25, width: 0.5, height: 0.5)), straightenAngle: 7)
                    let before = try r.render(source, adjustments: a)
                    for clockwise in [false, true] {
                        var next = a; next.geometry.rotate(clockwise: clockwise)
                        var expected = ImageGeometry(); expected.quarterTurns = clockwise ? 1 : 3
                        assertMatches(try r.render(source, adjustments: next), r.geometry(before, expected), r)
                    }
                    for horizontal in [false, true] {
                        var next = a; next.geometry.flip(horizontal: horizontal)
                        var expected = ImageGeometry(); expected.flip(horizontal: horizontal)
                        assertMatches(try r.render(source, adjustments: next), r.geometry(before, expected), r)
                    }
                }
            }
        }
    }

    func testCropBoundsAspectAndMovementAreConstrained() throws {
        let c = CropRegion(CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6))
        let square = c.fitted(aspect: 1, source: CGSize(width: 400, height: 240))
        XCTAssertEqual(square.width*400, square.height*240, accuracy: 0.0001)
        XCTAssertEqual(square.rect.midX, c.rect.midX, accuracy: 0.0001)
        let moved = square.moved(by: CGSize(width: 10, height: -10))
        XCTAssertEqual(moved.rect.maxX, 1, accuracy: 0.0001)
        XCTAssertEqual(moved.y, 0)
        let resized = CropRegion.between(anchor: CGPoint(x: 0.9, y: 0.8), point: CGPoint(x: -2, y: -1), ratio: 1.5)
        XCTAssertGreaterThanOrEqual(resized.x, 0); XCTAssertGreaterThanOrEqual(resized.y, 0)
        XCTAssertEqual(resized.width/resized.height, 1.5, accuracy: 0.0001)
        let tiny = CropRegion(CGRect(x: 0.999, y: 0.999, width: 0.001, height: 0.001)).pixelRect(in: CGSize(width: 400, height: 240))
        XCTAssertEqual(tiny, CGRect(x: 399, y: 239, width: 1, height: 1))
        XCTAssertEqual(CropAspect.fourThree.ratio(source: .zero), 4.0/3)
        let collapsed = CropRegion.between(anchor: CGPoint(x: 1, y: 1), point: CGPoint(x: 1, y: 1))
        XCTAssertLessThan(collapsed.width, 0.02); XCTAssertLessThan(collapsed.height, 0.02)
    }

    func testLegacyMetadataAndPresetsDecodeWithNeutralGeometry() throws {
        var a = Adjustments(); a.exposure = 1.25
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as? [String: Any])
        json.removeValue(forKey: "geometry")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(try JSONDecoder().decode(Adjustments.self, from: legacy), a)
        let metadata: [String: Any] = ["schemaVersion": 2, "renderVersion": 1, "workspaceID": UUID().uuidString,
                                     "images": ["missing.nef": ["favorite": true, "rejected": false, "exportReady": true, "adjustments": json]]]
        let directory = root.appendingPathComponent(".pictuner")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("workspace.json")
        let bytes = try JSONSerialization.data(withJSONObject: metadata); try bytes.write(to: url)
        let store = WorkspaceStore(root: root)
        XCTAssertNil(store.failure); XCTAssertEqual(store.document.schemaVersion, 6)
        XCTAssertEqual(store.settings(for: "missing.nef").adjustments, a)
        XCTAssertTrue(store.settings(for: "missing.nef").exportReady)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        var edited = store.settings(for: "missing.nef")
        edited.adjustments.geometry.rotate(clockwise: true)
        edited.adjustments.geometry.crop = CropRegion(CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.8))
        store.update(edited, for: "missing.nef"); XCTAssertTrue(store.save())
        XCTAssertEqual(WorkspaceStore(root: root).settings(for: "missing.nef"), edited)
        json["geometry"] = ["quarterTurns": 0, "flipHorizontal": false, "flipVertical": false,
                            "crop": ["x": 0, "y": 0, "width": -1, "height": 1]]
        XCTAssertThrowsError(try JSONDecoder().decode(Adjustments.self, from: JSONSerialization.data(withJSONObject: json)))
    }

    func testPreviewDetailHistogramAndExportShareGeometry() throws {
        let url = try fixture(), bytes = try Data(contentsOf: url), r = Renderer()
        var a = Adjustments(); a.geometry.rotate(clockwise: true); a.geometry.flip(horizontal: true)
        a.geometry.crop = CropRegion(CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        a.exposure = -0.4; a.vignette = 0.2
        let full = try r.render(r.load(url), adjustments: a)
        let frame = try r.preview(url: url, adjustments: a, detailViewport: DetailViewport(region: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), scale: 1))
        XCTAssertEqual(frame.sourceSize, CGSize(width: 120, height: 200))
        assertMatches(CIImage(cgImage: frame.edited), full, r)
        let detail = try XCTUnwrap(frame.detail)
        XCTAssertEqual(detail.edited.width, 60); XCTAssertEqual(detail.edited.height, 100)
        let expected = full.cropped(to: CGRect(x: 30, y: 50, width: 60, height: 100)).transformed(by: CGAffineTransform(translationX: -30, y: -50))
        assertMatches(CIImage(cgImage: detail.edited), expected, r)
        XCTAssertEqual(frame.histogram.red.reduce(0,+), 120*200)
        // Removing geometry must invalidate the cached transformed baseline.
        let neutral = try r.preview(url: url, adjustments: Adjustments())
        XCTAssertEqual(neutral.sourceSize, CGSize(width: 400, height: 240))
        var options = ExportOptions(); options.format = .png
        let output = root.appendingPathComponent("export")
        let result = Exporter.run(items: [ExportItem(photo: Photo(relativePath: "quadrants.png", url: url), adjustments: a)], destination: output, roots: [], options: options, cancellation: ExportCancellation()) { _, _ in }
        XCTAssertEqual(result.completed, 1); XCTAssertTrue(result.errors.isEmpty)
        assertMatches(try XCTUnwrap(CIImage(contentsOf: output.appendingPathComponent("quadrants.png"))), full, r)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    @MainActor private func settle(_ model: AppModel) async throws {
        for _ in 0..<300 where model.isLoading || model.isRendering || model.preview == nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(model.preview); XCTAssertFalse(model.isRendering)
    }
    @MainActor func testCropCancelApplyUndoRedoAndNavigation() async throws {
        let url = try fixture()
        try FileManager.default.copyItem(at: url, to: root.appendingPathComponent("second.png"))
        let model = AppModel(restoringSession: false)
        model.open(WorkspaceReference(path: root.path)); try await settle(model)
        model.rotate(clockwise: true); try await settle(model)
        model.setZoom(2)
        model.beginCrop(); try await settle(model)
        XCTAssertEqual(model.viewport, PhotoViewport())
        let before = model.settings.adjustments
        model.setCropAspect(.square)
        let draft = try XCTUnwrap(model.cropDraft)
        XCTAssertEqual(draft.width*240, draft.height*400, accuracy: 0.0001)
        model.cancelCrop(); try await settle(model)
        XCTAssertEqual(model.settings.adjustments, before)
        model.beginCrop(); try await settle(model)
        model.updateCrop(CropRegion(CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))
        model.applyCrop(); try await settle(model)
        XCTAssertFalse(model.isCropping); XCTAssertEqual(model.preview?.sourceSize, CGSize(width: 120, height: 200))
        let applied = model.settings.adjustments
        model.undo(); try await settle(model); XCTAssertEqual(model.settings.adjustments, before)
        model.redo(); try await settle(model); XCTAssertEqual(model.settings.adjustments, applied)
        model.clearCrop(); try await settle(model); XCTAssertNil(model.settings.adjustments.geometry.crop)
        model.undo(); try await settle(model); XCTAssertEqual(model.settings.adjustments, applied)
        XCTAssertTrue(model.flush())
        XCTAssertEqual(WorkspaceStore(root: root).settings(for: "quadrants.png").adjustments, applied)
        model.beginCrop(); try await settle(model)
        model.updateCrop(.full)
        model.navigate(1); try await settle(model)
        XCTAssertFalse(model.isCropping); XCTAssertEqual(model.settings.adjustments.geometry, ImageGeometry())
        XCTAssertTrue(model.prepareToQuit())
    }

    @MainActor func testReusableEditsPreserveEachPhotosFraming() async throws {
        let url = try fixture()
        try FileManager.default.copyItem(at: url, to: root.appendingPathComponent("second.png"))
        let model = AppModel(restoringSession: false, supportDirectory: root.appendingPathComponent("support"))
        model.open(WorkspaceReference(path: root.path)); try await settle(model)
        model.rotate(clockwise: true); model.flip(horizontal: true)
        model.beginCrop(); try await settle(model)
        model.setStraightenDraft(4); try await settle(model); model.applyCrop(); try await settle(model)
        var edited = model.settings.adjustments; edited.exposure = 0.75; model.setAdjustments(edited)
        model.copyAdjustments(); model.selectAll(); model.applyToSelection()
        let other = try XCTUnwrap(model.photos.first { $0.id == "second.png" })
        XCTAssertEqual(model.savedSettings(for: other).adjustments.geometry, ImageGeometry())
        XCTAssertEqual(model.savedSettings(for: other).adjustments.exposure, 0.75)
        model.select(other); try await settle(model)
        model.flip(horizontal: false)
        let framing = model.settings.adjustments.geometry
        model.pasteAdjustments(); XCTAssertEqual(model.settings.adjustments.geometry, framing)
        model.applyColorAdjustments(Adjustments()); XCTAssertEqual(model.settings.adjustments.geometry, framing)
        model.savePreset(name: "Color"); XCTAssertEqual(model.presets.last?.adjustments.geometry, ImageGeometry())
        XCTAssertTrue(model.prepareToQuit())
    }

    @MainActor func testCropKeyboardApplyCancelAndArrowMove() {
        let canvas = PhotoCanvas(); canvas.sourceSize = CGSize(width: 400, height: 240)
        canvas.crop = CropRegion(CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
        var done: Bool?, changes = 0
        canvas.cropFinished = { done = $0 }; canvas.cropChanged = { _ in changes += 1 }
        func key(_ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        canvas.keyDown(with: key(124)); XCTAssertEqual(changes, 1)
        XCTAssertEqual(canvas.crop?.x ?? 0, 0.1025, accuracy: 0.0001)
        canvas.keyDown(with: key(36)); XCTAssertEqual(done, true)
        canvas.keyDown(with: key(53)); XCTAssertEqual(done, false)
    }
}
