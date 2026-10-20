import XCTest
import SwiftUI
import AppKit
import CoreImage
@testable import Pictuner

final class InspectorLayoutTests: XCTestCase {
    @MainActor func testAllAdjustmentsFitTogetherWithoutScrollingWithSelectiveOnOrOff() {
        let model = AppModel(restoringSession: false)
        model.presets = [UserPreset(name: "A custom preset with a long name", adjustments: Adjustments())]
        for columnHeight: CGFloat in [InspectorView.minimumHeight, 1000, 1100] {
            let histogramHeight = InspectorView.histogramHeight(for: columnHeight)
            for filmstripOnRight in [false, true] {
                let availableHeight = columnHeight - (filmstripOnRight ? Filmstrip.height+1 : 0)
                let compact = InspectorView.needsCompactSpacing(height: availableHeight, histogramHeight: histogramHeight)
                for enabled in [false, true] {
                    model.settings.adjustments.selective.enabled = enabled
                    let view = NSHostingView(rootView: InspectorView(histogramHeight: histogramHeight, compact: compact).environmentObject(model).frame(width: InspectorView.width))
                    view.layoutSubtreeIfNeeded()
                    let size = view.fittingSize
                    XCTAssertGreaterThan(size.height, 200)
                    XCTAssertLessThanOrEqual(size.height, availableHeight, "All controls with a \(histogramHeight)-point histogram require \(size.height) points; they must fit without scrolling")
                    XCTAssertEqual(size.width, InspectorView.width, accuracy: 0.5)
                }
            }
        }
    }

    @MainActor func testPhotoAndCropToolbarsFitNarrowPreview() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PicTunerLayout-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let renderer = Renderer()
        let image = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.8)).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        try renderer.context.writePNGRepresentation(of: image, to: root.appendingPathComponent("photo.png"), format: .RGBA8, colorSpace: renderer.colorSpace)
        let model = AppModel(restoringSession: false)
        model.open(WorkspaceReference(path: root.path))
        for _ in 0..<200 where model.preview == nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(model.preview)
        func assertFits() {
            let view = NSHostingView(rootView: PhotoToolbar().environmentObject(model).fixedSize())
            view.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(view.fittingSize.width, 400, "Photo actions must fit the narrowest preview")
            XCTAssertEqual(view.fittingSize.height, 42, accuracy: 0.5)
        }
        assertFits()
        model.selectedIDs.insert("another-photo.png") // Reveal the batch menu's populated state.
        assertFits()
        model.beginCrop()
        XCTAssertTrue(model.isCropping)
        assertFits()
        let straighten = NSHostingView(rootView: StraightenToolbar().environmentObject(model).frame(width: 400))
        straighten.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(straighten.fittingSize.width, 400)
        XCTAssertEqual(straighten.fittingSize.height, 36, accuracy: 0.5)
        model.cancelCrop()
        for _ in 0..<200 where model.isRendering { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(model.prepareToQuit())
    }
}
