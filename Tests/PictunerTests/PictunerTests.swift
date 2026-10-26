import XCTest
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import AppKit
@testable import Pictuner

final class PictunerTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PictunerTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testSettingsSurviveReopeningAndMissingImages() throws {
        let store = WorkspaceStore(root: root)
        var settings = ImageSettings()
        settings.adjustments.exposure = 1.25
        settings.adjustments.selective.enabled = true
        settings.adjustments.selective.hue = 0.98
        settings.favorite = true
        settings.exportReady = true
        store.update(settings, for: "nested/missing.dng")
        XCTAssertTrue(store.save())
        let reopened = WorkspaceStore(root: root)
        XCTAssertNil(reopened.failure)
        XCTAssertEqual(reopened.settings(for: "nested/missing.dng"), settings)
    }

    func testVersionOneMigrationPreservesEditsAndLeavesPhotosUnmarked() throws {
        let directory = root.appendingPathComponent(".pictuner")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var settings = ImageSettings()
        settings.favorite = true
        settings.adjustments.exposure = 1.25
        var document = WorkspaceDocument()
        document.images["nested/car.nef"] = settings
        document.lastImage = "nested/car.nef"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        json["schemaVersion"] = 1
        var images = try XCTUnwrap(json["images"] as? [String: [String: Any]])
        images["nested/car.nef"]?.removeValue(forKey: "exportReady")
        json["images"] = images
        let original = try JSONSerialization.data(withJSONObject: json)
        let url = directory.appendingPathComponent("workspace.json")
        try original.write(to: url)
        let store = WorkspaceStore(root: root)
        XCTAssertNil(store.failure)
        XCTAssertEqual(store.document.schemaVersion, 6)
        XCTAssertEqual(store.document.lastImage, "nested/car.nef")
        XCTAssertEqual(store.settings(for: "nested/car.nef"), settings)
        XCTAssertFalse(store.settings(for: "nested/car.nef").exportReady)
        XCTAssertEqual(try Data(contentsOf: url), original, "Loading must not rewrite existing metadata")
        XCTAssertTrue(store.save())
        let reopened = WorkspaceStore(root: root)
        XCTAssertEqual(reopened.document.schemaVersion, 6)
        XCTAssertEqual(reopened.settings(for: "nested/car.nef"), settings)
    }

    func testCorruptMetadataIsNeverReplaced() throws {
        let directory = root.appendingPathComponent(".pictuner")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("workspace.json")
        let original = Data("invalid json".utf8)
        try original.write(to: url)
        let store = WorkspaceStore(root: root)
        XCTAssertNotNil(store.failure)
        store.update(ImageSettings(), for: "test.jpg")
        XCTAssertFalse(store.save())
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testNewerVersionIsPreserved() throws {
        let directory = root.appendingPathComponent(".pictuner")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("workspace.json")
        let original = Data(#"{"schemaVersion":99,"renderVersion":1}"#.utf8)
        try original.write(to: url)
        let store = WorkspaceStore(root: root)
        XCTAssertFalse(store.save())
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testConcurrentEditorsCannotClobberMetadata() throws {
        let first = WorkspaceStore(root: root)
        XCTAssertTrue(first.save())
        let second = WorkspaceStore(root: root)
        var settings = ImageSettings(); settings.adjustments.contrast = 1.5
        first.update(settings, for: "one.jpg")
        XCTAssertTrue(first.save())
        let snapshot = try Data(contentsOf: first.metadataURL)
        second.update(ImageSettings(), for: "two.jpg")
        XCTAssertFalse(second.save())
        XCTAssertEqual(try Data(contentsOf: first.metadataURL), snapshot)
    }

    func testMetadataSymlinkIsRejected() throws {
        let source = root.appendingPathComponent("original.jpg")
        try Data("source".utf8).write(to: source)
        let directory = root.appendingPathComponent(".pictuner")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("workspace.json"), withDestinationURL: source)
        XCTAssertFalse(WorkspaceStore(root: root).save())
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
    }

    func testScanIsRecursiveNaturallySortedAndSkipsMetadataAndSymlinks() throws {
        for path in ["10.jpg", "2.jpg", "nested/camera.nef", ".pictuner/cache.png", "notes.txt"] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias.jpg"), withDestinationURL: root.appendingPathComponent("2.jpg"))
        XCTAssertEqual(try ImageFiles.scan(root).map(\.relativePath), ["2.jpg", "10.jpg", "nested/camera.nef"])
    }

    func testExportNeverOverwritesExistingFileOrLinks() throws {
        let workspace = root.appendingPathComponent("workspace")
        let output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let source = workspace.appendingPathComponent("car.jpg")
        let original = Data("original photo".utf8)
        try original.write(to: source)
        let symlink = output.appendingPathComponent("car.jpg")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
        let replacement = Data("edited copy".utf8)
        XCTAssertNil(try Exporter.publish(replacement, to: symlink, collision: .skip, protectedRoots: [workspace]))
        let renamed = try Exporter.publish(replacement, to: symlink, collision: .rename, protectedRoots: [workspace])
        XCTAssertEqual(renamed?.lastPathComponent, "car-1.jpg")
        XCTAssertEqual(try Data(contentsOf: source), original)
        let hardLink = output.appendingPathComponent("hard.jpg")
        try FileManager.default.linkItem(at: source, to: hardLink)
        XCTAssertNil(try Exporter.publish(replacement, to: hardLink, collision: .skip, protectedRoots: [workspace]))
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testExportRejectsWorkspaceAndSymlinkedParent() throws {
        let workspace = root.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: workspace)
        XCTAssertThrowsError(try Exporter.publish(Data(), to: workspace.appendingPathComponent("image.jpg"), collision: .rename, protectedRoots: [workspace]))
        XCTAssertThrowsError(try Exporter.publish(Data(), to: alias.appendingPathComponent("image.jpg"), collision: .rename, protectedRoots: [workspace]))
    }

    func pixel(_ image: CIImage, renderer: Renderer) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        renderer.context.render(image, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: renderer.colorSpace)
        return bytes
    }

    func testNeutralPipelineAndExposure() throws {
        let renderer = Renderer()
        let input = CIImage(color: CIColor(red: 0.3, green: 0.4, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        XCTAssertEqual(pixel(try renderer.render(input, adjustments: Adjustments()), renderer: renderer), pixel(input, renderer: renderer))
        var a = Adjustments(); a.exposure = 1
        let brighter = pixel(try renderer.render(input, adjustments: a), renderer: renderer)
        XCTAssertGreaterThan(brighter[0], pixel(input, renderer: renderer)[0])
    }

    func testSelectiveColorKeepsGreenAndMutesBlue() throws {
        let renderer = Renderer()
        var a = Adjustments()
        a.selective.enabled = true; a.selective.hue = 1.0/3; a.selective.selectedSaturation = 1
        a.selective.saturation = 1; a.selective.brightness = 1
        a.selective.hueRange = 0.05; a.selective.softness = 0.01
        for (color, shouldBeGray) in [(CIColor(red: 0, green: 1, blue: 0), false), (CIColor(red: 0, green: 0, blue: 1), true)] {
            let input = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
            let output = pixel(try renderer.render(input, adjustments: a), renderer: renderer)
            if shouldBeGray { XCTAssertEqual(output[0], output[1], accuracy: 1); XCTAssertEqual(output[1], output[2], accuracy: 1) }
            else { XCTAssertGreaterThan(output[1], 240); XCTAssertLessThan(output[0], 10) }
        }
    }

    func testHueWraparoundAndMaskSoftness() throws {
        let renderer = Renderer()
        var selective = SelectiveColor()
        selective.enabled = true; selective.hue = 0.99; selective.saturation = 1; selective.brightness = 1
        selective.hueRange = 0.04; selective.softness = 0.1
        let red = CIImage(color: CIColor(red: 1, green: 0.04, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let mask = pixel(try renderer.selective(red, selective, mask: true), renderer: renderer)
        XCTAssertGreaterThan(mask[0], 245)
        let orange = CIImage(color: CIColor(red: 1, green: 0.4, blue: 0)).cropped(to: red.extent)
        let soft = pixel(try renderer.selective(orange, selective, mask: true), renderer: renderer)
        XCTAssertGreaterThan(soft[0], 0); XCTAssertLessThan(soft[0], 255)
    }

    func testFullExportRendersResizesAndPreservesSource() throws {
        let workspace = root.appendingPathComponent("workspace")
        let output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let source = workspace.appendingPathComponent("test.png")
        let renderer = Renderer()
        let input = CIImage(color: CIColor(red: 0.3, green: 0.4, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 50))
        try renderer.context.writePNGRepresentation(of: input, to: source, format: .RGBA8, colorSpace: renderer.colorSpace)
        let bytes = try Data(contentsOf: source)
        var options = ExportOptions(); options.format = .png; options.longEdge = 40
        var a = Adjustments(); a.exposure = 1
        let result = Exporter.run(items: [ExportItem(photo: Photo(relativePath: "test.png", url: source), adjustments: a)], destination: output, roots: [workspace], options: options, cancellation: ExportCancellation()) { _, _ in }
        XCTAssertEqual(result.completed, 1); XCTAssertEqual(result.errors, [])
        let exported = try XCTUnwrap(CIImage(contentsOf: output.appendingPathComponent("test.png")))
        XCTAssertEqual(exported.extent.size, CGSize(width: 40, height: 20))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertGreaterThan(pixel(exported, renderer: renderer)[0], pixel(input, renderer: renderer)[0])
    }

    func testHistogramCountsAndOriginalPreview() throws {
        let renderer = Renderer()
        let input = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 10))
        let histogram = renderer.histogram(input)
        XCTAssertEqual(histogram.red[255], 200)
        XCTAssertEqual(histogram.green[0], 200)
        XCTAssertEqual(histogram.luminance.reduce(0, +), 200)
    }
}

final class WorkflowTests: XCTestCase {
    @MainActor func testExportFilterControlsNavigationAndRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PicTunerFilter-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let renderer = Renderer()
        for name in ["1.png", "2.png", "3.png"] {
            let image = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 20))
            try renderer.context.writePNGRepresentation(of: image, to: root.appendingPathComponent(name), format: .RGBA8, colorSpace: renderer.colorSpace)
        }
        let model = AppModel(restoringSession: false, supportDirectory: root.appendingPathComponent("support"))
        model.open(WorkspaceReference(path: root.path))
        for _ in 0..<100 where model.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.photos.count, 3)
        model.setExportReady(true, for: ["1.png", "3.png"])
        model.toggleExportOnly()
        XCTAssertEqual(model.visiblePhotos.map(\.name), ["1.png", "3.png"])
        model.navigate(1)
        XCTAssertEqual(model.activePhoto?.name, "3.png")
        model.navigate(1)
        XCTAssertEqual(model.activePhoto?.name, "3.png")
        model.navigate(-1)
        XCTAssertEqual(model.activePhoto?.name, "1.png")
        model.toggleExportReady()
        XCTAssertEqual(model.activePhoto?.name, "3.png")
        model.toggleRejected()
        XCTAssertTrue(model.visiblePhotos.isEmpty)
        XCTAssertNil(model.activePhoto)
        model.navigate(1)
        XCTAssertNil(model.activePhoto)
        model.toggleExportOnly()
        XCTAssertEqual(model.visiblePhotos.count, 3)
        XCTAssertEqual(model.activePhoto?.name, "1.png")
        XCTAssertTrue(model.prepareToQuit())
    }

    @MainActor func testRapidSelectionCannotPublishPreviousImageAndEditsPersist() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PictunerWorkflow-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let renderer = Renderer()
        for (name, color) in [("1.png", CIColor(red: 0.1, green: 0.5, blue: 0.1)), ("2.png", CIColor(red: 0.1, green: 0.1, blue: 0.5))] {
            let image = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 120, height: 80))
            try renderer.context.writePNGRepresentation(of: image, to: root.appendingPathComponent(name), format: .RGBA8, colorSpace: renderer.colorSpace)
        }
        let model = AppModel(restoringSession: false, supportDirectory: root.appendingPathComponent("support"))
        model.open(WorkspaceReference(path: root.path))
        for _ in 0..<100 where model.photos.count != 2 { try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertEqual(model.photos.count, 2)
        var a = Adjustments(); a.exposure = 1.2
        model.setAdjustments(a)
        model.navigate(1)
        for _ in 0..<100 where model.isRendering { try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertEqual(model.activePhoto?.name, "2.png")
        XCTAssertEqual(model.settings.adjustments.exposure, 0)
        let preview = try XCTUnwrap(model.preview)
        let sample = Renderer.sample(preview.edited, at: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(sample.0, 2.0/3, accuracy: 0.03)
        let store = WorkspaceStore(root: root)
        XCTAssertEqual(store.settings(for: "1.png").adjustments.exposure, 1.2)
        model.navigate(-1)
        XCTAssertEqual(model.settings.adjustments.exposure, 1.2)
        XCTAssertTrue(model.prepareToQuit())
    }

    @MainActor func testSliderGestureCoalescesUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PictunerUndo-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("test.jpg"))
        let model = AppModel(restoringSession: false, supportDirectory: root.appendingPathComponent("support"))
        model.open(WorkspaceReference(path: root.path))
        for _ in 0..<100 where model.photos.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        model.editingGesture(true)
        for exposure in [0.2, 0.4, 0.6] { var a = Adjustments(); a.exposure = exposure; model.setAdjustments(a) }
        model.editingGesture(false)
        model.undo()
        XCTAssertEqual(model.settings.adjustments.exposure, 0)
        XCTAssertFalse(model.canUndo)
        model.redo()
        XCTAssertEqual(model.settings.adjustments.exposure, 0.6)
        XCTAssertTrue(model.prepareToQuit())
    }

    @MainActor func testOnlyExplicitlyMarkedPhotosExportAcrossWorkspaceAndScopes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PictunerExportFlags-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["1.jpg", "2.jpg", "nested/3.jpg", "nested/4.jpg"] { try Data().write(to: root.appendingPathComponent(name)) }
        let model = AppModel(restoringSession: false, supportDirectory: root.appendingPathComponent("support"))
        let reference = WorkspaceReference(path: root.path)
        model.open(reference)
        for _ in 0..<100 where model.photos.count != 4 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.photos.count, 4)
        XCTAssertEqual(model.exportOptions.scope, .ready)
        XCTAssertTrue(model.exportItems().isEmpty, "New images are never implicitly approved")
        model.toggleExportReady() // 1.jpg
        model.toggleFavorite()
        model.select(model.photos[1])
        model.toggleFavorite() // Favorite alone does not qualify 2.jpg.
        model.setExportReady(true, for: ["nested/3.jpg", "nested/4.jpg"])
        XCTAssertEqual(model.exportItems().map { $0.photo.id }, ["1.jpg", "nested/3.jpg", "nested/4.jpg"])
        model.select(model.photos[2])
        model.toggleRejected()
        XCTAssertFalse(model.settings.exportReady)
        XCTAssertEqual(model.exportReadyCount, 2)
        model.selectFolder("nested")
        XCTAssertEqual(model.exportItems().map { $0.photo.id }, ["1.jpg", "nested/4.jpg"], "Default scope includes marked photos throughout the workspace")
        model.exportOptions.scope = .currentFolder
        XCTAssertEqual(model.exportItems().map { $0.photo.id }, ["nested/4.jpg"])
        model.exportOptions.scope = .selected
        model.selectedIDs = ["1.jpg", "2.jpg", "nested/3.jpg", "nested/4.jpg"]
        XCTAssertEqual(model.exportItems().map { $0.photo.id }, ["1.jpg", "nested/4.jpg"])
        model.exportOptions.scope = .favorites
        XCTAssertEqual(model.exportItems().map { $0.photo.id }, ["1.jpg"])
        model.exportOptions.scope = .ready
        XCTAssertTrue(model.flush())
        model.open(reference)
        for _ in 0..<100 where model.photos.count != 4 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.exportItems().map { $0.photo.id }, ["1.jpg", "nested/4.jpg"])
        // Marking a rejected photo explicitly removes its rejection; unmarking is persistent.
        model.select(model.photos[2])
        model.toggleExportReady()
        XCTAssertFalse(model.settings.rejected)
        XCTAssertTrue(model.settings.exportReady)
        model.setExportReady(false, for: ["1.jpg", "nested/3.jpg", "nested/4.jpg"])
        XCTAssertTrue(model.exportItems().isEmpty)
        XCTAssertTrue(model.prepareToQuit())
        let reopened = WorkspaceStore(root: root)
        XCTAssertFalse(reopened.settings(for: "1.jpg").exportReady)
        XCTAssertTrue(reopened.settings(for: "1.jpg").favorite)
    }

    @MainActor func testBatchUndoRestoresOtherImages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PictunerBatch-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["1.jpg", "2.jpg", "3.jpg"] { try Data().write(to: root.appendingPathComponent(name)) }
        let model = AppModel(restoringSession: false, supportDirectory: root.appendingPathComponent("support"))
        model.open(WorkspaceReference(path: root.path))
        for _ in 0..<100 where model.photos.count != 3 { try await Task.sleep(for: .milliseconds(20)) }
        var a = Adjustments(); a.exposure = 1.5
        model.setAdjustments(a)
        model.selectedIDs = Set(model.photos.prefix(2).map(\.id))
        model.applyToSelection()
        XCTAssertEqual(model.savedSettings(for: model.photos[1]).adjustments.exposure, 1.5)
        XCTAssertEqual(model.savedSettings(for: model.photos[2]).adjustments.exposure, 0)
        model.undo()
        XCTAssertEqual(model.settings.adjustments.exposure, 1.5)
        XCTAssertEqual(model.savedSettings(for: model.photos[1]).adjustments.exposure, 0)
        model.redo()
        XCTAssertEqual(model.savedSettings(for: model.photos[1]).adjustments.exposure, 1.5)
        XCTAssertTrue(model.prepareToQuit())
    }

    @MainActor func testSaveConflictCanBeRecoveredByExplicitDiscard() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PictunerConflict-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("photo.jpg"))
        let model = AppModel(restoringSession: false, supportDirectory: root.appendingPathComponent("support"))
        model.open(WorkspaceReference(path: root.path))
        for _ in 0..<100 where model.photos.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(model.flush())
        let external = WorkspaceStore(root: root)
        var settings = ImageSettings(); settings.adjustments.exposure = 0.5
        external.update(settings, for: "photo.jpg")
        XCTAssertTrue(external.save())
        var a = Adjustments(); a.exposure = 1.5
        model.setAdjustments(a)
        XCTAssertFalse(model.flush())
        XCTAssertTrue(model.hasUnsavedEdits)
        model.discardAndReload()
        for _ in 0..<100 where model.photos.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.settings.adjustments.exposure, 0.5)
        XCTAssertTrue(model.prepareToQuit())
    }

    @MainActor func testComparisonKeyReleaseRepeatAndFocusLoss() throws {
        let canvas = PhotoCanvas()
        var states: [Bool] = []
        canvas.compare = { states.append($0) }
        func space(_ type: NSEvent.EventType, repeated: Bool = false) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: repeated, keyCode: 49))
        }
        canvas.keyDown(with: try space(.keyDown))
        canvas.keyDown(with: try space(.keyDown, repeated: true))
        canvas.keyUp(with: try space(.keyUp))
        XCTAssertEqual(states, [true, false])
        canvas.keyDown(with: try space(.keyDown))
        _ = canvas.resignFirstResponder()
        XCTAssertEqual(states.suffix(2), [true, false])
    }

    func testRealRAWDevelopmentAndFullResolutionExport() throws {
        guard let path = ProcessInfo.processInfo.environment["PICTUNER_RAW_FIXTURE"] else {
            throw XCTSkip("Set PICTUNER_RAW_FIXTURE to a supported camera RAW file to run the integration test.")
        }
        let url = URL(fileURLWithPath: path)
        let before = try Data(contentsOf: url)
        let renderer = Renderer()
        let developed = try renderer.load(url)
        XCTAssertGreaterThan(developed.extent.width, 3000)
        let preview = try renderer.preview(url: url, adjustments: Adjustments())
        XCTAssertEqual(preview.sourceSize, developed.extent.size)
        XCTAssertLessThanOrEqual(preview.edited.width, 1800)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("PictunerRAWExport-\(UUID())")
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = Exporter.run(items: [ExportItem(photo: Photo(relativePath: url.lastPathComponent, url: url), adjustments: Adjustments())], destination: destination, roots: [url.deletingLastPathComponent()], options: ExportOptions(), cancellation: ExportCancellation()) { _, _ in }
        XCTAssertEqual(result.errors, [])
        XCTAssertEqual(result.completed, 1)
        let outputURL = destination.appendingPathComponent(url.deletingPathExtension().lastPathComponent).appendingPathExtension("jpg")
        let exported = try XCTUnwrap(CIImage(contentsOf: outputURL))
        XCTAssertEqual(exported.extent.size, developed.extent.size)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
}
