import SwiftUI
import AppKit
import ImageIO

private let accent = Color(red: 0.95, green: 0.69, blue: 0.36)

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var zoom = 1.0
    var body: some View {
        HStack(spacing: 0) {
            WorkspaceSidebar().frame(minWidth: 190, idealWidth: 215, maxWidth: 250)
            Divider()
            VStack(spacing: 0) {
                previewToolbar
                Divider()
                ZStack {
                    PreviewCanvas(image: displayImage, clipping: displayClipping, identity: model.selectedID, zoom: zoom, picking: model.pickingColor, compare: { model.showingOriginal = $0 }, navigate: model.navigate, sample: model.sampleColor)
                    if model.activePhoto == nil { emptyState }
                    else if let error = model.previewError {
                        ContentUnavailableView("Unable to open image", systemImage: "exclamationmark.triangle", description: Text(error))
                    } else if model.preview == nil { ProgressView("Developing image…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
                    VStack {
                        HStack {
                            if model.showingOriginal { badge("ORIGINAL", icon: "circle.lefthalf.filled") }
                            else if model.showMask { badge("COLOR MASK", icon: "viewfinder") }
                            else if model.pickingColor { badge("CLICK A COLOR IN THE PHOTO", icon: "eyedropper") }
                            Spacer()
                            if model.isRendering && model.preview != nil { ProgressView().controlSize(.small).padding(12) }
                        }
                        Spacer()
                    }.padding(18).allowsHitTesting(false)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.aperture").foregroundStyle(accent)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.showExportSheet = true } label: { Label("Export Copies", systemImage: "square.and.arrow.up") }
                    .disabled(model.photos.isEmpty || model.exporting)
            }
        }
        .onChange(of: model.selectedID) { _, _ in zoom = 1 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in model.showingOriginal = false }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in model.showingOriginal = false }
        .sheet(isPresented: $model.showExportSheet) { ExportSheet().tint(accent) }
        .alert("Pictuner", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
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
    private var previewToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.activePhoto?.name ?? "Your next great edit").font(.system(size: 13, weight: .medium)).lineLimit(1)
                if let preview = model.preview {
                    Text("\(Int(preview.sourceSize.width)) × \(Int(preview.sourceSize.height))\(model.activePhoto?.isRAW == true ? "  ·  RAW" : "")").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            CompareButton(enabled: model.preview != nil, comparing: model.showingOriginal, onChange: { model.showingOriginal = $0 }).frame(width: 185, height: 24)
            Menu {
                Button("Fit") { zoom = 1 }
                Button("2× Fit") { zoom = 2 }
                Button("4× Fit") { zoom = 4 }
            } label: { Text(zoom == 1 ? "Fit" : "\(Int(zoom))×").monospacedDigit() }.frame(width: 55)
        }.padding(.horizontal, 16).frame(height: 58)
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.aperture").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(accent)
            Text(model.isLoading ? "Finding your photos…" : model.activeWorkspace == nil ? "A little light. A little color." : "No photos here yet.").font(.system(size: 24, weight: .light))
            Text(model.activeWorkspace == nil ? "Open a folder and make it yours.\nYour originals always stay untouched." : "Choose a folder with JPEG, PNG, or supported RAW images.").font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            if model.activeWorkspace == nil { Button("Add Workspace…", action: model.addWorkspace).buttonStyle(.borderedProminent).controlSize(.large) }
            if model.isLoading { ProgressView().controlSize(.small) }
        }.padding(32)
    }
    private func badge(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.system(size: 10, weight: .semibold)).tracking(1).padding(.horizontal, 10).padding(.vertical, 7).background(.regularMaterial, in: Capsule())
    }
    private var statusBar: some View {
        HStack(spacing: 10) {
            if model.exporting {
                ProgressView(value: model.exportProgress).frame(width: 90)
                Text(model.exportLabel).lineLimit(1)
                Button("Cancel", action: model.cancelExport).buttonStyle(.link)
            } else {
                Image(systemName: model.saveStatus == "All edits saved" ? "checkmark.circle" : "exclamationmark.circle")
                Text(model.saveStatus).lineLimit(1).help(model.saveStatus)
                if model.saveStatus.hasPrefix("Edits are not saved") { Button("Retry") { model.flush() }.buttonStyle(.link) }
            }
            Spacer()
            Text("\(model.visiblePhotos.count) photos · \(model.exportReadyCount) marked for export\(model.selectedCount > 1 ? " · \(model.selectedCount) selected" : "")")
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 14).frame(height: 30)
    }
}

private struct WorkspaceSidebar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("WORKSPACES").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary); Spacer(); Button(action: model.addWorkspace) { Image(systemName: "plus") }.buttonStyle(.plain).help("Add Workspace") }.padding(18)
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
                                    Button("Remove Workspace Reference") { model.removeWorkspace(workspace) }
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
            VStack(alignment: .leading, spacing: 7) {
                Label("Originals stay original", systemImage: "lock.shield").font(.system(size: 11, weight: .medium))
                Text("Edits are saved alongside your workspace. Export when you're ready.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            }.foregroundStyle(.secondary).padding(18)
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
