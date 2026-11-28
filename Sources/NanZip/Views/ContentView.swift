import NanZipCore
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeaderView(model: model)
                .padding(.horizontal, 14)
                .padding(.top, 10)

            Group {
                switch model.mode {
                case .extract:
                    if model.archiveURL == nil {
                        EmptyDropView(model: model, mode: .extract)
                    } else {
                        ArchiveWorkspaceView(model: model)
                    }
                case .compress:
                    CompressionWorkspaceView(model: model)
                case .batch:
                    BatchWorkspaceView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            StatusBarView(model: model)
        }
        .background {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .overlay {
            if model.isDropTargeted {
                DropOverlay(mode: model.mode)
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $model.isDropTargeted,
            perform: handleDrop(providers:)
        )
        .onOpenURL { model.handleOpenURL($0) }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )
        ) {
            Button("知道了", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                NanZipGlassButton {
                    if model.mode == .extract {
                        model.presentOpenPanel()
                    } else if model.mode == .compress {
                        model.presentCompressionInputPanel()
                    } else {
                        model.presentBatchInputPanel()
                    }
                } label: {
                    Label(
                        model.mode == .extract
                            ? "打开压缩包"
                            : (model.mode == .compress ? "添加文件" : "添加任务"),
                        systemImage: model.mode == .extract ? "archivebox" : "plus"
                    )
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if model.isBusy {
                    Button(role: .destructive) {
                        model.cancelCurrentOperation()
                    } label: {
                        Label("取消", systemImage: "stop.circle")
                    }
                } else if model.mode == .extract {
                    Button {
                        model.extractAll()
                    } label: {
                        Label("解压全部", systemImage: "arrow.down.doc")
                    }
                    .disabled(!model.canExtract)
                } else if model.mode == .compress {
                    Button {
                        model.startCompression()
                    } label: {
                        Label("开始压缩", systemImage: "archivebox")
                    }
                    .disabled(!model.canCompress)
                } else {
                    Button {
                        model.startBatch()
                    } label: {
                        Label("开始批量处理", systemImage: "play.fill")
                    }
                    .disabled(!model.canRunBatch)
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                if let url = object {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            model.handleDroppedURLs(urls)
        }
        return true
    }
}

private struct WorkspaceHeaderView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NanZipGlassContainer(spacing: 10) {
            HStack(spacing: 12) {
                Picker("工作模式", selection: Binding(
                    get: { model.mode },
                    set: { model.selectMode($0) }
                )) {
                    ForEach(WorkspaceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 230)

                Text(
                    model.mode == .extract
                        ? "归档浏览 · 智能解压 · 预览 · 修复"
                        : (model.mode == .compress
                            ? "新建压缩包 · 分卷 · AES 加密 · 多线程 7-Zip"
                            : "批量压缩/解压 · 高级覆盖规则 · 独立 XPC 服务")
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if model.isBusy {
                    ProgressView().controlSize(.small)
                }

                Text("7-Zip")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.09), in: Capsule())
            }
            .padding(8)
            .nanZipGlassCard(cornerRadius: 16)
        }
    }
}

private struct ArchiveWorkspaceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ArchiveActionBar(model: model)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            HStack(spacing: 0) {
                HSplitView {
                    ArchiveSidebarView(model: model)
                        .frame(minWidth: 170, idealWidth: 205, maxWidth: 280)

                    VStack(spacing: 0) {
                        ArchivePathBar(model: model)
                        ArchiveTableView(model: model)
                    }
                    .frame(minWidth: 560)
                }

                if model.previewItem != nil {
                    Divider()
                    ArchivePreviewInspector(model: model)
                        .frame(minWidth: 280, idealWidth: 330, maxWidth: 420)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            ExtractionOptionsView(model: model)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
        .padding(.top, 8)
    }
}

private struct ArchiveActionBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NanZipGlassContainer(spacing: 2) {
            HStack(spacing: 2) {
                BandizipActionButton(title: "打开", systemImage: "folder") {
                    model.presentOpenPanel()
                }
                BandizipActionButton(title: "解压", systemImage: "arrow.down.doc") {
                    if model.selectedFileCount > 0 { model.extractSelected() } else { model.extractAll() }
                }
                .disabled(!model.canExtract)
                BandizipActionButton(title: "新建", systemImage: "doc.badge.plus") {
                    model.selectMode(.compress)
                }
                Divider().frame(height: 38).padding(.horizontal, 5)
                BandizipActionButton(title: "添加", systemImage: "plus.square.on.square") {
                    model.presentAddFilesPanel()
                }
                .disabled(!model.canAddToArchive)
                BandizipActionButton(title: "替换", systemImage: "arrow.triangle.2.circlepath") {
                    model.presentReplaceFilePanel()
                }
                .disabled(!model.canReplaceSelected)
                BandizipActionButton(title: "删除", systemImage: "trash") {
                    model.deleteSelectedEntries()
                }
                .disabled(!model.canDeleteSelected)
                Divider().frame(height: 38).padding(.horizontal, 5)
                BandizipActionButton(title: "测试", systemImage: "checkmark.shield") {
                    model.testCurrentArchive()
                }
                .disabled(!model.canTestArchive)

                Menu {
                    Button("智能解压") { model.extractSmart() }
                        .disabled(!model.canExtract)
                    Button("解压到当前目录") { model.extractHere() }
                        .disabled(!model.canExtract)
                    Button("解压到指定文件夹…") { model.extractToChosenFolder() }
                        .disabled(!model.canExtract)
                    Divider()
                    Button("预览所选文件") {
                        if let item = model.selectedItems.first { model.beginPreview(item) }
                    }
                    .disabled(!model.canPreviewSelected)
                    Button("浏览嵌套归档") { model.openNestedArchive() }
                        .disabled(!model.canOpenNestedArchive)
                    Divider()
                    Button("修复 ZIP 副本…") { model.presentRepairPanel() }
                        .disabled(model.archiveURL?.pathExtension.lowercased() != "zip" || model.isBusy)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 21, weight: .medium))
                            .frame(height: 24)
                        Text("更多")
                            .font(.caption)
                    }
                    .frame(width: 62, height: 54)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 62, height: 54)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .nanZipGlassCard(cornerRadius: 14)
        }
    }
}

private struct BandizipActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .medium))
                    .frame(height: 24)
                Text(title)
                    .font(.caption)
            }
            .frame(width: 62, height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

private struct ArchiveSidebarView: View {
    @ObservedObject var model: AppModel

    private var nodes: [ArchiveFolderNode] {
        ArchiveFolderNode.makeTree(from: model.items)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("归档")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

            List(selection: Binding(
                get: { model.selectedFolderPath },
                set: {
                    model.selectedFolderPath = $0 ?? ""
                    model.selectedIDs = []
                }
            )) {
                Label(model.archiveURL?.lastPathComponent ?? "压缩包", systemImage: "archivebox.fill")
                    .tag("")
                OutlineGroup(nodes, children: \.children) { node in
                    Label(node.name, systemImage: "folder.fill")
                        .tag(node.path)
                }
            }
            .listStyle(.sidebar)
        }
        .background(.regularMaterial.opacity(0.55))
    }
}

private struct ArchivePathBar: View {
    @ObservedObject var model: AppModel

    private var breadcrumb: String {
        if let nested = model.currentNestedBreadcrumbTitle {
            return "嵌套归档 / \(nested)"
        }
        if model.selectedFolderPath.isEmpty {
            return model.archiveURL?.lastPathComponent ?? "归档"
        }
        return model.selectedFolderPath
    }

    var body: some View {
        HStack(spacing: 10) {
            if model.canNavigateBack {
                Button {
                    model.navigateBackFromNestedArchive()
                } label: {
                    Label("返回", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
            }
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(breadcrumb)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            TextField("搜索归档", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

private struct ArchiveTableView: View {
    @ObservedObject var model: AppModel
    @State private var columnCustomization = TableColumnCustomization<ArchiveItem>()
    @AppStorage("nanzip.archive.columnCustomization.data") private var columnCustomizationData = Data()

    var body: some View {
        Group {
            if model.isLoading {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("正在读取归档目录…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.filteredItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: model.searchText.isEmpty ? "folder" : "magnifyingglass")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text(model.searchText.isEmpty ? "此文件夹为空" : "没有匹配的文件")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(
                    model.filteredItems,
                    selection: $model.selectedIDs,
                    columnCustomization: $columnCustomization
                ) {
                    TableColumn("名称") { (item: ArchiveItem) in
                        Label {
                            Text(item.name).lineLimit(1)
                        } icon: {
                            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(for: item))
                                .foregroundStyle(item.isDirectory ? .blue : .secondary)
                        }
                    }
                    .width(min: 200, ideal: 230)
                    .customizationID("name")

                    TableColumn("原始大小") { item in
                        Text(item.isDirectory ? "—" : Formatting.bytes(item.size))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 65, ideal: 72)
                    .customizationID("originalSize")

                    TableColumn("压缩后") { item in
                        Text(item.isDirectory ? "—" : Formatting.bytes(item.compressedSize))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 65, ideal: 72)
                    .customizationID("packedSize")

                    TableColumn("压缩率") { item in
                        Text(ratioText(item))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 50, ideal: 55)
                    .customizationID("ratio")

                    TableColumn("修改日期") { item in
                        Text(Formatting.date(item.modifiedAt))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 100, ideal: 120)
                    .customizationID("modified")

                    TableColumn("方法") { item in
                        Text(item.isDirectory ? "—" : (item.method.isEmpty ? "—" : item.method))
                            .foregroundStyle(.tertiary)
                    }
                    .width(min: 55, ideal: 65)
                    .customizationID("method")
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .contextMenu(forSelectionType: ArchiveItem.ID.self) { ids in
                    if ids.count == 1,
                       let item = model.items.first(where: { ids.contains($0.id) }) {
                        Button("预览") { model.beginPreview(item) }
                            .disabled(item.isDirectory)
                        Button("打开嵌套归档") { model.openNestedArchive() }
                            .disabled(!ArchiveService.supportedExtensions.contains(
                                (item.name as NSString).pathExtension.lowercased()
                            ))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.opacity(0.76))
        .onChange(of: model.selectedIDs) { _, _ in
            model.updatePreviewForSelection()
        }
        .onAppear(perform: restoreColumnCustomization)
        .onChange(of: columnCustomization) { _, customization in
            if let data = try? JSONEncoder().encode(customization) {
                columnCustomizationData = data
            }
        }
    }

    private func restoreColumnCustomization() {
        guard !columnCustomizationData.isEmpty,
              let customization = try? JSONDecoder().decode(
                TableColumnCustomization<ArchiveItem>.self,
                from: columnCustomizationData
              ) else { return }
        columnCustomization = customization
    }

    private func ratioText(_ item: ArchiveItem) -> String {
        guard !item.isDirectory, let ratio = item.compressionRatio else { return "—" }
        return String(format: "%.0f%%", ratio * 100)
    }

    private func fileIcon(for item: ArchiveItem) -> String {
        switch (item.name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return "photo"
        case "mp4", "mov", "mkv", "avi": return "film"
        case "mp3", "wav", "flac", "aac": return "waveform"
        case "pdf": return "doc.richtext"
        case "txt", "md", "rtf": return "doc.text"
        case "swift", "py", "js", "ts", "c", "h", "cpp": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}

private struct ArchivePreviewInspector: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("快速预览").font(.headline)
                    Text(model.previewItem?.name ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button {
                    model.revealPreviewFile()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .disabled(model.previewURL == nil)
                Button {
                    model.clearPreview()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(12)
            Divider()

            if model.isPreviewing {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.large)
                    Text("仅提取当前条目…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.previewError {
                ContentUnavailableView(
                    "无法预览",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if let item = model.previewItem,
                      ArchiveService.supportedExtensions.contains(
                        (item.name as NSString).pathExtension.lowercased()
                      ) {
                ContentUnavailableView {
                    Label("嵌套归档", systemImage: "archivebox")
                } description: {
                    Text("使用 NanZip 的内置归档浏览器打开，不交给第三方预览扩展。")
                } actions: {
                    Button("直接浏览") { model.openNestedArchive() }
                }
            } else if let previewURL = model.previewURL {
                QuickLookPreviewView(url: previewURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "选择一个文件",
                    systemImage: "eye",
                    description: Text("图片、文档、PDF、音视频等将在这里显示。")
                )
            }
        }
        .background(.regularMaterial.opacity(0.78))
    }
}

private struct QuickLookPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
    }
}

private struct ExtractionOptionsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(model.destinationURL?.path ?? "请选择解压位置")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(model.destinationURL == nil ? .secondary : .primary)
                Spacer()
                Button("选择位置…") { model.presentDestinationPanel() }
                if model.destinationURL != nil {
                    Button { model.revealDestination() } label: {
                        Image(systemName: "folder.badge.questionmark")
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 12) {
                SecureField("密码（可选）", text: $model.password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit { model.reloadWithPassword() }
                Toggle("记住密码", isOn: $model.rememberPassword)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Picker("解压规则", selection: $model.extractionPolicy) {
                    ForEach(ExtractionDestinationPolicy.allCases, id: \.self) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                Picker("文件名编码", selection: $model.compressionFilenameEncoding) {
                    ForEach(ArchiveFilenameEncoding.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
                .onChange(of: model.compressionFilenameEncoding) { _, _ in
                    model.reloadWithPassword()
                }
                Picker("同名文件", selection: $model.overwritePolicy) {
                    ForEach(ArchiveOverwritePolicy.allCases, id: \.self) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
                Spacer()
                NanZipProminentButton {
                    if model.selectedFileCount > 0 { model.extractSelected() } else { model.extractAll() }
                } label: {
                    Label(model.selectedFileCount > 0 ? model.selectionLabel : "解压全部", systemImage: "arrow.down.doc.fill")
                }
                .disabled(model.selectedFileCount > 0 ? !model.canExtractSelected : !model.canExtract)
            }

            if model.isExtracting {
                ProgressStatusView(progress: model.progress, currentPath: model.currentPath)
            }
        }
        .padding(12)
        .nanZipGlassCard(cornerRadius: 14)
    }
}

private struct CompressionWorkspaceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("新建压缩包").font(.title2.weight(.semibold))
                    Text("添加文件后设置格式、压缩级别和密码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.compressionDestinationURL?.path ?? "未选择保存位置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            VStack(spacing: 10) {
                CompressionInputsView(model: model)
                CompressionOptionsView(model: model)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
        .padding(.top, 8)
    }
}

private struct CompressionInputsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("添加到压缩包").font(.headline)
                Spacer()
                Button("添加…") { model.presentCompressionInputPanel() }
                Button("清空") {
                    model.compressionInputs.removeAll()
                    model.compressionDestinationURL = nil
                    model.compressionStatusMessage = "选择文件或文件夹后开始压缩"
                }
                .disabled(model.compressionInputs.isEmpty)
            }
            .padding(10)
            Divider()

            if model.compressionInputs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "plus.rectangle.on.folder")
                        .font(.system(size: 34))
                        .foregroundStyle(.blue)
                    Text("拖入文件或文件夹").font(.headline)
                    Text("文件夹会保留自身名称").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                List {
                    ForEach(model.compressionInputs, id: \.self) { url in
                        HStack(spacing: 9) {
                            Image(systemName: isDirectory(url) ? "folder.fill" : "doc.fill")
                                .foregroundStyle(isDirectory(url) ? .blue : .secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent).lineLimit(1)
                                Text(url.deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button { model.removeCompressionInput(url) } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .frame(minHeight: 150)
                .scrollContentBackground(.hidden)
            }
        }
        .background(.background.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.32), lineWidth: 1)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var value: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &value) && value.boolValue
    }
}

private struct CompressionOptionsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                GridRow {
                    Text("文件名")
                    HStack {
                        Text(model.compressionDestinationURL?.path ?? "请选择保存位置")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("浏览…") { model.presentCompressionDestinationPanel() }
                    }
                }
                GridRow {
                    Text("压缩格式")
                    Picker("压缩格式", selection: $model.compressionFormat) {
                        ForEach(CompressionFormat.allCases, id: \.self) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 150)
                    .onChange(of: model.compressionFormat) { _, _ in
                        model.refreshCompressionDestinationForFormat()
                    }
                }
                GridRow {
                    Text("压缩级别")
                    Picker("压缩级别", selection: $model.compressionLevel) {
                        ForEach(CompressionLevel.allCases, id: \.self) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
                GridRow {
                    Text("密码")
                    HStack {
                        SecureField("可选密码", text: $model.compressionPassword)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .disabled(!model.compressionFormatSupportsEncryption)
                        if model.compressionFormatSupportsEncryption {
                            Text("AES")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.blue.opacity(0.1), in: Capsule())
                        } else {
                            Text("该格式不支持密码").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                GridRow {
                    Text("分卷")
                    HStack {
                        Picker("分卷大小", selection: $model.compressionVolumeChoice) {
                            ForEach(CompressionVolumeChoice.allCases) { choice in
                                Text(choice.title).tag(choice)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 150)
                        Text("生成 .001、.002… 分卷")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("文件名编码")
                    Picker("文件名编码", selection: $model.compressionFilenameEncoding) {
                        ForEach(ArchiveFilenameEncoding.allCases, id: \.self) { encoding in
                            Text(encoding.title).tag(encoding)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }
                GridRow {
                    Text("完整性")
                    Label("创建后自动测试压缩包", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                if model.isCompressing {
                    ProgressStatusView(progress: model.compressionProgress, currentPath: model.compressionCurrentPath)
                } else {
                    Text(model.compressionStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { model.selectMode(.extract) }
                    .disabled(model.isCompressing)
                NanZipProminentButton {
                    model.startCompression()
                } label: {
                    Label("开始", systemImage: "archivebox.fill")
                }
                .disabled(!model.canCompress)
            }
        }
        .padding(12)
        .nanZipGlassCard(cornerRadius: 14)
    }
}

private struct BatchWorkspaceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("批量任务").font(.title2.weight(.semibold))
                    Text("按顺序调用独立 XPC 服务，单项失败不会中断队列")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("批量模式", selection: $model.batchMode) {
                    ForEach(BatchOperationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                .onChange(of: model.batchMode) { _, _ in
                    model.clearBatchQueue()
                }
            }

            HStack(spacing: 14) {
                Label(
                    model.batchOutputDirectory?.path ?? "输出到各文件所在目录",
                    systemImage: "folder"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                Button("选择输出目录…") { model.presentBatchOutputPanel() }

                if model.batchMode == .extract {
                    Picker("解压规则", selection: $model.extractionPolicy) {
                        ForEach(ExtractionDestinationPolicy.allCases, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 170)
                } else {
                    Picker("格式", selection: $model.compressionFormat) {
                        ForEach(CompressionFormat.allCases, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    Picker("分卷", selection: $model.compressionVolumeChoice) {
                        ForEach(CompressionVolumeChoice.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                }
                Picker("同名文件", selection: $model.overwritePolicy) {
                    ForEach(ArchiveOverwritePolicy.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)
                Spacer()
                Button("添加任务…") { model.presentBatchInputPanel() }
            }

            VStack(spacing: 0) {
                HStack {
                    Text("任务队列").font(.headline)
                    Spacer()
                    Text("\(model.batchItems.count) 项")
                        .foregroundStyle(.secondary)
                    Button("清空") { model.clearBatchQueue() }
                        .disabled(model.batchItems.isEmpty || model.isBatchRunning)
                }
                .padding(10)
                Divider()

                if model.batchItems.isEmpty {
                    ContentUnavailableView(
                        model.batchMode == .extract ? "添加多个压缩包" : "添加多个文件或文件夹",
                        systemImage: "square.stack.3d.up",
                        description: Text("每个任务会生成独立结果，并逐项显示成功或失败原因。")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(model.batchItems) { item in
                            HStack(spacing: 10) {
                                Image(systemName: item.state.symbol)
                                    .foregroundStyle(color(for: item.state))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.url.lastPathComponent).lineLimit(1)
                                    Text(item.state.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button {
                                    model.batchItems.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.borderless)
                                .disabled(model.isBatchRunning)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .background(.background.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.separator.opacity(0.32), lineWidth: 1)
            }

            HStack {
                if model.isBatchRunning {
                    ProgressView(value: model.batchProgress)
                        .frame(maxWidth: 300)
                }
                Text(model.batchStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if model.isBatchRunning {
                    Button("取消") { model.cancelCurrentOperation() }
                }
                NanZipProminentButton {
                    model.startBatch()
                } label: {
                    Label("开始批量处理", systemImage: "play.fill")
                }
                .disabled(!model.canRunBatch)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func color(for state: BatchItemState) -> Color {
        switch state {
        case .waiting: return .secondary
        case .running: return .blue
        case .success: return .green
        case .failed: return .red
        }
    }
}

private struct ProgressStatusView: View {
    let progress: Double
    let currentPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress)
            HStack {
                Text(currentPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct EmptyDropView: View {
    @ObservedObject var model: AppModel
    let mode: WorkspaceMode

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            HStack(spacing: 18) {
                EmptyActionTile(
                    title: "打开压缩包",
                    subtitle: "浏览、解压或编辑已有归档",
                    systemImage: "archivebox.fill",
                    color: .blue
                ) {
                    model.presentOpenPanel()
                }
                EmptyActionTile(
                    title: "新建压缩包",
                    subtitle: "ZIP、7Z、TAR，多线程压缩",
                    systemImage: "doc.badge.plus",
                    color: .orange
                ) {
                    model.selectMode(.compress)
                }
            }
            Text("也可以把文件拖入窗口")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(30)
    }
}

private struct EmptyActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(color)
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 230, height: 150)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .nanZipGlassCard(cornerRadius: 18)
    }
}

private struct DropOverlay: View {
    let mode: WorkspaceMode

    private var accent: Color { mode == .extract ? .blue : .cyan }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Group {
            if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(accent.opacity(0.18)).interactive(), in: shape)
                    .overlay {
                        shape.strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [10, 7]))
                    }
            } else {
                shape
                    .fill(accent.opacity(0.08))
                    .overlay {
                        shape.strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [10, 7]))
                    }
            }
        }
        .overlay {
            VStack(spacing: 10) {
                Image(systemName: mode == .extract ? "arrow.down.doc.fill" : "arrow.up.doc.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(accent)
                Text(mode == .extract ? "松开以打开压缩包" : "松开以添加项目")
                    .font(.headline)
                    .foregroundStyle(accent)
            }
        }
    }
}

private struct StatusBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            if model.isBusy {
                ProgressView().controlSize(.small)
            }

            if model.mode == .extract, model.archiveURL != nil {
                Text("\(model.selectedItems.count) 项已选")
                if !model.selectedItems.isEmpty {
                    Text("原始 \(Formatting.bytes(model.selectedUncompressedTotal))")
                    Text("压缩后 \(Formatting.bytes(model.selectedCompressedTotal))")
                } else {
                    Text("文件 \(model.fileCount)")
                    Text("原始 \(Formatting.bytes(model.totalUncompressedSize))")
                }
                Text("归档 \(Formatting.bytes(model.archiveFileSize))")
                Spacer()
                Text(model.statusMessage)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if model.mode == .compress {
                Text(model.compressionStatusMessage)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(model.compressionDestinationURL?.path ?? "未选择保存位置")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(model.statusMessage)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

private struct ArchiveFolderNode: Identifiable {
    let id: String
    let path: String
    let name: String
    let children: [ArchiveFolderNode]?

    static func makeTree(from items: [ArchiveItem]) -> [ArchiveFolderNode] {
        var paths = Set<String>()
        for item in items {
            let components = item.path.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            let directoryComponents = item.isDirectory ? components : Array(components.dropLast())
            for index in 1...max(1, directoryComponents.count) where index <= directoryComponents.count {
                paths.insert(directoryComponents.prefix(index).joined(separator: "/"))
            }
        }

        func parentPath(of path: String) -> String {
            let components = path.split(separator: "/")
            guard components.count > 1 else { return "" }
            return components.dropLast().joined(separator: "/")
        }

        func children(of parent: String) -> [ArchiveFolderNode] {
            paths
                .filter { parentPath(of: $0) == parent }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { path in
                    let nested = children(of: path)
                    return ArchiveFolderNode(
                        id: path,
                        path: path,
                        name: path.split(separator: "/").last.map(String.init) ?? path,
                        children: nested.isEmpty ? nil : nested
                    )
                }
        }
        return children(of: "")
    }
}
