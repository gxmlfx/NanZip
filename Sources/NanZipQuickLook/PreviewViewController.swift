import AppKit
import NanZipCore
import Quartz
import QuickLookUI
import SwiftUI

final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView()
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let items = try ArchiveService.listArchive(at: url, password: nil)
                DispatchQueue.main.async {
                    self.installPreview(url: url, items: items)
                    handler(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    self.installError(error)
                    handler(error)
                }
            }
        }
    }

    private func installPreview(url: URL, items: [ArchiveItem]) {
        let rootView = QuickLookArchiveView(archiveURL: url, items: items)
        let hostingController = NSHostingController(rootView: rootView)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func installError(_ error: Error) {
        let view = QuickLookErrorView(message: error.localizedDescription)
        let hostingController = NSHostingController(rootView: view)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
    }
}

private struct QuickLookArchiveView: View {
    let archiveURL: URL
    let items: [ArchiveItem]

    private var fileCount: Int {
        items.filter { !$0.isDirectory }.count
    }

    private var totalSize: Int64 {
        items.reduce(0) { $0 + ($1.isDirectory ? 0 : $1.size) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(archiveURL.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(fileCount) 个文件 · \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(.regularMaterial)

            Divider()

            Table(items) {
                TableColumn("名称") { item in
                    Text(item.path)
                        .lineLimit(1)
                }
                .width(min: 260, ideal: 420)
                TableColumn("原始大小") { item in
                    Text(item.isDirectory ? "—" : (item.isSymlink ? "符号链接" : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .width(min: 80, ideal: 100)
                TableColumn("压缩后") { item in
                    Text(item.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: item.compressedSize, countStyle: .file))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .width(min: 80, ideal: 100)
                TableColumn("方法") { item in
                    Text(item.isDirectory || item.method.isEmpty ? "—" : item.method)
                        .foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 90)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
        .frame(minWidth: 720, minHeight: 500)
    }
}

private struct QuickLookErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.orange)
            Text("无法预览压缩包")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(32)
        .frame(minWidth: 560, minHeight: 320)
    }
}
