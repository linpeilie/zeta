# 发版指南

最后更新：2026-07-31

## 1. 发布方式

Zeta 使用 [GitHub Actions 发布工作流](../../.github/workflows/release.yml) 自动构建并发布
Windows、macOS 和 Linux 桌面安装包。工作流只监听推送到 GitHub 的 `v*` Tag；
创建普通分支、提交代码或推送不符合规则的 Tag 都不会发版。

发布流程不会对 Windows 包进行代码签名，也不会对 macOS 包进行签名或 notarization。
用户首次运行时可能看到 Windows SmartScreen 或 macOS Gatekeeper 提示。

## 2. 发布前准备

1. 确认待发布代码已经合并到默认分支，并且本地工作区没有未提交改动。
2. 更新 `pubspec.yaml` 中的 `version`：

   ```yaml
   version: 0.2.0+2
   ```

   `0.2.0` 是 build name，对应 Git Tag 的核心版本；`2` 是数字 build number。
   Windows 和 macOS 桌面版本要求 build name 使用 `x.y.z` 三段数字格式。
3. 提交版本变更并推送到 GitHub。
4. 在创建 Tag 前执行本地质量检查：

   ```sh
   flutter pub get --enforce-lockfile
   flutter analyze
   flutter test
   ```

## 3. Tag 规则

### 3.1 正式版本

正式版本 Tag 必须精确匹配 `v<build name>`。例如：

| `pubspec.yaml` | 合法 Tag | Release 类型 |
| --- | --- | --- |
| `version: 0.2.0+2` | `v0.2.0` | 正式版本 |

### 3.2 预发布版本

预发布版本在相同核心版本后追加合法的 SemVer 预发布标识：

| `pubspec.yaml` | 合法 Tag | Release 类型 |
| --- | --- | --- |
| `version: 0.2.0+2` | `v0.2.0-beta.1` | Pre-release |
| `version: 0.2.0+2` | `v0.2.0-rc.1` | Pre-release |

预发布标识只能包含 ASCII 字母、数字和连字符，可以用点分隔。纯数字标识不得包含前导零。

以下 Tag 会被质量门禁拒绝：

- `v0.3.0`：核心版本与 `pubspec.yaml` 不一致。
- `v0.2.0-beta..1`：包含空标识段。
- `v0.2.0-beta.01`：纯数字标识包含前导零。
- `v0.2.0+2`：Tag 不接受 build metadata；build number 只保留在应用和附件版本中。

## 4. 创建并推送 Tag

以正式发布 `v0.2.0` 为例：

```sh
git switch main
git pull --ff-only
git tag -a v0.2.0 -m "Zeta v0.2.0"
git push origin v0.2.0
```

预发布只需要替换 Tag：

```sh
git tag -a v0.2.0-beta.1 -m "Zeta v0.2.0-beta.1"
git push origin v0.2.0-beta.1
```

Tag 必须指向已经包含正确 `pubspec.yaml` 版本的提交。推送后无需手动创建 GitHub
Release。

## 5. 自动化流程

Tag 推送后，工作流同时启动以下四个作业：

- `Validate, analyze, and test`：校验 Tag 与应用版本，执行静态分析和全部测试。
- `Build Windows x64`：构建 Windows x64，并生成便携 ZIP 和 Inno Setup 安装程序。
- `Build macOS universal`：构建 macOS，并生成 ZIP 和 DMG。
- `Build Linux x64`：构建 Linux x64，并生成 `tar.gz` 和 Debian 安装包。

四个作业全部成功后，`Publish GitHub Release` 会合并三平台 Artifact、校验附件数量和
SHA-256，然后使用 Tag 创建 Release 并自动生成 Release Notes。任何门禁或构建失败都会
阻止发布。

每次成功发布包含 12 个附件：

| 平台 | 分发包 | 校验文件 |
| --- | --- | --- |
| Windows | `zeta-<version>-windows-x64.zip`、`zeta-<version>-windows-x64-setup.exe` | 两个 `.sha256` |
| macOS | `zeta-<version>-macos-universal.zip`、`zeta-<version>-macos-universal.dmg` | 两个 `.sha256` |
| Linux | `zeta-<version>-linux-x64.tar.gz`、`zeta_<version>_amd64.deb` | 两个 `.sha256` |

附件中的 `<version>` 使用 `pubspec.yaml` 完整版本。例如 Tag 为
`v0.2.0-beta.1`、应用版本为 `0.2.0+2` 时，附件仍使用 `0.2.0+2`。

## 6. 发布后验证

1. 在 GitHub Actions 页面确认四个并行作业和发布作业全部成功。
2. 在 Releases 页面确认标题、Tag、自动生成的 Release Notes 和版本类型正确。
3. 确认 Release 包含 6 个分发包和 6 个 `.sha256` 文件。
4. 下载至少一个平台的分发包并验证 SHA-256：

   ```sh
   # Linux
   sha256sum --check zeta-0.2.0+2-linux-x64.tar.gz.sha256

   # macOS
   shasum -a 256 --check zeta-0.2.0+2-macos-universal.dmg.sha256
   ```

   Windows PowerShell：

   ```powershell
   $expected = (Get-Content .\zeta-0.2.0+2-windows-x64.zip.sha256).Split()[0]
   $actual = (Get-FileHash .\zeta-0.2.0+2-windows-x64.zip -Algorithm SHA256).Hash
   $actual.ToLowerInvariant() -eq $expected.ToLowerInvariant()
   ```

5. 对目标平台执行一次安装和启动冒烟测试。

## 7. 失败处理

- 临时网络、runner 或上传失败：在 GitHub Actions 页面重跑失败作业。相同 Tag 的发布会
  更新同一个 Release，并覆盖同名附件。
- 任一平台构建失败：Release 作业不会运行；修复问题后应发布新的版本 Tag。
- Tag 与版本不一致：先确认 Release 尚未创建且错误 Tag 没有被外部使用，再删除错误 Tag、
  修正版本提交并重新创建：

  ```sh
  git push origin --delete v0.2.0
  git tag --delete v0.2.0
  ```

- 已经公开的 Tag 或 Release 不得改写。发现发布缺陷时，在 Release Notes 中标明问题，并以
  新版本号发布修复版本。

## 8. 发布检查清单

- [ ] `pubspec.yaml` 的 build name 和 build number 已更新。
- [ ] 版本提交已合并并推送到默认分支。
- [ ] `flutter analyze` 和 `flutter test` 已通过。
- [ ] Tag 核心版本与 build name 一致。
- [ ] GitHub Actions 全部成功。
- [ ] Release 类型、Release Notes 和 12 个附件正确。
- [ ] SHA-256 校验和目标平台启动冒烟通过。
