# NanZip

NanZip 是一个使用 SwiftUI 和内置开源 7-Zip 引擎构建的原生 macOS 归档工具。

GitHub: https://github.com/<GITHUB_OWNER>/NanZip

## 功能

- 浏览 ZIP、7Z、RAR、TAR、GZ、BZ2、XZ、ZST 等归档
- 解压全部或所选文件
- 密码解压、进度与取消
- 同名文件保留两者或覆盖
- 创建 ZIP、7Z、TAR、TAR.GZ、TAR.BZ2、TAR.XZ
- ZIP/7Z 密码加密
- 添加、替换、删除归档内条目
- 完整性测试
- Finder 右键菜单：`NanZip > 压缩 / 解压`
- Quick Look 空格预览归档目录
- 路径穿越防护
- macOS 26/27 Liquid Glass 界面，macOS 14–25 材质回退

## 构建

```sh
cd "$HOME/Projects/NanZip"
./Scripts/fetch-7zz.sh
NANZIP_SIGN_IDENTITY="<APPLE_DEVELOPMENT_IDENTITY>" ./Scripts/build-app.sh
```

构建产物：

- 本地：`build/NanZip.app`
- 安装位置：`$NANZIP_INSTALL_APP`

## 目录结构

- `Sources/NanZip`: SwiftUI 主应用
- `Sources/NanZipCore`: 归档、压缩、编辑和共享模型
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

- RAR 解压尚未用真实 RAR/RAR5 样本做回归测试。
- 分卷、归档内媒体预览、修复和密码恢复尚未实现。
- 主应用尚未迁移到独立 XPC 服务或 App Sandbox。
- 详细差距见 `docs/BANDIZIP_FEATURE_GAP.md`。
