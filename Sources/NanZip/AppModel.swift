import AppKit
import Combine
import Foundation
import NanZipCore
import UniformTypeIdentifiers

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case extract
    case compress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .extract: return "解压"
        case .compress: return "压缩"
        }
    }

    var symbol: String {
        switch self {
        case .extract: return "arrow.down.doc"
        case .compress: return "arrow.up.doc"
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
    @Published var compressionDestinationURL: URL?
    @Published var isCompressing = false
    @Published var compressionProgress: Double = 0
    @Published var compressionCurrentPath = ""
    @Published var compressionStatusMessage = "选择文件或文件夹后开始压缩"

    private var loadTask: Task<Void, Never>?
    private var extractionTask: Task<Void, Never>?
    private var compressionTask: Task<Void, Never>?
    private var cancellationToken: CancellationToken?

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

    var selectionLabel: String {
        selectedFileCount > 0 ? "解压所选（\(selectedFileCount)）" : "解压所选"
    }

    var isBusy: Bool {
        isLoading || isExtracting || isCompressing || isEditingArchive
    }

    var canCompress: Bool {
        !compressionInputs.isEmpty && !isBusy
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
        } else if archiveURL == nil {
            statusMessage = "拖入压缩包或点击“打开压缩包”"
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
        }
        compressionStatusMessage = "已添加 \(compressionInputs.count) 个项目"
    }

    func removeCompressionInput(_ url: URL) {
        compressionInputs.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        if compressionInputs.isEmpty {
            compressionDestinationURL = nil
            compressionStatusMessage = "选择文件或文件夹后开始压缩"
        } else {
            compressionDestinationURL = suggestedArchiveDestination()
        }
    }

    func refreshCompressionDestinationForFormat() {
        guard !compressionInputs.isEmpty else { return }
        compressionDestinationURL = suggestedArchiveDestination()
    }

    func openArchive(_ url: URL) {
        loadTask?.cancel()
        mode = .extract
        archiveURL = url
        items = []
        selectedIDs = []
        selectedFolderPath = ""
        searchText = ""
        progress = 0
        currentPath = ""
        destinationURL = suggestedExtractionDestination(for: url)
        isLoading = true
        statusMessage = "正在读取归档目录…"

        let passphrase = password.isEmpty ? nil : password
        loadTask = Task {
            do {
                let loadedItems = try await Task.detached(priority: .userInitiated) {
                    try ArchiveService.listArchive(at: url, password: passphrase)
                }.value

                if Task.isCancelled { return }
                items = loadedItems
                isLoading = false
                statusMessage = loadedItems.isEmpty
                    ? "压缩包中没有可显示的文件"
                    : "已读取 \(fileCount) 个文件"
            } catch {
                if Task.isCancelled { return }
                isLoading = false
                items = []
                handle(error)
            }
        }
    }

    func reloadWithPassword() {
        guard let archiveURL else { return }
        openArchive(archiveURL)
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
        beginArchiveEdit(operationName: "正在添加文件…") { [password, archiveURL] token in
            try ArchiveEditingService.addFiles(
                to: archiveURL,
                fileURLs: files,
                password: password.isEmpty ? nil : password,
                cancellationToken: token
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

        beginArchiveEdit(operationName: "正在替换归档内容…") { [password, archiveURL] token in
            try ArchiveEditingService.replaceEntries(
                in: archiveURL,
                replacements: [ArchiveReplacement(archivePath: item.path, sourceURL: sourceURL)],
                password: password.isEmpty ? nil : password,
                cancellationToken: token
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
        beginArchiveEdit(operationName: "正在删除归档内容…") { [password, archiveURL] token in
            try ArchiveEditingService.deleteEntries(
                from: archiveURL,
                paths: paths,
                password: password.isEmpty ? nil : password,
                cancellationToken: token
            )
        }
    }

    func testCurrentArchive() {
        guard let archiveURL else { return }
        beginArchiveEdit(operationName: "正在测试压缩包完整性…") { [password, archiveURL] token in
            _ = token
            try ArchiveService.testArchive(at: archiveURL, password: password.isEmpty ? nil : password)
            return ArchiveEditSummary(changedEntries: 0, archiveURL: archiveURL)
        }
    }

    func startCompression() {
        guard !compressionInputs.isEmpty else { return }
        if compressionDestinationURL == nil {
            presentCompressionDestinationPanel()
            guard compressionDestinationURL != nil else { return }
        }
        guard let compressionDestinationURL else { return }

        let options = CompressionOptions(
            format: compressionFormat,
            level: compressionLevel,
            password: compressionFormatSupportsEncryption ? compressionPassword : nil
        )
        let token = CancellationToken()
        cancellationToken = token
        isCompressing = true
        compressionProgress = 0
        compressionCurrentPath = ""
        compressionStatusMessage = "正在创建 \(options.format.title) 压缩包…"

        let inputs = compressionInputs
        compressionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await Task.detached(priority: .userInitiated) {
                    try CompressionService.createArchive(
                        inputURLs: inputs,
                        destinationURL: compressionDestinationURL,
                        options: options,
                        cancellationToken: token
                    ) { update in
                        DispatchQueue.main.async {
                            self.compressionProgress = update.fraction
                            self.compressionCurrentPath = update.currentPath
                        }
                    }
                }.value

                isCompressing = false
                compressionProgress = 1
                compressionStatusMessage = "已创建 \(summary.outputURL.lastPathComponent)"
                statusMessage = compressionStatusMessage
            } catch {
                isCompressing = false
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
        statusMessage = "正在取消…"
        compressionStatusMessage = "正在取消…"
    }

    func revealDestination() {
        guard let destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    func revealCompressionOutput() {
        guard let url = compressionDestinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
        operation: @escaping @Sendable (CancellationToken) throws -> ArchiveEditSummary
    ) {
        guard let archiveURL else { return }
        let token = CancellationToken()
        cancellationToken = token
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
                selectedIDs = []
                statusMessage = summary.changedEntries > 0
                    ? "归档内容已更新（\(summary.changedEntries) 项）"
                    : "压缩包完整性测试通过"
                let preservedDestination = destinationURL
                openArchive(archiveURL)
                destinationURL = preservedDestination
            } catch {
                isEditingArchive = false
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
        guard let destinationURL else {
            presentDestinationPanel()
            return
        }

        let token = CancellationToken()
        cancellationToken = token
        isExtracting = true
        progress = 0
        currentPath = ""
        statusMessage = "正在解压 \(label)…"

        let passphrase = password.isEmpty ? nil : password
        let overwritePolicy = overwritePolicy

        extractionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await Task.detached(priority: .userInitiated) {
                    try ArchiveService.extract(
                        archiveURL: archiveURL,
                        destinationURL: destinationURL,
                        selectedPaths: selectedPaths,
                        totalBytes: totalBytes,
                        password: passphrase,
                        overwritePolicy: overwritePolicy,
                        cancellationToken: token
                    ) { update in
                        DispatchQueue.main.async {
                            self.progress = update.fraction
                            self.currentPath = update.currentPath
                        }
                    }
                }.value

                isExtracting = false
                progress = 1
                let skipped = summary.skippedEntries > 0
                    ? "，跳过 \(summary.skippedEntries) 个特殊条目"
                    : ""
                statusMessage = "已解压 \(summary.extractedFiles) 个文件\(skipped)"
            } catch {
                isExtracting = false
                if case ArchiveError.cancelled = error {
                    statusMessage = "已取消解压"
                    return
                }
                handle(error)
            }
        }
    }

    private func suggestedExtractionDestination(for archiveURL: URL) -> URL {
        let parent = archiveURL.deletingLastPathComponent()
        var name = archiveURL.lastPathComponent
        while !name.isEmpty {
            let ext = (name as NSString).pathExtension.lowercased()
            guard ArchiveService.supportedExtensions.contains(ext) else { break }
            name = (name as NSString).deletingPathExtension
        }
        if name.isEmpty { name = "解压结果" }
        return parent.appendingPathComponent(name, isDirectory: true)
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
