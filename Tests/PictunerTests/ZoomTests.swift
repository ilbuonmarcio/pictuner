import XCTest
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@testable import Pictuner

final class ZoomTests: XCTestCase {
    let source = CGSize(width: 4000, height: 3000)
    let canvas = CGSize(width: 800, height: 600)

    func testActualPixelsAccountForRetinaAndFitKeepsWholePhotoVisible() {
        var viewport = PhotoViewport()
        let fit = viewport.imageRect(source: source, canvas: canvas, backing: 2)
        XCTAssertGreaterThanOrEqual(fit.minX, 27)
        XCTAssertGreaterThanOrEqual(fit.minY, 27)
        XCTAssertLessThanOrEqual(fit.maxX, canvas.width-27)
        XCTAssertLessThanOrEqual(fit.maxY, canvas.height-27)
        viewport.setScale(1, source: source, canvas: canvas, backing: 2)
        let native = viewport.imageRect(source: source, canvas: canvas, backing: 2)
        XCTAssertEqual(native.width*2, source.width)
        XCTAssertEqual(native.height*2, source.height)
        XCTAssertEqual(viewport.label, "100%")
        viewport.setScale(nil, source: source, canvas: canvas, backing: 2)
        XCTAssertEqual(viewport, PhotoViewport())
    }

    func testZoomKeepsImagePointUnderCursorAndLimitsScaleAndPan() {
        var viewport = PhotoViewport()
        let anchor = CGPoint(x: 470, y: 260)
        func unitPoint(_ viewport: PhotoViewport) -> CGPoint {
            let rect = viewport.imageRect(source: source, canvas: canvas, backing: 2)
            return CGPoint(x: (anchor.x-rect.minX)/rect.width, y: (anchor.y-rect.minY)/rect.height)
        }
        let before = unitPoint(viewport)
        viewport.setScale(1, anchor: anchor, source: source, canvas: canvas, backing: 2)
        let after = unitPoint(viewport)
        XCTAssertEqual(before.x, after.x, accuracy: 0.00001)
        XCTAssertEqual(before.y, after.y, accuracy: 0.00001)
        viewport.setScale(99, source: source, canvas: canvas, backing: 2)
        XCTAssertEqual(viewport.scale, 8)
        viewport.pan(by: CGSize(width: 1_000_000, height: -1_000_000), source: source, canvas: canvas, backing: 2)
        let rect = viewport.imageRect(source: source, canvas: canvas, backing: 2)
        XCTAssertLessThanOrEqual(rect.minX, 0.001)
        XCTAssertGreaterThanOrEqual(rect.maxX, canvas.width-0.001)
        XCTAssertLessThanOrEqual(rect.minY, 0.001)
        XCTAssertGreaterThanOrEqual(rect.maxY, canvas.height-0.001)
    }

    func testDetailRequestsUseVisibleSourceRegionAndSmallImagesNeedNoDetail() throws {
        let viewport = PhotoViewport(scale: 1)
        let detail = try XCTUnwrap(viewport.detailViewport(source: source, canvas: canvas, backing: 2))
        XCTAssertEqual(detail.region.width*source.width, 1600, accuracy: 0.001)
        XCTAssertEqual(detail.region.height*source.height, 1200, accuracy: 0.001)
        XCTAssertEqual(detail.region.midX, 0.5, accuracy: 0.001)
        XCTAssertEqual(detail.scale, 1)
        XCTAssertNil(viewport.detailViewport(source: CGSize(width: 1200, height: 800), canvas: canvas, backing: 2))
    }

    private func checkerboard() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PictunerDetail-\(UUID()).png")
        let width = 2400, height = 1600
        var bytes = [UInt8](repeating: 255, count: width*height*4)
        for y in 0..<height {
            for x in 0..<width {
                let value: UInt8 = x % 2 == 0 ? 32 : 224
                let offset = (y*width+x)*4
                bytes[offset] = value; bytes[offset+1] = value; bytes[offset+2] = value
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
    private func pixel(_ image: CGImage, x: Int, y: Int, renderer: Renderer) -> [UInt8] {
        var values = [UInt8](repeating: 0, count: 4)
        renderer.context.render(CIImage(cgImage: image), toBitmap: &values, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: renderer.colorSpace)
        return values
    }

    func testDetailRevealsNativePixelPatternAndUsesGlobalEffectCoordinates() throws {
        let url = try checkerboard()
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = Renderer()
        let region = CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1)
        var adjustments = Adjustments(); adjustments.exposure = 0.25; adjustments.vignette = 0.7
        let preview = try renderer.preview(url: url, adjustments: adjustments, detailViewport: DetailViewport(region: region, scale: 1))
        let detail = try XCTUnwrap(preview.detail)
        XCTAssertEqual(detail.edited.width, 240)
        XCTAssertEqual(detail.edited.height, 160)
        let first = pixel(detail.original, x: 10, y: 10, renderer: renderer)
        let next = pixel(detail.original, x: 11, y: 10, renderer: renderer)
        XCTAssertGreaterThan(abs(Int(first[0])-Int(next[0])), 180, "Native detail must retain the one-pixel pattern lost when stretching the overview")
        let source = try renderer.load(url)
        let crop = CGRect(x: 240, y: 160, width: 240, height: 160)
        let direct = try renderer.cgImage(renderer.render(source, adjustments: adjustments).cropped(to: crop))
        let expected = pixel(direct, x: 30, y: 30, renderer: renderer)
        let actual = pixel(detail.edited, x: 30, y: 30, renderer: renderer)
        for index in 0..<3 { XCTAssertEqual(Int(actual[index]), Int(expected[index]), accuracy: 2) }
        // Reuse the crop with changed settings: detail must update, not freeze its first rendering.
        adjustments.exposure = 1.25
        let brighter = try XCTUnwrap(renderer.preview(url: url, adjustments: adjustments, detailViewport: DetailViewport(region: region, scale: 1)).detail)
        XCTAssertGreaterThan(pixel(brighter.edited, x: 30, y: 30, renderer: renderer)[0], actual[0])
    }

    @MainActor func testZoomDrawingCannotCoverSurroundingControls() throws {
        let renderer = Renderer()
        let solid = try renderer.cgImage(CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32)))
        let canvas = PhotoCanvas(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
        XCTAssertTrue(canvas.clipsToBounds)
        canvas.image = solid; canvas.sourceSize = CGSize(width: 4000, height: 3000)
        canvas.showGrid = true
        // A larger backing surface represents the toolbar, sidebar, inspector, and filmstrip.
        // Deliberately provide no implicit AppKit clip: the canvas must bound its own drawing.
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 160,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        for scale in [1.0, 2, 8] {
            for overlays in [false, true] {
                canvas.viewport = PhotoViewport(scale: scale, center: CGPoint(x: 0.7, y: 0.3))
                canvas.clipping = overlays ? solid : nil
                canvas.detailImage = overlays ? solid : nil
                canvas.detailClipping = overlays ? solid : nil
                canvas.detailRegion = overlays ? CGRect(x: 0, y: 0, width: 1, height: 1) : nil
                canvas.crop = overlays ? CropRegion(CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)) : nil
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = graphics
                graphics.cgContext.saveGState()
                graphics.cgContext.setFillColor(NSColor.green.cgColor)
                graphics.cgContext.fill(CGRect(x: 0, y: 0, width: 200, height: 160))
                graphics.cgContext.translateBy(x: 40, y: 40)
                canvas.draw(canvas.bounds)
                graphics.cgContext.restoreGState()
                NSGraphicsContext.restoreGraphicsState()
                // Every edge must retain the surrounding UI, even with all overlays enabled.
                for (x, y) in [(20, 80), (180, 80), (100, 20), (100, 140)] {
                    let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    XCTAssertGreaterThan(color.greenComponent, 0.95, "Drawing escaped at \(scale)x, overlays=\(overlays), point=\(x),\(y)")
                    XCTAssertLessThan(color.redComponent, 0.05)
                }
                let center = try XCTUnwrap(bitmap.colorAt(x: 100, y: 80)?.usingColorSpace(.deviceRGB))
                XCTAssertGreaterThan(center.redComponent, 0.9, "The image must still draw inside the preview")
            }
        }
    }

    @MainActor func testZoomPreservesEditsComparisonAndResetsForNextPhoto() async throws {
        let url = try checkerboard()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PictunerZoomWorkspace-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: url) }
        for name in ["1.png", "2.png"] { try FileManager.default.copyItem(at: url, to: root.appendingPathComponent(name)) }
        let model = AppModel(restoringSession: false, supportDirectory: root.appendingPathComponent("support"))
        model.open(WorkspaceReference(path: root.path))
        for _ in 0..<200 where model.preview == nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(model.preview)
        XCTAssertTrue(model.flush())
        let metadata = root.appendingPathComponent(".pictuner/workspace.json")
        let saved = try Data(contentsOf: metadata)
        model.updateCanvasGeometry(CGSize(width: 300, height: 200), backing: 2)
        model.setZoom(1)
        // A delayed native geometry notification must preserve a newer menu zoom choice.
        model.updateCanvasGeometry(CGSize(width: 300, height: 200), backing: 2)
        XCTAssertEqual(model.viewport.scale, 1)
        for _ in 0..<200 where model.isRendering { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(model.preview?.detail)
        XCTAssertEqual(model.preview?.detail?.edited.width, 600)
        let beforeComparison = model.viewport
        model.showingOriginal = true
        XCTAssertEqual(model.viewport, beforeComparison)
        model.showingOriginal = false
        XCTAssertFalse(model.settings.adjustments.isEdited)
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(try Data(contentsOf: metadata), saved, "Zooming must not modify photo metadata")
        model.navigate(1)
        XCTAssertEqual(model.viewport, PhotoViewport())
        XCTAssertTrue(model.prepareToQuit())
    }
}
