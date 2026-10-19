import XCTest
import AppKit
import CoreImage
import Combine
@testable import Pictuner

final class LivePreviewTests: XCTestCase {
    private func placeholder() throws -> PreviewResult {
        let bytes = Data([128, 128, 128, 255])
        let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
        let image = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return PreviewResult(original: image, edited: image, samplingImage: image, mask: nil, clipping: image, originalClipping: image, histogram: HistogramData(), originalHistogram: HistogramData(), sourceSize: CGSize(width: 1, height: 1))
    }
    private func request(_ exposure: Double, url: URL = URL(fileURLWithPath: "/test/photo.png")) -> PreviewRequest {
        var settings = Adjustments(); settings.exposure = exposure
        return PreviewRequest(url: url, adjustments: settings, longEdge: 1000)
    }

    @MainActor func testSlowFrameIsDisplayedWhileNewerInputIsPendingAndBacklogIsCoalesced() async throws {
        let firstStarted = expectation(description: "First frame starts immediately")
        let frames = expectation(description: "In-flight frame and latest pending value are both published")
        frames.expectedFulfillmentCount = 2
        frames.assertForOverFulfill = true
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let stub = try placeholder()
        let coordinator = PreviewCoordinator { request in
            if request.adjustments.exposure == 0 {
                firstStarted.fulfill()
                guard gate.wait(timeout: .now()+3) == .success else { throw PictunerError.message("Timed out waiting for test input") }
            }
            return stub
        }
        var exposures: [Double] = [], latestFlags: [Bool] = []
        coordinator.onResult = { request, _, isLatest in
            exposures.append(request.adjustments.exposure); latestFlags.append(isLatest); frames.fulfill()
        }
        coordinator.request(request(0))
        await fulfillment(of: [firstStarted], timeout: 2)
        for value in 1...50 { coordinator.request(request(Double(value))) }
        gate.signal()
        await fulfillment(of: [frames], timeout: 3)
        XCTAssertEqual(exposures, [0, 50], "Continuous input must neither starve completed frames nor accumulate an obsolete queue")
        XCTAssertEqual(latestFlags, [false, true])
    }

    @MainActor func testSwitchingWorkspaceDiscardsOldFrameEvenWithSameFilename() async throws {
        let started = expectation(description: "Old photo is rendering")
        let newPhoto = expectation(description: "Only the new workspace frame is delivered")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let stub = try placeholder()
        let oldURL = URL(fileURLWithPath: "/first/photo.png"), newURL = URL(fileURLWithPath: "/second/photo.png")
        let coordinator = PreviewCoordinator { request in
            if request.url == oldURL {
                started.fulfill()
                guard gate.wait(timeout: .now()+3) == .success else { throw PictunerError.message("Timed out waiting for test selection") }
            }
            return stub
        }
        var delivered: [URL] = []
        coordinator.onResult = { request, _, _ in delivered.append(request.url); newPhoto.fulfill() }
        coordinator.request(request(0, url: oldURL))
        await fulfillment(of: [started], timeout: 2)
        coordinator.invalidate()
        coordinator.request(request(1, url: newURL))
        gate.signal()
        await fulfillment(of: [newPhoto], timeout: 3)
        XCTAssertEqual(delivered, [newURL])
    }

    @MainActor func testCompletionIsDeliveredInMouseTrackingRunLoopMode() throws {
        let stub = try placeholder()
        let coordinator = PreviewCoordinator { _ in stub }
        var displayed = false
        coordinator.onResult = { _, _, _ in displayed = true }
        // Exercise a tracking loop without injecting input into the user's desktop.
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(rawValue: RunLoop.Mode.eventTracking.rawValue as CFString))
        coordinator.request(request(1))
        let deadline = Date().addingTimeInterval(2)
        while !displayed && Date() < deadline {
            RunLoop.main.run(mode: .eventTracking, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(displayed, "A preview must be publishable before mouse tracking ends")
    }

    @MainActor func testPreviewChangesDuringContinuousSliderInputBeforeReleaseAndRefinesAfterward() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PictunerLive-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let renderer = Renderer()
        let image = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 2400, height: 1600))
        try renderer.context.writePNGRepresentation(of: image, to: root.appendingPathComponent("photo.png"), format: .RGBA8, colorSpace: renderer.colorSpace)
        let model = AppModel(restoringSession: false, supportDirectory: root.appendingPathComponent("support"))
        model.open(WorkspaceReference(path: root.path))
        for _ in 0..<200 where model.preview == nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(model.preview)
        model.updateViewport(PhotoViewport(scale: 1), canvas: CGSize(width: 300, height: 200), backing: 2)
        for _ in 0..<200 where model.isRendering { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(model.preview?.detail)
        var frameCount = 0
        var colors = Set<UInt8>()
        let observation = model.$preview.compactMap { $0 }.dropFirst().sink { preview in
            frameCount += 1
            let bytes = (preview.detail?.edited ?? preview.edited).dataProvider?.data as Data?
            if let first = bytes?.first { colors.insert(first) }
        }
        defer { observation.cancel() }
        model.editingGesture(true)
        for step in 1...50 {
            model.adjustmentBinding(\.exposure).wrappedValue = Double(step)/25
            try await Task.sleep(for: .milliseconds(10)) // Faster than the old 60 ms debounce.
        }
        XCTAssertGreaterThan(frameCount, 2, "The preview must update repeatedly while the gesture is still active")
        XCTAssertGreaterThan(colors.count, 2, "Frames must contain changing image pixels, not only slider labels")
        XCTAssertEqual(model.preview?.edited.width, 1000)
        model.editingGesture(false)
        for _ in 0..<200 where model.isRendering { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.preview?.edited.width, 1800)
        let expected = try renderer.cgImage(renderer.render(renderer.resize(try renderer.load(root.appendingPathComponent("photo.png")), longEdge: 1800), adjustments: model.settings.adjustments))
        let actualColor = Renderer.sample(try XCTUnwrap(model.preview?.edited), at: CGPoint(x: 0.5, y: 0.5))
        let expectedColor = Renderer.sample(expected, at: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(actualColor.2, expectedColor.2, accuracy: 0.01)
        model.undo()
        XCTAssertEqual(model.settings.adjustments.exposure, 0, "One continuous drag remains one undo operation")
        XCTAssertTrue(model.prepareToQuit())
    }

    func testPreviewCachePreservesHighlightHeadroomForLaterExposureChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PictunerHDR-\(UUID()).tiff")
        defer { try? FileManager.default.removeItem(at: root) }
        let renderer = Renderer()
        let input = CIImage(color: CIColor(red: 2, green: 1.5, blue: 1.2)).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        try renderer.context.writeTIFFRepresentation(of: input, to: root, format: .RGBAh, colorSpace: CGColorSpace(name: CGColorSpace.extendedSRGB)!)
        _ = try renderer.preview(url: root, adjustments: Adjustments())
        var a = Adjustments(); a.exposure = -2
        let preview = try renderer.preview(url: root, adjustments: a)
        let direct = try renderer.cgImage(renderer.render(try renderer.load(root), adjustments: a))
        let actual = Renderer.sample(preview.edited, at: CGPoint(x: 0.5, y: 0.5))
        let expected = Renderer.sample(direct, at: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(actual.0, expected.0, accuracy: 0.01)
        XCTAssertEqual(actual.1, expected.1, accuracy: 0.01)
        XCTAssertEqual(actual.2, expected.2, accuracy: 0.01)
    }
}
