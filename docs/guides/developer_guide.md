# 开发者文档

最后更新：2026-08-15

## 1. 项目简介

Zeta 是一个 Flutter Desktop 项目，当前支持 macOS、Linux 和 Windows 平台目录。应用主入口在 `lib/main.dart`，核心界面是三栏 Agent IDE 工作台。

## 2. 环境要求

- Flutter SDK，需兼容 `pubspec.yaml` 中的 Dart SDK 约束 `^3.12.2`。
- 支持 Flutter desktop 的本地开发环境。
- 如需运行默认 Agent provider，需要本机可执行 `codex app-server`；未指定
  `--listen` 时使用 stdio。
- Codex 适配层按 pinned schema 开发；协议版本与升级流程见
  [Codex app-server 协议版本锁定](../protocols/codex_app_server_protocol.md)。
- 如需使用 Grok ACP，建议安装 Grok CLI（grok-build）`0.2.119` 或更高版本。
  `0.2.119` 是 Zeta 的 Grok 多会话兼容基线；此前版本不支持多会话，在同时打开或执行
  多个 Grok 会话时可能出现会话状态、流式通知或回合终态无法正确隔离的问题。
- 如需使用 Claude Code，需本机可执行 `claude`；Claude.ai 交互式登录命令是
  `claude auth login`。当前 stream-json 取样基线为
  CLI `2.1.224`（不是最低版本承诺），详见
  [Claude Code stream-json 协议基线](../protocols/claude_code_stream_json_protocol.md)。
- 当前活跃 Provider 为 Codex、Grok 与 Claude Code。Cursor 已退役，不参与 catalog、UI、
  运行时组合、进程启动或会话恢复；旧配置仅用于 unavailable/fallback 兼容。

## 3. 常用命令

```sh
flutter pub get
dart format .
flutter analyze
flutter test
flutter run -d macos
flutter gen-l10n
dart run tool/check_localized_ui_strings.dart --check
```

开发中的快速回归使用 `tool/test_fast.ps1`（Windows）或
`bash tool/test_fast.sh`（macOS / Linux / Git Bash），它会排除 `slow` 标签。
提交前使用 `tool/test_full.ps1` 或 `bash tool/test_full.sh` 覆盖全部测试；完整入口会
生成 `.dart_tool/test-results/full.json`，并在终端列出最慢的测试文件与用例。
`dart_test.yaml` 的 `concurrency: 2` 是内存保护门禁，不因提速而调整。

重新导出 Codex app-server JSON Schema（协议升级 / 审计时）：

```sh
# macOS / Linux / Git Bash
./tool/gen_codex_schema.sh

# Windows PowerShell
./tool/gen_codex_schema.ps1
```

对真实 `codex app-server --stdio` 做核心链路与 Plan experimental 冒烟：

```sh
python tool/smoke_codex_app_server.py --expected-version 0.144.5
python tool/smoke_codex_plan_mode.py --expected-version 0.144.5

# 兼容性诊断可指定其他本机 CLI；省略 expected version 不等于通过目标版本门禁
python tool/smoke_codex_plan_mode.py --codex-bin "C:\...\codex.exe" --timeout 180
```

Plan smoke 会开启 experimental API、探测模式目录、发送 Plan / Default turn、结构化回答
一次用户提问，并模拟重启恢复。它使用临时只读 workspace，默认归档测试 thread，输出不含
Prompt、回复、文件内容、凭证、原始 JSONL、thread/turn id 或 stderr 原文。若
`turn/plan/updated` 等实验事件缺失，脚本会保留实际方法名级诊断并返回失败。

Cursor 的旧 smoke 与发布材料只作为
[退役历史证据](../history/cursor_acp_release_validation.md) 保留，当前版本没有 Cursor 启动工具。

Linux 或 Windows 开发时，将 `flutter run` 的设备改为对应桌面设备。

## 4. 目录结构

```text
lib/
  main.dart
  src/
    app/
      localization/
    core/
    features/
      agent/
        application/
        data/
        domain/
        presentation/
      agent_management/
        application/
        data/
        domain/
        presentation/
      desktop_notifications/
        application/
        data/
        domain/
      ide_session/
        application/
        data/
        domain/
      project_threads/
        application/
        domain/
        presentation/
      settings/
        application/
        data/
        domain/
        presentation/
      usage_statistics/
        application/
        data/
        domain/
        presentation/
      workspace/
        application/
        domain/
        presentation/
    ui/
      core/
      features/ide/
      localization/
        arb/
        generated/
test/
docs/
tool/
third_party/
  codex_app_server_schema/
linux/
macos/
windows/
```

重要模块：

- `lib/src/app`：应用装配、窗口启动、菜单桥接、shell controller 和常量。
- `lib/src/app/localization`：启动冻结 Locale、`ZetaLocalization` delegates，以及
  按 feature 拆分的不可变文本目录适配器。
- `lib/src/core`：日志、`~/.zeta` 路径布局、原子文本写入等跨功能基础设施。
- `lib/src/features/agent`：Agent provider 抽象、Codex app-server、Grok ACP、Claude Code
  stream-json、
  共享事件映射、纯同步 conversation reducer、事件 processor、scope-aware effect runner、
  类型化 UI 更新端口、presentation frame scheduler、对话状态和 Agent pane。无 pump 的
  调度单测使用 `FakeAgentFrameScheduler` 手动推进 frame。
- `lib/src/features/agent_management`：Codex/Grok/Claude Code CLI 检测、身份/版本/账号
  诊断、显式连接测试、配置安全编辑和 Agent 管理页面。自动检测不调用模型；Claude Code
  的连接测试只发无 Prompt initialize，但 CLI 仍可能维护自身认证/bootstrap 缓存。
- `lib/src/features/desktop_notifications`：Agent attention 去重、可见性抑制、
  系统通知插件适配和三端任务栏/Dock/urgency MethodChannel。
- `lib/src/features/ide_session`：IDE 会话模型、状态构建、恢复协调和持久化。
- `lib/src/features/project_threads`：项目 thread 列表状态、恢复快照、分页控制器和 view model；
  打开中 thread 的执行中/等待态由常驻 workspace 的 `threadSnapshot` 经
  `syncRuntimeSnapshot` 写入，不依赖 shell 单路 provider 事件流。
- `lib/src/features/settings`：常规/外观设置，含 `AppLanguage` 与 `general.json` v3 codec。
- `lib/src/features/usage_statistics`：Codex 全局历史读取、版本化派生索引、统计聚合
  controller、响应式统计页面和任务详情抽屉。
- `lib/src/features/workspace`：工作区目录规则、文件树构建、文件节点映射和 file tree pane。
- `lib/src/ui/core`：主题、窗口框架、pane、panel、`IdeChip`、empty state 和状态标签等共享 UI 原语。
- `lib/src/ui/features/ide`：IDE shell 视图、项目列表 pane 和 active provider controller。
- `lib/src/ui/localization`：ARB、generated `AppLocalizations`、`context.l10n`、
  Zeta shadcn 适配器与相对时间静态 token。
- `test/src`：app、core、feature 各层的单元测试和 widget 测试。
- `tool/`：仓库维护脚本（含 Codex schema 导出、真实 CLI smoke 与
  `check_localized_ui_strings.dart`）。
- `third_party/codex_app_server_schema/`：pinned Codex app-server JSON Schema 快照。

桌面通知不得从 Provider raw payload 直接组装；应复用归一化
`AgentAttentionSignal`，并保证正文不含 prompt、回复、命令和完整路径。扩展事件类别或
平台行为前先阅读
[Agent 桌面通知与任务栏未读提醒详细设计](../architecture/desktop_agent_notification_design.md)。

## 5. 开发流程

1. 修改前先理解目标模块的现有职责和依赖方向。
2. Dart 文件改动后运行 `dart format .`。
3. 完成代码改动后运行 `flutter analyze`。
4. 修改行为或新增逻辑时运行 `flutter test`，并补充对应测试。
5. 如果平台生成文件发生变化，确认是否由 Flutter 工具产生，并在提交说明中解释原因。

## 6. 编码约定

- 使用现代空安全 Dart。
- 优先使用 `const` 和不可变 widget。
- UI 状态简单时使用 Flutter 内建机制，例如 `StatefulWidget`、`ChangeNotifier`、`ValueListenableBuilder`。
- 复杂状态按“不可变 domain state + application controller + presentation view model/listenable signal”拆分。
- 对可能被后续请求覆盖的异步流程使用 token 或版本号隔离旧结果。
- 对外暴露集合时优先返回不可变集合或 unmodifiable view。
- 公共 API 添加 `///` 文档。
- 新实现中，对公共 API、协议适配、状态机、错误处理和不直观分支优先补充中文注释。
- 不使用 `print`，需要保留的诊断信息使用 `dart:developer` 或项目日志封装。

更完整的架构和评审规则见 [工程规范](../architecture/engineering_standards.md)。

## 7. Agent provider 开发指南

Provider 实例只由 app 组合层的 `AgentProviderRuntimeRegistry` 创建和销毁；任何其他
文件调用 `AgentProviderBundleFactory.createBundle` 都是架构错误。会话前/全局操作通过
`AgentProviderGlobalRuntime` 使用每个 Provider ID 唯一的 global 实例，包括项目列表、
历史、用量、连接检测、模型和 Skill 目录；global 不参与空闲回收。

每个逻辑会话由 `AgentConversationBinding` 聚合，以 `draft(providerId, entryId)` 或
`thread(providerId, threadId)` 为稳定 key。Workspace 只持有 Binding lease；新建/打开
和历史读取不创建 session runtime。只有用户第一次提交输入时调用 `beginTurn()`，随后
start/resume/send；其他 session RPC 只能 `runCurrent()`，runtime 不存在时 fail-closed。
Binding 生命周期必须显式区分 dormant、starting、attached 与 cleared；消费者不得根据
`currentRuntime == null` 猜测断连。只有曾 attached 且匹配精确 runtime identity 的 cleared
转换可以中断当前 turn，首次初始化失败继续走本次请求的失败收尾。
Workspace 创建真实 thread entry 时必须同时注入匹配的 thread summary 与 Binding；一个
ViewModel 的 thread 身份固定，不提供 `switchThread` 或带 restored session/provider 的通用
workspace 更新入口。project/file context 更新不改变会话，选择另一 thread 就选择另一 entry。
草稿拿到 threadId 后原子晋升，冲突必须拒绝。Binding Manager 每分钟 single-flight
扫描，没有运行中 turn/RPC 且空闲满 10 分钟的 runtime 按精确 identity 条件回收；旧进程
dispose 完成前同 scope acquire 必须等待。配置失效会同时清理 global 与全部 session，
窗口退出等待 registry 完成清理。
Registry acquire 必须显式选择 global/session scope；使用统计面板只通过 global runtime
访问中立 quota 端口，不接受 raw Provider/lease loader 兼容路径。

新增 provider 时：

1. 先确认现有 `AgentProviderBundle` 端口是否足够。能力域接到
   `conversation`、`threadCatalog`、`threadSubscription`、`threadNaming`、
   `threadArchival`、`threadDeletion`、`threadCompaction`、`threadBranching`、
   `turnSteering`、`permissionResponses`、`questions`、`deniedActionOverride`、
   `modelCatalog`、`localThreadList`、
   `sessionConfiguration`、`planApproval`、`conversationModes`、`skills`、
   `permissionPolicy` 等端口。不支持的端口必须为 `null`，禁止 no-op 或
   `UnsupportedError` 伪实现。controller / ViewModel 必须始终停留在中立端口边界。
2. 在 data 组合层声明初始化前可判断的静态 `AgentProviderCapabilities` 与 bootstrap
   policy（见 `AgentProviderStaticCapabilities`）；不要往 Shared Domain 增加厂商命名
   默认值或 `defaultsFor(kind)`。握手后若能力发生变化，由 `runtime.capabilities`
   返回更精确的动态值。
3. 在 data 层新增具体 provider 实现，只实现真实支持的中立端口，并由
   `AgentProviderBundleFactory.createBundle` 直接返回原生 Bundle。application /
   presentation 只接收 bundle 端口。
4. 把 provider 原始事件映射成 `AgentEvent`、`AgentToolCall`、
   `AgentPermissionRequest`、`AgentQuestionRequest`、`AgentThreadSummary`、
   `AgentSessionConfigOption` 等中立模型。
   Provider 原始 `sourceItemId` / `sourceMessageId` 只作为 source metadata；进入 application
   前必须由 adapter/reducer 生成最终 entryId。文件变更同样要在 Provider-local tracker 中
   形成完整 `AgentFileChangeSnapshot`，不得把 partial/raw 留给 Store 或 UI 补齐。
5. 如果出现新的可选能力域，优先新增 bundle 可选端口及其测试；不要把非通用能力
   直接做成所有 provider 的必选方法。旧 `AgentProvider` 大接口已删除，不得恢复。
6. ACP provider 复用无状态 `AcpSessionUpdateDecoder`、`AcpPermissionMapper`、
   `AcpContentCodec` 和 `AcpSessionConfigMapper`；每个厂商自行实现 adapter/reducer，决定
   message segment、reasoning phase、tool upsert、去重和 lifecycle。共享 ACP 文件不得
   包含厂商分支或 eventId/turn scope 叙事策略。
7. 在 factory 中接入 provider kind。
8. JSON-RPC provider 必须把裸 peer 包装为 `ProviderRuntimeJsonRpcPeer`，在握手成功后
   `markReady`、失败时 `markFailed`；dispose 先 `beginClosing`，再收尾 pending 交互和关闭 peer。
9. Thread 的 list/read 与变更操作必须通过 `ProviderOperationScheduler`：list/read 使用
   Project/Thread `sharedRead`，resume/fork/rename/archive/delete/compact 使用 Thread
   `exclusive`；不要在持有资源键时再次调度同键操作。
10. 添加单元测试覆盖初始化、session、turn、权限请求、capability gate、生命周期门控、
    调度顺序和错误映射；已迁移能力域至少补 `AgentProviderBundle` 端口一致性测试，并
    回归 `AgentConversationViewModel` / `ProjectThreadsController` 的使用路径。
11. 为流式 Provider 增加 adapter/reducer 序列测试；若同时支持 history/replay，必须使用
    独立 reducer 实例，并用完整 canonical signature regression 比较相对顺序。Store 只按
    entryId/tool id dumb merge，新增 Provider 不得修改 Store 来补叙事规则。
12. 增加 Binding 生命周期测试：创建/打开/读历史不启动 session，首次 `beginTurn` 才创建；
    同一 Binding 最多一个实例，不同 thread 各自独立。覆盖 draft 晋升、TTL、运行中 turn/RPC、
    重叠 sweep、ABA identity、dispose/acquire 屏障、配置失效、旧 generation 丢弃与 global
    永不回收；同时断言 starting 不产生中断、初始化失败回到 dormant、只有匹配 identity 的
    cleared 才结算中断。任一 session 的恢复、发送或结束不得污染其他 session 的事件、权限或 reducer。
    fork 必须覆盖真实 thread A → 新 thread B：返回的 session 通过 Shell 通用新 thread
    登记/选择流程进入列表，B 使用独立 Entry/Binding 并成为当前选择，A 不改绑，随后
    rename/send 只能作用于 B；普通 fork 不得提前创建 B 的 session runtime。

### 文件变更证据接入

文件变更不是独立 Provider capability，也不新增端口；它是现有 tool/turn 事件中的中立 typed
payload。Provider 在事件进入共享 pipeline 前负责把协议事实投影为完整
`AgentFileChangeSnapshot`：

- owner/change id、顺序、动作、`revision`、`replayability` 和 partial 更新的 last-valid
  规则都属于 Provider-local mapper/tracker；同一 owner 的每次更新必须是完整替换。
- `fileChanges == null` 表示没有结构化文件证据；空 `changes` 是权威清空。evidence 为 `null`
  只表示路径/动作摘要，不是隐藏的第四种正文格式。
- replacement 只表示替换片段，written content 只表示请求写入的内容，unified patch 只表示
  Provider 给出的补丁。空字符串是合法显式值，不得据此猜新建、删除或字段缺失。
- 同一 tool 的 status/terminal 更新必须继续携带完整 snapshot；Store 不负责“新值为空时保留旧值”。
- 只有命令、审批参数或工作区结果时不生成 snapshot；禁止解析命令、读取当前文件或运行 Git
  diff 补证据。presentation 可以高亮 typed patch，但不能从 header 反推路径、动作或 identity。
- live/history/replay 分别创建 tracker/reducer。`replayable` 做逐位置 canonical 回归；
  `liveOnly` 在 UI 明确标为实时降级，不计作历史恢复。

当前 Provider 映射：

| Provider 输入 | 输出 |
| --- | --- |
| Grok ACP `content[type=diff]` | 路径 + replacement；Grok tracker 在重复、status-only 和终态更新中携带完整快照 |
| Claude Code `Edit` | `file_path/old_string/new_string/replace_all` → replacement；`tool_result` 复用 `tool_use` 快照 |
| Claude Code `Write` | `file_path/content` → written content；没有协议动作时保持 unknown |
| Claude Code `NotebookEdit` / `MultiEdit` | 仅已确认路径 + unknown 摘要，不解析未知结构 |
| Codex `fileChange` / `patchUpdated` / history ThreadItem | replayable tool-scoped unified patch |
| Codex `turn/diff/updated` | 没有 tool 证据时的 typed `liveOnly` fallback；后到 tool 证据由 Codex tracker empty-clear |
| Codex `commandExecution` | 普通 execute tool；不产生文件变更 snapshot |

fixture 必须标明真实采样或 schema provenance，并用合成 sentinel 替换正文、路径和 id。文件
evidence 只在内存时间线存在，不得进入日志、缓存、通知、thread summary 或持久化 JSON。

交互响应按领域语义拆分：权限请求调用 `respondToPermission`；结构化用户提问仅由实现
`AgentQuestionResponseProvider` 的 Provider 通过 `respondToQuestion` 回写，空 answers
表示 Skip；计划审批仍使用 `AgentPlanApprovalPort`。三类请求可以共享 Pending Interaction
Dock，但不得共享 request/decision 模型或 pending registry。

Claude Code 的 `AskUserQuestion` 在 stdio host 下包在 `can_use_tool` control_request 中，
但领域语义仍是用户提问。Claude data adapter 必须在 remembered permission 与普通权限
handler 之前识别它，映射问题和选项，并通过独立 question pending registry 回写
`updatedInput.answers`；不得把它保存为工具 allow/deny 决定。

### 权限选项选择（Permission Policy Port）

- **端口**：实现 `AgentPermissionPolicyProvider` 的 Provider 经
  `AgentProviderBundle.permissionPolicy` 暴露 `AgentPermissionPolicyPort`。
  UI / application 只调用 `listPermissionOptions` 与 `applyPermissionSelection`；
  已删除 `listPermissionProfiles` / `updatePermissionSelection` 及旧 capability 位。
- **中立模型**：`AgentPermissionOption`（id/label/description/allowed）与
  `AgentPermissionSelection(optionId)`。共享层不得解析 `:workspace`、`yoloMode`、
  `approvalPolicy` 等协议字符串。
- **default vs effective**：
  每个 `AgentConversationBinding` 独占一个不可变的
  `AgentConversationPermissionState`，只保存本 Binding 的 threadId、provider default、
  session effective、一次性 current-turn override、runtime selection、source、last scope、
  warning 和持久化失败；不得维护跨 provider/runtime/thread map 或 active runtime 注册表。
  `AgentConversationPermissionSelectionController` 编排 apply/持久化，
  `AgentPermissionCatalogController` 独立管理目录加载和 stale retention。Composer 展示
  effective；持久化只写 default optionId。
  create/resume/fork/send 前由 application 冻结 `AgentPermissionRequestSnapshot`，优先级为
  thread-effective → provider default → catalog default。`AgentPermissionRequestResolver` 只定义
  这条无状态优先级；真正的 selection 均来自 Binding。无打开 Canvas 的 Project Threads
  fork 在 Binding 存在时读取该 Binding；不存在时才使用持久化 provider default 与 catalog default。
- **Settings feedback**：Codex notification mapper 通过专属 codec 原子解码
  profile/approval/sandbox，domain 只接收 `AgentPermissionSelection`。application 按通知
  threadId 写入匹配 Binding 的 `serverSettings` effective；当前 Binding 不接收其他 thread
  的通知，也不会修改 provider default 或再次调用 permission port apply。
- **Apply 状态机**：`currentTurn` 在下一次 snapshot 冻结时原子取走；`currentSession` 只提交
  当前 Binding；`runtime` 只更新该 Binding 所属 CLI 实例的状态，不广播到其他 Binding；
  `nextSession` 只更新 preference/pending hint。旧 generation 的迟到 apply 直接丢弃。
- **持久化恢复**：Provider apply 成功后再保存默认偏好；保存失败保留已生效状态并显示
  “已应用但保存失败”，通过 `retryPermissionPreferencePersistence` 只重试保存，不重复 apply。
- **V1 → V2 配置迁移**：`AgentProviderSettings.currentVersion = 2`；decoder 宽容读
  V1/V2。该 decoder 只存在于 data/config 的 `AgentProviderSettingsCodec`；domain config
  不再暴露 `tryDecode`。codec 先检查 V2 optionId key；仅当
  key 缺失时，才通过组合层注册的 Codex/Grok migrator 迁到单一
  `selectedPermissionOptionId`。Domain 不认识 legacy 字段，writer 只写 optionId。
- **Catalog 错误**：Codex adapter 只把明确的 `UnsupportedError`、JSON-RPC method-not-found
  或实验 API 明确关闭归类为 unsupported 并返回 built-ins；超时、连接/服务错误与 malformed
  response 均抛给 application。分页任一页失败不返回部分列表，重复 cursor 有界终止。
  `AgentPermissionCatalogController` 保存完整 last-known-good、记录非阻断错误，并以 refresh
  generation 防止旧请求回写。
- **Provider 边界**：
  - Codex：`CodexPermissionPolicyAdapter` + `CodexPermissionPolicyCodec` /
    `CodexPermissionRuntimeSnapshot`（data 层单请求编码值，含 approval/sandbox/profile）。
    adapter apply 只归一化 optionId，不保存共享选择；client/encoder 逐请求把中立快照编码为
    profile/approval/sandbox。Provider config 只在请求没有 selection 时作不可变 fallback。
  - Grok：`GrokPermissionPolicyAdapter` + `GrokPermissionModeCodec`（mode ↔ session
    meta / live 通知）。adapter 返回 `runtime` scope 后只提交到拥有该 runtime 的 Binding，
    不改写其他会话。
- 清空用户偏好使用 `AgentProviderConfig.withPermissionPreference(null)`（或
  `copyWith` + `agentProviderConfigUnset` 哨兵），禁止 `value ?? oldValue` 无法清空。
- Provider、bundle 与 `AgentTurnConfiguration` 只接受 `AgentPermissionRequestSnapshot`；旧裸
  selection 参数与兼容合并 facade 已删除，fake/harness 也不得重新引入。

最终权限调用链固定为：

```text
provider config --seed--> ConversationBinding --> AgentConversationPermissionState
thread settings --> data codec --> neutral event --> matching Binding state
user selection --> policy port --> AgentPermissionApplyResult --> owning Binding state

create/resume/fork/send --> Binding.permissions.snapshotForRequest()
  --> immutable snapshot
  --> bundle port --> Codex/Grok/Claude Code provider --> provider data codec --> wire request
```

验收时必须覆盖：两个 thread/两个 Canvas 的真实 wire 参数、runtime scope 只影响所属 Binding、
快速 Provider 重绑后的迟到 apply、disposed controller 的迟到结果、旧 runtime generation 丢弃，
以及 provider apply 成功但配置持久化失败时的只重试持久化语义。

### Skill 输入与 Composer token

- Domain 使用 `AgentUserInput.skill`、`AgentSkillMetadata` / `AgentSkillsCatalog`；
  capability 位为 `supportsSkillInput`（Codex 开，Grok 与 Claude Code 关）。
- Codex 通过可选端口 `bundle.skills`（`AgentSkillsPort`）暴露 `skills/list` 与
  `skills/changed`；application 层由 `AgentSkillsCatalogController` 做
  stale-while-revalidate / single-flight。
- Composer 用 `ComposerDocumentController`：skill 以 `U+FFFC` sentinel 占位、
  `WidgetSpan` 渲染为 `$name` chip，退格整块删除；发送时序列化为文本 `$name` 并附带
  `type: skill` 输入项。触发入口为输入 `$` 或 More actions → Insert skill；
  候选列表以 Composer 锚定的 popover 展示，支持 `$query` 实时过滤与 ↑↓/Enter/Esc。
  Chip 与列表项展示 `displayName`；tooltip / 协议文本仍对齐 Codex
  的 `$name` 与 `[$name](path)` 形态。
- Grok / ACP 不得静默吞掉 `AgentUserInput.skill`；应在 `sendMessage` 显式
  `UnsupportedError`，UI 靠 capability 隐藏入口。
- `@mention` v1 仍为纯文本旁路列表，不与 skill token 混用同一原子编辑语义。

### 斜线命令菜单（`/`）

- 在 Composer 中输入 `/`，且 `/` 前为空或仅空白（空格/换行/制表）时弹出斜线菜单。
  路径中间的 `/`（如 `/Users/foo` 或 `hello/`）不得触发。
- 菜单分层展示：**命令** 与 **Skills**。当前命令仅 `Plan`（依赖可用的 Plan
  conversation mode）；Skills 分区复用 `skillCandidates`，仅在
  `supportsSkillInput` 时出现。
- 选择 `Plan`：消费 `/query` 并切换下一回合为 Plan 模式，不向文本插入
  `/plan`。选择 Skill：消费 `/query` 并走既有 skill token 插入路径。
- 支持 `/query` 实时过滤与 ↑↓/Enter/Esc；与 `$` skill picker 互斥，同一时刻
  只打开其中一个。

### Plan conversation mode 开发与验证

- 存在两种**能力**，不是两种厂商名：对话 Plan（`conversationModes` 目录含 Plan）与
  权限 Plan（`permissionPolicy` 目录项 `planningOnly == true`）。共享层只认端口和
  标记，不得解析 optionId、不得按 providerId 分支。
- Domain 只使用 `AgentConversationMode*`；Codex 的 `collaborationMode` JSON 只存在于
  data client / mapper / encoder。`planningOnly` 由各 Provider 的权限 catalog 打标
  （Claude 的 Plan 档为 true）。
- `AgentConversationModeController` 管理目录、draft、confirmed、pending 和 generation；
  ViewModel 只负责绑定 Provider/thread 与冻结 `AgentTurnConfiguration`，Widget 不直接发 RPC。
- Plan 终态的执行确认由 `AgentPlanExecutionHandoffController` 管理，是非持久化的本地
  application 状态。必须在 `completeLiveTurnGroup` 清除 structured plan 之前捕获快照；
  Widget 只渲染请求并调用 ViewModel 的 start/revise/dismiss 动作。
- 执行交接与 Provider 计划审批共用 `_AgentPlanDockCard` 壳（正文可滚、底栏固定）；
  交接卡出现时 `blocksComposer` 为 true，隐藏主 Composer。交接底栏整合修订输入与
  「执行计划」：执行始终新建 Default 回合；「继续规划 / 发送修改」保持 Plan，可选
  发送修订文本。对话流中的 `AgentMessageKind.plan` 折叠消息卡保持独立，不承载执行动作。
  Provider 审批卡按钮应写成「接受计划」，不要和交接「执行」混用。
  `localExecutionHandoff` 的接受必须结束当前回合（Claude：allow `ExitPlanMode` 后
  interrupt），再由 Zeta 用非 planning 权限自动新开执行回合；不得让 CLI 在原
  `--permission-mode plan` 进程里继续写文件。
- Run plan 必须先选择 Default（若对话 Plan 可用），再创建一个新的 turn；不得把它实现成
  当前 turn steer，也不得调用 `AgentPlanApprovalPort`。有权限端口时，执行快照不得使用
  `planningOnly` 项：优先恢复进入只读规划前的选择（同 Binding/thread，**不**绑 runtime
  generation），否则 catalog 中第一个非 planning 的 allowed 项；都没有则禁止执行。
  点交接「执行」会 **会话内 adopt** 该权限（可 apply 到当前 runtime），**不** persist
  用户默认。离开只读规划 ≠ 预授权命令/文件/网络。卡内改选仍只写本地一次性快照，
  不 apply、不持久化。继续规划显式保留 Plan，关闭不改变权限状态。
- 新增或修改该流程时至少覆盖：成功 Plan 展示、失败/中断不展示、结构化步骤回退、
  Default 执行快照、planningOnly 种子丢弃、Plan 前权限恢复、catalog fallback、
  卡上改选零 apply、点执行会话 adopt、继续规划模式、
  陈旧请求与 thread/provider/workspace 切换清理。
- 模式来自 `bundle.conversationModes` 的运行时目录。端口为空、method-not-found、目录损坏
  或缺少 Default/Plan 时隐藏选择器，继续使用原有普通对话，不用 Prompt 伪造 Plan。
- 模式选择是“下一回合”配置。活动 turn 使用 `turn/steer` 时不修改 mode；切回 Default
  必须在下一次 `turn/start` 显式提交。
- 重启后先从 Zeta thread 快照恢复 draft/confirmed；`thread/read` 若没有 mode，不得清空
  本地已知值，随后以 settings notification 收敛确认态。
- 协议升级时先运行 fake contract tests，再执行 `tool/smoke_codex_plan_mode.py`；记录实际
  OS、CLI、Schema 模式和通过/失败项，不记录业务内容。

### 共享适配层修改判定

实现 Provider 差异时，先按下表确定代码归属。共享层只实现机制，不解释某个 Provider
“这条事件真正代表什么”。

| 变化 | 归属 | 共享层要求 |
|------|------|------------|
| 通用 ACP/JSON-RPC 字段的语法解析 | 无状态 decoder/codec/transport | 只输出 typed 值，不保存 turn/segment 状态，不按 Provider 分支 |
| 厂商扩展字段、source id 稳定性、eventId/messageId 复用 | 对应 Provider mapper/adapter | 在进入 application 前完成兼容和证据校验 |
| entryId、message segment、reasoning phase、boundary、去重、first-terminal-wins | 对应 Provider reducer | 输出语义完整的 `AgentEvent`，不得要求 Store 二次猜测 |
| 文件变更 identity、动作、累计 snapshot、tool/turn fallback | 对应 Provider file-change mapper/tracker | 输出完整 typed snapshot；command-only 不猜文件，Store/UI 不读 raw |
| live/history/replay 对齐 | 对应 Provider history/replay adapter | 复用算法但创建独立 reducer 实例 |
| 连续事件批内合并与 barrier 顺序 | `AgentEventCoalescingPolicy` + `CoalescingEventBuffer` | policy 定义 typed key/merge/barrier；buffer 只实现有界通用算法，不读 Provider raw 字段 |
| 事件订阅、旧 scope 隔离和有界交付 | `AgentEventPipeline` + `BoundedEventDispatcher` | Pipeline 唯一拥有 subscription/gate/buffer/dispatcher；dispatcher 每 turn 有界并让步 event queue |
| 时间线新增、更新和 tool upsert | `AgentConversationTimelineStore` | 只按 normalized id dumb merge，不识别 Provider |
| Provider capability 与启动时机 | Provider 实现、bundle 和 app 组合层 | 通过中立 capability/policy 暴露，不把协议判断放入 UI |

新增 Provider 的正常改动范围应是：Provider 自有 data 文件、必要的中立 domain contract、
factory/catalog 组合以及 Provider 契约测试。`AgentEventCoalescingPolicy`、
`CoalescingEventBuffer` 和
`AgentConversationTimelineStore` 不应因为新增 Provider 而改变；确有跨 Provider 的新语义时，
先设计 typed domain 字段和通用测试，再修改共享层。

提交评审前逐项确认：

1. 搜索共享层是否新增具体 Provider import、名称、kind、id 或实现类型判断。
2. 搜索 Store/ViewModel/UI 是否新增 raw/extra key、文件变更 wire key、命令/patch header 推断、
   eventId、source id 或“最后开放条目”推断。
3. 使用 Provider-local 序列测试证明 `raw update → AgentEvent` 已完成身份、边界和终态决策。
4. 使用 Provider 无关 fixture 回归 CoalescingPolicy/Buffer、Pipeline 与 TimelineStore；新增 Provider 时这些测试不应依赖
   新 Provider 的类或 fixture。

任一项不满足时，不得以“兼容性”或“临时兜底”为由合入共享层；应先回到对应 Provider
adapter/reducer 修正。完整规范见
[工程规范 §4.2](../architecture/engineering_standards.md#42-共享适配层纯度门禁)。

注意：默认策略应保持保守，不自动授权命令执行或文件写入。
未支持操作必须 capability=false，并抛出 `UnsupportedError`；不得静默成功。

Agent 管理适配与会话 provider 适配保持分层：管理 data 层可以执行 `--version`、
`login status` 和 app-server `initialize` / `model/list` 等无计费探测，但不得通过
真实模型 turn 做自动连接测试。配置文件保存必须走
`CodexAgentManagementRepository` 的校验、冲突检测、备份和临时文件替换流程；
日志必须在 data 层脱敏后再交给 presentation。

模型目录读取必须经过 app 注入的 `AgentModelCatalogRepository`，不要让首页、thread 或
管理页各自维护缓存。默认读取采用 1 小时 fresh / 7 天 max-stale 的
stale-while-revalidate：先发布可用旧目录，再以 single-flight 刷新；用户显式测试连接或
刷新时传 `forceRefresh`。Codex `initialize` 不应隐式请求 `model/list`，目录请求必须处理
全部 cursor 分页并在成功后一次性写缓存；失败不得用空列表污染旧缓存。仓储调用
`refreshLoader` 时必须绕过 provider 实例缓存；single-flight identity 包含安全配置指纹，
配置更新通过 generation 使旧任务失效。Provider 主动推送的完整 `AgentModelListEvent`
只在非目录刷新阶段记录到同一仓储，且内容未变化时跳过持久化。

Claude Code 模型目录是 Provider-local 的特殊协议来源，但不改变上述中立仓储契约：

- 独立 metadata peer 固定使用 `--no-session-persistence --setting-sources user`，只发送带
  随机 id 的 `control_request.initialize`，不发送 Prompt 或模型 turn。
- mapper 只消费 `response.models` 与 `account.subscriptionType` 白名单；模型以 `value`
  作为稳定 id/CLI 参数，旧形状才 fallback 到 `name`；`value=default` 必须在 Claude
  data mapper 中过滤。`resolvedModel` 只允许进入中立 `AgentModelInfo.model` 供历史匹配，
  raw、账号身份与未兑现的 Fast/auto 字段不得上浮。`supportsEffort=true` 时必须把
  `supportedEffortLevels` 映射为 `supportedReasoningEfforts`，并同时声明 Provider 的
  `supportsReasoningOptions` 能力，否则 Composer 会按能力门禁隐藏这些档位。
- initialize 表示当前 CLI 有效选项快照，不是实时远端全量保证。不得用 `/v1/models`、
  内置静态目录或 CLI 私有缓存补项。
- probe 失败或模型为空必须抛错；app 仓储保留 stale cache，无缓存时 UI 显示中立错误，
  不得以空目录覆盖缓存。Provider coordinator 只能合并 in-flight，不能持有第二套长期 TTL。
- 历史模型与缓存目录无法匹配时只允许强制刷新一次；仍不可匹配则保留当前有效模型，
  不得把目录外模型 id 写进 Composer selection。
- `claudeCode.accountDataEnrichment` 只控制额度凭据与 usage REST；关闭时模型和套餐名称仍
  来自 initialize。

当前活跃 Provider 是 Codex、Grok 与 Claude Code。Cursor 退役兼容必须遵守以下约束：旧 `cursor` id
与 `cursorAcp` kind 可宽容解码，但
`CursorRetirementPolicy` 必须在 catalog、选择、恢复和 factory 边界 fail-closed；fallback
只存在内存，不得保存覆盖旧设置。Cursor 不参与 live/replay/load、ACP 扩展、进程启动或
运行时组合；不得读取、迁移、改写或删除 Cursor 自有目录和遗留索引。
- 对话详情的 provider 事件订阅由 `AgentEventPipeline` 唯一拥有；Pipeline 组合
  `AgentProviderEventListenerGate`、`AgentEventCoalescingPolicy`、
  `CoalescingEventBuffer` 与 `BoundedEventDispatcher`。切换 Thread/Provider 时先废弃旧
  generation，再取消 source；Provider 若实现 `AgentRuntimeScopeProvider`，监听还必须校验
  runtime/epoch，旧 listener `onDone` 只能释放自身 Pipeline。
- 高频事件只在 `AgentEventCoalescingPolicy` + `CoalescingEventBuffer` 的 Application
  投影边界合并。新增可合并事件时，
  key 必须包含 thread、turn、item 和 event kind；完整 item、终态、审批、错误与连接状态
  不得进入可替代缓冲，并应先 flush 此前 delta。Transport/mapper 层保持逐条处理。
- Buffer 输出经默认每 turn 64 个事件的 `BoundedEventDispatcher` FIFO 交付，并通过
  `Timer.run` continuation 让出 Dart event queue；它不使用 Flutter idle/frame task。
- Pipeline 输出统一进入 `AgentConversationEventProcessor`。Reducer 只能同步产生
  typed state、`AgentTimelineMutation`、ThreadSnapshot、`AgentUiUpdateRequest` 和
  `AgentConversationEffect`；不得依赖 Flutter scheduler、Timer、Future 或执行外部回调。
  live/history/replay 必须创建独立 reducer/context，不能共享错误去重、deprecation 或本地
  identity 状态。
- EffectRunner 执行 turn-completed 回调、模型目录记录和结构化错误日志，并在执行前重新校验
  listener generation、runtime/epoch 与必要 thread scope；TimelineStore 只执行增量 mutation，
  不决定 UI urgency。
- 多 thread 常驻时，侧栏 busy 真源是各 entry 的 `AgentConversationThreadSnapshot`
  （`isTurnRunning` / `runtimeStatus` / waiting），经 shell `syncRuntimeSnapshot` 写入
  `runningThreadIds` 与摘要 status。Processor 在对应 mutation 后登记 snapshot 刷新，
  presentation 仅在 typed UI scheduler 的安全发布回调中写入 listenable；turn 结束后若无
  waiting，不得让列表残留 sticky
  `active`。后台完成仅非选中 thread 记入 `completedThreadIds`。细节见
  `plan/agent_running_status_ux_plan.md`（已随 `plan/` 目录移除，仅存于 Git 历史）。

### 新增 AgentEvent 接入清单

新增或改变 `AgentEvent` 时，提交者必须逐项回答并用测试固定：

1. 规范化 identity 由哪个 Provider data adapter/reducer 产生？
2. 事件属于哪个 Thread/turn，接收条件是什么？
3. 是否允许 detached runtime；若允许，是否已在精确 critical allowlist 中？
4. 是否可合并，key 是否覆盖 thread/turn/item/kind/detail？
5. merge 是追加、替换还是不可合并？
6. 是否为输入 barrier，处理前需要 flush 哪些 pending？
7. 是否属于不可丢失 critical event？
8. Reducer 产生哪些 state 或 timeline mutation？
9. 哪些 typed UI region 会变化？
10. UI urgency 是 next-frame 还是 immediate，理由是什么？
11. 是否产生一次性 `AgentUiEffect`？
12. 是否产生 scope-aware `AgentConversationEffect`？
13. 是否改变 `AgentConversationThreadSnapshot`？
14. live/history/replay 是否需要独立 reducer/context 行为？
15. Codex/Grok/Claude Code 或其他 Provider 是否都有相应契约测试？
16. 是否把 raw payload、source id 推断或 Provider 分支泄漏到 presentation/Store？

以上问题未全部明确前，不得把事件接入主链路。

修改 Codex 适配层前，先对照
[`third_party/codex_app_server_schema`](../../third_party/codex_app_server_schema/)
与 [协议版本锁定文档](../protocols/codex_app_server_protocol.md)；升级 CLI 时先
`./tool/gen_codex_schema.sh --diff`（或 PowerShell `-Diff`）再改代码。

新 provider 支持 Composer 模型配置时，必须把协议字段映射为中立
`AgentModelInfo.supportedReasoningEfforts` 和 `serviceTiers`，保留服务端数组顺序。
Fast 是产品语义，运行时仍必须传递 provider 的精确 `serviceTierId`；不得在 widget
中解析 `model/list` 或猜测协议 JSON key。

Claude initialize 的 `supportedEffortLevels` 只在 `supportsEffort=true` 时映射为
`supportedReasoningEfforts`，保持 CLI 原始顺序并保留未知字符串以兼容后续档位；选择值由
Provider 在下一回合通过 `--effort` 传递。initialize 未声明默认 effort 时不得自行猜测。

## 8. UI 开发指南

- `IdeHome` 持有主要页面唯一的 `WindowFrame` 和 `IdeWorkbenchScaffold`。新增主要页面时
  只提供 Navigation、Canvas、Inspector slot 内容，不得用页面组件替换整个 Workbench。
- 工作台外圈 padding 只写在 `IdeHome`：左右与底部 `IdeSpacing.space8`，顶部
  `space0` 与标题栏贴齐，标题栏不再画底部分隔线。Scaffold 外侧贴边，rail 只保留
  内侧 `space4`；Feature 页不要再套一层窗口级外距。
- Agent 首页、设置/Agent 管理和使用统计分别按设计文档中的 slot 矩阵组合：Agent 首页
  的 Navigation slot 使用一个 `ProjectAgentSidebar` 组合 Projects / Threads 与底部统计；
  设置 Feature 使用 `SettingsNavigationPane` + `SettingsPageCanvas`，使用统计只占用 Canvas。
- Agent 首页不得重新挂载 Activity Rail，也不得恢复 Projects / 统计 / Files 的局部显隐
  入口。合并左栏只由 `WindowFrame.titleBarLeadingActions` 中的标题栏按钮控制，Files
  Inspector 只由 `WindowFrame.titleBarActions` 中的右侧栏按钮控制；隐藏后入口仍可操作。
- Inspector 只承载 Files，不再编排右下 Tools 占位面板或纵向分隔拖拽。Compact 下复用
  Workbench Inspector Overlay，scrim / Esc 关闭后必须恢复标题栏右侧入口焦点。
- `ProjectAgentSidebar` 只编排两个业务 Widget 的约束与自然高度。它不得读取 Provider
  数据；Projects 与 cardless `AgentUsagePanelContent` 共用一个 `PanelCard`，统计常驻
  折叠摘要。无额度窗口时折叠态不渲染套餐进度行；冷加载 Skeleton 保留开合按钮。
  展开态由折叠摘要向上弹出的 Popover 承载：正文为套餐名加固定高度横向胶囊
  画廊（1/2/3+ 窗口分别占满、对半、各 40%）和 Token 统计；无额度窗口时不渲染整块套餐
  区。额度卡片使用紧凑 `space6` 内边距，重置时刻使用 `meta` 样式；距当前 7 天内显示
  `mm-dd HH:mm`，超过 7 天只显示 `mm-dd`，Claude Code 五小时窗口显示为 `5h`。
  Provider Tabs 与刷新常驻底部右侧，不显示独立标题栏、折叠按钮或拖动分隔，正文超出
  可用高度时只在弹层内滚动，左栏本身不为展开态让位。点击弹层外部或摘要开合按钮收敛回
  折叠态。Compact 下复用 Workbench Navigation Overlay，scrim / Esc 关闭后必须恢复标题栏
  入口焦点，不能通过压缩 Canvas 模拟窄屏侧栏。
- 左栏显隐、左栏宽度和统计 Provider 选择统一写入应用级
  `IdeWorkbenchLayoutState`。JSON 按字段宽容读取；统计展开态是临时弹层状态，只留在
  presentation 层，不写会话；旧 `agentUsageHeightFraction` 与 `agentUsageExpanded` 仅保留
  解码/回写兼容，不得再用于 presentation 布局。
- 需要跨页面保持的 Canvas 应使用稳定位置、稳定 Key 和保活容器。Key 必须放在可能因
  slot 增删而换位的 Flex 子节点上，不能只放在其内部后代；保活容器必须只布局活动页，
  非活动页面同时退出布局并暂停 ticker。
- Agent 会话与主要页面统一使用 `IdeRetainedPageView`；不要用 `IndexedStack` 保留
  长时间线，否则隐藏页面仍会参与 resize layout。
- `IdeConstraintBucketBuilder` 的稳定回调可跨父级 resize 复用 child。若 builder 捕获
  可变父配置，应让回调身份随配置变化；AgentPane 本身只在 compact / regular 档位或
  view model 真正替换时重建响应式业务树。
- Agent 时间线新增可见内容时应扩展稳定 viewport item（block / activity / footer），
  保持 `SliverList.builder`、`findChildIndexCallback` 和 prepend 锚点修正；不要恢复
  `SingleChildScrollView + Column` 或把整个长 turn 合并为一个 sliver child。
- grouping、unified diff 与代码高亮必须分别受 render revision、projection cache 和
  缓存的高亮 TextSpan identity 约束。窗口宽度变化不是数据变化，不得触发这些解析。
- Composer、Pending interaction 与 Active plan 的高度关系必须在同一次 layout 中解决；
  禁止重新引入 post-frame 测量、`GlobalKey` 查高或 layout 后 `setState` 反馈环。
- 页面容器只负责切换 slot。搜索、筛选、未保存配置确认等业务状态继续归对应 Feature；
  例如离开 Agent 管理前通过 `SettingsPageCanvasState.confirmCanLeave()` 查询。
- Agent 标题栏「更多」菜单打开的上下文详情面板是只读审计视图：正文放在统一
  `SelectionArea` 内；展开原始消息时，JSON 高亮 `RichText` 必须接入选择注册器，旁边提供
  「复制原文」按钮。复制只写系统剪贴板并给出 Toast，不得写入 Zeta 持久化状态或日志。
- 保持三栏工作台的职责边界：Projects 管项目和 threads，Agent 管对话，Files 管文件上下文。
- 复杂交互逻辑优先放入 view model，widget 层负责渲染和用户输入。
- 桌面工具界面需要保持信息密度，但文本必须可读，按钮和状态提示不能挤压变形。
- Projects 侧栏的项目项与 thread 项只使用水平 padding；不要为条目增加上下
  padding，行高由内容和稳定点击区域 token 决定。
- 非文本按钮应提供 tooltip。
- 新增面板或重复项时优先复用 `Pane`、`PanelCard`、主题常量和现有间距。
- UI 组件库使用 `shadcn_flutter`，必须 `as sf` 导入；Graphite 语义 token 通过
  `IdeThemeScope` / `IdeColors.of(context)` / `IdeTextStyles.of(context)` 读取。
- 通知反馈使用 `showIdeToast`（`lib/src/ui/core/ide_toast.dart`）。
- 不要再引入已移除的 `shadcn_ui` 或任何旧 `Shad*` API。

### 界面语言与文案

- 首期只支持英语与简体中文。产品语义是 `zh-Hans`；资源文件因 Flutter `gen-l10n`
  要求基础 `zh` fallback，使用 `app_en.arb` + `app_zh.arb`（`@@locale: zh`），
  不要再拆第三种界面语言。
- 语言偏好是 `settings` domain 的 `AppLanguage`，持久化码 `en` / `zh-Hans`。
  Flutter `Locale` 只允许出现在 `lib/src/app/localization` 与 presentation / `ui/`。
- 生产路径：`MainApp` 在 `waitForGeneralSettings` 时等常规设置加载完成，按
  `settings.appLanguage` 冻结 Locale 与文本目录，再挂 `IdeHome`。测试可用
  `displayLanguageOverride`；`waitForGeneralSettings` 默认 false，避免 Widget
  测试第一帧找不到宿主。
- 设置常规页用现有 `IdeSelect<AppLanguage>`，选项自称固定 `English` /
  `简体中文`。保存走 persist-first：成功后当前界面只显示「重启后生效」，
  失败 Toast 且不改内存选择。当前进程不监听系统 locale，也不因语言字段重挂
  Workbench。
- 首次启动只解析系统首选语言第一项（`resolveAppLanguageFromFirstSystemLocale`）：
  `en-*` → 英语；`zh-Hant` / `zh-TW` / `zh-HK` / `zh-MO` → 英语；`zh-Hans` /
  `zh-CN` / `zh-SG` / 无 script·region 的 `zh` → 简体中文；其他或空 → 英语。
  已有安装（marker / 旧 general）播种简体中文，不跟升级时的系统语言走。
- Widget 与 `ui/core` 走 `context.l10n`。application / data / reducer 注入对应
  feature 的不可变目录：`AgentUiTextCatalog`、`AgentManagementTextCatalog`、
  `UsageStatisticsTextCatalog`、`DesktopAttentionTextCatalog`。目录由
  `ZetaTextCatalogs` 在 app 组合层包装同一份 `AppLocalizations`；测试与未注入
  路径可用与 zh ARB 对齐的 `Fallback*`。禁止把 generated l10n、`Locale` 或
  `BuildContext` 下沉到 application / data / domain。
- 英文 ARB 是 key、description、placeholder 的模板真源；两份 ARB 必须对齐。
  placeholder 一律 `String`，禁用 plural / date / number formatter。日期、数字、
  百分比、相对时间继续用语言无关算法（相对时间只翻译
  `formatLocalizedRelativeTime` 的静态 token）。`Agent` / `Provider` / `Thread` /
  `Token` 保持英文。
- `shadcn_flutter` 上游只有英语。新增或改组件库文案走
  `ZetaShadcnLocalizations`；Calendar / DatePicker 的月份、星期和日期格式
  token 在 en/zh 使用相同英文值。升级 `shadcn_flutter` 前必须重跑
  `test/src/ui/localization/zeta_shadcn_localizations_test.dart`。
- 共享时间线内部的 Zeta fallback 只许走注入的 `AgentUiTextCatalog`，不得在
  G1 文件里写死中英文或按 Provider 选文案。
- 新增用户可见 Zeta 文案后：同时改 `app_en.arb` / `app_zh.arb`，跑
  `flutter gen-l10n`，再跑
  `dart run tool/check_localized_ui_strings.dart --check`。扫描器跳过品牌、
  产品术语、Provider/user/raw、协议 key 与日志；`--check` 只拒绝新的
  `(file, text)` zeta_copy。不要把新债务写进
  `tool/localization_literal_allowlist.json`。
- Provider 返回的标题、选项、回复、工具输出，以及用户输入、项目名、文件名、
  路径、命令、模型名保持原文。日志继续用稳定技术英语并脱敏。localized string
  只进当前进程的 UI / 时间线 / 通知，不写入 session、cache、usage index 或其他
  JSON。
- 原生文件选择器和 Cocoa 标准应用/Edit/View/Window/Help 菜单是操作系统拥有
  表面，可以继续使用系统语言。Zeta 自有 Windows/Linux 菜单与 macOS File /
  Open Project 标签走当前进程 l10n；macOS 在 Locale 就绪后才 configure。

- Agent 管理位于设置页；桌面宽度使用表格信息密度，窄窗口改为卡片和上下布局。
- 被禁用 Agent 的历史会话只读：允许加载和查看历史，但隐藏输入区，并阻止新建、
  分叉、重命名、归档和删除等写操作。
- Provider 的 thread 菜单、header、附件和选择器必须按 capabilities 渲染，不按
  provider kind 或显示名称硬编码。
- 使用统计是标题栏全局页面，不属于设置分区。统计表格在窄窗口保留横向滚动，
  分析区按可用宽度从双栏切换为单栏。
- 修改主要页面切换行为时，必须使用实际 `IdeHome` 补 Widget 测试，至少验证
  `WindowFrame`/Workbench/AgentPane Element、当前 Thread、草稿、对话滚动位置、
  Pane 宽度和可见状态没有被重置。
- 修改 resize 热路径时，除 Widget 回归外还要在 Windows Profile 运行
  1280→1000→1280 的 10 秒场景，并记录 UI/Raster p95、慢帧率、隐藏页
  build/layout、viewport item、projection/diff/highlight 与 transient callback 计数。
  Debug 数据不能作为性能通过结论；未达标数据必须如实保留。

### Composer 模型配置开发约束

- 入口、列表和卡片只消费 `AgentModelConfigUiState`；归一化、持久化、回滚与
  provider 更新必须留在 `AgentConversationModelSelectionController`。
- `selectedModelId` 与 `expandedModelId` 不得合并：前者影响下一回合且持久化，
  后者仅用于 Popover 展开卡片并在重新打开时清空。
- 新的模型行使用稳定 `ValueKey(model.id)`，禁用项保留可读原因；列表刷新不得
  清空旧快照、改变 Popover 打开方向或抢走用户滚动。
- 一次修改必须同步更新 selection 与对应模型偏好；保存失败时从最近确认
  快照整体回滚，不得只回滚某个字段。
- 交互变更至少覆盖：鼠标选择、重新打开收起、键盘 roving focus、Fast / `xhigh`
  冲突确认、保存回滚/重试与运行中的下一回合 Banner。
- 目录首次加载失败时必须渲染 `AgentModelConfigUiState.refreshError` 的中立状态；tooltip、
  semantics 和日志不得展示 Provider 原始异常。已有 stale 列表时保留列表并显示刷新警示。
- 历史 parser 必须在 Provider data 边界把协议别名归一化到
  `AgentHistoryTurn.modelId`、`reasoningEffort`、`serviceTierId` 和 `explicitFast` typed 字段；
  reasoning effort 明确区分 unknown、Provider default 与 explicit value，Fast 是否可由
  service tier 推导也由 Provider 决定。共享 TimelineStore/ViewModel/footer 只消费 typed
  字段；缺失或冲突证据保持 unknown，不得从 raw、当前选择、模型默认值或相邻 turn 猜测。

### 使用统计开发约束

- 合并左栏的折叠/展开内容只消费中立 `AgentUsagePanelController` / `AgentUsagePanelEntry`；
  不得按 Provider id、kind 或显示名分支，也不得把原始配额 payload 带入 presentation。
- 左栏只发现完整 Provider 目录，并按需读取当前选中项；首次启动、Tab 切换与配置目录
  更新不得顺带加载未选中的套餐或 Token。完整使用统计页仍通过全量查询聚合所有 Provider。
- 统计 Provider 选择与会话 active Provider 是两套状态。前台或后台 thread 终态必须通过
  typed signal 携带实际 Provider；Shell 只更新统计选择、Workbench 快照并请求静默刷新，
  不得写 `AgentProviderController`、Provider 配置或会话 Binding。一次终态只刷新一次。
- 新 provider 的套餐读取实现 `AgentUsageQuotaProvider` 可选端口；不支持时
  `bundle.usageQuota` 必须为 `null`。Grok 通过 `_x.ai/billing` 映射
  到 `AgentUsageQuotaSnapshot`，原始 billing JSON 不得泄漏到 presentation。
- Claude 的 `planType` 只来自 initialize metadata；可选 `/api/oauth/usage` 仅补额度窗口
  与 extra usage。只有增强开启、非 API key、token 有效且 scopes 同时含
  `user:inference` / `user:profile` 时才能读凭据并发请求；5 秒超时、60 秒节流且不重试。
  REST 失败或增强关闭返回 plan-only，UI 不得伪造 0% 窗口、100% 剩余、币种或余额。
- 调用统计依赖中立 `AgentUsageRecord`，provider 原始 JSON key 只允许出现在 data 层。
- Codex 使用统计扫描 `$CODEX_HOME/sessions/**/rollout-*.jsonl`：只要首行是合法
  `session_meta`（含可解析时间戳）即收录，**不得**按 `originator` 前缀白名单过滤；
  `zeta`、`Codex Desktop`、`codex_cli_rs` 等客户端会话均应计入 Token。
- Grok 使用统计扫描 `$GROK_HOME/sessions/**/updates.jsonl`，解析后投影为
  `GrokUsageIndexedSession` 白名单快照（不含 entries / raw / 原始错误正文）。
- Claude Code 使用统计扫描用户 `.claude/projects/**/*.jsonl`，复用 Provider 自有历史
  reader/mapper/reducer 投影单回合绝对 usage；cache creation/read 合并为 cached input，
  不做累计差分。Provider source 必须同时声明是否发现可读取历史，使“完全无历史”和
  “有历史但当前时间窗无调用”分别展示为暂无历史与 0。
- Codex `token_count` 是 thread 累计值，写入 turn 记录前必须相对上一 turn 做非负差分。
- 派生索引 `usage_statistics_index.json`（version ≥ 4）通过通用
  `UsageStatisticsPartitionStore` 按 `providers.<providerId>` 保存 Provider 不透明分区；
  当前生产分区包括 Codex、Grok 与 Claude Code。扫描层共用 `usageSourceId` +
  `usageFileFingerprint` + `forceRefresh` 命中语义；并行刷新必须原子合并，禁止整表覆盖
  写丢另一分区。
- 分区 Store 的 JSON 必须保持版本化和宽容读取；v2 顶层 `sessions` 迁移进 `codex`
  分区；索引损坏时从 provider 历史重建，不得阻断页面或应用启动。
- 派生索引禁止保存 Prompt、回复、工具输出、session JSONL 路径和原始错误文本。
- 历史 TTFT 缺失时保持 `null`；UI 显示“数据不足”和有效样本数，禁止用总耗时冒充。
- 套餐类型、额度窗口、重置时间、余额和可用重置卡数量都是 Provider 返回数据的只读投影；
  重置卡数量必须采用 Provider 明示的权威总数，不得用可能被截断的明细条数推算。不得据此
  添加 Zeta 登录/账号体系、购买、续费、支付入口或任何写回 Provider 账号的动作。

## 9. 会话和持久化

Zeta 自有数据统一写入用户主目录下的以下结构：

```text
~/.zeta/
  config/
    providers.json
    appearance.json
    general.json
  state/
    ide_session.json
    cursor_sessions.json  # 退役遗留数据，只读保护边界
    usage_statistics_index.json
    session/<providerId>/<threadId>.json
    migration_marker.json
  logs/
    zeta-YYYY-MM-DD.log
  cache/
    agent_models_v1.json
```

`main` 在 `runApp` 前解析 HOME、配置文件日志并执行一次性迁移；`app` 把具体文件
注入各 feature data store。旧版 SharedPreferences key 只作为迁移来源，目标文件已
存在时不会被覆盖；迁移失败时本次运行使用内存状态，既不阻止主界面，也不写空
目标覆盖待迁移数据，下次启动会继续重试。

会话状态使用版本化 JSON。变更字段时：

- 保持 `tryDecode` 宽容读取，损坏内容不能导致启动失败。
- 新字段提供默认值。
- 如破坏兼容性，提升版本并保留旧版本迁移逻辑。
- 不要把 provider 全局配置复制进每个项目状态。
- 不要在 presentation/application 中直接构造 `File('~/.zeta/...')`。

`general.json` 当前为 v3，保存发送快捷键、通知开关和 `appLanguage`
（`en` / `zh-Hans`）。v1/v2 宽容升级补简体中文并保留旧字段；未知语言回退英语；
损坏或未知版本在无法识别语言时才使用启动编排的 fallback。存储迁移 marker 为
v2：已有安装播种简体中文，真正的新安装按系统首选语言第一项播种；语言写入
成功后才完成 marker。编码结果不得包含任何 localized UI 字符串。

`providers.json` 中的 `modelPreferences` 是 provider 全局配置，按 `modelId` 保存
`reasoningEffort`、`fastEnabled`、`serviceTierId`、`updatedAt` 和条目 `version`。
解码时忽略损坏条目并兼容旧版单一 selection；写入时 selection 与完整偏好 map
必须作为同一快照保存。

`cache/agent_models_v1.json` 是可丢弃、可重建的版本化缓存，只保存规范化后的
`AgentModelInfo` 白名单字段和不含密钥的配置指纹。损坏、版本不兼容、配置指纹变化或
超过最长离线期限时视为空缓存；不得持久化 provider raw payload、环境变量值或凭证。

`state/session/<providerId>/<threadId>.json` 保存 Zeta 发起 turn 时的白名单上下文
（turnId、modelId、reasoningEffort、时间戳、终态）。打开历史会话时按字段覆盖
Provider 历史；文件缺失或损坏时回落原解析逻辑。不保存 prompt、回复、工具输出或
raw payload。

Agent CLI 的数据不属于这套目录：Codex/Grok/Claude Code/Cursor 配置与 session 历史
继续保留在各 CLI 自有目录（包括 `~/.codex`、`~/.grok`、`~/.claude`、`~/.cursor`
与项目 `.cursor/*`）。Provider 自有 data adapter 可以按明确功能读取对应 CLI 的配置、
会话、日志和账号 metadata；application/presentation 不自行遍历这些目录，也不接收原始
路径或 payload。读取权限不自动授权迁移、复制、改写或删除；派生索引与隐藏列表仍只写
`~/.zeta`。
退役遗留的 `cursor_sessions.json` 不再参与恢复或运行时组合，仅作为受保护用户数据原样
保留；Codex 使用统计仍只读原 rollout JSONL，并把可重建的派生索引写入
`~/.zeta/state`。

`AgentFileChangeSnapshot` 及其替换片段、写入内容、unified patch 只属于当前内存时间线。
不得把它们加入 IDE session、thread summary、模型缓存、使用统计索引、日志或系统通知；ignored
诊断只允许 method/type/reason/count 等白名单字段，损坏 evidence 只计数，不串行化原文。

## 10. 文件系统注意事项

- 文件树不应递归扫描整个项目。
- 不跟随符号链接。
- 大目录和工具缓存目录应继续忽略。
- 目录读取失败返回空列表或用户可理解状态，不让异常冒泡到 UI 崩溃。

## 11. 测试建议

- 纯逻辑、JSON 编解码和状态机使用单元测试。
- Widget 渲染和用户交互使用 `flutter_test`。
- 外部 CLI、文件系统和持久化优先使用 fake 或 callback 注入。
- 共享 decoder、CoalescingPolicy/Buffer 和 TimelineStore 使用 Provider 无关 fixture，并增加架构守卫，
  防止具体 Provider import、kind/id 分支或 raw identity 推断回流。
- Provider adapter/reducer 使用带 Provider/CLI 版本的脱敏 fixture 覆盖 source id 复用、
  message/tool/reasoning 交错、重复事件、终态竞态和迟到事件。
- 文件变更 producer 使用标明 provenance 的合成 fixture，覆盖完整 snapshot、status/terminal
  保留、command-only 负向路径、live/history/replay 隔离和 presentation raw-key purity guard。
- 对乐观配置增加“运行态更新→持久化失败→确认态回滚→重试”测试，
  并用可控 Completer 覆盖快速连续修改的最终快照语义。
- 新增或改写用户可见文案后，运行 ARB 契约测试、
  `dart run tool/check_localized_ui_strings.dart --check`，以及
  `test/src/architecture/` 下的本地化分层 / 持久化守卫。同一份 fake 数据在
  en / zh-Hans 下只应改变 Zeta chrome，Provider/user/raw 内容逐字相同。
- 只有端到端用户流程稳定后再添加 integration test。

### 执行中 Plan 浮动面板的手动验收

使用可写的 Codex thread，并保持在普通执行模式（非 Plan 审批模式）。在输入框中发送以下
提示词：

```text
这是一次 Plan 面板 UI 测试。请只读检查当前项目，不修改任何文件。

开始时先创建一个至少包含 4 个步骤的执行计划，并在执行过程中持续更新计划状态：
同一时间只能有一个步骤处于 in_progress，每完成一步立即标记 completed，再开始下一步。

任务步骤：
1. 定位应用入口和组合边界
2. 梳理 Agent feature 的目录结构
3. 查找主要 Widget 测试及其覆盖范围
4. 总结当前项目架构和测试现状

请按计划逐步执行，最后给出简短总结。
```

收到首个包含不少于 2 个步骤的结构化计划更新后，按以下项目验收：

1. 输入框上方出现水平居中的浮动 Plan 卡片，默认折叠，宽度不超过 340px，背景不透明度
   为 80%；时间线滚动时卡片保持在输入区上方，卡片两侧不产生整行留白或遮挡，仍可拖动
   底层时间线。
2. 折叠态显示 `Plan`、当前步骤序号/总数和单行当前步骤摘要；点击卡片后展开，再次点击
   收起。
3. 展开态显示步骤状态列表；步骤较多时仅列表区滚动，列表区高度不超过 200px。折叠摘要
   和展开列表中的长文本保持单行省略，鼠标悬浮后显示完整内容，短文本不显示 Tooltip。
4. 步骤推进时，已完成、执行中和待执行标记随结构化计划更新变化；收到后序 `inProgress`
   或 `completed` 状态时，即使前序步骤缺少完成通知，也会自动补为已完成。全部步骤完成后
   卡片仍保留到 turn 终态。
5. 权限审批、计划审批或用户提问出现时卡片暂时隐藏；交互结束后恢复原折叠状态。
6. turn 完成、取消或失败后卡片立即消失；结构化计划不会额外生成时间线 Plan 消息。

窄视口和放大字体可分别通过缩窄应用窗口、提高系统文本缩放后重复上述流程检查。自动化
回归可运行：

```sh
flutter test test/src/features/agent/presentation/agent_conversation_widget_test.dart
flutter test test/src/features/agent/presentation/agent_conversation_view_model_test.dart
flutter test test/src/features/agent/application/agent_conversation_timeline_store_test.dart
```

## 12. 常见问题

### Codex provider 启动失败

确认本机可以直接运行：

```sh
codex app-server
```

如果命令不存在或协议变更，应用会显示 provider 不可用或错误状态。
协议字段变更时，按 [协议版本锁定文档](../protocols/codex_app_server_protocol.md)
重新导出 schema 并 diff，再更新适配层。

### 旧 Cursor 配置显示 unavailable

这是退役后的预期行为。应用只在内存中回退到任一已启用且未退役的 Provider（Codex、
Grok 或 Claude Code），不会自动保存覆盖旧配置，也不会读取或修改 Cursor 会话数据。历史背景见
[Cursor Agent 退役历史说明](../history/cursor_agent_guide.md)。

### 会话恢复后项目消失

恢复流程会过滤不存在的目录。确认项目路径仍然存在，并且应用有权限读取。

### 文件树没有显示某些目录

被忽略目录不会显示，例如 `.git`、`.dart_tool`、`build`、`node_modules`。这是为了避免大型仓库打开时卡顿。
