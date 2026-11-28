import Foundation

public enum XPCSharedStorage {
    public static var stagingRoot: URL {
        URL(fileURLWithPath: "/Users/Shared/NanZip/XPCStaging", isDirectory: true)
    }

    public static func prepare() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: stagingRoot.path
        )
    }

    public static func removeStaleDirectories(olderThan age: TimeInterval = 24 * 60 * 60) {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: stagingRoot,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for url in contents {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let modified = values?.contentModificationDate ?? .distantPast
            if modified < cutoff {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
