# NanZip

NanZip 是一个使用 SwiftUI 和系统 `libarchive` 构建的原生 macOS 归档工具。

GitHub: https://github.com/gxmlfx/NanZip

## 功能

- 浏览 ZIP、7Z、RAR、TAR、GZ、BZ2、XZ、ZST 等归档
- 解压全部或所选文件
- 密码解压、进度与取消
- 同名文件保留两者或覆盖
- 创建 ZIP、7Z、TAR.GZ、TAR.BZ2、TAR.XZ
- ZIP WinZip AES-256 加密
- Finder 右键菜单：`NanZip > 压缩 / 解压`
- Quick Look 空格预览归档目录
- 路径穿越防护
- macOS 26/27 Liquid Glass 界面，macOS 14–25 材质回退

## 构建

```sh
cd /Users/gxmlfx/Projects/NanZip
NANZIP_SIGN_IDENTITY="Apple Development: gxmlfx@icloud.com (48CV566UYY)" ./Scripts/build-app.sh
```

构建产物：

- 本地：`build/NanZip.app`
- 安装位置：`/Volumes/APFS P Drive/Applications/NanZip.app`

## 目录结构

- `Sources/NanZip`: SwiftUI 主应用
- `Sources/NanZipCore`: 归档、压缩和共享模型
- `Sources/NanZipFinder`: Finder Sync 扩展
- `Sources/NanZipQuickLook`: Quick Look 扩展
- `Sources/CArchive`: libarchive C 桥接

## 文档

- `docs/PROJECT_STATE.md`
- `docs/DEVELOPMENT_LOG.md`
- `docs/CONTEXT_HANDOFF.md`
- `docs/ROADMAP.md`
- `docs/UPSTREAM_RESEARCH.md`
- `docs/TESTING.md`

## 当前限制

- RAR 解压尚未用真实 RAR/RAR5 样本做回归测试。
- 符号链接在列表中可见，但当前解压时会安全跳过。
- 分卷、归档内文件预览、修复和密码恢复尚未实现。
- 主应用尚未迁移到独立 XPC 服务或 App Sandbox。
