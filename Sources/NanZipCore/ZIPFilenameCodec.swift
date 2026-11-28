import Foundation

public struct ArchiveNameMapping: Sendable {
    public let rawPath: String
    public let displayPath: String
    public let isDirectory: Bool

    public init(rawPath: String, displayPath: String, isDirectory: Bool) {
        self.rawPath = rawPath
        self.displayPath = displayPath
        self.isDirectory = isDirectory
    }
}

enum ZIPFilenameCodec {
    static func decodedEntryNames(
        from data: Data,
        encoding: ArchiveFilenameEncoding
    ) -> [String] {
        let signature = Data([0x50, 0x4B, 0x01, 0x02])
        var names: [String] = []
        var searchStart = data.startIndex

        while searchStart < data.endIndex,
              let headerRange = data.range(
                of: signature,
                options: [],
                in: searchStart..<data.endIndex
              ) {
            let offset = headerRange.lowerBound
            guard offset + 46 <= data.endIndex else { break }
            let flags = readUInt16(data, offset + 8)
            let nameLength = Int(readUInt16(data, offset + 28))
            let extraLength = Int(readUInt16(data, offset + 30))
            let commentLength = Int(readUInt16(data, offset + 32))
            let nameStart = offset + 46
            guard nameStart + nameLength <= data.endIndex else { break }
            let bytes = data.subdata(in: nameStart..<(nameStart + nameLength))
            names.append(decode(bytes, flags: flags, encoding: encoding))
            searchStart = min(
                data.endIndex,
                nameStart + nameLength + extraLength + commentLength
            )
        }
        return names
    }

    static func mappings(
        rawItems: [ArchiveItem],
        archiveData: Data,
        encoding: ArchiveFilenameEncoding
    ) -> [ArchiveNameMapping] {
        let decoded = decodedEntryNames(from: archiveData, encoding: encoding)
        guard decoded.count == rawItems.count else {
            return rawItems.map {
                ArchiveNameMapping(
                    rawPath: $0.path,
                    displayPath: $0.path,
                    isDirectory: $0.isDirectory
                )
            }
        }
        return zip(rawItems, decoded).map { item, path in
            ArchiveNameMapping(
                rawPath: item.path,
                displayPath: path.replacingOccurrences(of: "\\", with: "/"),
                isDirectory: item.isDirectory
            )
        }
    }

    private static func decode(
        _ data: Data,
        flags: UInt16,
        encoding: ArchiveFilenameEncoding
    ) -> String {
        if flags & 0x0800 != 0, let value = String(data: data, encoding: .utf8) {
            return value
        }
        switch encoding {
        case .automatic:
            if let value = String(data: data, encoding: .utf8) {
                return value
            }
            if let value = String(data: data, encoding: cp437Encoding) {
                return value
            }
        case .utf8:
            if let value = String(data: data, encoding: .utf8) { return value }
        case .cp437, .cp936, .cp932:
            if let stringEncoding = encoding.stringEncoding,
               let value = String(data: data, encoding: stringEncoding) {
                return value
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static var cp437Encoding: String.Encoding {
        String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)
            )
        )
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }
}
