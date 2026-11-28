import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    private let archiveExtensions: Set<String> = [
        "zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2",
        "xz", "txz", "zst", "tzst", "cab", "iso", "cpio", "001"
    ]

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/", isDirectory: true)
        ]
        NSLog("NanZipFinder initialized")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        NSLog("NanZipFinder menu requested, kind=\(menuKind.rawValue)")
        let selectedURLs = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard !selectedURLs.isEmpty else { return nil }

        let menu = NSMenu(title: "NanZip")
        let parentItem = NSMenuItem(title: "NanZip", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "NanZip")

        let compressItem = NSMenuItem(
            title: selectedURLs.count == 1 ? "压缩" : "压缩所选项目",
            action: #selector(compressSelection(_:)),
            keyEquivalent: ""
        )
        compressItem.target = self
        submenu.addItem(compressItem)

        if selectedURLs.count == 1,
           archiveExtensions.contains(selectedURLs[0].pathExtension.lowercased()) {
            submenu.addItem(menuItem(title: "智能解压", action: #selector(smartExtractSelection(_:))))
            submenu.addItem(menuItem(title: "解压到当前目录", action: #selector(extractHereSelection(_:))))
            submenu.addItem(menuItem(title: "解压到指定文件夹…", action: #selector(extractChooseSelection(_:))))
            submenu.addItem(.separator())
            submenu.addItem(menuItem(title: "在 NanZip 中打开", action: #selector(extractSelection(_:))))
        }

        parentItem.submenu = submenu
        menu.addItem(parentItem)
        return menu
    }

    @objc private func compressSelection(_ sender: Any?) {
        openMainApp(host: "compress", urls: FIFinderSyncController.default().selectedItemURLs() ?? [])
    }

    @objc private func extractSelection(_ sender: Any?) {
        openMainApp(host: "extract", urls: FIFinderSyncController.default().selectedItemURLs() ?? [])
    }

    @objc private func smartExtractSelection(_ sender: Any?) {
        openMainApp(host: "smart-extract", urls: FIFinderSyncController.default().selectedItemURLs() ?? [])
    }

    @objc private func extractHereSelection(_ sender: Any?) {
        openMainApp(host: "extract-here", urls: FIFinderSyncController.default().selectedItemURLs() ?? [])
    }

    @objc private func extractChooseSelection(_ sender: Any?) {
        openMainApp(host: "extract-choose", urls: FIFinderSyncController.default().selectedItemURLs() ?? [])
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func openMainApp(host: String, urls: [URL]) {
        guard !urls.isEmpty else { return }
        let payload = urls.map(\.path).joined(separator: "\n")
        let encoded = Data(payload.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var components = URLComponents()
        components.scheme = "nanzip"
        components.host = host
        components.queryItems = [URLQueryItem(name: "paths", value: encoded)]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }
}
