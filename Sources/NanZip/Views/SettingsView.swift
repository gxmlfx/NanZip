import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var accounts: [String] = []
    @State private var keychainMessage = ""

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("通用", systemImage: "gearshape") }
            passwordSettings
                .tabItem { Label("密码管理器", systemImage: "key.fill") }
            aboutSettings
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .padding(18)
        .onAppear(perform: reloadAccounts)
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("归档关联")
                .font(.headline)
            Text("将 NanZip 设置为 ZIP 默认应用。macOS 会保留系统确认流程，不会静默修改关联。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("将 NanZip 设为默认 ZIP 应用") {
                model.setNanZipAsDefaultArchiveApplication()
            }

            Divider()
            Text("安全与架构")
                .font(.headline)
            Label("主应用启用 App Sandbox", systemImage: "checkmark.shield.fill")
            Label("归档引擎在独立 XPC 服务中运行", systemImage: "checkmark.shield.fill")
            Text("Finder Quick Actions 与 Finder Sync 菜单可作为系统服务入口。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
    }

    private var passwordSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Keychain 密码管理器").font(.headline)
                Spacer()
                Button("刷新") { reloadAccounts() }
            }
            Text("密码只保存在登录钥匙串；归档成功解压或测试后可选择记住。")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(accounts, id: \.self) { account in
                HStack {
                    Image(systemName: "archivebox")
                        .foregroundStyle(.secondary)
                    Text((account as NSString).lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Button(role: .destructive) {
                        try? PasswordStore.deleteAccount(account)
                        reloadAccounts()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .overlay {
                if accounts.isEmpty {
                    Text("尚未保存归档密码")
                        .foregroundStyle(.secondary)
                }
            }

            if !keychainMessage.isEmpty {
                Text(keychainMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var aboutSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("NanZip 0.5").font(.title2.weight(.bold))
                    Text("原生 macOS 归档工作区").foregroundStyle(.secondary)
                }
            }
            Text("ZIP、7Z、TAR.GZ、TAR.BZ2、TAR.XZ 创建与浏览；分卷、加密、智能解压、归档内预览、嵌套浏览、批量处理和 ZIP 修复。")
                .fixedSize(horizontal: false, vertical: true)
            Text("macOS 26/27 使用 Liquid Glass 渐进增强；macOS 14–25 保留原生材质回退。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(16)
    }

    private func reloadAccounts() {
        accounts = PasswordStore.allArchiveAccounts()
        keychainMessage = accounts.isEmpty ? "" : "已保存 \(accounts.count) 个归档密码"
    }
}
