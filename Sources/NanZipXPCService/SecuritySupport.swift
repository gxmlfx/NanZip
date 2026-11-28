import Foundation
import NanZipCore
import Security

enum XPCSecurityError: LocalizedError {
    case noCodeSignature
    case noTeamIdentifier
    case inaccessibleGrant(String)
    case unauthorizedPath(String)

    var errorDescription: String? {
        switch self {
        case .noCodeSignature:
            return "XPC 服务没有有效的代码签名。"
        case .noTeamIdentifier:
            return "XPC 服务签名缺少 Team Identifier，拒绝接受客户端。"
        case .inaccessibleGrant(let path):
            return "安全作用域授权不可用：\(path)"
        case .unauthorizedPath(let path):
            return "请求路径不在本次授权的安全作用域内：\(path)"
        }
    }
}

enum ClientIdentityValidator {
    static func requirementForCurrentService() throws -> String {
        guard let teamID = ownTeamIdentifier() else {
            throw XPCSecurityError.noTeamIdentifier
        }
        // Only the main NanZip app signed by the same team may connect.
        return "anchor apple generic and identifier \"com.gxmlfx.nanzip\" and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    private static func ownTeamIdentifier() -> String? {
        var dynamicCode: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &dynamicCode) == errSecSuccess,
              let dynamicCode else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(dynamicCode, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
              let dictionary = information as? [String: Any] else {
            return nil
        }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
