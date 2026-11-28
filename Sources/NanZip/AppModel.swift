import AppKit
import Combine
import Foundation
import NanZipCore
import UniformTypeIdentifiers

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case extract
    case compress
    case batch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .extract: return "解压"
        case .compress: return "压缩"
        case .batch: return "批量"
        }
    }

    var symbol: String {
        switch self {
        case .extract: return "arrow.down.doc"
        case .compress: return "arrow.up.doc"
        case .batch: return "square.stack.3d.up"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var mode: WorkspaceMode = .extract

    @Published var archiveURL: URL?
    @Published var items: [ArchiveItem] = []
    @Published var selectedIDs: Set<ArchiveItem.ID> = []
    @Published var selectedFolderPath = ""
    @Published var searchText = ""
    @Published var destinationURL: URL?
    @Published var destinationIsUserSelected = false
    @Published var password = ""
    @Published var overwritePolicy: ArchiveOverwritePolicy = .keepBoth
    @Published var isLoading = false
    @Published var isExtracting = false
    @Published var isEditingArchive = false
    @Published var progress: Double = 0
    @Published var currentPath = ""
    @Published var statusMessage = "拖入压缩包或点击“打开压缩包”"
    @Published var errorMessage: String?
    @Published var isDropTargeted = false

    @Published var compressionInputs: [URL] = []
    @Published var compressionFormat: CompressionFormat = .zip
    @Published var compressionLevel: CompressionLevel = .balanced
    @Published var compressionPassword = ""
    @Published var compressionVolumeChoice: CompressionVolumeChoice = .none
    @Published var compressionFilenameEncoding: ArchiveFilenameEncoding = .automatic
    @Published var compressionDestinationURL: URL?
    @Published var compressionDestinationIsUserSelected = false
    @Published var isCompressing = false
    @Published var compressionProgress: Double = 0
    @Published var compressionCurrentPath = ""
    @Published var compressionStatusMessage = "选择文件或文件夹后开始压缩"

    @Published var extractionPolicy: ExtractionDestinationPolicy = .smart
    @Published var rememberPassword = false
    @Published var previewURL: URL?
    @Published var previewItem: ArchiveItem?
    @Published var isPreviewing = false
    @Published var previewError: String?
    @Published var archiveBreadcrumbs: [ArchiveBreadcrumb] = []

    @Published var batchMode: BatchOperationMode = .extract
    @Published var batchItems: [BatchQueueItem] = []
    @Published var batchOutputDirectory: URL?
    @Published var isBatchRunning = false
    @Published var batchProgress: Double = 0
    @Published var batchStatusMessage = "添加压缩包或文件后开始批量处理"

    private var loadTask: Task<Void, Never>?
    private var extractionTask: Task<Void, Never>?
    private var compressionTask: Task<Void, Never>?
    private var cancellationToken: CancellationToken?
    private var activeXPCOperationID: String?
    private var previewWorkingDirectory: URL?
    private var quickActionObserver: NSObjectProtocol?
    private var pendingQuickExtractionPolicy: ExtractionDestinationPolicy?

    init() {
        XPCSharedStorage.removeStaleDirectories()
        quickActionObserver = NotificationCenter.default.addObserver(
            forName: .nanZipQuickAction,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let payload = notification.object as? NanZipQuickActionPayload else { return }
            Task { @MainActor in
                self?.handleQuickAction(payload)
            }
        }
    }

    deinit {
        if let quickActionObserver {
            NotificationCenter.default.removeObserver(quickActionObserver)
        }
    }

    var filteredItems: [ArchiveItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return items.filter { $0.path.localizedLowercase.contains(query.localizedLowercase) }
        }
        return items.filter { $0.parentPath == selectedFolderPath }
    }

    var selectedItems: [ArchiveItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    var selectedEntryPaths: Set<String> {
        Set(selectedItems.map(\.path))
    }

    var totalUncompressedSize: Int64 {
        items.reduce(0) { $0 + ($1.isDirectory ? 0 : $1.size) }
    }

    var totalCompressedSize: Int64 {
        items.reduce(0) { $0 + ($1.isDirectory ? 0 : $1.compressedSize) }
    }

    var archiveFileSize: Int64 {
        guard let archiveURL,
              let values = try? archiveURL.resourceValues(forKeys: [.fileSizeKey]) else {
            return 0
        }
        return Int64(values.fileSize ?? 0)
    }

    var fileCount: Int {
        items.reduce(0) { $0 + ($1.isDirectory ? 0 : 1) }
    }

    var selectedPaths: Set<String>? {
        let selectedItems = items.filter {
            selectedIDs.contains($0.id) && !$0.isDirectory && !$0.isSymlink
        }
        guard !selectedItems.isEmpty else { return nil }
        return Set(selectedItems.map(\.path))
    }

    var selectedFileCount: Int {
        items.filter {
            selectedIDs.contains($0.id) && !$0.isDirectory && !$0.isSymlink
        }.count
    }

    var selectedUncompressedSize: Int64 {
        guard let selectedPaths else { return 0 }
        return items
            .filter { selectedPaths.contains($0.path) }
            .reduce(0) { $0 + $1.size }
    }

    var canExtract: Bool {
        archiveURL != nil && !items.isEmpty && !isBusy
    }

    var selectedUncompressedTotal: Int64 {
        selectedItems.reduce(0) { $0 + ($1.isDirectory ? 0 : $1.size) }
    }

    var selectedCompressedTotal: Int64 {
        selectedItems.reduce(0) { $0 + ($1.isDirectory ? 0 : $1.compressedSize) }
    }

    var canAddToArchive: Bool {
        archiveURL != nil && !isBusy
    }

    var canReplaceSelected: Bool {
        archiveURL != nil && selectedItems.count == 1 && !isBusy &&
            selectedItems[0].isDirectory == false
    }

    var canDeleteSelected: Bool {
        archiveURL != nil && !selectedItems.isEmpty && !isBusy
    }

    var canTestArchive: Bool {
        archiveURL != nil && !isBusy
    }

    var canExtractSelected: Bool {
        canExtract && selectedFileCount > 0
    }

    var canPreviewSelected: Bool {
        selectedItems.count == 1 && selectedItems[0].isDirectory == false && !isBusy
    }

    var canOpenNestedArchive: Bool {
        guard selectedItems.count == 1, let item = selectedItems.first, !item.isDirectory else {
            return false
        }
        let ext = (item.name as NSString).pathExtension.lowercased()
        return ArchiveService.supportedExtensions.contains(ext)
    }

    var canNavigateBack: Bool {
        archiveBreadcrumbs.count > 1 && !isBusy
    }

    var currentNestedBreadcrumbTitle: String? {
        archiveBreadcrumbs.last?.nestedEntryPath
    }

    var selectionLabel: String {
        selectedFileCount > 0 ? "解压所选（\(selectedFileCount)）" : "解压所选"
    }

    var isBusy: Bool {
        isLoading || isExtracting || isCompressing || isEditingArchive || isBatchRunning
    }

    var canCompress: Bool {
        !compressionInputs.isEmpty && !isBusy
    }

    var canRunBatch: Bool {
        !batchItems.isEmpty && !isBusy && !isBatchRunning
    }

    var compressionInputCount: Int {
        compressionInputs.reduce(0) { partial, url in
            partial + (directoryEntryCount(url) ?? 1)
        }
    }

    var compressionTotalBytes: Int64 {
        compressionInputs.reduce(0) { $0 + sizeOfItem($1) }
    }

    var compressionFormatSupportsEncryption: Bool {
        compressionFormat.supportsEncryption
    }

    func selectMode(_ newMode: WorkspaceMode) {
        mode = newMode
        if newMode == .compress {
            statusMessage = compressionStatusMessage
        } else if newMode == .batch {
            statusMessage = batchStatusMessage
        } else if archiveURL == nil {
            statusMessage = "拖入压缩包或点击“打开压缩包”"
        } else if !items.isEmpty {
            statusMessage = "已读取 \(fileCount) 个文件 · \(ArchiveOperationBridge.hasEmbeddedXPCService ? "XPC" : "本机引擎")"
        }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择压缩包"
        panel.prompt = "打开"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ArchiveService.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openArchive(url)
    }

    func presentDestinationPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择解压位置"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = destinationURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destinationURL = url
        destinationIsUserSelected = true
    }

    func presentCompressionInputPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择要压缩的文件和文件夹"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK else { return }
        addCompressionInputs(panel.urls)
    }

    func presentCompressionDestinationPanel() {
        let panel = NSSavePanel()
        panel.title = "保存压缩包"
        panel.prompt = "保存"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = compressionDestinationURL?.lastPathComponent
            ?? suggestedArchiveName()
        if let type = UTType(filenameExtension: compressionFormat.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        compressionDestinationURL = url
        compressionDestinationIsUserSelected = true
    }

    func addCompressionInputs(_ urls: [URL]) {
        mode = .compress
        let existing = Set(compressionInputs.map { $0.standardizedFileURL.path })
        var updated = compressionInputs
        for url in urls where !existing.contains(url.standardizedFileURL.path) {
            updated.append(url.standardizedFileURL)
        }
        compressionInputs = updated
        if compressionDestinationURL == nil {
            compressionDestinationURL = suggestedArchiveDestination()
            compressionDestinationIsUserSelected = false
        }
        compressionStatusMessage = "已添加 \(compressionInputs.count) 个项目"
    }

    func removeCompressionInput(_ url: URL) {
        compressionInputs.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        if compressionInputs.isEmpty {
            compressionDestinationURL = nil
            compressionDestinationIsUserSelected = false
            compressionStatusMessage = "选择文件或文件夹后开始压缩"
        } else {
            compressionDestinationURL = suggestedArchiveDestination()
        }
    }

    func refreshCompressionDestinationForFormat() {
        guard !compressionInputs.isEmpty else { return }
        compressionDestinationURL = suggestedArchiveDestination()
        compressionDestinationIsUserSelected = false
    }

    func openArchive(_ url: URL) {
        cleanupBreadcrumbTemporaryDirectories(after: 0)
        archiveBreadcrumbs = [
            ArchiveBreadcrumb(
                archiveURL: url,
                nestedEntryPath: nil,
                temporaryDirectory: nil
            )
        ]
        loadArchive(url)
    }

    private func loadArchive(_ url: URL) {
        loadTask?.cancel()
        clearPreview()
        mode = .extract
        archiveURL = url
        items = []
        selectedIDs = []
        selectedFolderPath = ""
        searchText = ""
        progress = 0
        currentPath = ""
        destinationURL = suggestedExtractionDestination(for: url)
        destinationIsUserSelected = false
        isLoading = true
        statusMessage = "正在读取归档目录…"

        if password.isEmpty, let savedPassword = PasswordStore.password(for: url) {
            password = savedPassword
            rememberPassword = true
        }
        let passphrase = password.isEmpty ? nil : password
        let operationID = UUID().uuidString
        activeXPCOperationID = operationID
        let request = ArchiveXPCRequest(
            operationID: operationID,
            operation: .list,
            archivePath: url.path,
            password: passphrase,
            filenameEncoding: compressionFilenameEncoding
        )
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loadedItems = try await Task.detached(priority: .userInitiated) {
                    try ArchiveOperationBridge.list(request)
                }.value

                if Task.isCancelled { return }
                items = loadedItems
                isLoading = false
                activeXPCOperationID = nil
                statusMessage = loadedItems.isEmpty
                    ? "压缩包中没有可显示的文件"
                    : "已读取 \(fileCount) 个文件 · \(ArchiveOperationBridge.hasEmbeddedXPCService ? "XPC" : "本机引擎")"
                if let quickPolicy = pendingQuickExtractionPolicy {
                    pendingQuickExtractionPolicy = nil
                    extractionPolicy = quickPolicy
                    DispatchQueue.main.async { [weak self] in
                        self?.startExtraction(
                            selectedPaths: nil,
                            totalBytes: self?.totalUncompressedSize ?? 0,
                            label: "全部文件"
                        )
                    }
                }
            } catch {
                if Task.isCancelled { return }
                isLoading = false
                activeXPCOperationID = nil
                pendingQuickExtractionPolicy = nil
                items = []
                handle(error)
            }
        }
    }

    func reloadWithPassword() {
        guard let archiveURL else { return }
        loadArchive(archiveURL)
    }

    func openNestedArchive() {
        guard let archiveURL,
              selectedItems.count == 1,
              let item = selectedItems.first,
              !item.isDirectory else { return }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("nanzip-nested-\(UUID().uuidString)", isDirectory: true)
        let operationID = UUID().uuidString
        activeXPCOperationID = operationID
        let request = ArchiveXPCRequest(
            operationID: operationID,
            operation: .preview,
            archivePath: archiveURL.path,
            destinationPath: work.path,
            entryPath: item.path,
            password: password.isEmpty ? nil : password,
            filenameEncoding: compressionFilenameEncoding
        )
        isEditingArchive = true
        statusMessage = "正在打开嵌套归档…"
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ArchiveOperationBridge.preview(request, cancellationToken: CancellationToken())
                }.value
                isEditingArchive = false
                activeXPCOperationID = nil
                archiveBreadcrumbs.append(
                    ArchiveBreadcrumb(
                        archiveURL: result.extractedURL,
                        nestedEntryPath: item.path,
                        temporaryDirectory: result.workingDirectoryURL
                    )
                )
                loadArchive(result.extractedURL)
            } catch {
                isEditingArchive = false
                activeXPCOperationID = nil
                try? FileManager.default.removeItem(at: work)
                handle(error)
            }
        }
    }

    func navigateBackFromNestedArchive() {
        guard archiveBreadcrumbs.count > 1 else { return }
        let removed = archiveBreadcrumbs.removeLast()
        if let directory = removed.temporaryDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
        guard let parent = archiveBreadcrumbs.last else { return }
        loadArchive(parent.archiveURL)
    }

    private func cleanupBreadcrumbTemporaryDirectories(after index: Int) {
        guard archiveBreadcrumbs.count > index else { return }
        for breadcrumb in archiveBreadcrumbs.dropFirst(index + 1) {
            if let directory = breadcrumb.temporaryDirectory {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    func extractAll() {
        startExtraction(
            selectedPaths: nil,
            totalBytes: totalUncompressedSize,
            label: "全部文件"
        )
    }

    func extractSelected() {
        guard let selectedPaths else { return }
        startExtraction(
            selectedPaths: selectedPaths,
            totalBytes: selectedUncompressedSize,
            label: "\(selectedPaths.count) 个文件"
        )
    }

    func extractSmart() {
        extractionPolicy = .smart
        extractAll()
    }

    func extractHere() {
        extractionPolicy = .here
        extractAll()
    }

    func extractToChosenFolder() {
        presentDestinationPanel()
        guard destinationURL != nil else { return }
        extractionPolicy = .custom
        if selectedFileCount > 0 {
            extractSelected()
        } else {
            extractAll()
        }
    }

    func updatePreviewForSelection() {
        guard selectedItems.count == 1,
              let item = selectedItems.first,
              !item.isDirectory else {
            clearPreview()
            return
        }
        beginPreview(item)
    }

    func beginPreview(_ item: ArchiveItem) {
        guard let archiveURL else { return }
        clearPreview()
        previewItem = item
        isPreviewing = true
        previewError = nil
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("nanzip-preview-ui-\(UUID().uuidString)", isDirectory: true)
        let request = ArchiveXPCRequest(
            operation: .preview,
            archivePath: archiveURL.path,
            destinationPath: work.path,
            entryPath: item.path,
            password: password.isEmpty ? nil : password,
            filenameEncoding: compressionFilenameEncoding
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ArchiveOperationBridge.preview(request, cancellationToken: CancellationToken())
                }.value
                guard self.previewItem?.id == item.id else {
                    try? FileManager.default.removeItem(at: result.workingDirectoryURL)
                    return
                }
                previewWorkingDirectory = result.workingDirectoryURL
                previewURL = result.extractedURL
                isPreviewing = false
            } catch {
                isPreviewing = false
                previewError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func clearPreview() {
        previewURL = nil
        previewItem = nil
        isPreviewing = false
        previewError = nil
        if let previewWorkingDirectory {
            try? FileManager.default.removeItem(at: previewWorkingDirectory)
        }
        previewWorkingDirectory = nil
    }

    func revealPreviewFile() {
        guard let previewURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([previewURL])
    }

    func presentAddFilesPanel() {
        guard let archiveURL else { return }
        let panel = NSOpenPanel()
        panel.title = "添加到 \(archiveURL.lastPathComponent)"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let files = panel.urls
        let operationID = UUID().uuidString
        let request = ArchiveXPCRequest(
            operationID: operationID,
            operation: .add,
            archivePath: archiveURL.path,
            inputPaths: files.map(\.path),
            password: password.isEmpty ? nil : password
        )
        beginArchiveEdit(
            operationName: "正在添加文件…",
            operationID: operationID
        ) { token in
            let changed = try ArchiveOperationBridge.edit(request, cancellationToken: token)
            return ArchiveEditSummary(
                changedEntries: changed,
                archiveURL: archiveURL
            )
        }
    }

    func presentReplaceFilePanel() {
        guard let archiveURL,
              selectedItems.count == 1,
              let item = selectedItems.first,
              !item.isDirectory else { return }

        let panel = NSOpenPanel()
        panel.title = "替换 \(item.path)"
        panel.prompt = "替换"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        let operationID = UUID().uuidString
        let request = ArchiveXPCRequest(
            operationID: operationID,
            operation: .replace,
            archivePath: archiveURL.path,
            password: password.isEmpty ? nil : password,
            replacements: [
                ArchiveXPCReplacement(archivePath: item.path, sourcePath: sourceURL.path)
            ]
        )
        beginArchiveEdit(
            operationName: "正在替换归档内容…",
            operationID: operationID
        ) { token in
            let changed = try ArchiveOperationBridge.edit(request, cancellationToken: token)
            return ArchiveEditSummary(
                changedEntries: changed,
                archiveURL: archiveURL
            )
        }
    }

    func deleteSelectedEntries() {
        guard let archiveURL, !selectedEntryPaths.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "删除归档中的所选内容？"
        alert.informativeText = "将从 \(archiveURL.lastPathComponent) 中删除 \(selectedEntryPaths.count) 个条目。原始磁盘文件不会受影响。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let paths = selectedEntryPaths
        let operationID = UUID().uuidString
        let request = ArchiveXPCRequest(
            operationID: operationID,
            operation: .delete,
            archivePath: archiveURL.path,
            selectedPaths: paths,
            password: password.isEmpty ? nil : password
        )
        beginArchiveEdit(
            operationName: "正在删除归档内容…",
            operationID: operationID
        ) { token in
            let changed = try ArchiveOperationBridge.edit(request, cancellationToken: token)
            return ArchiveEditSummary(
                changedEntries: changed,
                archiveURL: archiveURL
            )
        }
    }

    func testCurrentArchive() {
        guard let archiveURL else { return }
        let operationID = UUID().uuidString
        let request = ArchiveXPCRequest(
            operationID: operationID,
            operation: .test,
            archivePath: archiveURL.path,
            password: password.isEmpty ? nil : password
        )
        beginArchiveEdit(
            operationName: "正在测试压缩包完整性…",
            operationID: operationID,
            savePasswordOnSuccess: true
        ) { _ in
            try ArchiveOperationBridge.test(request)
            return ArchiveEditSummary(changedEntries: 0, archiveURL: archiveURL)
        }
    }

    func presentRepairPanel() {
        guard let archiveURL, archiveURL.pathExtension.lowercased() == "zip" else { return }
        let panel = NSSavePanel()
        panel.title = "修复损坏的 ZIP"
        panel.prompt = "创建修复副本"
        panel.canCreateDirectories = true
        let base = archiveURL.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(base)-repaired.zip"
        panel.directoryURL = archiveURL.deletingLastPathComponent()
        if let zipType = UTType(filenameExtension: "zip") {
            panel.allowedContentTypes = [zipType]
        }
        guard panel.runModal() == .OK, let output = panel.url else { return }
        repairCurrentZIP(to: output)
    }

    private func repairCurrentZIP(to outputURL: URL) {
        guard let archiveURL else { return }
        let operationID = UUID().uuidString
        let options = CompressionOptions(
            format: .zip,
            level: .balanced,
            password: password.isEmpty ? nil : password,
            filenameEncoding: compressionFilenameEncoding
        )
        let request = ArchiveXPCRequest(
            operationID: operationID,
            operation: .repair,
            archivePath: archiveURL.path,
            destinationPath: outputURL.path,
            password: password.isEmpty ? nil : password,
            compressionOptions: options
        )
        let token = CancellationToken()
        cancellationToken = token
        activeXPCOperationID = operationID
        isEditingArchive = true
        progress = 0.05
        currentPath = "正在扫描可恢复的 ZIP 条目…"
        statusMessage = "正在创建修复副本…"
        Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await Task.detached(priority: .userInitiated) {
                    try ArchiveOperationBridge.repair(
                        request,
                        cancellationToken: token,
                        progress: { _, _ in }
                    )
                }.value
                isEditingArchive = false
                activeXPCOperationID = nil
                progress = 1
                statusMessage = "已恢复 \(summary.recoveredFiles) 个文件到 \(summary.outputURL.lastPathComponent)"

                let alert = NSAlert()
                alert.messageText = "ZIP 修复副本已创建"
                alert.informativeText = "恢复 \(summary.recoveredFiles) 个文件，跳过 \(summary.skippedEntries) 个无法安全恢复的条目。原压缩包未被修改。"
                alert.addButton(withTitle: "在 Finder 中显示")
                alert.addButton(withTitle: "好")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.activateFileViewerSelecting([summary.outputURL])
                }
            } catch {
                isEditingArchive = false
                activeXPCOperationID = nil
                handle(error)
            }
        }
    }

    func startCompression() {
        guard !compressionInputs.isEmpty else { return }
        if compressionDestinationURL == nil || !compressionDestinationIsUserSelected {
            presentCompressionDestinationPanel()
            guard compressionDestinationURL != nil else { return }
        }
        guard let compressionDestinationURL else { return }

        let options = CompressionOptions(
            format: compressionFormat,
            level: compressionLevel,
            password: compressionFormatSupportsEncryption ? compressionPassword : nil,
            volumeSizeBytes: compressionVolumeChoice.bytes,
            filenameEncoding: compressionFilenameEncoding
        )
        let token = CancellationToken()
        cancellationToken = token
        let operationID = UUID().uuidString
        activeXPCOperationID = operationID
        isCompressing = true
        compressionProgress = 0
        compressionCurrentPath = ""
        compressionStatusMessage = "正在创建 \(options.format.title) 压缩包…"

        let inputs = compressionInputs
        let request = ArchiveXPCRequest(
            operationID: operationID,
            operation: .compress,
            destinationPath: compressionDestinationURL.path,
            inputPaths: inputs.map(\.path),
            password: options.password,
            compressionOptions: options
        )
        compressionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await Task.detached(priority: .userInitiated) {
                    try ArchiveOperationBridge.compress(
                        request,
                        cancellationToken: token,
                        progress: { update in
                            DispatchQueue.main.async {
                                self.compressionProgress = update.fraction
                                self.compressionCurrentPath = update.currentPath
                            }
                        }
                    )
                }.value

                isCompressing = false
                activeXPCOperationID = nil
                compressionProgress = 1
                compressionStatusMessage = "已创建 \(summary.outputURL.lastPathComponent)"
                statusMessage = compressionStatusMessage
            } catch {
                isCompressing = false
                activeXPCOperationID = nil
                if case ArchiveError.cancelled = error {
                    compressionStatusMessage = "已取消压缩"
                    statusMessage = compressionStatusMessage
                    return
                }
                handle(error)
            }
        }
    }

    func cancelCurrentOperation() {
        cancellationToken?.cancel()
        if let activeXPCOperationID {
            ArchiveXPCClient.shared.cancel(activeXPCOperationID)
        }
        statusMessage = "正在取消…"
        compressionStatusMessage = "正在取消…"
    }

    func presentBatchInputPanel() {
        let panel = NSOpenPanel()
        panel.title = batchMode == .extract ? "选择要批量解压的压缩包" : "选择要批量压缩的文件和文件夹"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = batchMode == .compress
        panel.allowsMultipleSelection = true
        if batchMode == .extract {
            panel.allowedContentTypes = ArchiveService.supportedExtensions.compactMap {
                UTType(filenameExtension: $0)
            }
        }
        guard panel.runModal() == .OK else { return }
        let existing = Set(batchItems.map { $0.url.standardizedFileURL.path })
        for url in panel.urls where !existing.contains(url.standardizedFileURL.path) {
            batchItems.append(BatchQueueItem(url: url.standardizedFileURL))
        }
        batchStatusMessage = "已添加 \(batchItems.count) 个项目"
    }

    func presentBatchOutputPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择批量输出文件夹"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = batchOutputDirectory
        guard panel.runModal() == .OK else { return }
        batchOutputDirectory = panel.url
    }

    func clearBatchQueue() {
        guard !isBatchRunning else { return }
        batchItems = []
        isBatchRunning = false
        batchProgress = 0
        batchStatusMessage = "添加压缩包或文件后开始批量处理"
    }

    func startBatch() {
        guard !batchItems.isEmpty, !isBatchRunning else { return }
        if batchOutputDirectory == nil {
            presentBatchOutputPanel()
            guard batchOutputDirectory != nil else { return }
        }
        isBatchRunning = true
        batchProgress = 0
        batchStatusMessage = "准备批量处理…"
        let mode = batchMode
        let inputs = batchItems
        let outputDirectory = batchOutputDirectory
        let compressionOptions = CompressionOptions(
            format: compressionFormat,
            level: compressionLevel,
            password: compressionFormatSupportsEncryption ? compressionPassword : nil,
            volumeSizeBytes: compressionVolumeChoice.bytes,
            filenameEncoding: compressionFilenameEncoding
        )
        let defaultOverwrite = overwritePolicy == .ask ? .keepBoth : overwritePolicy
        let policy = extractionPolicy
        let passphrase = password.isEmpty ? nil : password

        Task { [weak self] in
            guard let self else { return }
            var succeeded = 0
            var failed = 0
            for input in inputs {
                if cancellationToken?.isCancelled == true { break }
                guard let index = batchItems.firstIndex(where: { $0.id == input.id }) else { continue }
                batchItems[index].state = .running
                batchStatusMessage = "正在处理 \(input.url.lastPathComponent)…"
                let token = CancellationToken()
                cancellationToken = token
                do {
                    if mode == .compress {
                        let outputParent = outputDirectory ?? input.url.deletingLastPathComponent()
                        try FileManager.default.createDirectory(at: outputParent, withIntermediateDirectories: true)
                        let output = outputParent.appendingPathComponent(
                            "\(input.url.lastPathComponent).\(compressionFormat.fileExtension)"
                        )
                        let operationID = UUID().uuidString
                        activeXPCOperationID = operationID
                        let request = ArchiveXPCRequest(
                            operationID: operationID,
                            operation: .compress,
                            destinationPath: output.path,
                            inputPaths: [input.url.path],
                            password: compressionOptions.password,
                            compressionOptions: compressionOptions
                        )
                        let summary = try await Task.detached(priority: .userInitiated) {
                            try ArchiveOperationBridge.compress(
                                request,
                                cancellationToken: token,
                                progress: { _ in }
                            )
                        }.value
                        batchItems[index].state = .success(
                            "已创建 \(summary.outputURL.lastPathComponent)"
                        )
                    } else {
                        let operationID = UUID().uuidString
                        activeXPCOperationID = operationID
                        let listRequest = ArchiveXPCRequest(
                            operationID: operationID,
                            operation: .list,
                            archivePath: input.url.path,
                            password: passphrase,
                            filenameEncoding: compressionFilenameEncoding
                        )
                        let listed = try await Task.detached(priority: .userInitiated) {
                            try ArchiveOperationBridge.list(listRequest)
                        }.value
                        let baseDestination = outputDirectory ?? input.url.deletingLastPathComponent()
                        let destination = ExtractionDestinationResolver.resolve(
                            archiveURL: input.url,
                            items: listed,
                            policy: policy,
                            customDestination: baseDestination
                        )
                        let extractID = UUID().uuidString
                        activeXPCOperationID = extractID
                        let extractRequest = ArchiveXPCRequest(
                            operationID: extractID,
                            operation: .extract,
                            archivePath: input.url.path,
                            destinationPath: destination.path,
                            password: passphrase,
                            overwritePolicy: defaultOverwrite,
                            filenameEncoding: compressionFilenameEncoding
                        )
                        let summary = try await Task.detached(priority: .userInitiated) {
                            try ArchiveOperationBridge.extract(extractRequest)
                        }.value
                        batchItems[index].state = .success("解压 \(summary.extractedFiles) 个文件")
                    }
                    succeeded += 1
                } catch {
                    batchItems[index].state = .failed(
                        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                    failed += 1
                }
                activeXPCOperationID = nil
                batchProgress = Double(succeeded + failed) / Double(max(inputs.count, 1))
            }
            isBatchRunning = false
            cancellationToken = nil
            batchProgress = succeeded + failed == inputs.count ? 1 : batchProgress
            batchStatusMessage = "批量完成：成功 \(succeeded)，失败 \(failed)"
            statusMessage = batchStatusMessage
        }
    }

    func revealDestination() {
        guard let destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    func revealCompressionOutput() {
        guard let url = compressionDestinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func setNanZipAsDefaultArchiveApplication() {
        NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL,
            toOpen: .zip
        ) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.errorMessage = "无法设置默认归档应用：\(error.localizedDescription)"
                } else {
                    self?.statusMessage = "已将 NanZip 设为 ZIP 默认应用；macOS 可能显示确认提示"
                }
            }
        }
    }

    func handleDroppedURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if mode == .compress {
            addCompressionInputs(urls)
            return
        }
        if urls.count == 1, let url = urls.first {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                openArchive(url)
            } else if isDirectory.boolValue {
                addCompressionInputs(urls)
            }
        } else {
            addCompressionInputs(urls)
        }
    }

    private func handleQuickAction(_ payload: NanZipQuickActionPayload) {
        guard let first = payload.urls.first else { return }
        switch payload.action {
        case .compress:
            addCompressionInputs(payload.urls)
        case .extractHere:
            pendingQuickExtractionPolicy = .here
            openArchive(first)
        case .extractChoose:
            pendingQuickExtractionPolicy = nil
            destinationURL = nil
            openArchive(first)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.presentDestinationPanel()
            }
        }
    }

    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "nanzip" else {
            handleDroppedURLs([url])
            return
        }

        let pathPayload = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "paths" })?
            .value
        let paths = decodePaths(pathPayload)
        guard !paths.isEmpty else { return }

        switch url.host?.lowercased() {
        case "extract":
            if let first = paths.first {
                openArchive(URL(fileURLWithPath: first))
            }
        case "smart-extract":
            if let first = paths.first {
                pendingQuickExtractionPolicy = .smart
                openArchive(URL(fileURLWithPath: first))
            }
        case "extract-here":
            if let first = paths.first {
                pendingQuickExtractionPolicy = .here
                openArchive(URL(fileURLWithPath: first))
            }
        case "extract-choose":
            if let first = paths.first {
                pendingQuickExtractionPolicy = nil
                openArchive(URL(fileURLWithPath: first))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.presentDestinationPanel()
                }
            }
        case "compress":
            addCompressionInputs(paths.map { URL(fileURLWithPath: $0) })
        default:
            handleDroppedURLs(paths.map { URL(fileURLWithPath: $0) })
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func beginArchiveEdit(
        operationName: String,
        operationID: String? = nil,
        savePasswordOnSuccess: Bool = false,
        operation: @escaping @Sendable (CancellationToken) throws -> ArchiveEditSummary
    ) {
        guard let archiveURL else { return }
        let token = CancellationToken()
        cancellationToken = token
        activeXPCOperationID = operationID
        isEditingArchive = true
        progress = 0
        currentPath = ""
        statusMessage = operationName

        Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await Task.detached(priority: .userInitiated) {
                    try operation(token)
                }.value
                isEditingArchive = false
                activeXPCOperationID = nil
                if savePasswordOnSuccess, rememberPassword, !password.isEmpty {
                    try? PasswordStore.save(password: password, for: archiveURL)
                }
                selectedIDs = []
                statusMessage = summary.changedEntries > 0
                    ? "归档内容已更新（\(summary.changedEntries) 项）"
                    : "压缩包完整性测试通过"
                let preservedDestination = destinationURL
                openArchive(archiveURL)
                destinationURL = preservedDestination
            } catch {
                isEditingArchive = false
                activeXPCOperationID = nil
                if case ArchiveError.cancelled = error {
                    statusMessage = "操作已取消"
                } else if let sevenZipError = error as? SevenZipError,
                          case .cancelled = sevenZipError {
                    statusMessage = "操作已取消"
                } else {
                    handle(error)
                }
            }
        }
    }

    private func startExtraction(
        selectedPaths: Set<String>?,
        totalBytes: Int64,
        label: String
    ) {
        guard let archiveURL else { return }
        if !destinationIsUserSelected {
            presentDestinationPanel()
            guard destinationIsUserSelected, destinationURL != nil else { return }
        }
        if extractionPolicy == .custom && destinationURL == nil {
            presentDestinationPanel()
            return
        }
        let requestedDestination = destinationURL ?? suggestedExtractionDestination(for: archiveURL)
        let resolvedDestination = ExtractionDestinationResolver.resolve(
            archiveURL: archiveURL,
            items: items,
            policy: extractionPolicy,
            customDestination: requestedDestination
        )
        destinationURL = resolvedDestination

        let effectivePolicy = resolveAskPolicyIfNeeded(
            destination: resolvedDestination,
            selectedPaths: selectedPaths
        )
        guard let effectivePolicy else { return }

        let token = CancellationToken()
        cancellationToken = token
        let operationID = UUID().uuidString
        activeXPCOperationID = operationID
        isExtracting = true
        progress = 0.05
        currentPath = "正在提交到独立 XPC 归档服务…"
        statusMessage = "正在解压 \(label)…"

        let passphrase = password.isEmpty ? nil : password
        let request = ArchiveXPCRequest(
            operationID: operationID,
            operation: .extract,
            archivePath: archiveURL.path,
            destinationPath: resolvedDestination.path,
            selectedPaths: selectedPaths,
            password: passphrase,
            overwritePolicy: effectivePolicy,
            filenameEncoding: compressionFilenameEncoding
        )

        extractionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await Task.detached(priority: .userInitiated) {
                    try ArchiveOperationBridge.extract(request) { update in
                        DispatchQueue.main.async {
                            self.progress = update.fraction
                            self.currentPath = update.currentPath
                        }
                    }
                }.value

                isExtracting = false
                activeXPCOperationID = nil
                progress = 1
                let skipped = summary.skippedEntries > 0
                    ? "，跳过 \(summary.skippedEntries) 个特殊条目"
                    : ""
                statusMessage = "已解压 \(summary.extractedFiles) 个文件\(skipped)"
                if rememberPassword, let passphrase, !passphrase.isEmpty {
                    try? PasswordStore.save(password: passphrase, for: archiveURL)
                }
            } catch {
                isExtracting = false
                activeXPCOperationID = nil
                if case ArchiveError.cancelled = error {
                    statusMessage = "已取消解压"
                    return
                }
                if let xpcError = error as? ArchiveXPCClientError,
                   case .remote(let message) = xpcError,
                   message.contains("取消") {
                    statusMessage = "已取消解压"
                    return
                }
                handle(error)
            }
        }
    }

    private func resolveAskPolicyIfNeeded(
        destination: URL,
        selectedPaths: Set<String>?
    ) -> ArchiveOverwritePolicy? {
        guard overwritePolicy == .ask else { return overwritePolicy }
        let candidates: [ArchiveItem]
        if let selectedPaths {
            candidates = items.filter { selectedPaths.contains($0.path) && !$0.isDirectory }
        } else {
            candidates = items.filter { !$0.isDirectory }
        }
        let hasConflict = candidates.contains { item in
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent(item.path).path
            )
        }
        guard hasConflict else { return .overwrite }

        let alert = NSAlert()
        alert.messageText = "目标位置已有同名文件"
        alert.informativeText = "请选择本次解压的覆盖规则。"
        alert.addButton(withTitle: "覆盖")
        alert.addButton(withTitle: "跳过")
        alert.addButton(withTitle: "保留两者")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .overwrite
        case .alertSecondButtonReturn: return .skip
        case .alertThirdButtonReturn: return .keepBoth
        default: return nil
        }
    }

    private func suggestedExtractionDestination(for archiveURL: URL) -> URL {
        archiveURL.deletingLastPathComponent().appendingPathComponent(
            ExtractionDestinationResolver.archiveBaseName(for: archiveURL),
            isDirectory: true
        )
    }

    private func suggestedArchiveName() -> String {
        let base: String
        if compressionInputs.count == 1 {
            base = compressionInputs[0].lastPathComponent
        } else {
            base = "Archive"
        }
        return "\(base).\(compressionFormat.fileExtension)"
    }

    private func suggestedArchiveDestination() -> URL? {
        guard let parent = compressionInputs.first?.deletingLastPathComponent() else {
            return nil
        }
        return parent.appendingPathComponent(suggestedArchiveName())
    }

    private func directoryEntryCount(_ url: URL) -> Int? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil
        ) else { return 1 }
        var count = 0
        while enumerator.nextObject() != nil { count += 1 }
        return count
    }

    private func sizeOfItem(_ url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }
        if !isDirectory.boolValue {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values?.fileSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    private func decodePaths(_ encoded: String?) -> [String] {
        guard var encoded, !encoded.isEmpty else { return [] }
        encoded = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 { encoded.append("=") }
        guard let data = Data(base64Encoded: encoded),
              let string = String(data: data, encoding: .utf8) else {
            return []
        }
        return string
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private func handle(_ error: Error) {
        if case ArchiveError.cancelled = error {
            statusMessage = "操作已取消"
            return
        }

        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            errorMessage = description
        } else {
            errorMessage = error.localizedDescription
        }
        statusMessage = "操作失败"
        if mode == .compress {
            compressionStatusMessage = "压缩任务失败"
        }
    }
}
