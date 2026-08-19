# VGV 分层迁移任务清单

中文 ｜ [English](../../en/architecture/migration_tasks.md)

本清单把 [migration_topology.md](./migration_topology.md) 转为可执行步骤。状态只有在本步骤代码、测试、架构门禁和中英文文档同一轮全部通过后才能勾选。

## 0. 进度总览

| 阶段 | 步骤 | 状态 |
| --- | --- | --- |
| P-1 基线与 ADR | 0–2 | ☑ |
| P0 工程地基 | 3–6 | ☑ |
| P1 共享契约与基础设施 | 7–10 | ☐ |
| P2 Provider 与 Management Data | 11–17 | ☐ |
| P3 其余 Data | 18–21 | ☐ |
| P4 Repository | 22–26 | ☐ |
| P5 app_ui 与 l10n | 27–28 | ☐ |
| P6 小 Feature Bloc/Presentation | 29–31 | ☐ |
| P7 Agent 会话 | 32–33 | ☐ |
| P8 Shell、Router 与收口 | 34–36 | ☐ |

明确不在任何阶段内：`app_update`、Velopack、更新 native channel、旧仓库 `tool/packaging/`、历史版本数据迁移、OS 外部 deep link。

**明确在范围内**（2026-08-19 裁决，见[逐文件清单 §5](./migration_manifest.md)）：
`third_party/codex_app_server_schema/`（269 个文件，Codex `0.144.5` stable schema pin，步骤 12 contract test 的基准）；
`tool/` 下的 5 个 `smoke_*.py`、`gen_codex_schema.{sh,ps1}`、`check_localized_ui_strings.dart` 与其 allowlist
（步骤 17 / 28 / 33 / 36 的验收直接依赖）。

---

## 1. 全局约定

### 1.1 四层与依赖

```text
Presentation → Bloc/Cubit → Repository → Data
```

- Data/Repository 位于 `packages/`，零 Flutter。
- Repository 之间零依赖。
- `lib/bootstrap.dart` 是唯一可同时 import Data、Repository 与 app platform adapter 的文件；`main_*` 只调用 bootstrap。
- `lib/app/platform/**` 只可 import `desktop_platform_api`、Flutter services 与对应 plugin，不可 import 其他 Data client。
- 其余 app `lib/**` 不 import 任一 Data package、`dart:io` 或 `package:flutter/services.dart`。
- Widget 不直接调用 Repository；Page 只负责创建/提供 Bloc，View/Widget 派发事件和渲染。
- app 的业务代码不直接 import package `src/`。

### 1.2 包结构

每个包使用 Very Good CLI 对应模板创建，并保持：

```text
packages/<name>/
├── lib/
│   ├── <name>.dart
│   └── src/
├── test/
└── pubspec.yaml
```

- 本地包一律 `path:` dependency。
- package barrel 是唯一公共入口。
- response model 留 Data；domain model 留 Repository。
- ADR-001 的 `agent_provider_contracts` 是唯一模型归属例外。
- Repository 通过构造函数接收 Data client/port，绝不内部创建具体实现。

### 1.3 Bloc/Cubit

- 事件与多形态状态使用 sealed class；State/Event 使用 Equatable。
- 单状态类提供 `copyWith` 和明确 status enum。
- 业务错误保存 typed failure，不保存已经本地化的字符串或直接渲染 Exception。
- Bloc 之间零构造依赖。
- 每个异步事件显式选择 `restartable()`、`droppable()` 或 `sequential()`。
- `close()` 取消 subscription、timer、lease；过期 async completion 用 generation/key 拒绝。
- Bloc 测试一律 `blocTest()`。

### 1.4 GoRouter

- 使用 `go_router`、`go_router_builder` 和 `@TypedGoRoute` / `@TypedShellRoute`。
- 不写裸路径导航，不使用 `extra`。
- 常规导航用生成 route 的 `go()`；只在需要返回值时用 `push()`。
- route 参数使用稳定 URL-safe ID，不直接携带本地文件路径。
- Router 拥有 page/projectId/threadId；Bloc 不依赖 GoRouter。
- 本次只做应用内导航，不注册 OS deep link。

### 1.5 l10n

- ARB 是 Zeta 自有 UI 文案的唯一真源。
- packages 不产出需要本地化的 Zeta UI 文案；用户内容、Provider 原文和内部诊断字符串不受此限制。
- packages 不依赖 `AppLocalizations`。
- `app_ui` 文案由构造参数传入。
- Bloc 不使用 `BuildContext`；需要后台文案时注入无 BuildContext 的 app copy resolver。

### 1.6 测试

- 测试镜像 `lib/`；mock 使用私有 mocktail 类。
- `setUp`/`tearDown` 位于 group 内；每个测试独立、可随机顺序执行。
- Widget 测试使用共享 `pumpApp`，MockBloc/MockCubit，不内联 `MaterialApp`。
- 行为由 unit/widget test 验证；静态视觉由带 `TestTag.golden` 的 golden 验证。
- Data/Repository 测成功、空值、边界、异常转换、取消和 resource close。
- Bloc 测每个 handler、transformer 顺序、过期结果和负向安全语义。

### 1.7 每步完成定义

每个步骤必须在同一最终迭代观察到四门全绿：

1. analyze：`mcp__dart__analyze_files`，`applyFixes: true`。
2. format：`mcp__dart__dart_format`，最终一轮 `0 changed`。
3. test：`mcp__very-good-cli__test`，子包传 `directory`，始终传 `timeout_seconds`。
4. coverage：同一个 test 调用同时传 `coverage: true`、`min_coverage: 100`、`check_ignore: true`。

生成代码通过 `exclude_coverage` 排除：`**/*.{g,freezed,gen}.dart` 以及 generated/l10n 目录。100% 指可测试的人工代码，不允许删除断言、降低阈值或忽略可达代码来过门。

一个步骤打勾前还必须：

- [ ] 对应 source→target manifest 已更新。
- [ ] 架构门禁通过，没有新增 allowlist。
- [ ] 资源生命周期测试通过。
- [ ] 中文/英文文档在同一提交更新。

### 1.8 安全、供应链与无障碍

- 真实密钥不得写入源码、assets、`--dart-define` 或 native config；Provider 凭据由 Provider CLI / OS 凭据存储管理。
- process 使用参数列表启动，不拼接 shell command；外部 ID、canonical path、symlink 与目录边界必须 fail closed。
- 最终 `pubspec.lock` 必须通过 OSV 漏洞扫描和依赖许可证检查；任何忽略项必须就地记录适用性理由。
- 无障碍目标固定为 WCAG 2.2 AA，覆盖 macOS / Windows / Linux。
- widget test 与 VoiceOver/Narrator/NVDA/Orca 手工 smoke 均按 AA 执行；reduce-motion 作为额外 VGV 平台门禁。

### 1.9 文档双语目录约定

- `docs/` 按语言分为 `docs/zh/` 与 `docs/en/` 两棵树。
- 两棵树的**子目录结构与文件名完全一致**；文件名不带语言后缀，语言由所在目录决定。
- 新增或修改文档时，两个语言版本必须在**同一个提交**里更新。
- 唯一例外是 `history/`：归档文档保持原语言不补译，另一侧放指向它的说明。
- 仓库根目录的 `README` / `CONTRIBUTING` 继续使用 `xxx.md` + `xxx.en.md` 后缀形式，不进 `docs/`。

---

## P-1 · 基线与 ADR

### 步骤 0 — 在旧 `dev` 清退 Cursor 代码

当前没有发布用户，不做兼容迁移或旧数据升级。只清理源码、fixture 和开发数据假设。

**状态：已完成。** 旧仓库提交：`b5c2f3e8`（2026-08-19）。经迁移裁决，旧仓库覆盖率只记录不设门禁：人工代码覆盖率为 83.97%（35,075 / 41,771）；analyze、format、test 全绿。新 VGV workspace 仍按 §1.7 执行 100% 覆盖率门禁。

- [x] 删除 `cursor_retirement_policy.dart` 及 barrel export。
- [x] 删除 provider factory/static capabilities/settings/turn-context/management/UI 的 Cursor 分支。
- [x] 删除 Cursor l10n 键、测试和 fixture。
- [x] `AgentProviderKind` 只保留当前产品需要的枚举；不为未发布 schema 保留兼容值。
- [x] 不修改 `zeta_storage_migrator` 去处理历史 Cursor 数据。
- [x] 旧仓库 analyze、format、test 全绿后提交；此提交之后停止功能开发。旧仓库 coverage 按上述裁决豁免。

### 步骤 1 — 固定最终基线与 source→target manifest

**状态：已完成。** 最终基线 `b5c2f3e8a9ac544e9832866e86ff633661c46053`；1,507 个跟踪文件全部唯一归类，生成器无 `UNCLASSIFIED` 且中英文渲染幂等。质量门：analyze 0 问题、format 0 changed、8 tests、人工 Dart coverage 100%（30 / 30）。

- [x] 记录最终旧仓库 commit SHA、clean status、Flutter/Dart 版本和 `pubspec.lock` hash。
- [x] 重新统计人工 Dart、generated Dart、test、ARB、native 与 assets。
- [x] 建 `docs/zh/architecture/migration_manifest.md` 与 `docs/en/architecture/migration_manifest.md`。
- [x] 每个 Git 跟踪文件恰好标记为 `move`、`rewrite`、`regenerate`、`delete` 或 `out-of-scope`。
- [x] native Runner、MethodChannel、pubspec、fonts/icons、CI 文件必须在 manifest 中。
- [x] 未跟踪 `.workflow/feature/2026-08-18-PC端构建与版本检查/` 明确不属于输入。

### 步骤 2 — ADR 与业务状态归属

**状态：已完成。** ADR-001—004 已接受；ownership map 已按最终基线复核 24 处 `ChangeNotifier/Listenable` 与 57 个 application 文件；`.architecture.yaml` 可解析并登记 1 个 contracts 例外包、14 个 Data 包、9 个 Repository 包，open decisions = 0。质量门：analyze 0 问题、format 0 changed、8 tests、人工 Dart coverage 100%（30 / 30）。

- [x] ADR-001：`agent_provider_contracts` 的模型例外、允许依赖和复核条件。
- [x] ADR-002：Flutter platform adapter 只位于 `lib/app/platform/`，Repository 依赖纯 Dart port。
- [x] ADR-003：Router 是导航标识唯一真源，session restore 只产生 initial location/redirect。
- [x] ADR-004：Conversation reducer/effect 边界——domain snapshot 聚合留 Repository，UI/交互状态进 Bloc。
- [x] 建逐类 ownership 表：旧 Controller/Store/Service → Data/Repository/Bloc/Presentation。
- [x] 建机器可读 `.architecture.yaml`：package layer、ADR-001、composition-root allowlist。
- [x] open-decision register 已清零，并记录 WCAG 2.2 AA / macOS / Windows / Linux 的最终决策。

**P-1 出口：已通过。** 最终 SHA 已固定；manifest 无未归属文件；ADR 和 ownership 表已同步中英文版本并通过机器校验。

---

## P0 · 工程地基

### 步骤 3 — 平台、身份与版本

**状态：已完成。** 平台目录、三平台身份、flavor 名称和版本均已完成；Windows 本地 debug/release 构建通过，GitHub Actions `desktop-build` 运行 `32220262496` 的 macOS、Windows、Linux × development、staging、production 共 9 个 release build 全部通过。质量门：analyze 0 问题、format 0 changed、8 tests、Dart coverage 100%（30 / 30）。

- [x] 删除新仓库 `android/`、`ios/`、`web/`。
- [x] 补齐 Linux desktop scaffold。
- [x] macOS、Windows、Linux 统一 application/bundle ID `cn.easii.zeta`。
- [x] 三个 flavor 的 product name 都为 `Zeta`，移除 `[DEV]` / `[STG]` 与 `.dev` / `.stg` 身份后缀。
- [x] `macos/Runner/Configs/AppInfo.xcconfig` 不再保留 `my_app` / `com.example.myApp`。
- [x] version 保持 `1.0.0+1`。
- [x] 三个 flavor 共用 `~/.zeta` 与同一 schema；文档说明不能并存安装。
- [x] 三平台、三 entrypoint 的空壳 build 通过。
  - [x] Windows：development/staging/production，debug 与 release。
  - [x] Linux：development/staging/production，GitHub Actions release。
  - [x] macOS：development/staging/production flavor，GitHub Actions release。

### 步骤 4 — Dart workspace 与依赖基线

**状态：已完成。** 根 workspace 已登记 25 个迁移目标包与 1 个仅供开发的 Widgetbook 工具包；全部使用 Flutter 3.47.0 / Dart 3.13.0、一致的 Very Good Analysis 配置和本地 `path:` 依赖。最终质量门：workspace `pub get` 成功解析 `test 1.31.1` / `test_api 0.7.12`，analyze 0 问题，format 111 files / 0 changed，26 个可测试 package root 共 99 tests 全绿，人工 Dart coverage 100%（132 / 132）；许可证门扫描 166 个 package、168 个许可证并通过，OSV-Scanner 与 Very Good CLI 版本已固定在 CI。

- [x] 根 `pubspec.yaml` 声明 Dart workspace members；不引入 Melos。
- [x] 统一 SDK 为根仓库约束，所有 package 继承一致版本。
- [x] 引入 `go_router`、`go_router_builder`、`build_runner`、`bloc_concurrency`。
- [x] 迁入当前功能依赖；不添加 updater/Velopack 依赖。
- [x] 所有本地包使用 `path:`。
- [x] 根与各包统一 Very Good Analysis。
- [x] 提交最终 `pubspec.lock`；CI 固定 OSV scanner 和 license checker 版本。

### 步骤 5 — Assets 与 l10n 基线

**状态：已完成。** 已从冻结基线逐文件迁入 Geist、JetBrainsMono、branding、三种 Agent 图标和三平台应用图标，23 个资产文件的 SHA-256 均与旧仓库一致；macOS 全部配置统一使用 `AppIcon` asset catalog，Windows RC 与 Linux bundle/resource loader 均指向迁入图标。脚手架西班牙语 ARB 已删除，en/zh 各 1,035 个消息键且 metadata/placeholder 集合一致；`required-resource-attributes`、escaping、format 与生成代码覆盖排除已合并，`l10n` / `l10nOrNull` 可用，连续两次代码生成幂等。质量门：analyze 0 问题，format 112 files / 0 changed，26 个可测试 package root 共 104 tests 全绿，人工 Dart coverage 100%（134 / 134）；Windows production release 构建通过。

- [x] 迁 Geist、JetBrainsMono、branding 和 agent icons。
- [x] 三平台应用图标与资源 manifest 对齐。
- [x] 删除脚手架西班牙语 ARB。
- [x] 迁当前 `dev` en/zh ARB；以步骤 0 后重新统计的键数为准。
- [x] 合并 `l10n.yaml`：required attributes、escaping、generated coverage exclusion。
- [x] 迁 `l10n` / `l10nOrNull` 扩展。
- [x] 生成代码成功，en/zh key set 完全一致。

### 步骤 6 — CI 与架构门禁

**状态：已完成。** `.architecture.yaml` 现已显式登记 contracts、Data、Repository、presentation、tooling 与三个 vendor client 集合；24 个架构契约测试覆盖 package/path 依赖、Flutter 隔离、composition root、platform adapter、外部 `src/`、typed navigation、Bloc 隔离、`app_ui` 和供应链例外。CI 按 27 个 workspace root 独立报告 analyze/format，并对 26 个含测试的 root 执行随机顺序 test + 100% coverage；Widgetbook 明确作为 tooling-only root 报告 analyze/format，无 test 目录。包括独立 golden job 在内的全部 CI test 调用均使用 Flutter-backed `very_good test`，且不传该命令不支持的 `--check-ignore`；generated `*.g.dart`、`*.freezed.dart`、`*.gen.dart` 通过 `--exclude-coverage` 离开 coverage 分母。Agent/MCP green-gate 调用仍按 §1.7 保留 `check_ignore: true`。最终本地同轮门禁：27/27 roots analyze 0 问题，format 116 files / 0 changed，26 个可测试 roots 共 128 tests，人工 Dart coverage 100%（134 / 134）。三平台 production 构建由 `desktop-build` 最近全绿运行 `32229542327` 证明。

- [x] 四门按 §1.7 固定顺序执行，workspace 每个 package 独立报告。
- [x] 架构测试读取 `.architecture.yaml` 并断言四层依赖。
- [x] 禁止 repository→repository、vendor client 互依、外部 `src/` import。
- [x] 禁止 `bootstrap.dart` 之外的业务代码 import Data；platform adapter 只允许 `desktop_platform_api` / Flutter services / 对应 plugin。
- [x] 禁止 `extra:`、裸路径导航、Bloc→Bloc 构造依赖。
- [x] 禁止 `app_ui` 依赖 Repository/Data/AppLocalizations。
- [x] CI 增加 test random ordering 和 golden tag job。
- [x] CI 增加 `pubspec.lock` OSV 扫描、依赖许可证检查和未解释 advisory 例外检查。
- [x] 三平台 CI 至少构建 production entrypoint。

**P0 出口：已通过。** 空工程三平台可构建；身份一致；workspace 和架构门禁在 CI 生效。

---

## P1 · 共享契约与基础设施

### 步骤 7 — `agent_provider_contracts`

- [x] 创建纯 Dart package，执行 ADR-001。
- [x] 迁 21 个 capability port、Provider bundle/factory、neutral event/session/thread/permission/plan/usage/input models。
- [x] 删除所有 TextCatalog/Fallback 类型；增加 typed failure/code。
- [x] 核验零 vendor 字段、零 IO、零 Flutter、零业务状态。
- [x] 对 sealed family、codec/pure model、Equatable/copyWith 补齐测试。

**状态：已完成。** package 已冻结 21 个 Provider port、35 个 `AgentEvent`
子类、27 个 capability flag、bundle/factory 表面及
`ResolvedCliProcessCommand`。所有公开集合字段均为防御性不可变快照，包含嵌套
诊断 payload；Provider 提供的内容可作为数据保留，Zeta 自有 status/failure/warning
文案则改为 typed code，由 Presentation 映射。按已批准的所有权拆分，attention 与
terminal signal 留在 contracts，turn activity state 与 elapsed 格式化留给后续
Bloc/Presentation。package 门禁：analyze 0 问题，format 52 files / 0 changed，
85 tests，人工 Dart coverage 100%（1,071 / 1,071）。冻结基线复核将原先的
36 个事件类型修正为 35 个；多计的一项是 `AgentTurnStartedEvent` 的重复构造路径，
并非额外子类。同一轮 workspace 最终门禁中，27/27 roots analyze 通过，format
检查 165 files / 0 changed；26/26 个可测试 roots 共 212 tests，人工 coverage
100%（1,204 / 1,204），Bloc lint 对 164 files 报告 0 issues。

### 步骤 8 — `zeta_logging` 与 `zeta_storage`

- [x] `zeta_logging` 迁 structured logging 和 sensitive-data redactor。
- [x] 所有日志出口默认脱敏；credential、prompt、Provider content 不进入结构化属性。
- [x] `zeta_storage` 只实现当前 schema 的原子读写、路径和 typed exception。
- [x] 不迁历史 SharedPreferences bridge 或旧版本升级逻辑。
- [x] 测临时目录、原子替换、失败不覆盖目标文件、路径错误与 close。

**状态：已完成。** `zeta_logging` 在 event 到达 listener、console 或 file sink
之前统一脱敏 message、error 与 stack；file sink 为私有实现，调用方不能绕过
`AppLogger`。structured prompt/content/payload/raw 字段整体遮挡，ignored-message
诊断只保留稳定 shape metadata，异常正文替换为宽泛类别，从而关闭旧版 console/error
原文输出的 **Critical** 风险。`zeta_storage` 已提供串行原子 UTF-8 替换、失败不覆盖、
close 语义、不含 migration marker 的当前 schema 路径、canonical absolute directory
解析，以及 sealed read/write/path/closed exception；旧版仅供 Presentation 使用的
`formatBytes` 明确不进入本包。package 门禁：43 tests，人工 coverage 100%
（399 / 399）。同一轮 workspace 最终门禁中，27/27 roots analyze 通过，format
检查 177 files / 0 changed；26/26 个可测试 roots 共 253 tests，人工 coverage
100%（1,601 / 1,601），Bloc lint 对 176 files 报告 0 issues。

### 步骤 9 — `json_rpc_transport`

**状态：已完成。** `json_rpc_transport` 现已拥有有界 JSONL stdio transport、
按 key 的 shared/exclusive operation scheduler 与 Provider runtime 生命周期门控。
`ProcessStarter`、`Clock` 和负责统一脱敏的 `AppLogger` 均可注入；测试不会启动
真实进程。sealed transport failure 覆盖 malformed/oversized frame、timeout、
process termination 与 closed connection。stderr 在离开包前脱敏，frame payload
不会进入诊断，close 或 process exit 会确定性取消 pending work。本包只依赖
`agent_provider_contracts` 已冻结的 runtime value type，不改任何 Provider port。
package 门禁：38 tests，人工 coverage 100%（540 / 540）。同一轮 workspace
最终门禁中，27/27 roots analyze 通过，format 检查 182 Dart files / 0 changed；
26/26 个可测试 roots 共 290 tests，人工 coverage 100%（2,140 / 2,140），
Bloc lint 对 181 files 报告 0 issues。

- [x] 迁 stdio transport、operation scheduler、runtime peer。
- [x] 定义 `TransportException` sealed family。
- [x] 构造注入 process starter、clock、logger。
- [x] 测 partial line、malformed JSON、timeout、cancel、stderr、process exit、double close。

### 步骤 10 — `desktop_platform_api` 与 app adapters

纯 Dart ports：

- [x] `SystemFontCatalogApi`，使用结构化不可变字体值。
- [x] `DesktopNotificationApi` / `DesktopAttentionApi`。
- [x] `FilePickerApi` / `DirectoryPickerApi` / `ClipboardApi` / `SystemFileManagerApi`。
- [x] `WindowBootstrapApi` / `WindowCommandApi` / `MenuCommandApi`。

Flutter adapters（仅 `lib/app/platform/`）：

- [x] MethodChannel system fonts、attention 和 native menu。
- [x] `flutter_local_notifications` adapter。
- [x] `file_selector`、pasteboard、window_manager、macos_window_utils adapter。
- [x] 每个 adapter 构造可注入 channel/plugin facade，widget/Bloc 不直接 import plugin。
- [x] platform port 只由 Repository 消费；Bloc/Presentation 直接 import `desktop_platform_api` 的架构测试为零容忍。
- [x] Dart contract test + macOS/Windows/Linux native channel contract test。

**P1 出口**：共享包独立全绿；平台插件 import 只存在于 allowlist。

**状态：已完成。** 经批准的契约校正保留结构化字体 identity、多图片文件选择、图片/文件
剪贴板读取、系统文件管理器启动、本地化原生菜单配置和窗口显示前 bootstrap，同时不向
共享边界暴露 Flutter 或 plugin 类型。所有 app adapter 均注入 channel/plugin facade；
source guard 只允许 `lib/app/platform/` 执行平台 IO，并禁止 Bloc/Presentation import
`desktop_platform_api`。CoreText、DirectWrite 与 Fontconfig runner 输出同一冻结字体 schema；
三平台均实现 badge/attention，macOS 额外实现版本化菜单 configure、enablement 与 command
callback。Step 专项测试包括 4 项纯 Dart package contract 与 30 项 app/native-channel 测试；
Windows Debug runner 已成功构建。最终 workspace 单轮门禁中，27/27 roots analyze 通过，
format 检查 206 个 Dart 文件且 0 变更；26/26 个 test roots 共 323 tests，人工 coverage
100%（2,454 / 2,454）；Bloc lint 对 205 个文件报告 0 issues。

---

## P2 · Provider 与 Management Data

### 步骤 11 — `agent_config_client`

- [x] 迁 provider config store/codec、model catalog cache、turn-context store/codec。
- [x] 只支持当前 schema；未知/损坏当前文件返回 typed decode failure，不做历史升级。
- [x] 不包含 CLI locator、选择状态或 Controller。
- [x] 临时目录测试全部读写/损坏/原子覆盖分支。

**状态：已完成。** 经批准的契约校正把 Provider settings 限定为 V2，并将损坏/不兼容
model cache 的读取从静默空结果改为 typed decode failure；未新增或修改 Provider 方法签名。
文件不存在仍按正常首次运行处理，返回空集合或 `null`。`agent_config_client` 现负责 Provider
定义、model catalog snapshot 与 thread 级白名单 turn metadata 的严格当前 schema codec 和
原子文件 store；非法 JSON、未知版本、字段结构错误、重复稳定 id、不安全路径片段与落盘
thread identity 不匹配均失败关闭，且 exception 不暴露原始文件内容或路径。active Provider
选择、CLI locator、历史迁移与 Controller 均未迁入。包级门禁为 25 tests，人工 coverage
100%（303 / 303）。同一轮最终 workspace 门禁中，27/27 roots analyze 通过，format 检查
212 个 Dart 文件且 0 变更；26/26 个 test roots 共 348 tests，人工 coverage 100%
（2,756 / 2,756）；Bloc lint 对 211 个文件报告 0 issues。

### 步骤 12 — `codex_app_server_client`

- [x] 迁 Codex provider、app-server client、mappers/codecs、process starter、CLI locator。
- [x] 迁 Codex history/usage 原始数据读取；只返回 Data model/neutral contract。
- [x] contract tests 覆盖 entryId、message chunk、terminal state、capabilities 和 approval mapping。

**状态：已完成。** `codex_app_server_client` 现独占 Codex app-server provider、JSON-RPC
client、协议 mapper/codec、permission adapter、进程恢复、唯一 CLI locator、本地 JSONL/thread
history、usage 映射和锁定的 `0.144.5` schema contract。barrel 只导出
`CodexProviderBundleFactory`、`CodexStaticCapabilities` 与 `CodexCliLocator`；factory 保留要求的
peer/process/logger/clock 注入缝，且未改任何共享 Provider port。协议测试覆盖稳定 entry identity、
流式 chunk、终态与错误、capability、approval/question、文件证据、malformed/future payload 和
lifecycle recovery。包级门禁为 168 tests，人工 coverage 100%（3,601 / 3,601）。
同一轮最终 workspace 门禁中，27/27 roots analyze 通过，format 检查 242 个 Dart 文件且
0 变更；26/26 个 test roots 共 515 tests，人工 coverage 100%（6,356 / 6,356）；Bloc lint
对 241 个文件报告 0 issues。

### 步骤 13 — `claude_code_client`

- [x] 迁 Claude provider、stream JSON peer、mappers/adapters、process starter、CLI locator。
- [x] 迁 history、quota、credential/keychain probe；凭据不落盘、不入日志。
- [x] contract tests 覆盖 permission/question/plan、identity、history 和 process lifecycle。

**状态：已完成。** `claude_code_client` 现独占 Claude stream-json provider、peer、协议
mapper/codec、permission/question/plan adapter、进程启动与恢复、唯一 CLI locator、本地历史、
模型/额度和只读 credential/keychain source。barrel 只导出 `ClaudeProviderBundleFactory`、
`ClaudeStaticCapabilities` 与 `ClaudeCodeCliLocator`；应用 localization/global logger 未迁入，
凭据只读、日志和异常均脱敏，且未修改共享适配层或 Provider port。Claude auth probe 仍归步骤 16，
token metering source 仍归步骤 21。真实 Claude Code 2.1.227 的无 Prompt initialize smoke 通过，
返回 5 个模型且唯一 default。包级四门为 264 tests，人工 coverage 100%（2,962 / 2,962）。
同一轮最终 workspace 门禁中，27/27 roots analyze 通过，format 检查 295 个 Dart 文件且 0 变更；
26/26 个 test roots 共 780 tests，人工 coverage 100%（9,317 / 9,317）；Bloc lint 对 294 个文件
报告 0 issues。

### 步骤 14 — `grok_acp_client`（已完成）

- [x] 迁 Grok provider、ACP codecs/mappers、process starter、CLI locator。
- [x] ACP 当前只有一个消费者，暂不抽共享包。
- [x] contract tests 覆盖 permission fail-closed、question/plan、identity、usage/history 和 malformed updates。

完成证据（2026-08-20）：barrel 只导出 bundle factory、静态 capability 与唯一 CLI locator；
Grok 私有 history reader/parser 随 vendor package 一并迁入，步骤 15 仍只负责跨 Provider 聚合。
包级门禁为 235 tests，人工 coverage 100%（3,257 / 3,257）；本机 Grok CLI 1.0.5 的真实 smoke
验证两个独立进程并发会话与新进程 `session/load` 恢复均通过。未修改共享 Provider port。
同一轮 workspace 门禁中，27/27 roots analyze/format 通过，26/26 test roots 共 1,014 tests，
人工 coverage 100%（12,573 / 12,573），Bloc lint 对 339 个文件报告 0 issues。

### 步骤 15 — `agent_history_client`（已完成）

- [x] 只保留跨 Provider history merge/replay 输入和通用容错。
- [x] vendor-specific parser 留各 vendor client，禁止重复实现。
- [x] 单条损坏可跳过并返回 typed warning；不得吞掉整体 IO failure。
- [x] 不生成 UI timeline card/projection。

完成证据（2026-08-20）：旧仓库没有可直接迁移的跨 Provider 聚合器，本包按既定契约新建
JSON Lines 外壳与 vendor decoder 注入边界。单条 malformed JSON、非 object 或显式 typed decode
failure 会被跳过并返回不含原始 payload 的 warning；整体 reader IO failure 与非预期 decoder
failure 原样抛出。后输入的同 id turn 在首次位置确定性覆盖，barrel 只导出 `history_merge.dart`，
且无 vendor、Flutter 或 Presentation 依赖。包级门禁为 5 tests，人工 coverage 100%（41 / 41）。
同一轮最终 workspace 门禁中，27/27 roots analyze/format 通过，26/26 test roots 共 1,018 tests，
人工 coverage 100%（12,613 / 12,613），Bloc lint 对 339 个文件报告 0 issues。

### 步骤 16 — `agent_management_client`

- [x] 迁三个 Agent management datasource、CLI process runner、Claude auth probe。
- [x] 提供 detect/test connection/read-write config/read logs 的 Data API。
- [x] 不依赖 `agent_provider_repository`，不保存选中 Agent/loading/progress UI 状态。
- [x] process、文件与 credential 分支全部使用注入 fake 测试。

**完成于 2026-08-20。** 本包现已承载 vendor-neutral management response、有界 CLI 执行、
可注入异步文件系统 IO、current-schema JSON/TOML 配置读取与原子写入、脱敏日志 tail，以及只保留
白名单字段的 Claude auth-status projection。vendor 自有 CLI locator 与无 Prompt protocol probe 均
通过注入复用，因此没有复制 locator，也没有修改共享 Provider port。包级门禁在 CI exclusion 下
运行 35 个随机顺序测试，人工 coverage 100%（329 / 329）。同一轮最终 workspace 门禁中，27/27
roots analyze/format 通过，26/26 test roots 共 1,052 tests，人工 coverage 100%（12,941 / 12,941），
Bloc lint 对 349 个文件报告 0 issues。

### 步骤 17 — Provider Data 集成门

- [x] 三个 vendor package 的 pubspec 互不可见。
- [x] CLI locator 每个 vendor 恰好一个实现和一个归属。
- [x] 现有协议 fixture 按 package 分配，无跨包 test import。
- [x] 真实 CLI 的只读 capability probe 冒烟；不启动会修改用户配置的操作。
- [x] 所有 process、stream、subscription 在 test teardown 可证明关闭。

**完成于 2026-08-20。** root architecture guard 现已持续约束三个 vendor package 互相隔离、每个
CLI locator 的声明唯一归属、test/fixture 只留在本包、5 个真实 CLI smoke harness 齐全，以及
runtime/process/stream/subscription 的显式 teardown 证据。缺失的两个 Codex smoke 脚本已经迁入；
Codex 与 Grok 新增 capability-only 模式，只执行 initialize（Codex 另执行 `model/list`），不认证、
不建 session、不发送 Prompt。本机只读 smoke 均通过：Codex 0.144.1（7 models）、Claude Code
2.1.227（5 models、1 default）、Grok 1.0.5（protocol v1、6 个 capability key、2 种 auth method），
并确认没有残留子进程。最终 workspace 同轮 27/27 roots analyze/format 通过，26/26 test roots 共
1,056 tests，人工 coverage 100%（12,941 / 12,941）；Bloc lint 对 350 个文件报告 0 issues。

**P2 出口**：Provider Data contract 全绿，三方隔离由 pubspec 和测试共同保证。

---

## P3 · 其余 Data

### 步骤 18 — `settings_client`

- [x] 迁 general/appearance store 与 codec，只支持当前 schema。
- [x] system font concrete implementation 不在本包；使用 `desktop_platform_api`。
- [x] 测缺失、空、损坏、权限拒绝、原子写失败。

**完成于 2026-08-20。** `settings_client` 现已提供 pure-Dart general schema v3 与 appearance
schema v1 codec、immutable 持久化 response、可注入 store，以及由 `AtomicTextFile` 支撑的生产
storage adapter。缺失/空白 clean-install 文档使用注入默认值；损坏或不支持的文档抛出不含原文的
typed failure，权限拒绝与 atomic write failure 原样传播。旧 Flutter `MethodChannel` font service 与
SharedPreferences migration 不进入本包；已有 `SystemFontCatalogApi` 端口保持不变，留给后续
Repository 步骤。包级 24 tests 全部通过，人工代码 coverage 100%（201 / 201），其中真实替换失败
测试证明旧文件保持不变。最终 workspace 同轮 27/27 roots analyze/format 通过，26/26 test roots 共
1,079 tests，人工 coverage 100%（13,141 / 13,141）；Bloc lint 对 357 个文件报告 0 issues。

### 步骤 19 — `workspace_client`

- [x] 下沉所有 `dart:io` 文件扫描、目录读取和 gitignore 输入。
- [x] `WorkspaceNodeResponse` 只反映外部文件系统；不保存 expanded/selected。
- [x] 测 symlink、权限拒绝、消失文件、大目录取消和 gitignore 边界。

**完成于 2026-08-20。** `workspace_client` 现已提供可注入的 pure-Dart filesystem boundary、可取消
且有界的 recursive scan、排序单层 directory read、带作用域的 raw gitignore input，以及由 caller
取消的 recursive watch stream。`WorkspaceNodeResponse` 只含 path/name/type。root/请求目录拒绝 link
与词法/canonical 逃逸；枚举从不跟随 link，跳过消失/不支持实体，并传播不含内容的 denied/IO
failure。gitignore matching policy 通过注入的 include/skip/prune filter 留给后续 Repository。包级
29 tests 全部通过，人工代码 coverage 100%（240 / 240），包含 1,000-entry cooperative cancellation
与 watch teardown。最终 workspace 同轮 27/27 roots analyze/format 通过，26/26 test roots 共 1,107
tests，人工 coverage 100%（13,380 / 13,380）；Bloc lint 对 367 文件报告 0 issues。

### 步骤 20 — `project_session_client`

- [ ] 迁 IDE session store 和当前 snapshot codec。
- [ ] Data model 不互引 Bloc State。
- [ ] 测 current schema round-trip、损坏文件、debounced write cancel 和 close flush。

### 步骤 21 — `usage_statistics_storage_client`

- [ ] 迁 usage partition/cache/index 的当前 schema。
- [ ] Codex/Claude/Grok 原始数据 reader 留在各 vendor client。
- [ ] cache 是可重建派生数据；损坏时清空并重算，不伪造成功。
- [ ] 测时间边界、分区、空源、取消扫描、缓存失效和大 fixture。

**P3 出口**：app feature 无 `dart:io`；所有外部数据入口可用纯 Dart fake 测试。

---

## P4 · Repository

### 步骤 22 — `agent_provider_repository`

- [ ] 构造注入 `agent_config_client` 和三方 bundle factory/catalog port。
- [ ] 提供 config snapshot/changes、bundleFor、model/mode/skill/permission catalog。
- [ ] 不依赖 conversation/management repository。
- [ ] model/permission/mode selection 的 UI 状态不进 Repository；只持久化显式输入。
- [ ] client exception → typed provider domain failure，保留 cause/stackTrace 供日志。

### 步骤 23 — `agent_conversation_repository`

- [ ] 构造函数不接收 `agent_provider_repository`。
- [ ] `openConversation` 接收 Bloc 已解析的 `AgentProviderBundle` / key。
- [ ] 迁 event pipeline、coalescing、dispatcher、domain reducer/effect、timeline aggregate、runtime registry/lease、turn context。
- [ ] Stream 只暴露 domain timeline snapshot；提供同步 snapshot。
- [ ] live/history/replay 使用独立 reducer 实例。
- [ ] 测 event storm、乱序拒绝、旧 runtime generation、backpressure、close、lease release。

### 步骤 24 — `agent_management_repository`

- [ ] 构造注入 management/config clients，不依赖 provider repository。
- [ ] detect/test/config/log response → management domain model。
- [ ] configuration validation 是 Repository 的纯 domain 方法，但 UI 只能通过 Bloc event 调用。
- [ ] 不保存 selected agent、progress、loading 或本地化 message。

### 步骤 25 — Settings / Workspace / Project Session Repository

- [ ] `settings_repository`：domain settings、系统字体转换、current schema 持久化。
- [ ] `workspace_repository`：index/query/tree 数据；expanded/selected 在 WorkspaceCubit。
- [ ] `project_session_repository`：session snapshot 与 thread catalog；search/selection/load status 在 Bloc。
- [ ] 三个包互不依赖，可共享 Data port 但不能共享 Repository。
- [ ] 测所有 Data exception 转换和 external-data Stream。

### 步骤 26 — Usage / Desktop Notifications / Desktop Platform Repository

- [ ] `usage_statistics_repository` 聚合三方 Data 和 cache，返回 report domain model；filter selection 在 Bloc。
- [ ] `desktop_notifications_repository` 只接受已本地化 copy 和中立 notification request。
- [ ] notifications repository 不依赖 settings repository。
- [ ] `desktop_platform_repository` 包装 directory picker、clipboard、window/menu ports，供 Bloc 使用，零 Flutter。
- [ ] 所有包零 Flutter/ChangeNotifier/ValueNotifier。

**P4 客观出口**：

- [ ] repository→repository dependency = 0。
- [ ] Repository Flutter dependency = 0。
- [ ] Repository 中 UI selection/loading/expanded 状态 = 0。
- [ ] `bootstrap.dart` 外 app 业务代码的 Data/IO import = 0。
- [ ] 每个 Repository package 独立四门全绿。

---

## P5 · app_ui 与 l10n

### 步骤 27 — `packages/app_ui`

- [ ] 无障碍基线固定为 WCAG 2.2 AA / macOS / Windows / Linux。
- [ ] 迁设计 token、基础组件、Workbench 原语、虚拟滚动与 WindowFrame 纯 UI 部分。
- [ ] 保留 shadcn_flutter，统一 `as sf` import。
- [ ] 一文件一公开组件、barrel、const constructor、公开 API dartdoc。
- [ ] token 走 ThemeExtension；不得依赖 Repository/Data/AppLocalizations。
- [ ] 组件文案全部构造参数传入。
- [ ] 每个公开组件有行为 widget test；视觉属性有 tagged golden。
- [ ] AA 测试覆盖 semantics、键盘/焦点、async live region、拖拽替代与焦点不被遮挡。
- [ ] 普通文本对比度 ≥4.5:1、大文本 ≥3:1、UI/焦点指示 ≥3:1；200% 文字缩放不丢失内容。
- [ ] 交互目标 AA 下限为 24×24 dp，设计目标为 VGV 48×48 dp；reduce-motion 作为额外平台门禁。

### 步骤 28 — l10n typed mapping

- [ ] 删除 4 组 TextCatalog/Fallback 与 `ZetaTextCatalogs`。
- [ ] 下层改为 typed failure/code；`lib/l10n/failure_messages.dart` 穷尽映射。
- [ ] `ZetaShadcnLocalizations` 和 shadcn ARB keys 留 app。
- [ ] 建无 BuildContext 的 `DesktopNotificationCopyResolver`，由 bootstrap 按冻结 Locale 注入。
- [ ] 核验 en/zh keys、placeholder metadata、escaping 完全一致。
- [ ] packages 的 `AppLocalizations` import = 0。

**P5 出口**：app_ui 独立全绿；中英文 UI smoke；仓库无 TextCatalog 残留。

---

## P6 · 小 Feature Bloc 与 Presentation

### 步骤 29 — Workspace / Settings / Desktop Notifications

**WorkspaceCubit**

- [ ] index/invalidate/toggle/select/reveal 方法；expanded/selected 只在 State。
- [ ] index 使用 `restartable()` 等价取消；reveal/目录选择走 `desktop_platform_repository`。

**SettingsCubit**

- [ ] load/persist/font catalog/language restart result。
- [ ] persistence 写按 `sequential()`；快速外观选择按明确策略合并。

**DesktopNotificationsBloc**

- [ ] 同时注入 settings 与 notification repository，不依赖 SettingsCubit。
- [ ] attention stream、visibility、read 状态和 badge 在一个 Bloc。
- [ ] copy resolver 无 BuildContext；notification side effect 顺序化。

- [ ] 每个 feature 建 Page/View/barrel、blocTest、MockBloc widget test。

### 步骤 30 — Project Threads / IDE Session

**ProjectThreadsBloc**

- [ ] project activation、search、archived filter、load initial/more、rename/archive/delete、runtime sync。
- [ ] search `restartable()`；load more `droppable()`；write operation `sequential()`。

**IdeSessionCubit**

- [ ] restore/save/flush；只保存业务 snapshot，不保存 GoRouter 对象。
- [ ] restore 产出 initial route input，由 app router redirect 消费。

- [ ] 两者不互相依赖；联动在 app composition/BlocListener。

### 步骤 31 — Agent Management / Usage Statistics

**AgentManagementBloc**

- [ ] selected agent、detect progress、test status、config editor validation、logs 全进 State。
- [ ] detect `droppable()` 或显式 cancel；选中切换后的 load `restartable()`；写配置 `sequential()`。
- [ ] UI 不直接调用 Repository validator。

**UsageStatisticsBloc / AgentUsagePanelCubit**

- [ ] filter/preset/project/provider/model/rank selection 全进 app State。
- [ ] refresh `restartable()`；重复 refresh `droppable()`；结果用 query generation 防旧值覆盖。
- [ ] fl_chart widgets 只接收已计算 domain points。

**P6 出口**：小 feature 形成统一迁移手法；无 Bloc→Bloc、Widget→Repository、隐式 async concurrency。

---

## P7 · Agent 会话

### 步骤 32 — `AgentConversationBloc`

- [ ] State 保留 header/composer/pending/expansion/history 五个 slice，全部 Equatable。
- [ ] Bloc 同时注入 provider 与 conversation repositories；先解析 bundle，再 open conversation。
- [ ] timeline subscription 使用 key/generation，切换时取消旧源。
- [ ] message submit/cancel/steer、model/mode/skill/permission selection、thread 操作全部事件化。
- [ ] permission response、question response、plan approval、plan execution handoff 使用独立 event 和 repository method。
- [ ] 四种安全语义按 `sequential()` 处理，测试任一事件不会预授权其他语义。
- [ ] 展开态和 UI 派生 getter 留 Bloc State/selector；Markdown/render cache 不进 State。
- [ ] `close()` 释放 subscription、conversation key、cache lease 和 timer。

### 步骤 33 — Agent Presentation、Capability 与性能

- [ ] Page 创建 Bloc；所有 widgets 改 BlocBuilder/BlocSelector，只订阅所需 slice。
- [ ] file selector、pasteboard 等通过 Bloc event + `desktop_platform_repository`，不直接 import plugin 或 Data port。
- [ ] 拆分 >1.5k 行的三个 presentation 文件；不做视觉重设计。
- [ ] 19 个 optional capability 各有“入口不出现”widget test。
- [ ] UI 误调用 unsupported capability 得到 typed fail-closed state。
- [ ] 迁 harness、event-storm、timeline projection、virtual scroll tests。
- [ ] 记录旧 `dev` 与新实现的长 timeline frame time、memory peak、高频 delta 合并指标；不得回退。
- [ ] Codex/Claude/Grok 真实 CLI 会话冒烟。

**P7 出口**：审批安全、事件顺序、provider switch、长时间线性能和资源关闭全部通过。

---

## P8 · Shell、Router 与收口

### 步骤 34 — `IdeShellBloc` 与 typed GoRouter

- [ ] `IdeShellBloc` 只保存 shell 业务状态，不保存另一个 Bloc 或 router location。
- [ ] 建 `@TypedShellRoute` 与 `/home`、project、thread、settings、agent management、usage routes。
- [ ] canonical project path → stable URL-safe projectId，并由 Repository 解析；URL 不直接放文件路径。
- [ ] session restore 计算 initial location/redirect；invalid ID redirect `/home`。
- [ ] menu action bridge 与 UI menu 使用生成 typed route。
- [ ] window/menu 命令通过 `desktop_platform_repository`；Bloc 不直接 import platform API。
- [ ] 禁止 `extra`、裸 path、Navigator push/pop。
- [ ] 测 restore、redirect、back、invalid/deleted project/thread、menu navigation、Page Bloc scope。

### 步骤 35 — Bootstrap、平台与 flavor 装配

- [ ] `bootstrap.dart` 构造全部 client、platform adapter、repository，再传给 App。
- [ ] `MultiRepositoryProvider` 只提供 Repository；Bloc 按 global/shell/route/conversation scope 创建。
- [ ] AgentConversationBloc 每个 workspace entry 一个实例并随 entry 关闭。
- [ ] 三个 flavor 使用同一 `cn.easii.zeta` / `Zeta` / `~/.zeta` / schema。
- [ ] 迁 window bootstrap、native menu、fonts、notification/badge、file selector、clipboard。
- [ ] 手写 macOS/Windows/Linux Runner 与 channel contract 全部从 manifest 勾销。
- [ ] 无 updater/Velopack channel、dependency 或 packaging hook。

### 步骤 36 — 最终验证与文档收口

- [ ] workspace 所有 package 同一最终迭代四门全绿，并记录测试数和覆盖率。
- [ ] macOS/Windows/Linux × development/staging/production build 通过；production release 冒烟。
- [ ] 空 `~/.zeta` 干净启动，创建当前 schema；不跑历史升级 fixture。
- [ ] en/zh 两次 UI smoke，Locale 冻结、无缺键。
- [ ] 按 WCAG 2.2 AA 完成 macOS VoiceOver、Windows Narrator/NVDA、Linux Orca 和纯键盘 smoke；记录 Linux 已知限制。
- [ ] 三路真实 CLI 端到端冒烟。
- [ ] event storm、长 timeline、process/subscription/timer/lease close 验收。
- [ ] `.architecture.yaml` 全部门禁通过，无未登记例外。
- [ ] OSV 扫描与依赖许可证检查通过；无未解释的 advisory/license 例外。
- [ ] secret scan、日志脱敏、process 参数化、路径/symlink 负向测试通过。
- [ ] manifest 每个文件已闭环，无 `app_update`/Velopack/packaging 遗留。
- [ ] 更新 `architecture/overview`、`layering`、`engineering_standards`、`design_document`、developer/internationalization/navigation guides 和 `CONTRIBUTING.md` 的中英文版本。
- [ ] `docs/zh/` 与 `docs/en/` 子目录结构一致、同名文件成对存在（`history/` 除外），且无死链。

---

## 附：最终客观指标

| 指标 | 目标 |
| --- | ---: |
| repository→repository dependencies | 0 |
| Data/Repository Flutter dependencies | 0 |
| vendor-client cross dependencies | 0 |
| business-code imports of Data / `dart:io` / Flutter services outside allowlist | 0 |
| external imports of package `src/` | 0 |
| packages imports of `AppLocalizations` | 0 |
| TextCatalog/Fallback remnants | 0 |
| Bloc→Bloc constructor dependencies | 0 |
| GoRouter `extra:` / raw-path navigation | 0 |
| migrated app-update/Velopack/packaging files | 0 |
| unexplained vulnerability/license exceptions | 0 |
| WCAG 2.2 AA blocking findings | 0 |
| testable hand-written Dart/Flutter coverage | 100% per package |
| unassigned files in migration manifest | 0 |

任何指标未达成，步骤 36 不得完成。
