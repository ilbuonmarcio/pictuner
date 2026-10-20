import XCTest
import SwiftUI
import CoreImage
@testable import Pictuner

final class ControlResetTests: XCTestCase {
    @MainActor func testPerControlDefaultsPreserveOtherEditsAndUndoPersistIndependently() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PicTunerReset-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let renderer = Renderer()
        let source = root.appendingPathComponent("photo.png")
        let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6)).cropped(to: CGRect(x: 0, y: 0, width: 120, height: 80))
        try renderer.context.writePNGRepresentation(of: image, to: source, format: .RGBA8, colorSpace: renderer.colorSpace)
        let sourceBytes = try Data(contentsOf: source)
        let model = AppModel(restoringSession: false)
        model.open(WorkspaceReference(path: root.path))
        for _ in 0..<200 where model.preview == nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(model.preview)
        var edited = Adjustments()
        edited.exposure = 0.75; edited.contrast = 1.6
        edited.selective.enabled = true; edited.selective.selectedSaturation = 1.8
        edited.geometry.rotate(clockwise: true)
        edited.geometry.crop = CropRegion(CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5))
        model.setAdjustments(edited)

        let contrastReset = ResetValueButton(title: "Contrast", value: model.adjustmentBinding(\.contrast), defaultValue: Adjustments().contrast)
        let selectiveReset = ResetValueButton(title: "Selected saturation", value: model.selectiveBinding(\.selectedSaturation), defaultValue: SelectiveColor().selectedSaturation)
        contrastReset.reset()
        var contrastOnly = edited; contrastOnly.contrast = 1
        XCTAssertEqual(model.settings.adjustments, contrastOnly, "Reset must affect only its own control, including nonzero defaults")
        selectiveReset.reset()
        var bothReset = contrastOnly; bothReset.selective.selectedSaturation = 1.2
        XCTAssertEqual(model.settings.adjustments, bothReset)
        // A default-value reset must not add an empty undo entry.
        selectiveReset.reset()
        model.undo(); XCTAssertEqual(model.settings.adjustments, contrastOnly)
        model.undo(); XCTAssertEqual(model.settings.adjustments, edited)
        model.redo(); XCTAssertEqual(model.settings.adjustments, contrastOnly)
        model.redo(); XCTAssertEqual(model.settings.adjustments, bothReset)
        XCTAssertTrue(model.flush())
        XCTAssertEqual(WorkspaceStore(root: root).settings(for: "photo.png").adjustments, bothReset)
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
        for _ in 0..<200 where model.isRendering { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(model.prepareToQuit())
    }
}
