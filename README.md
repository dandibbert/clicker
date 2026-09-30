# Clicker

原生 macOS 鼠标 / 键盘操作录制与回放工具，使用 SwiftUI、AppKit 和 Swift Package Manager 构建。

## 功能

- 录制鼠标、键盘操作并保存为脚本。
- 编辑动作、等待时间和脚本回放设置。
- 使用全局快捷键开始回放或停止录制 / 回放。
- 菜单栏控制、录制状态提示，以及浅色 / 深色外观。
- 录制保存失败后可重试或另存；普通退出会先处理未保存录制，中断的录制会明确标记。

录制与回放的行为、恢复边界及回归验收说明见 [可靠性修复说明](docs/AUDIT_FIXES.md)。

## 下载与运行

需要 **macOS 14 Sonoma 或更新版本**。

在仓库的 **Releases** 页面下载匹配处理器的 ZIP：

| 文件后缀 | 处理器 |
| --- | --- |
| `macos-arm64.zip` | Apple Silicon（M 系列） |
| `macos-x86_64.zip` | Intel |

解压后将 `Clicker.app` 拖到「应用程序」目录。首次使用时，按应用提示在「系统设置 → 隐私与安全性」中授予 **辅助功能** 与 **输入监控** 权限；录制内容可能包含敏感输入，请仅录制你有权操作的内容。

> 自动打包使用 ad-hoc 签名，**没有 Apple Developer ID 签名或公证**。macOS 可能阻止首次打开：确认下载来源后，可在「隐私与安全性」中允许打开。组织管理的 Mac 可能不允许运行此类应用。更新应用后，可能需要重新授予系统权限。

每个 ZIP 都附有 `.sha256` 校验文件，在下载目录执行：

```bash
shasum -a 256 -c Clicker-1.0.0-macos-arm64.zip.sha256
```

文件名应替换为实际下载的版本与架构。校验用于发现文件损坏，不代替来源验证或 Apple 公证。

## 本地开发

需要 Xcode 15+ 或相应的 Xcode Command Line Tools（Swift 5.9+）。

```bash
# 运行全部 Swift 测试
swift test

# 打包契约测试（Python 3 标准库；编译器 / 签名工具使用模拟）
python3 -B -m unittest discover -s Tests/Packaging -v

# 构建本机架构的 .app
./scripts/build-app.sh
open dist/Clicker.app

# 构建 ZIP 和 SHA-256 校验文件
./scripts/package-release.sh
```

输出位于 `dist/`，构建产物不会提交到 Git。

### 版本与签名

```bash
CLICKER_VERSION=1.2.3 CLICKER_BUILD_NUMBER=1 ./scripts/package-release.sh
```

`CLICKER_VERSION` 默认为 `1.0.0`，必须为不带 `v` 的 `X.Y.Z`；`CLICKER_BUILD_NUMBER` 默认为 `1`，必须为正整数。Swift 构建选项会传入构建命令，例如：

```bash
./scripts/package-release.sh --triple x86_64-apple-macosx14.0
```

本机安装了适合的签名证书时，可以设置 `CLICKER_SIGNING_IDENTITY`。此选项只负责签名，不会自动执行 Developer ID 分发所需的 hardened runtime 配置或公证；证书与私钥不应提交到仓库。

## GitHub Actions

`.github/workflows/build-release.yml` 提供：

- **每次分支推送 / Pull Request**：在 macOS 15 的 Apple Silicon 与 Intel runner 上测试、构建、验证签名并打包。
- **手动构建**：在 Actions → Build and Release → Run workflow 触发。
- **构建产物**：成功构建后，从 Actions 的 Artifacts 下载，两种架构分别保存 14 天。
- **版本发布**：推送 `vX.Y.Z` tag；两个架构的测试与打包均成功后，自动创建 GitHub Release，上传 ZIP 与 SHA-256 文件。

例如，发布已合并到 `main` 的版本：

```bash
git switch main
git pull --ff-only
git tag -a v1.0.0 -m "Clicker 1.0.0"
git push origin v1.0.0
```

当前发布流程仅支持正式版 tag，不支持预发布后缀。Release 阶段使用 GitHub 自动提供的 `GITHUB_TOKEN`，**无需配置个人 token 或 Apple 证书**；只有发布 job 获得仓库写权限。第三方 Actions 固定到 commit SHA，Dependabot 定期检查更新。

## 项目结构

```text
Sources/Clicker/       macOS 应用、录制、回放及界面
Sources/ClickerCore/   模型、动作编辑、分组与持久化
Tests/                Swift 测试及 Python 打包契约测试
Resources/            应用图标源文件
scripts/              .app、图标及发布包构建脚本
.github/              CI / 发布 workflow 与依赖更新配置
```

本机代理状态（`.omc/`）、构建产物、凭据及签名材料通过 `.gitignore` 排除。
