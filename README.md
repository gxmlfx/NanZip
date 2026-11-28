# NanZip

NanZip 是一个使用 SwiftUI、内置开源 7-Zip 引擎和独立 XPC 归档服务构建的原生 macOS 归档工具。界面以 Bandizip 的公开截图和 macOS 原生交互为参考，同时保留 macOS 14+ 兼容性。

GitHub: https://github.com/<GITHUB_OWNER>/NanZip

## 功能

- 浏览 ZIP、7Z、RAR、TAR、GZ、BZ2、XZ、ZST 等归档，并支持 `.001` 分卷入口
- 解压全部或所选文件，支持智能解压、当前位置、同名文件夹和指定文件夹
- 覆盖、跳过、保留两者、仅覆盖较旧文件和每次询问
- 创建 ZIP、7Z、TAR、TAR.GZ、TAR.BZ2、TAR.XZ
- ZIP/7Z 密码加密与分卷创建，支持 10/50/100/500 MB 分卷
- ZIP 文件名编码选择：自动、UTF-8、CP437、CP936/GBK、CP932/Shift-JIS
- 添加、替换、删除归档内条目和完整性测试
- 归档内表格原生列宽、列顺序和显隐自定义，并通过 `AppStorage` 保存
- 归档内图片、文本、文档、PDF、音视频 Quick Look 预览；仅按需提取当前文件
- 嵌套归档直接浏览与返回导航
- Keychain 密码管理器
- 未加密 ZIP 的本地文件头修复副本
- 批量压缩/解压队列、逐项状态和高级覆盖规则
- Finder Sync 菜单、Finder Quick Actions、ZIP 默认应用设置入口
- 主应用 App Sandbox；归档操作由独立签名的 XPC 服务执行
- 路径穿越防护
- macOS 26/27 Liquid Glass 界面，macOS 14–25 材质回退

## 安全架构

主应用启用 App Sandbox，并仅声明用户选择文件的读写权限。归档列表、提取、压缩、编辑、预览、修复和测试通过嵌入的 `NanZipXPCService.xpc` 执行；主应用不直接启动归档引擎。

当前 XPC 服务为独立签名的非 App Store 架构，服务进程本身未启用 App Sandbox。若目标是 Mac App Store，仍需实现安全作用域书签或等价文件访问传递，并对 XPC 服务启用沙盒。该限制不影响 Developer ID/直接分发场景，但发布前必须明确。

## 构建

```sh
cd "$HOME/Projects/NanZip"
./Scripts/fetch-7zz.sh
NANZIP_SIGN_IDENTITY="<APPLE_DEVELOPMENT_IDENTITY>" ./Scripts/build-app.sh
```

可选安装到指定位置：

```sh
NANZIP_SIGN_IDENTITY="<APPLE_DEVELOPMENT_IDENTITY>" \
NANZIP_INSTALL_APP="$HOME/Applications/NanZip.app" \
./Scripts/build-app.sh
```

构建产物：

- 本地：`build/NanZip.app`
- 安装位置：`$NANZIP_INSTALL_APP`

## 目录结构

- `Sources/NanZip`: SwiftUI 主应用、设置页、Quick Actions、XPC 客户端
- `Sources/NanZipCore`: 归档、压缩、编码、预览、ZIP 修复和共享协议
- `Sources/NanZipXPCService`: 独立 XPC 归档服务
- `Sources/NanZipFinder`: Finder Sync 扩展
- `Sources/NanZipQuickLook`: Quick Look 扩展
- 运行时内置 `7zz` 开源引擎

## 文档

- `docs/PROJECT_STATE.md`
- `docs/DEVELOPMENT_LOG.md`
- `docs/CONTEXT_HANDOFF.md`
- `docs/ROADMAP.md`
- `docs/UPSTREAM_RESEARCH.md`
- `docs/TESTING.md`
- `docs/BANDIZIP_UI_RESEARCH.md`
- `docs/BANDIZIP_FEATURE_GAP.md`

## 当前限制

- RAR/RAR5 解压尚未用真实 RAR/RAR5 样本做提交内回归测试。
- ZIP 修复当前针对未加密 ZIP 的中央目录损坏，通过扫描本地文件头恢复 Store/Deflate 条目；不是通用 7Z/RAR 修复器。
- CP437/CP936/CP932 手动代码页重命名当前针对 ZIP；其他格式依赖 7-Zip 的 Unicode 处理。
- Quick Look 可能与其他已安装归档预览扩展竞争，这是 macOS 扩展选择行为。
- 完全 App Store 兼容的沙盒 XPC 文件访问桥仍需实现。
- 详见 `docs/BANDIZIP_FEATURE_GAP.md`。
