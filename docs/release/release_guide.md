# 发版指南

最后更新：2026-08-25

## 1. 发布方式

Zeta 使用 [GitHub Actions 发布工作流](../../.github/workflows/release.yml) 自动构建并发布
Windows、macOS 和 Linux 桌面安装包。工作流只监听推送到 GitHub 的 `v*` Tag；Tag
必须指向 `dev` 分支历史中的提交，并通过下文的版本预检。

仓库启用了 GitHub immutable releases。工作流会先创建草稿 Release，在草稿阶段上传并
校验全部附件，最后才公开 Release。不要在工作流运行期间手动发布草稿。

当前发布仍不做 Windows 代码签名或 Apple notarization。macOS 派生包会重新执行 ad-hoc
codesign，以保证拆分架构后的应用包结构有效；用户首次运行时仍可能看到 SmartScreen 或
Gatekeeper 提示。

## 2. 发布前准备

1. 确认待发布代码已经合并到 `dev`，并且本地工作区没有未提交改动。
2. 更新 `pubspec.yaml` 中的 `version`：

   ```yaml
   version: 0.2.0+2
   ```

   `0.2.0` 是应用数字版本，必须与 Tag 的核心版本一致；`2` 是正整数 build number。
   Windows 和 macOS 的应用元数据继续使用这两个数字字段，不写入 Beta 后缀。
3. 提交版本变更并推送到 `dev`。
4. 在创建 Tag 前执行完整发版门禁：

   ```sh
   flutter pub get --enforce-lockfile
   flutter analyze
   bash tool/test_full.sh
   ```

## 3. Tag 规则

工作流只接受以下两种形式：

| `pubspec.yaml` | 合法 Tag | Release 类型 |
| --- | --- | --- |
| `version: 0.2.0+2` | `v0.2.0` | 正式版本、Latest |
| `version: 0.2.0+2` | `v0.2.0-beta.1` | Pre-release、非 Latest |

版本号各数字段不得包含前导零；Beta 序号必须是大于零且无前导零的整数。以下 Tag 会被
预检拒绝：

- `v0.3.0`：核心版本与 `pubspec.yaml` 不一致。
- `v0.2.0-beta.0` 或 `v0.2.0-beta.01`：Beta 序号不合法。
- `v0.2.0-rc.1`：当前发布通道只支持稳定版和 Beta。
- `0.2.0`：缺少 `v` 前缀。
- `v0.2.0+2`：Tag 不接受 build metadata。
- 指向 `dev` 分支历史之外提交的任何 Tag。

可在本地单独检查元数据：

```sh
dart tool/packaging/release_metadata.dart \
  --tag v0.2.0-beta.1 \
  --pubspec pubspec.yaml
```

命令输出 JSON；CI 另用 `--github-output` 写入 GitHub Actions 输出文件。

## 4. 创建并推送 Tag

以 Beta 发布为例：

```sh
git switch dev
git pull --ff-only
git tag -a v0.2.0-beta.1 -m "Zeta v0.2.0-beta.1"
git push origin v0.2.0-beta.1
```

正式版只需改用 `v0.2.0`。Tag 必须指向已经包含正确 `pubspec.yaml` 版本的提交；推送后
无需手动创建 GitHub Release。

## 5. 自动化流程

Tag 推送后的流程如下：

1. `Validate release metadata` 校验 Tag 格式、`pubspec.yaml` 和 `dev` 可达性。
2. 完整质量门禁与 Windows、macOS、Linux 构建并行执行；这些作业只有只读权限。
3. 发布作业汇总附件并核对精确的 24 项清单和本地 SHA-256。
4. 不存在 Release 时创建草稿；已有草稿时清理清单外附件并恢复上传。
5. GitHub 返回的附件名称、大小和 digest 全部匹配后，才将草稿发布。

只有最终发布作业拥有 `contents: write`。Beta 会自动标记为 Pre-release 且不设为 Latest。

每次成功发布包含 12 个分发包及各自的 `.sha256`，合计 24 个附件：

| 平台 | 分发包 |
| --- | --- |
| Windows x86_64 | ZIP、Inno Setup EXE |
| macOS arm64 | ZIP、DMG |
| macOS x86_64 | ZIP、DMG |
| macOS universal | ZIP、DMG |
| Linux x86_64 | `tar.gz`、DEB、RPM、AppImage |

附件中的 `<version>` 是 Tag 去掉 `v` 后的值，不含 build number。例如
`v0.2.0-beta.1` 生成 `zeta-0.2.0-beta.1-linux-x86_64.AppImage`。Linux Beta
包内部版本使用 `0.2.0~beta.1` 排序语义；Windows 和 macOS 应用元数据仍使用
`pubspec.yaml` 的数字版本。

macOS 先构建 universal App，并验证所有 Mach-O 同时包含 arm64/x86_64，再派生两个
单架构 App、重新 ad-hoc 签名和分别验证 ZIP/DMG。Linux 四种包都来自同一 staging
tree；AppImage 工具和 runtime 的下载提交及 SHA-256 固定，校验异常会直接失败。

## 6. 发布后验证

1. 在 GitHub Actions 页面确认预检、质量门禁、三个构建作业和发布作业全部成功。
2. 在 Releases 页面确认标题、Tag、Release Notes 和版本类型正确。
3. 确认 Release 包含 12 个分发包和 12 个 `.sha256` 文件。
4. 下载目标平台分发包并验证 SHA-256：

   ```sh
   sha256sum --check zeta-0.2.0-beta.1-linux-x86_64.AppImage.sha256
   shasum -a 256 --check zeta-0.2.0-beta.1-macos-universal.dmg.sha256
   ```

   Windows PowerShell：

   ```powershell
   $file = '.\\zeta-0.2.0-beta.1-windows-x86_64.zip'
   $expected = (Get-Content "$file.sha256").Split()[0]
   $actual = (Get-FileHash $file -Algorithm SHA256).Hash
   $actual.ToLowerInvariant() -eq $expected.ToLowerInvariant()
   ```

5. 验证 macOS 三种包的实际架构，并对目标平台执行安装和启动冒烟测试。

## 7. 失败恢复与不可变限制

- 构建或质量门禁失败：Release 作业不会运行；修复代码和版本后创建新 Tag。
- 草稿阶段上传失败：重跑失败作业。发布脚本会复用草稿，删除清单外的旧附件，并覆盖上传
  24 项精确清单。
- 已发布且远端附件与本次清单完全一致：重跑视为成功，不重复修改 Release。
- 已发布但附件缺失、名称/大小/digest 不一致：工作流明确失败。immutable Release 不能
  修复或补传，必须修正后创建新 Tag。
- 已经公开的 Tag 或 Release 不得改写、删除后复用。当前没有附件的 immutable
  `v0.1.0-beta.4` 保持原样；首次端到端验收必须使用新 Tag `v0.1.0-beta.5`。
- Tag 预检失败且尚未产生公开 Release 时，确认该 Tag 未被外部使用后才可删除错误 Tag；
  已公开版本一律递增版本并发新 Tag。

## 8. 发布检查清单

- [ ] `pubspec.yaml` 的数字版本和正整数 build number 已更新。
- [ ] 版本提交已合并并推送到 `dev`。
- [ ] `flutter analyze` 和 `bash tool/test_full.sh` 已通过。
- [ ] Tag 为 `vX.Y.Z` 或 `vX.Y.Z-beta.N`，且核心版本与应用版本一致。
- [ ] GitHub Actions 全部成功。
- [ ] Release 类型、Latest 状态、Release Notes 和 24 个附件正确。
- [ ] 远端 digest、本地 SHA-256、macOS 架构和目标平台启动冒烟均通过。
