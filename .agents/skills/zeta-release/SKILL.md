---
name: zeta-release
description: 为 Zeta 准备 beta 或 stable 正式版本：支持指定版本或只选通道自动递增版本，更新应用版本、按同通道 tag 确定提交范围、提炼用户更新说明，并交付人工审读及到 main 的 PR。PR 合入 main 后由流水线自动发布。
---

# Zeta 发布准备

在当前 Zeta 仓库执行。目标是可审读的版本改动和更新说明，以及在稳定版本就绪后通过 `gh` 在 GitHub 创建目标为 `main` 和 `develop` 的 PR；GitHub 上的 PR 合并成功即自动执行发布。Skill 不手工打 tag、不代替用户合并 PR，也不在本地执行发布分支与 main 之间的合并。

## 1. 确定发布通道或版本并读取项目约定

- 支持明确版本（如 `v0.1.0-beta.13`、`v0.1.0`），也支持“使用 $zeta-release 发布beta版本”或“使用 $zeta-release 发布正式版本”。只给通道时按下方规则自动选择版本，不要求用户再提供版本号；只有通道和版本都未给出、且上下文无法确定时才询问通道。stable、正式版视为同一通道。
- `vX.Y.Z-beta.N` 是 beta；`vX.Y.Z` 是 stable。数字不得有前导零，N 必须大于零；不接受 rc 或 tag build metadata。
- 先执行 `git status`，保留现有改动；定位仓库根目录并读取 `AGENTS.md`、`docs/zh/release/release_guide.md`、`docs/zh/development/documentation.md` 的更新日志规范，以及 `release.json`、`pubspec.yaml`、`.github/workflows/release.yml`。路径均相对仓库根目录。
- 若需理解代码，遵循仓库 CodeGraph 规则。现行发布校验以 `tool/packaging/release_plan.dart` 和 `release_metadata.dart` 为准，文档与脚本冲突时先查明原因。
- 核对当前分支和远端，遵循 `CONTRIBUTING.md` 的分支模型：常规发布在从 `develop` 创建的 `release/*` 准备；生产紧急修复在从 `main` 创建的 `hotfix/*` 准备。稳定版本完成后分别向 `main` 和 `develop` 发起 PR。不直接用 `develop` 或 `feature/*` 向 main 发版，不擅自切换或丢弃用户正在工作的分支。
- `main` 始终代表最新可发布稳定版本。beta 只在 `release/*` 准备与验证，不创建 beta 到 main 的发布 PR。当前工作流尚不支持从 `release/*` 发布 beta；可完成版本、文稿和验证，交稿须明确自动发布待适配，不宣称已支持或把 beta 合入 main 来绕过。
- 获取 main 仅用于只读比较和版本校验，不执行 `git merge`、会合并的 `git pull` 或 `git rebase` 来同步分支或消除 PR 冲突。发现分支分叉或冲突时报告状态，继续可独立完成的发布准备；分支同步和冲突处理须另有用户明确指示，不能作为创建 PR 的隐含步骤。
- 获取完整历史和最新远端 tags（不强制改写已有 tag）。网络失败或浅克隆历史不全时明确范围未验证，不能把缺失 tag 当成首次发布。
- 检查目标 tag 是否已存在于本地或远端。显式指定的版本重复或回退时明确拒绝，不擅自替用户改号；自动选择的版本遇到新的远端版本时重新获取基线并计算，若远端持续变化则暂停并说明，不无限重试。不移动、删除或复用公开 tag。

### 未指定版本号时的自动规则

版本选择规则与示例同步维护在 `docs/zh/release/release_guide.md` 的“自动选择下一个版本”。执行以下规则：

1. 获取最新远端 main 与完整 tags。将所有合法本地/远端发布 tag、`origin/main` 的发布版本和当前 `release.json` 的版本按第 2 节数值语义比较，取最大值 B；不能只看同通道 tag，也不能按日期或字符串排序。
2. 先检查是否正在继续同一个未发布草稿：当前通道相同，且版本改动、同版文稿或已有 PR 能证明这是已选定的待发布版本，并严格高于所有 tags 和 main 版本时，沿用草稿版本及 build number，增量更新文稿，不因重复调用再次加号。只有当前配置值而没有草稿证据，不能视为重跑。
3. 新准备的版本按下表从 B 推导。默认只递增补丁号，不根据提交内容擅自升级 major/minor；需要特定核心版本时由用户明确指定完整版本。

| 最大已知版本 B | 发布 beta | 发布正式版 |
| --- | --- | --- |
| `X.Y.Z-beta.N` | `X.Y.Z-beta.(N+1)` | `X.Y.Z` |
| `X.Y.Z` | `X.Y.(Z+1)-beta.1` | `X.Y.(Z+1)` |

4. 完整历史内没有合法发布 tag、main 也没有发布版本且当前没有 `release.json` 时，以 `pubspec.yaml` 核心版本初始化：beta 用 `X.Y.Z-beta.1`，正式版用 `X.Y.Z`。现有配置格式错误、远端不可用或历史不完整时不能使用首次发布回退。
5. 在修改文件前告知本次基线、所选通道和计算出的目标版本，然后直接继续版本更新及文稿准备，不增加确认步骤。继续执行第 2 节递增校验；自动选号不豁免任何检查。

自动选号发生在本地 Skill 准备阶段，结果写入 `release.json` 和 `pubspec.yaml`。CI 只读取并校验提交中的版本，不在发布时再递增。新一轮发布的 build number 仍独立按第 2 节规则处理。

## 2. 校验递增并更新应用版本

- `release.json` 的 `schemaVersion` 保持 1，`version` 写完整发布版本、不带 v（例如 `0.1.0-beta.13`）。这是流水线的发布版本真源。
- 在编辑之前比较目标版本与远端所有合法发布 tag，以及 `origin/main` 的发布版本。必须严格更大；相同和回退都拒绝。此处跨通道比较，与更新说明的“同通道基线”分开。
- 使用 `release_plan.dart` 的数值排序语义：先比较 X/Y/Z，再比较 beta 序号；同核心版本 `beta.12 > beta.9`，正式版高于任意 beta。正式版之后不能回到同核心 beta，但可发布更高核心版本的 beta。不得用字符串比较或只校验目标 tag 不存在。
- 第 5 节文稿准备完成后、提交前执行 `dart tool/packaging/release_plan.dart --previous-ref origin/main`（先获取最新远端 main 和完整 tags），校验版本、平台数字版本和同版更新说明。Skill 不使用 `--allow-existing` 绕过重复版本检查；该参数仅供 CI 重跑同一已发布提交。

- `pubspec.yaml` 写 `X.Y.Z+BUILD`；即使发布 beta，也不能写入 `-beta.N`。Windows/macOS 元数据依赖数字版本；不要机械替换所有平台文件中的版本字符串。
- 用户指定 build number 时校验为正整数；未指定时读取当前值和已发布版本的值，默认取可确认的最大值加一，并在交稿中说明。beta 序号不等于 build number。
- 重跑同一版本准备时先读已有文稿、版本改动和提交记录：已为该版本分配的 build number 保持不变，不重复递增；无法确认归属时说明并询问。
- 更新项目实际维护的其他版本真源；不改内部包独立版本、锁文件依赖或生成产物来凑一致。
- 执行 `dart tool/packaging/release_metadata.dart --tag <目标tag> --pubspec pubspec.yaml`，确认核心版本、build number 和通道正确。

## 3. 冻结范围：上一个同通道 tag → 当前最新提交

记录当前 `HEAD` 的完整 SHA 为 `HEAD_SHA`，后续读取固定 SHA，不让新提交悄悄改变范围。未提交代码不属于范围；如用户要把它们随版本发布，先列明，待提交后重算范围并补充文稿。

按提交图选择 `HEAD_SHA` 可达的最近同通道 tag，不按日期或字符串排序挑一个不可达 tag：

```sh
HEAD_SHA=$(git rev-parse HEAD)
# beta：最近的 beta tag，不限于同一核心版本
PREV=$(git describe --tags --abbrev=0 --match 'v*-beta.*' "$HEAD_SHA")
# stable：最近的正式 tag，排除全部预发布 tag
PREV=$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-*' "$HEAD_SHA")
git log --oneline --no-merges "$PREV..$HEAD_SHA"
git log --no-merges --format=fuller "$PREV..$HEAD_SHA"
```

上面的两种 `PREV` 命令只执行目标通道对应的一种。glob 只是候选过滤，必须再按第 1 节完整格式验证所选 tag；遇到不合法候选时排除它，重新选最近的合法同通道 tag。检查它确实是祖先且版本早于目标，发现倒退或分支歧义时先说明，不静默换通道。

- beta 不以 stable 为隐式基线；stable 不以最近 beta 为基线，正式版需要覆盖上次正式版以来的整体变化。
- 完整历史内确实没有同通道 tag 时，作为首次该通道发布读取仓库起点到 `HEAD_SHA` 的全部非合并提交，并在交稿中明确基线；用户指定其他基线时记录覆盖原因。
- 空范围如实说明，不编造新功能。提交清单排除 merge commit，但要结合 `git diff PREV HEAD_SHA` 核对最终状态，避免遗漏合并时的实际改动或把已回滚功能写入说明。

## 4. 按用户感知聚类提炼

执行项目更新日志规范，并额外排除单纯依赖升级：

- 每条先写用户得到了什么，再按需解释是什么功能或限制。按新功能、界面焕新、流畅度、稳定性等实际主题聚类，不强凑分类。
- 几十个性能提交合成一条“更顺滑”，说明改善场景；一个功能的多轮迭代合成一节，只写最终体验。
- 用户无感的重构、诊断设施、CI、依赖升级一律不写。修复只选用户真实痛过的问题，不用代码缺陷清单代替用户症状。
- 对拿不准“用户看到什么”的提交，读 commit body、diff，必要时读对应代码和测试确认。禁止仅凭标题脑补功能、性能数字、稳定性承诺或适用平台。证据仍不足则留在交稿待确认项，不放进用户说明。
- 合并重复与回滚链，核对 `HEAD_SHA` 中能力仍存在。实验性功能明确写“实验性”和实际限制。
- 在工作上下文保留“主题 → 提交 SHA → 用户变化证据”的对应关系供审读；技术证据不要混入用户文案。

## 5. 增量写入项目文档

- 先查找并读取本版本已有更新说明，包括 `CHANGELOG.md` 的同版内容。发布正文固定为 `docs/zh/release/notes/<目标tag>.md`；旧稿在其他位置时保留人工内容迁入此路径，并修正原入口，避免两份正文。
- 无论文件还是同版章节，只要存在就先完整读取，再局部增量编辑。保留人工措辞、已确认内容和限制；新提交并入已有主题、去重，不整篇重生成覆盖旧稿。旧稿与当前证据矛盾时修正相应段落并在交稿说明。
- `CHANGELOG.md` 为本版本提供简短入口并链接到独立文稿；已存在入口时只更新相关部分，不重复增加同版章节，不批量改写其他版本。
- 正文结构为“开场点出版本主线 → `###` 主题分节 → 每节 1～5 条 bullet 或短段”，节标题带一个 emoji。不额外规定开场句数、分节数量或禁止版本级 `##` 标题。
- 项目有英文同版文稿时同步操作、限制和事实；没有时按项目文档语言策略提供明确中文入口，不虚构已经完成的翻译。
- 发布流程使用 `--notes-file` 读取同版文稿，不再自动拼接提交列表；必须将更新说明与 `release.json`、`pubspec.yaml` 一起纳入 PR。

## 6. 自查与验证

- 每条 bullet 单独念给非程序员听：是否知道得到什么、在哪种场景有用？无法回答就重写或删除。
- 不区分大小写扫描用户文稿中的 `rebuild`、`provider`、`saveLayer`、`WidgetSpan`、`msgbus` 等实现术语，命中即打回重写；关键词扫描后仍要人工语义检查，不能只换成另一种术语。
- 核对实验性标注、每节条目数、标题 emoji、重复主题、版本号、链接和锚点，并执行 `git diff --check`。
- 发版准备按现行 AGENTS 和发版指南执行门禁：`flutter pub get --enforce-lockfile`、`flutter analyze`、`bash tool/test_full.sh`；Dart 改动另按规则格式化。使用 CI 指定包源，保留原锁文件，不顺便升级依赖。
- 验证失败或无法执行时记录真实原因；不把文稿完成说成发布通过，不把 fake 测试说成真实安装验收。

## 7. 交稿与发布、回合 PR

交付目标 tag/通道、应用版本及 build number、基线 tag 与 `HEAD_SHA`、文稿链接、主题证据摘要、验证结果和待确认项。明确提醒：**请人工审读并修改更新说明，再随本次代码一起提交，稳定版本就绪后通过 PR 合入 main，并回合 develop。**

- 遵循项目“不自动提交”规则；除非用户在当前会话明确授权提交，否则先交付修改和可直接使用的 Conventional Commit 信息。不要为创建 PR 私自提交用户尚未审读的内容。
- 同时准备 PR 标题与正文，正文说明用户变化、版本/范围、更新说明路径、验证和未完成事项。
- 以下到 main 的发布 PR 步骤仅适用于已就绪的稳定版本；beta 按第 1 节自动化边界交稿。
- 用户审读并提交后，核对 GitHub 仓库、源分支和 push 范围，将源分支推送到对应远端，通过 `gh` 创建到 `main` 的 PR。不能把不相关提交带入；沿用会话中已有的提交、推送和 PR 授权，不重复索要。
- 先用 `gh pr list --base main --head <源分支> --state open` 检查已有 PR；有则用 `gh pr edit` 更新标题和正文，无则用 `gh pr create --base main --head <源分支> --title <标题> --body-file <正文文件>` 创建。正文文件保留真实换行。交付真实 PR URL，并通过 `gh pr view` 核对源分支、目标分支与状态。没有凭据、远端分支或必要授权时如实说明尚未创建并交付准备好的内容，不能伪报 PR URL。
- “提交并发起 PR”指提交并推送源分支、在 GitHub 创建 PR，不授权本地 merge、rebase 或 `gh pr merge`。GitHub 报告 PR 冲突时交付 PR URL 和冲突状态，不自动修改分支历史；PR 由用户在 GitHub 审读并合并。
- 准备阶段不直接推送 main、不手工创建 tag 或 GitHub Release。提醒用户：PR 合并成功后会自动发布。流程固定合并提交，重新校验版本递增，通过测试和构建后自动创建指向该提交的 tag 并发布；合并后可跟踪 Actions 状态和 Release URL，不把 PR 创建等同于发布成功。
- 发布完成后查看 Actions 的 tag 核验结果：远端当前版本 tag 必须存在且解析到本次合并 SHA。tag 由发布流程自动创建，核验失败不能报告发布流程成功，也不手工覆盖已有 tag。

- 发布分支和紧急修复分支还须通过 `gh pr list --base develop --head <源分支> --state open` 检查回合 PR，使用 `gh pr create --base develop --head <源分支> --title <标题> --body-file <正文文件>` 创建，已有则用 `gh pr edit` 更新。交付两个目标 PR 的 URL 和状态，不自动合并。提醒用户在两个 PR 均合并且发布、标签成功后删除辅助分支，长期保留 main 和 develop。
