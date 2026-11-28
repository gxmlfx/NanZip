import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else {
            application.reply(toOpenOrPrint: .failure)
            return
        }
        let archiveExtensions = Set([
            "zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2",
            "xz", "txz", "zst", "tzst", "cab", "iso", "cpio", "lz", "lzma", "z"
        ])
        let areArchives = urls.allSatisfy {
            archiveExtensions.contains($0.pathExtension.lowercased())
        }
        post(areArchives ? .extractChoose : .compress, urls: urls)
        application.reply(toOpenOrPrint: .success)
    }

    @objc func compressFiles(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        post(.compress, urls: fileURLs(from: pasteboard))
    }

    @objc func extractHere(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        post(.extractHere, urls: fileURLs(from: pasteboard))
    }

    @objc func extractWithNanZip(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        post(.extractChoose, urls: fileURLs(from: pasteboard))
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }

    private func post(_ action: NanZipQuickAction, urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(
            name: .nanZipQuickAction,
            object: NanZipQuickActionPayload(action: action, urls: urls)
        )
    }
}
