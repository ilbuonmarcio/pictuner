import XCTest
import CoreImage
@testable import Pictuner

final class WorkspaceResetTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PicTunerWorkspaceReset-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func editedSettings() -> ImageSettings {
        var settings = ImageSettings()
        settings.favorite = true; settings.exportReady = true
        settings.adjustments.exposure = 1.3
        settings.adjustments.selective.enabled = true
        settings.adjustments.geometry.rotate(clockwise: true)
        settings.adjustments.geometry.flip(horizontal: true)
        settings.adjustments.geometry.crop = CropRegion(CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
        return settings
    }

    func testResetPersistsAllPhotosIncludingMissingAndUnreadableFiles() throws {
        let source = root.appendingPathComponent("unreadable.dng")
        let bytes = Data("undecodable image must remain untouched".utf8)
        try bytes.write(to: source)
        let store = WorkspaceStore(root: root)
        store.update(editedSettings(), for: "unreadable.dng")
        store.update(editedSettings(), for: "nested/missing.nef")
        var rejected = editedSettings(); rejected.rejected = true; rejected.exportReady = false
        store.update(rejected, for: "nested/rejected.png")
        store.setLastImage("nested/missing.nef")
        XCTAssertTrue(store.save())
        let workspaceID = store.document.workspaceID

        XCTAssertTrue(store.resetImages())
        let reopened = WorkspaceStore(root: root)
        XCTAssertEqual(reopened.document.workspaceID, workspaceID)
        XCTAssertEqual(reopened.document.lastImage, "nested/missing.nef")
        XCTAssertEqual(Set(reopened.document.images.keys), ["unreadable.dng", "nested/missing.nef", "nested/rejected.png"])
        XCTAssertTrue(reopened.document.images.values.allSatisfy { $0 == ImageSettings() })
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    func testFailedResetPreservesMemoryAndExternalMetadata() throws {
        let store = WorkspaceStore(root: root)
        let before = editedSettings()
        store.update(before, for: "photo.png")
        XCTAssertTrue(store.save())
        let external = WorkspaceStore(root: root)
        var externalSettings = before; externalSettings.adjustments.exposure = -0.7
        external.update(externalSettings, for: "photo.png")
        XCTAssertTrue(external.save())
        let externalBytes = try Data(contentsOf: external.metadataURL)

        XCTAssertFalse(store.resetImages())
        XCTAssertEqual(store.settings(for: "photo.png"), before)
        XCTAssertEqual(try Data(contentsOf: external.metadataURL), externalBytes)

        for data in [Data("invalid json".utf8), Data(#"{"schemaVersion":99,"renderVersion":1}"#.utf8)] {
            try data.write(to: store.metadataURL)
            XCTAssertFalse(WorkspaceStore(root: root).resetImages())
            XCTAssertEqual(try Data(contentsOf: store.metadataURL), data)
        }
        try FileManager.default.removeItem(at: store.metadataURL)
        let source = root.appendingPathComponent("source.png")
        try externalBytes.write(to: source)
        try FileManager.default.createSymbolicLink(at: store.metadataURL, withDestinationURL: source)
        XCTAssertFalse(WorkspaceStore(root: root).resetImages())
        XCTAssertEqual(try Data(contentsOf: source), externalBytes)
    }

    @MainActor private func makeModel() async throws -> AppModel {
        let renderer = Renderer()
        for path in ["photo.png", "nested/other.png"] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let image = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.7)).cropped(to: CGRect(x: 0, y: 0, width: 120, height: 80))
            try renderer.context.writePNGRepresentation(of: image, to: url, format: .RGBA8, colorSpace: renderer.colorSpace)
        }
        let store = WorkspaceStore(root: root)
        for path in ["photo.png", "nested/other.png", "nested/missing.nef"] { store.update(editedSettings(), for: path) }
        XCTAssertTrue(store.save())
        let model = AppModel(restoringSession: false, supportDirectory: root.appendingPathComponent("support"))
        let reference = WorkspaceReference(path: root.path)
        model.workspaces = [reference]
        model.open(reference)
        for _ in 0..<200 where model.preview == nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(model.preview)
        return model
    }

    @MainActor func testActiveResetClearsPendingEditsFlagsCropAndUndoButKeepsWorkspaceAndSelection() async throws {
        let model = try await makeModel()
        model.selectFolder("nested")
        for _ in 0..<200 where model.preview == nil { try await Task.sleep(for: .milliseconds(20)) }
        let selectedID = model.selectedID
        let selectedIDs = model.selectedIDs
        let reference = try XCTUnwrap(model.activeWorkspace)
        let originalBytes = try Dictionary(uniqueKeysWithValues: model.photos.map { ($0.id, try Data(contentsOf: $0.url)) })
        model.presets = [UserPreset(name: "Keep", adjustments: editedSettings().adjustments)]
        let presets = model.presets
        model.adjustmentBinding(\.exposure).wrappedValue = 2
        XCTAssertTrue(model.canUndo)
        model.beginCrop()
        XCTAssertTrue(model.isCropping)
        model.showingOriginal = true; model.showMask = true; model.pickingColor = true

        model.resetWorkspace(reference)

        XCTAssertEqual(model.activeWorkspace, reference)
        XCTAssertEqual(model.workspaces, [reference])
        XCTAssertEqual(model.folder, "nested")
        XCTAssertEqual(model.selectedID, selectedID)
        XCTAssertEqual(model.selectedIDs, selectedIDs)
        XCTAssertEqual(model.settings, ImageSettings())
        XCTAssertEqual(model.exportReadyCount, 0)
        XCTAssertFalse(model.hasUnsavedEdits)
        XCTAssertFalse(model.canUndo); XCTAssertFalse(model.canRedo)
        XCTAssertFalse(model.isCropping); XCTAssertFalse(model.showingOriginal)
        XCTAssertFalse(model.showMask); XCTAssertFalse(model.pickingColor)
        XCTAssertEqual(model.presets.map(\.name), presets.map(\.name))
        XCTAssertEqual(model.presets.map(\.adjustments), presets.map(\.adjustments))
        for _ in 0..<200 where model.isRendering { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.preview?.sourceSize, CGSize(width: 120, height: 80), "A pre-reset rotated/cropped frame must not replace the reset preview")
        XCTAssertTrue(model.prepareToQuit())
        let reopened = WorkspaceStore(root: root)
        XCTAssertTrue(reopened.document.images.values.allSatisfy { $0 == ImageSettings() })
        for photo in model.photos { XCTAssertEqual(try Data(contentsOf: photo.url), originalBytes[photo.id]) }
    }

    @MainActor func testInactiveResetLeavesActiveEditsAloneAndMissingWorkspaceIsNotRecreated() async throws {
        let model = try await makeModel()
        let inactive = root.appendingPathComponent("another-workspace")
        try FileManager.default.createDirectory(at: inactive, withIntermediateDirectories: true)
        let store = WorkspaceStore(root: inactive)
        store.update(editedSettings(), for: "missing.dng")
        XCTAssertTrue(store.save())
        let reference = WorkspaceReference(path: inactive.path)
        model.workspaces.append(reference)
        model.adjustmentBinding(\.exposure).wrappedValue = 2
        let settings = model.settings
        let active = model.activeWorkspace
        let selected = model.selectedID
        model.resetWorkspace(reference)
        XCTAssertEqual(model.settings, settings)
        XCTAssertEqual(model.activeWorkspace, active)
        XCTAssertEqual(model.selectedID, selected)
        XCTAssertTrue(model.canUndo)
        XCTAssertTrue(model.hasUnsavedEdits)
        XCTAssertEqual(WorkspaceStore(root: inactive).settings(for: "missing.dng"), ImageSettings())
        model.undo()
        XCTAssertEqual(model.settings, editedSettings())

        try FileManager.default.removeItem(at: inactive)
        model.resetWorkspace(reference)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inactive.path))
        for _ in 0..<200 where model.isRendering { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(model.prepareToQuit())
    }

    @MainActor func testActiveResetConflictDoesNotPublishDefaultsOrClearUndo() async throws {
        let model = try await makeModel()
        model.adjustmentBinding(\.exposure).wrappedValue = 2
        XCTAssertTrue(model.flush())
        let before = model.settings
        let store = WorkspaceStore(root: root)
        var external = before; external.adjustments.exposure = -1
        store.update(external, for: try XCTUnwrap(model.selectedID))
        XCTAssertTrue(store.save())
        let bytes = try Data(contentsOf: store.metadataURL)

        model.resetWorkspace(try XCTUnwrap(model.activeWorkspace))

        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.settings, before)
        XCTAssertTrue(model.canUndo)
        XCTAssertFalse(model.canEdit)
        XCTAssertEqual(try Data(contentsOf: store.metadataURL), bytes)
        for _ in 0..<200 where model.isRendering { try await Task.sleep(for: .milliseconds(20)) }
    }
}
