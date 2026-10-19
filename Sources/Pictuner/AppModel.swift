import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var workspaces: [WorkspaceReference] = []
    @Published var activeWorkspace: WorkspaceReference?
    @Published var photos: [Photo] = []
    @Published var selectedID: String?
    @Published var selectedIDs: Set<String> = []
    @Published var folder = ""
    @Published var settings = ImageSettings()
    @Published var preview: PreviewResult?
    @Published private(set) var viewport = PhotoViewport()
    @Published var showingOriginal = false
    @Published var showMask = false
    @Published var showClipping = false
    @Published var pickingColor = false
    @Published private(set) var cropDraft: CropRegion?
    @Published private(set) var cropAspect = CropAspect.free
    var isCropping: Bool { cropDraft != nil }
    var cropRatio: Double? { cropAspect.ratio(source: preview?.sourceSize ?? .zero) }
    @Published var isLoading = false
    @Published var isRendering = false
    @Published var previewError: String?
    @Published var saveStatus = "All edits saved"
    @Published var errorMessage: String?
    @Published var exportSummary: String?
    @Published var exportOptions = ExportOptions()
    @Published var showExportSheet = false
    @Published var exporting = false
    @Published var exportProgress = 0.0
    @Published var exportLabel = ""
    @Published var presets: [UserPreset] = []
    @Published var canUndo = false
    @Published var canRedo = false
    private var store: WorkspaceStore?
    private let previews: PreviewCoordinator
    private let scanQueue = DispatchQueue(label: "pictuner.scan", qos: .userInitiated)
    private let exportQueue = DispatchQueue(label: "pictuner.export", qos: .utility)
    private var workspaceRevision = UUID()
    private var saveRequest: DispatchWorkItem?
    private var copiedAdjustments: Adjustments?
    private var undoStack: [[String: Adjustments]] = []
    private var redoStack: [[String: Adjustments]] = []
    private var gestureStart: Adjustments?
    private var cancellation: ExportCancellation?
    private var editedSinceSave = false
    private var sessionTouched = false
    private let supportDirectory: URL?
    private var canvasSize = CGSize.zero
    private var canvasBacking = 1.0
    private var requestedDetailViewport: DetailViewport?

    // Retain the established storage path so the branding correction preserves saved workspaces and presets.
    private var supportURL: URL {
        supportDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Pictuner", isDirectory: true)
    }
    var activePhoto: Photo? { photos.first { $0.id == selectedID } }
    var visiblePhotos: [Photo] { photos.filter { folder.isEmpty || $0.relativePath.hasPrefix(folder + "/") } }
    var folders: [String] {
        var result = Set<String>()
        for photo in photos {
            let parts = photo.relativePath.split(separator: "/").dropLast()
            for count in 1...max(1, parts.count) where count <= parts.count { result.insert(parts.prefix(count).joined(separator: "/")) }
        }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var selectedCount: Int { selectedIDs.count }
    var exportReadyCount: Int { photos.filter { savedSettings(for: $0).exportReady && !savedSettings(for: $0).rejected }.count }
    var hasCopiedAdjustments: Bool { copiedAdjustments != nil }
    var canEdit: Bool { activePhoto != nil && store?.failure == nil }
    var hasUnsavedEdits: Bool { editedSinceSave }

    /// Only called from the explicit discard action in the save-error alert.
    func discardAndReload() {
        guard let reference = activeWorkspace else { return }
        saveRequest?.cancel()
        editedSinceSave = false; sessionTouched = false; errorMessage = nil
        open(reference)
    }

    init(restoringSession: Bool = true, supportDirectory: URL? = nil) {
        self.supportDirectory = supportDirectory
        let renderer = Renderer()
        previews = PreviewCoordinator { request in
            try renderer.preview(url: request.url, adjustments: request.adjustments, longEdge: request.longEdge, detailViewport: request.detailViewport)
        }
        previews.onResult = { [weak self] _, result, isLatest in
            guard let self else { return }
            self.isRendering = !isLatest
            switch result {
            case .success(let preview): self.preview = preview; self.previewError = nil
            case .failure(let error):
                // A pending newer setting may fix an intermediate failure; keep the last frame.
                if isLatest { self.preview = nil; self.previewError = error.localizedDescription }
            }
        }
        guard restoringSession else { return }
        if let data = try? Data(contentsOf: supportURL.appendingPathComponent("workspaces.json")),
           let saved = try? JSONDecoder().decode([WorkspaceReference].self, from: data) { workspaces = saved }
        if let data = try? Data(contentsOf: supportURL.appendingPathComponent("presets.json")),
           let saved = try? JSONDecoder().decode([UserPreset].self, from: data) { presets = saved }
        if let first = workspaces.first { open(first) }
    }

    func addWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "Add Workspace"
        panel.prompt = "Add Workspace"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let reference = WorkspaceReference(path: url.resolvingSymlinksInPath().standardizedFileURL.path)
        if !workspaces.contains(reference) {
            workspaces.append(reference)
            persistCatalog()
        }
        open(reference)
    }

    private func persistCatalog() {
        do {
            try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            try JSONEncoder().encode(workspaces).write(to: supportURL.appendingPathComponent("workspaces.json"), options: .atomic)
        } catch { errorMessage = "Could not remember workspaces: \(error.localizedDescription)" }
    }

    func removeWorkspace(_ reference: WorkspaceReference) {
        guard flush() else { return }
        workspaces.removeAll { $0 == reference }
        persistCatalog()
        if activeWorkspace == reference {
            workspaceRevision = UUID(); previews.invalidate(); isRendering = false
            cropDraft = nil
            activeWorkspace = nil; store = nil; photos = []; selectedID = nil; selectedIDs = []; preview = nil
            if let next = workspaces.first { open(next) }
        }
    }

    func open(_ reference: WorkspaceReference) {
        guard flush() else { return }
        activeWorkspace = reference; folder = ""; photos = []; selectedID = nil; selectedIDs = []; preview = nil
        cropDraft = nil
        settings = ImageSettings(); showingOriginal = false; previewError = nil; isLoading = true
        previews.invalidate(); isRendering = false
        let token = UUID(); workspaceRevision = token
        store = WorkspaceStore(root: reference.url)
        sessionTouched = false
        saveStatus = store?.failure ?? "All edits saved"
        if let failure = store?.failure { errorMessage = failure }
        scanQueue.async {
            let result = Result { try ImageFiles.scan(reference.url) }
            DispatchQueue.main.async {
                guard self.workspaceRevision == token else { return }
                self.isLoading = false
                switch result {
                case .success(let photos):
                    self.photos = photos
                    let remembered = self.store?.document.lastImage
                    self.select(photos.first { $0.id == remembered } ?? photos.first)
                case .failure(let error): self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func selectFolder(_ path: String) {
        guard flush() else { return }
        folder = path
        select(visiblePhotos.first)
    }

    func select(_ photo: Photo?, extending: Bool = false) {
        if photo?.id == selectedID && !extending { return }
        guard flush() else { return }
        previews.invalidate()
        if let photo {
            if extending { selectedIDs.insert(photo.id) } else { selectedIDs = [photo.id] }
        } else { selectedIDs = [] }
        selectedID = photo?.id
        settings = photo.map { store?.settings(for: $0.id) ?? ImageSettings() } ?? ImageSettings()
        if store?.document.lastImage != selectedID, store?.failure == nil {
            store?.setLastImage(selectedID)
            scheduleSave()
        }
        cropDraft = nil
        showingOriginal = false; pickingColor = false; showMask = false
        preview = nil; previewError = nil
        viewport = PhotoViewport(); requestedDetailViewport = nil
        undoStack = []; redoStack = []; gestureStart = nil; updateUndoState()
        requestPreview()
    }

    func navigate(_ direction: Int) {
        let visible = visiblePhotos
        guard let index = visible.firstIndex(where: { $0.id == selectedID }) else { return }
        let next = index + direction
        if visible.indices.contains(next) { select(visible[next]) }
    }

    func selectAll() { selectedIDs = Set(visiblePhotos.map(\.id)) }

    func adjustmentBinding(_ key: WritableKeyPath<Adjustments, Double>) -> Binding<Double> {
        Binding(get: { self.settings.adjustments[keyPath: key] }, set: { value in
            var a = self.settings.adjustments; a[keyPath: key] = value; self.setAdjustments(a)
        })
    }

    func selectiveBinding(_ key: WritableKeyPath<SelectiveColor, Double>) -> Binding<Double> {
        Binding(get: { self.settings.adjustments.selective[keyPath: key] }, set: { value in
            var a = self.settings.adjustments; a.selective[keyPath: key] = value; self.setAdjustments(a)
        })
    }

    func editingGesture(_ editing: Bool) {
        if editing { gestureStart = settings.adjustments }
        else if let before = gestureStart {
            if before != settings.adjustments, let id = selectedID { undoStack.append([id: before]); redoStack = [] }
            gestureStart = nil; updateUndoState()
            requestPreview() // Refine the final setting at the normal preview resolution.
        }
    }

    func setAdjustments(_ value: Adjustments) {
        guard canEdit, !isCropping, value != settings.adjustments else { return }
        if gestureStart == nil, let id = selectedID { undoStack.append([id: settings.adjustments]); redoStack = [] }
        if settings.adjustments.geometry != value.geometry { resetGeometryPreview() }
        settings.adjustments = value
        updateUndoState(); changed()
        requestPreview()
    }

    func undo() {
        if isCropping { cancelCrop(); return }
        guard canEdit, let value = undoStack.popLast() else { return }
        redoStack.append(restoreAdjustments(value))
        updateUndoState()
    }
    func redo() {
        if isCropping { cancelCrop(); return }
        guard canEdit, let value = redoStack.popLast() else { return }
        undoStack.append(restoreAdjustments(value))
        updateUndoState()
    }
    private func restoreAdjustments(_ values: [String: Adjustments]) -> [String: Adjustments] {
        var previous: [String: Adjustments] = [:]
        for (id, value) in values {
            var entry = store?.settings(for: id) ?? ImageSettings()
            previous[id] = entry.adjustments
            entry.adjustments = value
            store?.update(entry, for: id)
            if id == selectedID {
                if settings.adjustments.geometry != entry.adjustments.geometry { resetGeometryPreview() }
                settings = entry
            }
        }
        scheduleSave(); requestPreview()
        return previous
    }
    private func updateUndoState() { canUndo = !undoStack.isEmpty; canRedo = !redoStack.isEmpty }

    func toggleFavorite() { guard canEdit else { return }; settings.favorite.toggle(); changed() }
    func toggleRejected() {
        guard canEdit else { return }
        settings.rejected.toggle()
        if settings.rejected { settings.exportReady = false }
        changed()
    }
    func toggleExportReady() {
        guard let id = selectedID else { return }
        setExportReady(!settings.exportReady, for: [id])
    }
    func setExportReady(_ ready: Bool, for ids: Set<String>) {
        guard canEdit else { return }
        for photo in photos where ids.contains(photo.id) {
            var entry = savedSettings(for: photo)
            entry.exportReady = ready
            if ready { entry.rejected = false }
            store?.update(entry, for: photo.id)
            if photo.id == selectedID { settings = entry }
        }
        scheduleSave()
    }
    func savedSettings(for photo: Photo) -> ImageSettings { photo.id == selectedID ? settings : store?.settings(for: photo.id) ?? ImageSettings() }
    // Framing belongs to each photo; reusable color edits leave it alone.
    func applyColorAdjustments(_ value: Adjustments) {
        var value = value; value.geometry = settings.adjustments.geometry
        setAdjustments(value)
    }
    func copyAdjustments() {
        var value = settings.adjustments; value.geometry = ImageGeometry()
        copiedAdjustments = value; objectWillChange.send()
    }
    func pasteAdjustments() { if let value = copiedAdjustments { applyColorAdjustments(value) } }

    func applyToSelection() {
        guard canEdit else { return }
        var previous: [String: Adjustments] = [:]
        for id in selectedIDs where id != selectedID {
            var other = store?.settings(for: id) ?? ImageSettings()
            var value = settings.adjustments; value.geometry = other.adjustments.geometry
            guard other.adjustments != value else { continue }
            previous[id] = other.adjustments
            other.adjustments = value
            store?.update(other, for: id)
        }
        if !previous.isEmpty {
            undoStack.append(previous); redoStack = []; updateUndoState(); scheduleSave()
        }
    }

    func sampleColor(at point: CGPoint) {
        guard let preview, !isRendering, !showingOriginal else { return }
        let sample: (Double, Double, Double)
        let bottomPoint = CGPoint(x: point.x, y: 1-point.y)
        if let detail = preview.detail, detail.region.contains(bottomPoint) {
            let localPoint = CGPoint(x: (point.x-detail.region.minX)/detail.region.width, y: 1-(bottomPoint.y-detail.region.minY)/detail.region.height)
            sample = Renderer.sample(detail.samplingImage, at: localPoint)
        } else { sample = Renderer.sample(preview.samplingImage, at: point) }
        var a = settings.adjustments
        a.selective.enabled = true
        a.selective.hue = sample.0; a.selective.saturation = sample.1; a.selective.brightness = sample.2
        setAdjustments(a); pickingColor = false
    }

    func savePreset(name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var value = settings.adjustments; value.geometry = ImageGeometry()
        presets.append(UserPreset(name: name, adjustments: value))
        do {
            try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            try JSONEncoder().encode(presets).write(to: supportURL.appendingPathComponent("presets.json"), options: .atomic)
        } catch { errorMessage = "Could not save the preset: \(error.localizedDescription)" }
    }

    private func changed() {
        guard let id = selectedID else { return }
        store?.update(settings, for: id)
        scheduleSave()
    }

    private func scheduleSave() {
        editedSinceSave = true; sessionTouched = true; saveStatus = "Saving edits…"
        saveRequest?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveRequest = work
        DispatchQueue.main.asyncAfter(deadline: .now()+0.35, execute: work)
    }

    @discardableResult func flush() -> Bool {
        saveRequest?.cancel()
        guard editedSinceSave, let store else { return true }
        if store.save() {
            editedSinceSave = false; saveStatus = "All edits saved"; return true
        }
        saveStatus = store.failure ?? "Edits are not saved"
        errorMessage = saveStatus
        return false
    }

    func prepareToQuit() -> Bool {
        guard flush() else { return false }
        if sessionTouched { _ = store?.save() }
        return true
    }

    func requestPreview() {
        guard let photo = activePhoto else { isRendering = false; return }
        isRendering = true
        requestedDetailViewport = desiredDetailViewport
        var value = settings.adjustments
        if isCropping { value.geometry.crop = nil }
        previews.request(PreviewRequest(url: photo.url, adjustments: value, longEdge: gestureStart == nil ? 1800 : 1000, detailViewport: requestedDetailViewport))
    }

    private var desiredDetailViewport: DetailViewport? {
        guard !isCropping, let size = preview?.sourceSize else { return nil }
        return viewport.detailViewport(source: size, canvas: canvasSize, backing: canvasBacking)
    }

    func updateViewport(_ value: PhotoViewport, canvas: CGSize, backing: Double) {
        if viewport != value { viewport = value }
        canvasSize = canvas; canvasBacking = backing
        if desiredDetailViewport != requestedDetailViewport { requestPreview() }
    }

    func updateCanvasGeometry(_ canvas: CGSize, backing: Double) {
        var next = viewport
        if let size = preview?.sourceSize { next.constrain(source: size, canvas: canvas, backing: backing) }
        updateViewport(next, canvas: canvas, backing: backing)
    }

    func setZoom(_ scale: Double?) {
        guard !isCropping, let size = preview?.sourceSize else { return }
        var next = viewport
        next.setScale(scale, source: size, canvas: canvasSize, backing: canvasBacking)
        updateViewport(next, canvas: canvasSize, backing: canvasBacking)
    }

    func zoomBy(_ factor: Double) {
        guard let size = preview?.sourceSize else { return }
        setZoom(viewport.resolvedScale(source: size, canvas: canvasSize, backing: canvasBacking)*factor)
    }

    private func resetGeometryPreview() {
        previews.invalidate()
        preview = nil; previewError = nil
        viewport = PhotoViewport(); requestedDetailViewport = nil
        showingOriginal = false; pickingColor = false; showMask = false
    }

    func rotate(clockwise: Bool) {
        guard !isCropping else { return }
        var value = settings.adjustments; value.geometry.rotate(clockwise: clockwise)
        setAdjustments(value)
    }
    func flip(horizontal: Bool) {
        guard !isCropping else { return }
        var value = settings.adjustments; value.geometry.flip(horizontal: horizontal)
        setAdjustments(value)
    }
    func beginCrop() {
        guard canEdit, preview != nil, !isCropping else { return }
        cropDraft = settings.adjustments.geometry.crop ?? .full
        cropAspect = .free
        resetGeometryPreview(); requestPreview()
    }
    func updateCrop(_ value: CropRegion) { guard isCropping else { return }; cropDraft = value }
    func setCropAspect(_ value: CropAspect) {
        cropAspect = value
        if let ratio = cropRatio, let size = preview?.sourceSize, let draft = cropDraft {
            cropDraft = draft.fitted(aspect: ratio, source: size)
        }
    }
    func resetCropDraft() {
        cropDraft = .full
        setCropAspect(cropAspect)
    }
    func applyCrop() {
        guard let draft = cropDraft, preview != nil else { return }
        cropDraft = nil
        var value = settings.adjustments
        value.geometry.crop = draft == .full ? nil : draft
        resetGeometryPreview()
        if value != settings.adjustments { setAdjustments(value) } else { requestPreview() }
    }
    func cancelCrop() {
        guard isCropping else { return }
        cropDraft = nil
        resetGeometryPreview(); requestPreview()
    }
    func clearCrop() {
        var value = settings.adjustments; value.geometry.crop = nil
        setAdjustments(value)
    }

    func exportItems() -> [ExportItem] {
        photos.filter { photo in
            let entry = savedSettings(for: photo)
            guard entry.exportReady, !entry.rejected else { return false }
            switch exportOptions.scope {
            case .ready: return true
            case .currentFolder: return folder.isEmpty || photo.relativePath.hasPrefix(folder + "/")
            case .selected: return selectedIDs.contains(photo.id)
            case .favorites: return entry.favorite
            }
        }.map { ExportItem(photo: $0, adjustments: savedSettings(for: $0).adjustments) }
    }

    func startExport() {
        guard !isCropping else { return }
        guard flush() else { return }
        let items = exportItems()
        guard !items.isEmpty else { errorMessage = "No marked photos in this selection."; return }
        let panel = NSOpenPanel()
        panel.title = "Export"; panel.prompt = "Export"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let roots = workspaces.map(\.url)
        do { try Exporter.validateDestination(destination, roots: roots) }
        catch { errorMessage = error.localizedDescription; return }
        let options = exportOptions, cancellation = ExportCancellation()
        self.cancellation = cancellation
        showExportSheet = false; exporting = true; exportProgress = 0; exportLabel = "Preparing export…"
        exportQueue.async {
            let result = Exporter.run(items: items, destination: destination, roots: roots, options: options, cancellation: cancellation) { count, name in
                DispatchQueue.main.async { self.exportProgress = Double(count)/Double(items.count); self.exportLabel = name }
            }
            DispatchQueue.main.async {
                self.exporting = false
                var counts = ["\(result.completed) exported"]
                if result.skipped > 0 { counts.append("\(result.skipped) skipped") }
                if !result.errors.isEmpty { counts.append("\(result.errors.count) failed") }
                let heading = cancellation.cancelled ? "Export cancelled.\n" : ""
                self.exportSummary = heading + counts.joined(separator: ", ") + "." + (result.errors.isEmpty ? "" : "\n\n" + result.errors.prefix(8).joined(separator: "\n"))
            }
        }
    }
    func cancelExport() { cancellation?.cancel(); exportLabel = "Cancelling after the current image…" }
}
