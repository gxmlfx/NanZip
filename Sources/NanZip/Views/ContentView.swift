import NanZipCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ModeHeaderView(model: model)
                .padding(.horizontal, 18)
                .padding(.top, 12)

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
                    .padding(18)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $model.isDropTargeted,
            perform: handleDrop(providers:)
        )
        .onOpenURL { url in
            model.handleOpenURL(url)
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )
        ) {
            Button("知道了", role: .cancel) {
                model.clearError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                NanZipGlassButton {
                    if model.mode == .extract {
                        model.presentOpenPanel()
                    } else {
                        model.presentCompressionInputPanel()
                    }
                } label: {
                    Label(
                        model.mode == .extract ? "打开压缩包" : "添加文件",
                        systemImage: model.mode == .extract ? "archivebox" : "plus"
                    )
                }
                .help(model.mode == .extract ? "打开压缩包（⌘O）" : "添加文件或文件夹")
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
                } else {
                    Button {
                        model.startCompression()
                    } label: {
                        Label("开始压缩", systemImage: "arrow.up.doc")
                    }
                    .disabled(!model.canCompress)
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

private struct ModeHeaderView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NanZipGlassContainer(spacing: 10) {
            HStack(spacing: 12) {
                Picker("工作模式", selection: Binding(
                    get: { model.mode },
                    set: { model.selectMode($0) }
                )) {
                    ForEach(WorkspaceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 250)

                Text(model.mode == .extract ? "浏览、选择性解压、密码与安全检查" : "创建 ZIP、7Z、TAR 与加密 ZIP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if model.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(10)
            .nanZipGlassCard(cornerRadius: 18)
        }
    }
}

private struct ArchiveWorkspaceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            ArchiveHeaderView(model: model)
            ArchiveTableView(model: model)
            ExtractionOptionsView(model: model)
        }
        .padding(18)
    }
}

private struct ArchiveHeaderView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.orange.opacity(0.95), .red.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.archiveURL?.lastPathComponent ?? "")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 12) {
                    Label("\(model.fileCount) 个文件", systemImage: "doc.on.doc")
                    Label(Formatting.bytes(model.totalUncompressedSize), systemImage: "externaldrive")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("筛选文件", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 230)

            NanZipGlassButton {
                model.presentOpenPanel()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("打开另一个压缩包")
        }
        .padding(14)
        .nanZipGlassCard()
    }
}

private struct ArchiveTableView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if model.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("正在读取归档目录…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.filteredItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: model.searchText.isEmpty ? "doc.questionmark" : "magnifyingglass")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text(model.searchText.isEmpty ? "没有可显示的文件" : "没有匹配的文件")
                        .font(.headline)
                    if !model.searchText.isEmpty {
                        Button("清除筛选") {
                            model.searchText = ""
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.filteredItems, selection: $model.selectedIDs) {
                    TableColumn("名称") { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.isDirectory ? "folder.fill" : (item.isSymlink ? "link" : fileIcon(for: item)))
                                .foregroundStyle(item.isDirectory ? .blue : .secondary)
                                .frame(width: 16)
                            Text(item.name)
                                .lineLimit(1)
                            if !item.parentPath.isEmpty {
                                Text(item.parentPath)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .width(min: 260, ideal: 420)

                    TableColumn("大小") { item in
                        Text(item.isDirectory ? "—" : (item.isSymlink ? "符号链接" : Formatting.bytes(item.size)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 90, ideal: 110)

                    TableColumn("修改日期") { item in
                        Text(Formatting.date(item.modifiedAt))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 140, ideal: 180)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.3), lineWidth: 1)
        }
    }

    private func fileIcon(for item: ArchiveItem) -> String {
        let ext = (item.name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "gif", "webp":
            return "photo"
        case "mp4", "mov", "mkv", "avi":
            return "film"
        case "mp3", "wav", "flac", "aac":
            return "waveform"
        case "pdf":
            return "doc.richtext"
        case "txt", "md", "rtf":
            return "doc.text"
        case "swift", "py", "js", "ts", "c", "h", "cpp":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc"
        }
    }
}

private struct ExtractionOptionsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(model.destinationURL?.path ?? "请选择解压位置")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(model.destinationURL == nil ? .secondary : .primary)
                Spacer()
                Button("选择位置…") {
                    model.presentDestinationPanel()
                }
                if model.destinationURL != nil {
                    Button {
                        model.revealDestination()
                    } label: {
                        Image(systemName: "folder.badge.questionmark")
                    }
                    .buttonStyle(.borderless)
                    .help("在 Finder 中显示解压位置")
                }
            }

            HStack(spacing: 12) {
                SecureField("密码（可选）", text: $model.password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                    .onSubmit {
                        model.reloadWithPassword()
                    }

                Picker("同名文件", selection: $model.overwritePolicy) {
                    ForEach(ArchiveOverwritePolicy.allCases, id: \.self) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)

                Spacer()

                NanZipGlassContainer(spacing: 8) {
                    if model.selectedFileCount == 0 {
                        NanZipProminentButton {
                            model.extractAll()
                        } label: {
                            Label("解压全部", systemImage: "arrow.down.doc.fill")
                        }
                        .disabled(!model.canExtract)
                    } else {
                        NanZipProminentButton {
                            model.extractSelected()
                        } label: {
                            Label(model.selectionLabel, systemImage: "arrow.down.doc.fill")
                        }
                        .disabled(!model.canExtractSelected)
                    }
                }
            }

            if model.isExtracting {
                ProgressStatusView(
                    progress: model.progress,
                    currentPath: model.currentPath
                )
            }
        }
        .padding(14)
        .nanZipGlassCard()
    }
}

private struct CompressionWorkspaceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            CompressionHeaderView(model: model)
            CompressionInputsView(model: model)
            CompressionOptionsView(model: model)
        }
        .padding(18)
    }
}

private struct CompressionHeaderView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.9), .cyan.opacity(0.62)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "arrow.up.doc.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("创建压缩包")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 12) {
                    Label("\(model.compressionInputs.count) 个项目", systemImage: "doc.on.doc")
                    Label(Formatting.bytes(model.compressionTotalBytes), systemImage: "externaldrive")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            NanZipGlassButton {
                model.presentCompressionInputPanel()
            } label: {
                Label("添加", systemImage: "plus")
            }

            if !model.compressionInputs.isEmpty {
                Button("清空") {
                    model.compressionInputs.removeAll()
                    model.compressionDestinationURL = nil
                    model.compressionStatusMessage = "选择文件或文件夹后开始压缩"
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .nanZipGlassCard()
    }
}

private struct CompressionInputsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if model.compressionInputs.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "plus.rectangle.on.folder")
                        .font(.system(size: 42))
                        .foregroundStyle(.blue)
                    Text("添加文件和文件夹")
                        .font(.headline)
                    Text("拖入项目，或点击下方按钮选择。文件夹会保留自身名称。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    NanZipProminentButton {
                        model.presentCompressionInputPanel()
                    } label: {
                        Label("选择项目", systemImage: "folder.badge.plus")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.compressionInputs, id: \.self) { url in
                        HStack(spacing: 10) {
                            Image(systemName: isDirectory(url) ? "folder.fill" : "doc.fill")
                                .foregroundStyle(isDirectory(url) ? .blue : .secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                Text(url.deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                model.removeCompressionInput(url)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.borderless)
                            .help("移除")
                        }
                        .padding(.vertical, 3)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.3), lineWidth: 1)
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
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive")
                    .foregroundStyle(.secondary)
                Text(model.compressionDestinationURL?.path ?? "请选择压缩包保存位置")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(model.compressionDestinationURL == nil ? .secondary : .primary)
                Spacer()
                Button("保存到…") {
                    model.presentCompressionDestinationPanel()
                }
                if model.compressionDestinationURL != nil {
                    Button {
                        model.revealCompressionOutput()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 12) {
                Picker("格式", selection: $model.compressionFormat) {
                    ForEach(CompressionFormat.allCases, id: \.self) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 145)
                .onChange(of: model.compressionFormat) { _, _ in
                    model.refreshCompressionDestinationForFormat()
                }

                Picker("压缩级别", selection: $model.compressionLevel) {
                    ForEach(CompressionLevel.allCases, id: \.self) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)

                if model.compressionFormatSupportsEncryption {
                    SecureField("AES-256 密码", text: $model.compressionPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
                    Text("AES-256")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.1), in: Capsule())
                } else if !model.compressionPassword.isEmpty {
                    Text("该格式暂不支持密码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NanZipGlassContainer(spacing: 8) {
                    NanZipProminentButton {
                        model.startCompression()
                    } label: {
                        Label(model.isCompressing ? "正在压缩" : "开始压缩", systemImage: "archivebox.fill")
                    }
                    .disabled(!model.canCompress)
                }
            }

            if model.isCompressing {
                ProgressStatusView(
                    progress: model.compressionProgress,
                    currentPath: model.compressionCurrentPath
                )
            } else if let destination = model.compressionDestinationURL,
                      FileManager.default.fileExists(atPath: destination.path) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("已创建：\(destination.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("在 Finder 中显示") {
                        model.revealCompressionOutput()
                    }
                    .font(.caption)
                }
            }
        }
        .padding(14)
        .nanZipGlassCard()
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

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: mode == .extract
                                ? [.orange.opacity(0.22), .blue.opacity(0.12)]
                                : [.blue.opacity(0.22), .cyan.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 150, height: 150)
                    .blur(radius: 1)

                Image(systemName: mode == .extract ? "archivebox.fill" : "arrow.up.doc.fill")
                    .font(.system(size: 72, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: mode == .extract
                                ? [.orange, .red.opacity(0.75)]
                                : [.blue, .cyan.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            VStack(spacing: 8) {
                Text(mode == .extract ? "把压缩包拖到这里" : "把文件和文件夹拖到这里")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(mode == .extract
                     ? "支持 ZIP、7Z、RAR、TAR、GZ、XZ、ZST 等常见格式"
                     : "支持 ZIP、7Z、TAR.GZ、TAR.BZ2、TAR.XZ，ZIP 可加密")
                    .foregroundStyle(.secondary)
            }

            NanZipProminentButton {
                mode == .extract ? model.presentOpenPanel() : model.presentCompressionInputPanel()
            } label: {
                Label(mode == .extract ? "打开压缩包…" : "选择项目…", systemImage: mode == .extract ? "folder" : "plus")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
            }

            Text(mode == .extract
                 ? "也可以拖入一个文件夹，将它设为解压目标位置"
                 : "ZIP 加密使用 WinZip AES-256；旧版系统保持普通材质界面")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct DropOverlay: View {
    let mode: WorkspaceMode

    private var accent: Color {
        mode == .extract ? .blue : .cyan
    }

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

    private var message: String {
        model.mode == .extract ? model.statusMessage : model.compressionStatusMessage
    }

    private var detail: String? {
        if model.mode == .extract {
            return model.destinationURL?.path
        }
        return model.compressionDestinationURL?.path
    }

    var body: some View {
        HStack(spacing: 8) {
            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 340, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
