import SwiftUI
import AppKit
import ImageIO

private let accent = Color(red: 0.95, green: 0.69, blue: 0.36)

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            WorkspaceSidebar().frame(minWidth: 190, idealWidth: 215, maxWidth: 250)
            Divider()
            VStack(spacing: 0) {
                previewToolbar
                Divider()
                ZStack {
                    PreviewCanvas(image: displayImage, clipping: displayClipping, detailImage: displayDetail, detailClipping: detailClipping, detailRegion: model.preview?.detail?.region, sourceSize: model.preview?.sourceSize ?? .zero, identity: model.selectedID, viewport: model.viewport, picking: model.pickingColor, crop: model.preview == nil ? nil : model.cropDraft, cropRatio: model.cropRatio, cropChanged: model.updateCrop, cropFinished: { if $0 { model.applyCrop() } else { model.cancelCrop() } }, viewportChanged: { model.updateViewport($0, canvas: $1, backing: $2) }, geometryChanged: { model.updateCanvasGeometry($0, backing: $1) }, compare: { model.showingOriginal = $0 }, navigate: model.navigate, sample: model.sampleColor)
                    if model.activePhoto == nil { emptyState }
                    else if let error = model.previewError {
                        ContentUnavailableView("Unable to open image", systemImage: "exclamationmark.triangle", description: Text(error))
                    } else if model.preview == nil { ProgressView().accessibilityLabel("Loading image").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
                    VStack {
                        HStack {
                            if model.showingOriginal { badge("Original", icon: "circle.lefthalf.filled") }
                            else if model.showMask { badge("Mask", icon: "viewfinder") }
                            else if model.pickingColor { badge("Pick a color", icon: "eyedropper") }
                            Spacer()
                            if model.isRendering && model.preview != nil { ProgressView().controlSize(.small).padding(12) }
                        }
                        Spacer()
                    }.padding(18).allowsHitTesting(false)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                PhotoToolbar()
                Divider()
                Filmstrip().frame(height: 118)
                Divider()
                statusBar
            }.frame(minWidth: 400)
            Divider()
            InspectorView().frame(width: 290)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1000, minHeight: 680)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.showExportSheet = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .disabled(model.photos.isEmpty || model.exporting || model.isCropping)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in model.showingOriginal = false }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in model.showingOriginal = false }
        .sheet(isPresented: $model.showExportSheet) { ExportSheet().tint(accent) }
        .alert("PicTuner", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            if model.hasUnsavedEdits {
                Button("Retry Saving") { model.flush() }
                Button("Reload & Discard Unsaved Edits", role: .destructive) { model.discardAndReload() }
            }
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("Export", isPresented: Binding(get: { model.exportSummary != nil }, set: { if !$0 { model.exportSummary = nil } })) {
            Button("OK") { model.exportSummary = nil }
        } message: { Text(model.exportSummary ?? "") }
    }

    private var displayImage: CGImage? {
        guard let preview = model.preview else { return nil }
        if model.showingOriginal { return preview.original }
        if model.showMask, let mask = preview.mask { return mask }
        return preview.edited
    }
    private var displayClipping: CGImage? {
        guard model.showClipping, !model.showMask else { return nil }
        return model.showingOriginal ? model.preview?.originalClipping : model.preview?.clipping
    }
    private var displayDetail: CGImage? {
        guard let detail = model.preview?.detail else { return nil }
        if model.showingOriginal { return detail.original }
        if model.showMask { return detail.mask ?? detail.edited }
        return detail.edited
    }
    private var detailClipping: CGImage? {
        guard model.showClipping, !model.showMask else { return nil }
        return model.showingOriginal ? model.preview?.detail?.originalClipping : model.preview?.detail?.clipping
    }
    private var previewToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let photo = model.activePhoto { Text(photo.name).font(.system(size: 13, weight: .medium)).lineLimit(1) }
                if let preview = model.preview {
                    Text("\(Int(preview.sourceSize.width)) × \(Int(preview.sourceSize.height))\(model.activePhoto?.isRAW == true ? "  ·  RAW" : "")").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            CompareButton(enabled: model.preview != nil, comparing: model.showingOriginal, onChange: { model.showingOriginal = $0 }).frame(width: 88, height: 24)
            HStack(spacing: 5) {
                Button { model.zoomBy(1/sqrt(2)) } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out · ⌘−").accessibilityLabel("Zoom out")
                Menu {
                    Button("Fit to Window") { model.setZoom(nil) }
                    ForEach([0.25, 0.5, 1, 2, 4, 8], id: \.self) { scale in
                        Button(scale == 1 ? "100% (Actual Pixels)" : "\(Int(scale*100))%") { model.setZoom(scale) }
                    }
                } label: { Text(model.viewport.label).monospacedDigit() }.frame(width: 74)
                    .accessibilityLabel("Zoom")
                Button { model.zoomBy(sqrt(2)) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in · ⌘+").accessibilityLabel("Zoom in")
            }.buttonStyle(.borderless).disabled(model.preview == nil || model.isCropping)
        }.padding(.horizontal, 16).frame(height: 58)
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text(model.isLoading ? "Loading…" : model.activeWorkspace == nil ? "No Workspace" : "No Images").font(.system(size: 18, weight: .medium))
            if model.activeWorkspace == nil { Button("Add Workspace…", action: model.addWorkspace).buttonStyle(.borderedProminent).controlSize(.large) }
            if model.isLoading { ProgressView().controlSize(.small) }
        }.padding(32)
    }
    private func badge(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 7).background(.regularMaterial, in: Capsule())
    }
    private var statusBar: some View {
        HStack(spacing: 10) {
            if model.exporting {
                ProgressView(value: model.exportProgress).frame(width: 90)
                Text(model.exportLabel).lineLimit(1)
                Button("Cancel", action: model.cancelExport).buttonStyle(.link)
            } else if model.saveStatus != "All edits saved" && model.saveStatus != "Saving edits…" {
                Image(systemName: "exclamationmark.circle")
                Text(model.saveStatus).lineLimit(1).help(model.saveStatus)
                if model.saveStatus.hasPrefix("Edits are not saved") { Button("Retry") { model.flush() }.buttonStyle(.link) }
            }
            Spacer()
            Text("\(model.visiblePhotos.count) photos\(model.exportReadyCount > 0 ? " · \(model.exportReadyCount) marked for export" : "")\(model.selectedCount > 1 ? " · \(model.selectedCount) selected" : "")")
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 14).frame(height: 30)
    }
}

private struct WorkspaceSidebar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Workspaces").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary); Spacer(); Button(action: model.addWorkspace) { Image(systemName: "plus") }.buttonStyle(.plain).help("Add Workspace") }.padding(18)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.workspaces) { workspace in
                        VStack(alignment: .leading, spacing: 3) {
                            Button { model.open(workspace) } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "folder.fill").foregroundStyle(model.activeWorkspace == workspace ? accent : .secondary)
                                    Text(workspace.name).lineLimit(1)
                                    Spacer(minLength: 0)
                                }.padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .background(model.activeWorkspace == workspace && model.folder.isEmpty ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                .contextMenu {
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([workspace.url]) }
                                    Button("Remove Workspace") { model.removeWorkspace(workspace) }
                                    Button("Refresh") { model.open(workspace) }
                                }
                            if model.activeWorkspace == workspace {
                                ForEach(model.folders.filter { !$0.contains("/") }, id: \.self) { FolderBranch(path: $0, depth: 0) }
                            }
                        }
                    }
                }.padding(.horizontal, 9)
            }
            Spacer(minLength: 0)
        }.background(Color(nsColor: .underPageBackgroundColor).opacity(0.4))
    }
}

private struct FolderBranch: View {
    @EnvironmentObject var model: AppModel
    let path: String
    let depth: Int
    @State private var expanded = true
    private var children: [String] { model.folders.filter { ($0 as NSString).deletingLastPathComponent == path } }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8)).frame(width: 12) }.buttonStyle(.plain).opacity(children.isEmpty ? 0 : 1)
                Button { model.selectFolder(path) } label: {
                    Label((path as NSString).lastPathComponent, systemImage: "folder").font(.system(size: 11)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.padding(.vertical, 6).padding(.leading, CGFloat(depth)*10+8).padding(.trailing, 8)
                .background(model.folder == path ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
            if expanded { ForEach(children, id: \.self) { child in AnyView(FolderBranch(path: child, depth: depth+1)) } }
        }
    }
}

private struct Filmstrip: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(model.visiblePhotos) { photo in
                        let settings = model.savedSettings(for: photo)
                        VStack(spacing: 5) {
                            ZStack(alignment: .bottomTrailing) {
                                ThumbnailView(photo: photo).frame(width: 100, height: 70).clipped()
                                HStack(spacing: 4) {
                                    if settings.exportReady { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Included in Export") }
                                    if settings.favorite { Image(systemName: "star.fill") }
                                    if settings.rejected { Image(systemName: "xmark.circle.fill") }
                                    if settings.adjustments.isEdited { Image(systemName: "slider.horizontal.3") }
                                }.font(.system(size: 9)).padding(4).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 3)).padding(3)
                            }.clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(model.selectedIDs.contains(photo.id) ? accent : .clear, lineWidth: 2))
                            Text(photo.name).font(.system(size: 9)).lineLimit(1).foregroundStyle(model.selectedID == photo.id ? .primary : .secondary).frame(width: 100)
                        }.id(photo.id)
                            .onTapGesture { model.select(photo, extending: NSEvent.modifierFlags.contains(.command)) }
                            .contextMenu {
                                Button(settings.exportReady ? "Remove from Export" : "Include in Export") { model.setExportReady(!settings.exportReady, for: [photo.id]) }
                                    .disabled(!model.canEdit)
                            }
                            .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton).accessibilityLabel(photo.name)
                            .accessibilityValue(settings.exportReady ? "Marked for export" : "Not marked for export")
                    }
                }.padding(.horizontal, 16).padding(.vertical, 12)
            }.scrollIndicators(.hidden)
                .onChange(of: model.selectedID) { _, id in if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } } }
        }
    }
}

private struct ThumbnailView: View {
    let photo: Photo
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            Color.white.opacity(0.035)
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: photo.isRAW ? "camera" : "photo").foregroundStyle(.tertiary) }
        }.task(id: photo.id) {
            let url = photo.url
            let result = await ThumbnailLoader.load(url)
            if !Task.isCancelled { image = result }
        }
    }
}
private enum ThumbnailLoader {
    static let queue = DispatchQueue(label: "pictuner.thumbnails", qos: .utility)
    static let cache = NSCache<NSURL, NSImage>()
    static func load(_ url: URL) async -> NSImage? {
        await withCheckedContinuation { continuation in
            queue.async {
                if let cached = cache.object(forKey: url as NSURL) { continuation.resume(returning: cached); return }
                let result: NSImage? = autoreleasepool {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 240] as CFDictionary) else { return nil }
                    return NSImage(cgImage: image, size: .zero)
                }
                cache.countLimit = 300
                if let result { cache.setObject(result, forKey: url as NSURL) }
                continuation.resume(returning: result)
            }
        }
    }
}
