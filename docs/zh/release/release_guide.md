# 发版指南

文档核对：2026-09-07；发布操作和远端设置未在本次重新验证。

## 1. 发布方式

常规发布在 `develop` 上准备版本与说明，不另建 `release/*`。生产紧急修复仍可从 `main` 拉出 `hotfix/*`。完成稳定版本验收后，从 `develop` 向 `main` 创建 PR，人工审读版本与更新说明后合并，即触发 [发布工作流](../../../.github/workflows/release.yml)。关闭但未合并的 PR 不发布；无需手动创建 tag。工作流固定使用该 PR 的合并提交，测试、构建和发布不会改用后来推进的 main。

发布准备可调用项目内 `$zeta-release` Skill，既可指定版本，也可只选择 beta 或正式版，由 Skill 自动确定下一个版本。Skill 在已检出的 `develop` 上就地准备，不创建或切换 `release/*`，也不代替人工审读、提交或合并 PR。

Skill 通过 `gh` 在 GitHub 创建 PR。本地获取 main 仅用于比较和校验，不自动执行 merge、会合并的 pull 或 rebase；遇到 PR 冲突时报告状态，分支同步与冲突处理须另有明确指示。

### 分支流转与当前自动化边界

完整[分支模型](../../../CONTRIBUTING.md#分支模型)以贡献指南为准。`$zeta-release` 常规路径只在 `develop` 上准备版本与说明，不拉 `release/*`。`main` 仅接收已就绪的稳定版本；beta 在 `develop` 上准备，不为发布 beta 将预发布版本合入 `main`。

当前工作流仍只在 PR 合入 `main` 后触发，且支持读取 beta 版本。它尚未适配从 `develop` 发布 beta；本次约定调整不代表该自动化已实现。beta 可继续准备版本与说明，发布需先适配工作流；不能沿用旧方式把 beta 合入 `main`。

## 2. 版本与更新说明

- 根目录 `release.json` 保存发布身份：`schemaVersion` 为 1，`version` 为 `X.Y.Z` 或 `X.Y.Z-beta.N`，不含 `v` 前缀。流水线由此生成 tag 和分发包版本。
- `pubspec.yaml` 保存 `X.Y.Z+BUILD`，核心版本必须一致，BUILD 为正整数。Windows/macOS 元数据不写 beta 后缀，beta 序号与 build number 独立。
- 数字段不能有前导零，beta 序号必须大于零。不支持 rc、tag build metadata 或其他预发布通道。
- 发布版本必须高于所有已有合法发布 tag；本地发布准备还要求高于目标 main 已记录的版本。按数字比较核心版本与 beta 序号，同核心正式版高于任意 beta，例如 `0.1.0-beta.9 < 0.1.0-beta.12 < 0.1.0 < 0.1.1-beta.1`。相同或回退均失败，不能靠提高 BUILD 绕过。
- 同版更新说明固定在 `docs/zh/release/notes/v<version>.md`，必须非空。按[更新日志规范](../development/documentation.md#更新日志规范)编写，已有文稿先读再增量修改；`CHANGELOG.md` 链接到正文。GitHub Release 直接读取这份文件，不再自动生成提交列表。

例如 beta 版本对应：

```json
{"schemaVersion": 1, "version": "0.1.0-beta.13"}
```

```yaml
version: 0.1.0+2
```

本次迁移的 `release.json` 仅记录已有 `0.1.0-beta.12` 基线，不代表准备再次发布该版本。首次使用新流程前，必须通过 Skill 自动选择或明确指定更高版本并补齐同版文稿，不能直接合并基线值尝试重发。

### 自动选择下一个版本

可以直接使用：

```text
使用 $zeta-release 发布beta版本
使用 $zeta-release 发布正式版本
使用 $zeta-release 准备 v0.2.0-beta.1
```

只给通道时不再追问版本号。Skill 获取完整历史、最新远端 main 和 tags，按数值排序取所有合法本地/远端发布 tag、main 发布版本和当前 `release.json` 版本中的最大值作为基线；不能只看同通道历史。显式给出的版本优先，重复或回退会被拒绝，不会悄悄改成其他版本。

| 最大已知版本 | 发布 beta | 发布正式版 |
| --- | --- | --- |
| `0.1.0-beta.12` | `0.1.0-beta.13` | `0.1.0` |
| `0.1.0` | `0.1.1-beta.1` | `0.1.1` |
| `0.2.0-beta.9` | `0.2.0-beta.10` | `0.2.0` |

通用规则：beta 基线递增 beta 序号，或去掉 beta 后缀转正式版；正式版基线递增补丁号，发布 beta 时再加 `-beta.1`。默认不自动提升主版本或次版本，需要时明确指定完整版本。

继续同一未发布草稿时，若同通道版本改动、同版文稿或已有 PR 能证明目标已选定，且它仍高于所有 tags 和 main 版本，则沿用该版本和 build number，并增量更新说明。仅有一个当前配置值不足以判定为草稿；不要每次调用都递增，也不要复用已发布版本。

完整历史内没有合法发布 tag、main 没有发布版本且当前没有 `release.json` 时，才以 `pubspec.yaml` 核心版本初始化：beta 为 `X.Y.Z-beta.1`，正式版为 `X.Y.Z`。配置损坏、网络失败或历史缺失必须说明并暂停，不能当作首次发布。通道和版本都未指定且上下文不明确时，只询问通道。

Skill 在修改前说明基线和选出的版本，随后直接继续，不额外要求确认。自动选号后仍校验严格递增；新一轮发布的 build number 独立取可确认最大值加一，继续草稿时保持原值。自动选号发生在 Skill 准备阶段，CI 只读取已提交版本，不再次递增。若新出现的远端版本使自动选号失效，重新获取基线计算；远端持续变化时暂停，避免无限重试。

## 3. 发布前准备

1. 获取完整远端历史和 tags，在当前 `develop` 上准备更高版本，不创建或切换 `release/*`。保留当前工作区；当前不在 `develop` 时不要代为切换。
2. 同时更新 `release.json`、`pubspec.yaml`、同版说明和 `CHANGELOG.md` 入口。
3. 执行版本检查和完整门禁：

   ```sh
   git fetch origin --tags
   dart tool/packaging/release_plan.dart --previous-ref origin/main
   flutter pub get --enforce-lockfile
   flutter analyze
   bash tool/test_full.sh
   ```

   使用 CI 指定的 `PUB_HOSTED_URL=https://pub.dev`，避免本机镜像配置改变锁文件。
4. 人工审读并修改说明，随代码提交、推送 `develop`。先用 `gh pr list --base main --head develop --state open` 查重，再用 `gh pr create --base main --head develop --title <标题> --body-file <正文文件>` 在 GitHub 创建 PR；已有 PR 用 `gh pr edit` 更新。通过 `gh pr view` 核对分支与状态，交付 PR URL。提交前执行本地版本与文稿校验。目标为 `main` 的 PR 会跑独立 CI；合并后由发布预检再次校验版本与文稿。
5. 检查通过后由用户在 GitHub 合并 PR，即授权流水线执行发布。“提交并发起 PR”不包含本地合并或 `gh pr merge`；Skill 不自动处理 PR 冲突。不要再手工打 tag、推送 tag 或提前创建 GitHub Release。

## 4. 自动化流程

独立 CI 由目标为 `develop` 或 `main` 的 PR 触发，不响应 push 或手动触发。`workflow_call` 保留，发布流程仍可调用全部检查，并通过 `checkout-ref` 固定被测合并提交；PR 的分支过滤不限制该调用。

1. 仅处理合入 main 的 PR，固定其合并 SHA，确认该 SHA 位于 main 历史中。
2. 从该提交读取发布版本与文稿，验证数字版本一致、版本递增和文稿存在。
3. 调用同一提交的 reusable CI；质量门禁通过后，在 Windows、macOS、Linux 构建分发包。
4. 发布作业串行执行，重新获取远端 tags 并检查版本，阻止并发构建的旧版本覆盖较新版本。
5. 核对 24 项附件清单和本地 SHA-256，通过 `gh release create --target <合并SHA> --notes-file <同版说明>` 自动创建 tag 并发布。beta 为 Pre-release、非 Latest；正式版为 Latest。
6. 验证公开状态、附件、Release attestation 和每个上传文件。
7. 发布完成后重新从远端获取当前版本 tag，解析其最终提交（兼容轻量 tag 和附注 tag），核对与本次合并 SHA 一致，并写入 Actions 摘要；tag 缺失或指向错误时流程失败，不覆盖或移动 tag。

仅最终发布作业拥有 `contents: write`。已有 tag 必须指向相同合并 SHA；不同提交复用相同版本会失败。发布流程不改写公开版本。

GitHub CLI 在有附件时自动完成临时草稿、附件上传和公开发布，脚本不传 `--draft`。自动 tag 的目标提交与文稿参数见 [GitHub CLI 文档](https://cli.github.com/manual/gh_release_create)。

## 5. 分发包与平台验收

成功发布包含 12 个分发包及其 `.sha256`，合计 24 项：

| 平台 | 分发包 |
| --- | --- |
| Windows x86_64 | ZIP、Inno Setup EXE |
| macOS arm64 / x86_64 / universal | 各一份 ZIP、DMG |
| Linux x86_64 | tar.gz、DEB、RPM、AppImage |

附件版本包含 beta 后缀、不含 build number。Linux beta 包内部使用 `X.Y.Z~beta.N` 排序语义；Windows/macOS 使用数字应用版本。

Windows 尚未代码签名，macOS 尚未 notarization；macOS 派生包重新 ad-hoc 签名。首次运行仍可能看到 SmartScreen 或 Gatekeeper 提示。macOS 构建 universal App 后派生单架构包；Linux 各种包来自同一 staging tree，下载的 AppImage 工具和 runtime 校验固定 SHA-256。真实安装与启动验收不能由自动化替代。

### macOS DMG 打包工具

DMG 使用 [sindresorhus/create-dmg 8.1.0](https://github.com/sindresorhus/create-dmg/tree/v8.1.0)
的原版默认背景、窗口和图标布局。CI 使用 Node.js 22.23.2；本地打包也建议使用该版本
（工具要求 Node.js ≥20），并先安装同一版本的 npm 工具（不是 Homebrew 的同名 Shell 工具）：

```sh
npm install --global create-dmg@8.1.0
create-dmg --version
```

然后按发布工作流构建 universal App，并运行 `bash tool/packaging/package_macos.sh <release-version>`。
脚本在每个架构的独立临时目录生成 `Zeta.dmg`，再恢复包含发布版本与架构的附件名称，
避免三种架构互相覆盖，也避免自动读取工作目录中的 `license.txt` / `license.rtf`。
镜像使用工具默认的 APFS / ULFO 格式；`--no-code-sign` 仅跳过 DMG 签名，App 的
ad-hoc 签名与 ZIP/DMG 内的架构、签名校验照常执行。打包时还会检查 Applications
符号链接与 Finder 布局文件，最终生成 SHA-256。

首次接入及升级工具后，由人工在 Finder 中验收默认背景、图标、窗口布局，以及拖拽到
Applications 后的启动行为；脚本校验不能替代外观和安装验收。

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

- 构建或质量门禁失败：发布作业不会运行，可重跑同一合并提交；需要代码修复时通过新 PR 提高发布版本。
- 附件上传失败：GitHub CLI 不会发布不完整的 Release。直接重跑失败作业。
- 工作流被强制取消后如果遗留草稿，发布脚本会输出草稿 URL 并失败关闭；人工确认并删除
  该草稿后再重跑。脚本不会猜测或自动删除远端草稿。
- 已发布且 tag 仍指向本次合并 SHA，Release 类型、24 个附件名称和 attestation 都正确：重跑视为成功，
  不重复修改 Release。
- 已发布但状态、附件清单或 attestation 不一致：工作流明确失败。immutable Release 不能
  修复或补传，必须修正并通过新 PR 发布更高版本。
- 已经公开的 Tag 或 Release 不得改写、删除后复用。失败后的下一版本由实际发布计划确定；先核对远端已有 Tag，不沿用历史任务中指定的临时版本号。

## 8. 发布检查清单

- [ ] `release.json` 完整版本、`pubspec.yaml` 数字版本和正整数 build number 一致。
- [ ] 同版更新说明已人工审读，版本严格高于既有版本。
- [ ] 版本与说明通过 PR 合入 `main`，发布固定该合并提交。
- [ ] `flutter analyze` 和 `bash tool/test_full.sh` 已通过。
- [ ] 自动生成的 tag 为 `vX.Y.Z` 或 `vX.Y.Z-beta.N`，指向本次合并提交。
- [ ] GitHub Actions 全部成功。
- [ ] Release 类型、Latest 状态、Release Notes 和 24 个附件正确。
- [ ] Release attestation、本地 SHA-256、macOS 架构和目标平台启动冒烟均通过。
