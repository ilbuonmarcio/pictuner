import XCTest
import SwiftUI
import AppKit
import CoreImage
import ImageIO
@testable import Pictuner

final class ExportRecipeTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PicTunerRecipes-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func fixture() throws -> URL {
        let width = 1024, height = 32
        var pixels = [Float](repeating: 1, count: width*height*4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y*width+x)*4
                pixels[offset] = Float(x)/Float(width-1)
                pixels[offset+1] = Float(y)/Float(height-1)
                pixels[offset+2] = 0.4
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        let renderer = Renderer()
        let image = CIImage(bitmapData: data, bytesPerRow: width*16, size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: renderer.colorSpace)
        let url = root.appendingPathComponent("gradient.png")
        try renderer.context.writePNGRepresentation(of: image, to: url, format: .RGBA16, colorSpace: renderer.colorSpace)
        return url
    }

    func testRecipesPreserveJobScopeAndFileSafetyChoicesAndAllowCustomization() {
        var options = ExportOptions()
        options.scope = .selected; options.preserveFolders = false; options.collision = .skip
        options.longEdge = 1280
        for recipe in ExportRecipe.allCases {
            recipe.apply(to: &options)
            XCTAssertEqual(options.recipe, recipe)
            XCTAssertEqual(options.scope, .selected)
            XCTAssertFalse(options.preserveFolders)
            XCTAssertEqual(options.collision, .skip)
            XCTAssertEqual(options.longEdge, 0, "Every requested recipe retains full resolution")
            if recipe == .lossless {
                XCTAssertEqual(options.format, .png); XCTAssertEqual(options.pngBitDepth, .sixteen)
                options.pngBitDepth = .eight
            } else {
                XCTAssertEqual(options.format, .jpeg)
                options.quality = 0.7
            }
            XCTAssertNil(options.recipe, "Changing encoding settings must show Custom")
        }
        ExportRecipe.webPage.apply(to: &options); XCTAssertEqual(options.quality, 0.8)
        ExportRecipe.instagram.apply(to: &options); XCTAssertEqual(options.quality, 1)
        ExportRecipe.fullResolution.apply(to: &options); XCTAssertEqual(options.quality, 0.95)
        options.resetEncoding()
        XCTAssertEqual(options.format, ExportOptions().format)
        XCTAssertEqual(options.quality, ExportOptions().quality)
        XCTAssertEqual(options.longEdge, 0); XCTAssertEqual(options.pngBitDepth, .eight)
        XCTAssertEqual(options.scope, .selected); XCTAssertEqual(options.collision, .skip)
        XCTAssertFalse(options.preserveFolders)
    }

    func testEveryRecipeWritesFullResolutionEditedCopiesWithCorrectFormatAndDepth() throws {
        let url = try fixture(), original = try Data(contentsOf: url), renderer = Renderer()
        var adjustments = Adjustments()
        adjustments.geometry.rotate(clockwise: true)
        adjustments.geometry.crop = CropRegion(CGRect(x: 0, y: 0.25, width: 1, height: 0.5))
        adjustments.exposure = -0.3
        for recipe in ExportRecipe.allCases {
            var options = ExportOptions(); recipe.apply(to: &options)
            let destination = root.appendingPathComponent(recipe.id)
            let item = ExportItem(photo: Photo(relativePath: url.lastPathComponent, url: url), adjustments: adjustments)
            let result = Exporter.run(items: [item], destination: destination, roots: [], options: options, cancellation: ExportCancellation()) { _, _ in }
            XCTAssertEqual(result.completed, 1); XCTAssertEqual(result.errors, [])
            let output = destination.appendingPathComponent(recipe == .lossless ? "gradient.png" : "gradient.jpg")
            let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
            XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 32)
            XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 512)
            XCTAssertEqual((properties[kCGImagePropertyDepth] as? NSNumber)?.intValue, recipe == .lossless ? 16 : 8)
            XCTAssertEqual(CGImageSourceGetType(imageSource) as String?, recipe == .lossless ? "public.png" : "public.jpeg")
            XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
            XCTAssertEqual(decoded.colorSpace?.name, CGColorSpace.sRGB)
            XCTAssertEqual(try Data(contentsOf: url), original)
            // Lossless output must preserve the rendered RGB samples, not simply copy its source.
            if recipe == .lossless {
                let expected = try renderer.cgImage(renderer.render(renderer.load(url), adjustments: adjustments), format: .RGBA16)
                var actualPixels = [Float](repeating: 0, count: 32*512*4)
                var expectedPixels = actualPixels
                renderer.context.render(CIImage(cgImage: decoded), toBitmap: &actualPixels, rowBytes: 32*16, bounds: CGRect(x: 0, y: 0, width: 32, height: 512), format: .RGBAf, colorSpace: renderer.colorSpace)
                renderer.context.render(CIImage(cgImage: expected), toBitmap: &expectedPixels, rowBytes: 32*16, bounds: CGRect(x: 0, y: 0, width: 32, height: 512), format: .RGBAf, colorSpace: renderer.colorSpace)
                for offset in stride(from: 0, to: actualPixels.count, by: 41) {
                    XCTAssertEqual(actualPixels[offset], expectedPixels[offset], accuracy: 2.0/65535)
                }
                let levels = Set(stride(from: 0, to: actualPixels.count, by: 4).map { Int((actualPixels[$0]*65535).rounded()) })
                XCTAssertGreaterThan(levels.count, 256, "16-bit output must retain precision beyond the 8-bit preview")
            }
        }
    }

    @MainActor func testRecipeSelectionCannotGrantExportApproval() async throws {
        for name in ["1.jpg", "2.jpg", "3.jpg"] { try Data().write(to: root.appendingPathComponent(name)) }
        let model = AppModel(restoringSession: false, supportDirectory: root.appendingPathComponent("support"))
        model.open(WorkspaceReference(path: root.path))
        for _ in 0..<200 where model.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.photos.count, 3)
        model.setExportReady(true, for: ["1.jpg", "3.jpg"])
        model.select(model.photos[2]); model.toggleRejected()
        model.select(model.photos[1]); model.toggleFavorite()
        model.selectedIDs = ["1.jpg", "2.jpg", "3.jpg"]
        for recipe in ExportRecipe.allCases {
            recipe.apply(to: &model.exportOptions)
            XCTAssertEqual(model.exportItems().map { $0.photo.id }, ["1.jpg"])
        }
        for _ in 0..<200 where model.isRendering { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.prepareToQuit())
    }

    func testLosslessRAWRecipeKeepsFullResolutionAndSourceBytes() throws {
        guard let path = ProcessInfo.processInfo.environment["PICTUNER_RAW_FIXTURE"] else {
            throw XCTSkip("Set PICTUNER_RAW_FIXTURE to include 16-bit PNG camera RAW export.")
        }
        let url = URL(fileURLWithPath: path), original = try Data(contentsOf: url)
        let renderer = Renderer(), size = try renderer.load(url).extent.size
        var options = ExportOptions(); ExportRecipe.lossless.apply(to: &options)
        var adjustments = Adjustments(); adjustments.exposure = -0.2
        let destination = root.appendingPathComponent("raw-lossless")
        let result = Exporter.run(items: [ExportItem(photo: Photo(relativePath: url.lastPathComponent, url: url), adjustments: adjustments)], destination: destination, roots: [url.deletingLastPathComponent()], options: options, cancellation: ExportCancellation()) { _, _ in }
        XCTAssertEqual(result.completed, 1); XCTAssertEqual(result.errors, [])
        let output = destination.appendingPathComponent(url.deletingPathExtension().lastPathComponent).appendingPathExtension("png")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue, size.width)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, size.height)
        XCTAssertEqual((properties[kCGImagePropertyDepth] as? NSNumber)?.intValue, 16)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    @MainActor func testExportSheetFitsAllRecipeAndCustomStates() {
        let model = AppModel(restoringSession: false)
        var recipeHeights: [CGFloat] = []
        for recipe in ExportRecipe.allCases {
            recipe.apply(to: &model.exportOptions)
            let view = NSHostingView(rootView: ExportSheet().environmentObject(model))
            view.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(view.fittingSize.height, 650)
            XCTAssertLessThanOrEqual(view.fittingSize.width, 540)
            recipeHeights.append(view.fittingSize.height)
        }
        model.exportOptions.longEdge = 2048
        XCTAssertNil(model.exportOptions.recipe)
        let view = NSHostingView(rootView: ExportSheet().environmentObject(model))
        view.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(view.fittingSize.height, 650)
        for height in recipeHeights {
            XCTAssertEqual(view.fittingSize.height, height, accuracy: 0.5, "Switching recipes or adjusting a slider must not shift the controls")
        }
    }
}
