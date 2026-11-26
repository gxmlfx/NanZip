import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("NanZip")
                        .font(.title2.weight(.bold))
                    Text("原生 macOS 归档工作区")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("当前版本 0.2")
                    .font(.headline)
                Text("归档浏览、选择解压、ZIP/7Z/TAR 创建、AES-256 加密、Finder 右键菜单和 Quick Look 预览。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("界面兼容")
                    .font(.headline)
                Text("macOS 26/27 使用 Liquid Glass 渐进增强；macOS 14–25 使用原生材质与渐变回退。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("格式说明")
                    .font(.headline)
                Text("创建支持 ZIP、7Z、TAR.GZ、TAR.BZ2、TAR.XZ。加密创建当前仅对 ZIP 提供 WinZip AES-256。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(28)
    }
}
