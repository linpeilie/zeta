# WP-B：Provider 共享机制包（zeta_agent_provider_sdk）

> 状态：待实施 · 依赖：WP-A 完成 · 预估：0.5 天
> 目标：把「被两家以上引用、或协议通用但零厂商语义」的机制文件，从 `zeta_agent_providers` 与 `lib/` 搬进 `packages/zeta_agent_provider_sdk`；并提供可复用的 Provider 契约测试套件骨架。

---

## 1. 背景

共享机制的物理位置决定三方插件能否独立编译。当前这些文件混在 `zeta_agent_providers/lib/src/`（12 个）与 `lib/src/features/agent_management/data/`（1 个）里。

### 1.1 归属证据（import 反查）

对 13 个候选文件逐一反查 `lib/src/**` 的 import 引用（命令：`Grep "import 'package:zeta_agent_providers/src/<相对路径>"`，范围 `packages/zeta_agent_providers/lib` + `lib/`），结果：

| # | 文件 | 实际引用方（文件:行） | 结论 |
|---|------|----------------------|------|
| 1 | `datasources/transport/json_rpc_stdio_transport.dart` | codex：`codex_process_starter.dart:4`、`codex_permission_policy_adapter.dart:4`、`codex_app_server_agent_provider.dart:10`；grok：`grok_process_starter.dart:4`、`grok_acp_agent_provider.dart:14`；claude：`claude_code_agent_provider.dart:23`、`stream_json_peer.dart:6`、`claude_code_process_starter.dart:6`、`claude_code_cli_metadata_probe.dart:10`；`native_agent_provider_bundles.dart:8` | **三家共用 → sdk** |
| 2 | `datasources/transport/provider_operation_scheduler.dart` | codex：`codex_app_server_agent_provider.dart:11`；grok：`grok_acp_agent_provider.dart:15` | **两家共用 → sdk** |
| 3 | `datasources/transport/provider_runtime_json_rpc_peer.dart` | codex：`codex_app_server_agent_provider.dart:12`；grok：`grok_acp_agent_provider.dart:16`；自身 import #1 | **两家共用 → sdk** |
| 4 | `mappers/acp_content_codec.dart` | grok：`grok_session_update_mapper.dart:1`、`grok_file_change_tracker.dart:1`、`grok_acp_agent_provider.dart:17` | 仅 Grok 引用，但 ACP 是开放协议、文件内零厂商语义 → **sdk**（与 G1 正文「共享 ACP mapper」认定一致） |
| 5 | `mappers/acp_permission_mapper.dart` | grok：`grok_acp_agent_provider.dart:18`；自身 import #8 | 同上 → **sdk** |
| 6 | `mappers/acp_session_config_mapper.dart` | **无生产引用**（仅 root 测试 `acp_session_config_mapper_test.dart:7` 与 barrel 导出）；ACP 协议通用 | → **sdk**（测试随迁；标注「当前无生产引用，属前瞻机制」） |
| 7 | `mappers/acp_session_update_decoder.dart` | grok：`grok_session_update_mapper.dart:2`、`grok_file_change_tracker.dart:2`、`grok_updates_history_parser.dart:4`；自身 import #10 | 同上 → **sdk** |
| 8 | `mappers/agent_provider_payload.dart` | grok：3 处；claude：4 处（`claude_code_question_adapter.dart:2`、`claude_code_plan_approval_adapter.dart:3`、`claude_code_event_mapper.dart:7`、`claude_code_control_request_handler.dart:3`）；codex：`codex_app_server_agent_provider.dart:16`；#5 | **三家共用 → sdk** |
| 9 | `mappers/agent_provider_timestamp.dart` | `grok_provider_payload.dart:1`、`codex_provider_payload.dart:1` | **两家共用 → sdk** |
| 10 | `mappers/agent_tool_input_detail.dart` | grok：`grok_session_update_mapper.dart:7`；claude：`claude_code_event_mapper.dart:6` | **两家共用 → sdk** |
| 11 | `mappers/context_window_codec.dart` | #7（共享）；`grok_models_cli.dart:6`（grok 私有） | 无厂商语义 → **sdk** |
| 12 | `cli_command_locator.dart` | 三个厂商 locator（`codex_cli_locator.dart:3`、`grok_cli_locator.dart:3`、`claude_code_cli_locator.dart:3`）+ 三个 process starter（codex:4、grok:4、claude:5）+ `claude_code_cli_metadata_probe.dart:6` + app 侧 `cli_process_runner.dart`（仅用其 `ResolvedCliCommand`） | **三家共用 → sdk** |
| 13 | `agent_ignored_message_logger.dart` | codex：`codex_app_server_agent_provider.dart:7`；grok：`grok_acp_agent_provider.dart:8` | **两家共用 → sdk** |

**两个归属修正**（相对初版归属直觉）：

- `datasources/claude_code/stream_json_peer.dart`（443 行）：虽无 `claude_code_` 前缀，但全文 Claude 专有（L9 `zetaLoggerFor('zeta.agent.claude_code.stream_json')`、L14 doc 声明 Claude stream-json 归一化），**归 Claude 包**，不进 sdk。
- `datasources/acp/grok_models_cli.dart`：被 `grok_acp_agent_provider.dart:61/79/144` 与 grok 测试引用，**归 Grok 包**，不进 sdk（它 import 的 #11 照常进 sdk）。

**三个逐字事实补充**（完整勘察报告对账）：

- #13 `agent_ignored_message_logger.dart` 是 15 个候选中**唯一** import Flutter 的文件（L2 `package:flutter/foundation.dart`，用 `kReleaseMode`）。处理：T4 搬迁时做**一行等价替换**——`kReleaseMode` → `const bool.fromEnvironment('dart.vm.product')`（这正是 flutter/foundation 里 `kReleaseMode` 的逐字定义，语义不变；现有 `agent_ignored_message_logger_test.dart` 覆盖回归）。替换后 sdk 保持纯 Dart。这是本 WP 唯一一处对文件体的非 import 改动，PR 描述里必须点名。
- #9 `agent_provider_timestamp.dart` **未被 barrel 导出**；全仓唯一从包外 import 其 src 路径的是包内测试 `packages/zeta_agent_providers/test/agent_provider_payload_test.dart:2`——该测试随迁 sdk，import 改为 sdk barrel。
- 架构守卫 `test/src/features/agent/architecture/agent_core_raw_payload_freeze_test.dart:133/154` 以**字符串**引用 `mappers/agent_provider_payload.dart` 路径——搬迁后字符串不失效（守卫静默漏检），WP-E T1-6 已点名更新，WP-B 迁移时在 PR 描述里登记此挂起项。

另注：`zeta_agent_providers/lib/src/codex_cli_locator.dart` 等三个厂商 locator 各自 re-export/包装 #12，随迁各自包（WP-C 清单已含）。

**barrel-only 确认**：`lib/` 与 `test/` 中对 `package:zeta_agent_providers/src/...` 的直接 import 为零（唯一例外是该包内部测试 `packages/zeta_agent_providers/test/agent_provider_payload_test.dart:2`），全部经 barrel——搬迁后只需改 barrel 与包内相对 import，外部引用面不变。

### 1.2 app 侧随迁文件

`lib/src/features/agent_management/data/cli_process_runner.dart`：L5 import providers barrel，实际只用 `ResolvedCliCommand`（L37/45/46：`command.executable` / `command.argumentsFor(...)`）。三家管理仓库与 plugin 内 CLI 探测都依赖它 → **迁 sdk**（`src/cli_process_runner.dart`）。

---

## 2. 目标与非目标

**目标**
- 上表 13+1 个文件物理迁入 sdk，包内 import 改为 sdk 内部相对路径。
- 提供 `runAgentProviderContractTests(...)` 契约测试套件骨架（WP-C 三家包各自接入）。
- sdk 纯度守卫：零 import 任何 `zeta_agent_provider_<x>`。

**非目标**
- 不改任何被迁文件的实现逻辑与公开签名（纯搬运 + import 改写）。
- 不实现契约套件全部用例——骨架 + 从现有测试映射的第一批用例，WP-C 逐包补齐。

---

## 3. 包设计

```
packages/zeta_agent_provider_sdk/
├── pubspec.yaml
├── analysis_options.yaml          # include: package:flutter_lints/flutter.yaml
├── lib/
│   ├── zeta_agent_provider_sdk.dart                 # 主 barrel（纯机制）
│   ├── zeta_agent_provider_sdk_testing.dart         # 测试辅助入口（独立 barrel）
│   └── src/
│       ├── transport/
│       │   ├── json_rpc_stdio_transport.dart        # 自 providers datasources/transport/
│       │   ├── provider_operation_scheduler.dart
│       │   └── provider_runtime_json_rpc_peer.dart
│       ├── acp/
│       │   ├── acp_content_codec.dart               # 自 providers mappers/
│       │   ├── acp_permission_mapper.dart
│       │   ├── acp_session_config_mapper.dart
│       │   └── acp_session_update_decoder.dart
│       ├── payload/
│       │   ├── agent_provider_payload.dart
│       │   ├── agent_provider_timestamp.dart        # 原包内私有未导出，迁后升格 barrel 导出
│       │   ├── agent_tool_input_detail.dart
│       │   └── context_window_codec.dart
│       ├── diagnostics/
│       │   └── agent_ignored_message_logger.dart    # 诊断工具，不属于 payload 语义
│       ├── cli/
│       │   ├── cli_command_locator.dart
│       │   └── cli_process_runner.dart              # 自 app agent_management/data/
│       └── testing/
│           └── agent_provider_contract_tests.dart   # 契约测试套件（仅 testing barrel 导出）
└── test/                                            # sdk 自测（搬迁时随迁的机制单测）
```

> **testing 独立 barrel 的硬理由**：契约套件 import `package:test/test.dart`。若经主
> barrel 导出，`test` 会成为主库的传递依赖、污染每个插件包的生产编译面。独立
> entrypoint `zeta_agent_provider_sdk_testing.dart` 隔离之；`test` 列为 sdk 的
> **常规 dependencies**（lib/ 暴露它的类型就必须是常规依赖，pub 规则），主 barrel
> 不 export `src/testing/`。

`pubspec.yaml`：

```yaml
name: zeta_agent_provider_sdk
description: Zeta agent provider plugin SDK - shared transport, ACP codec, payload helpers and contract test suite.
publish_to: none
resolution: workspace

environment:
  sdk: ^3.12.2

dependencies:
  zeta_agent_core:        # AgentEvent / AgentProviderBundle / AgentUiTextCatalog ...
  zeta_agent_provider_api: # WP-A 产物：贡献类型与 definition
  zeta_plugin_kernel:     # ZetaPlugin 契约
  zeta_foundation:        # zetaLoggerFor / Clock / OperationId
  acp_sdk: ^<对齐根 pubspec 锁定版本>   # acp_* codec 的协议类型来源
  test: ^1.25.0           # src/testing/ 的契约套件要 export test 的类型（group/test）

dev_dependencies: {}      # sdk 自测复用 dependencies 的 test
```

> sdk 为**纯 Dart 包**（无 `flutter:` 段）：唯一潜在的 Flutter 依赖（`agent_ignored_message_logger` 的 `kReleaseMode`）在 T4 以一行等价替换消除（见 §1.1 事实补充）。包内测试用 `test` 而非 `flutter_test`，与 `zeta_plugin_kernel` 形态对齐。

依赖规则（写进包内 README 与 WP-E 守卫）：

```
sdk → {agent_core, provider_api, plugin_kernel, foundation, acp_sdk}
sdk ✗→ {zeta_agent_provider_<x>, zeta(根应用), flutter/*}
```

### 3.1 搬迁时的 import 改写规则

| 原 import | 新 import |
|-----------|-----------|
| `package:zeta_agent_providers/src/datasources/transport/x.dart` | `package:zeta_agent_provider_sdk/src/transport/x.dart`（sdk 内部用相对路径 `transport/x.dart`） |
| `package:zeta_agent_providers/src/mappers/acp_*.dart` | `../acp/acp_*.dart`（sdk 内相对） |
| `package:zeta_agent_providers/src/mappers/agent_provider_*.dart` 等 | `../payload/*.dart` |
| `package:zeta_agent_providers/src/agent_ignored_message_logger.dart` | `../diagnostics/agent_ignored_message_logger.dart` |
| `package:zeta_agent_providers/src/cli_command_locator.dart` | `../cli/cli_command_locator.dart` |

**搬迁期不改行为**：文件体除 import 行外逐字节保留（含中文 doc 注释）。每个文件搬迁提交单独成 commit，便于 bisect。

---

## 4. 契约测试套件设计

### 4.1 动机

「每个插件包可独立测试」的硬含义：插件包的测试不依赖根应用，也不依赖其他插件包。但 Provider 契约（G1/G2/G4/G5 的行为面）必须在每个包内可验证，否则拆分后契约只在 CI 全量时间接覆盖。

### 4.2 套件骨架

```dart
// packages/zeta_agent_provider_sdk/lib/src/testing/agent_provider_contract_tests.dart
import 'package:test/test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

/// 被测插件提供的夹具。插件包在自己的 test/ 里实现一次。
abstract interface class AgentProviderContractFixture {
  /// 静态 definition（compile-time metadata）。
  AgentProviderDefinition get definition;

  /// 用默认 fake 依赖创建 bundle（端口可为 fake 实现，但不得为 null 时谎报能力）。
  AgentProviderBundle createBundle();

  /// 该 Provider 的样本 wire 事件（脱敏 fixture），供事件归约契约使用。
  /// 可选：空列表则跳过事件面契约。
  List<Object> get sampleWirePayloads => const [];
}

/// 在插件包的测试里调用：runAgentProviderContractTests(() => CodexContractFixture());
void runAgentProviderContractTests(
  AgentProviderContractFixture Function() createFixture,
) {
  group('definition 契约', () {
    test('providerId 与 providerType 非空且稳定', () { /* … */ });
    test('staticCapabilities 与 definition 字段一致（端口声明不得超出能力）', () { /* … */ });
    test('metricLabel 只含规范化字符（G7 标签维度）', () { /* … */ });
  });

  group('bundle 端口/能力一致性', () {
    // 映射自现有 packages/zeta_agent_providers/test/agent_providers_contracts_test.dart
    test('可选端口非空 ⇒ 对应 capability 为 true', () {
      final bundle = createFixture().createBundle();
      // 对 AgentProviderBundle 的 20 个可选端口逐一断言：
      // threadCatalog/threadSubscription/threadNaming/threadArchival/
      // threadDeletion/threadCompaction/threadBranching/turnSteering/
      // permissionResponses/questions/deniedActionOverride/modelCatalog/
      // conversationModes/skills/localThreadList/sessionConfiguration/
      // planApproval/permissionPolicy/usageQuota
      // （清单以 zeta_agent_core 的 agent_provider_bundle.dart 为唯一真源，
      //   套件用镜像清单，漂移时测试失败提示同步）
    });
    test('capability=false 的端口必须为 null（G4 fail-closed）', () { /* … */ });
    test('必选端口 runtime / conversation 不得为 null', () { /* … */ });
  });

  group('事件契约（G1/G2）', () {
    test('适配层输出的 AgentEvent 不带 null entryId / 空字符串', () { /* … */ });
    test('raw payload 经 wrapAgentProviderPayload 包装（递归冻结）', () { /* … */ });
  });

  group('审批语义（G5）', () {
    test('权限/提问/Plan 审批端口返回的 decision 模型互不混用', () { /* … */ });
  });
}
```

### 4.3 现有测试 → 契约套件映射

WP-C 拆分时按下表归类（完整清单在 WP-C §4 的测试迁移表；此处定义类别语义）：

| 现有测试（例） | 归属 | 处理 |
|----------------|------|------|
| `packages/zeta_agent_providers/test/agent_providers_contracts_test.dart` | 三家混合断言 | **拆分**：每家断言进各自包的 `test/contracts_test.dart`（调套件 + 包私有补充）；文件本体删除 |
| `packages/zeta_agent_providers/test/agent_provider_payload_test.dart` | 共享机制（timestamp/payload） | **迁 sdk** `test/`，src 裸路径 import 改 sdk barrel |
| `test/src/features/agent/data/mappers/acp_session_update_decoder_test.dart`、`acp_content_codec_test.dart`、`acp_session_config_mapper_test.dart`、`agent_provider_raw_payload_test.dart` | 共享机制 | **迁 sdk** `test/`（Provider 无关 fixture 保持不动） |
| `test/src/features/agent/data/datasources/transport/json_rpc_stdio_transport_test.dart`、`provider_operation_scheduler_test.dart`、`provider_runtime_json_rpc_peer_test.dart` | 共享机制 | **迁 sdk** `test/` |
| `test/src/features/agent/data/cli_command_locator_test.dart`、`agent_ignored_message_logger_test.dart` | 共享机制（CLI 组） | **迁 sdk** `test/` |
| `test/src/features/agent/data/datasources/app_server/*`、`mappers/codex_*` | codex 私有 | 迁 codex 包 `test/`（WP-C T1） |
| `test/src/features/agent/data/datasources/acp/*`、`mappers/grok_*`、`local_history/grok_*` | grok 私有 | 迁 grok 包 `test/`（WP-C T2） |
| `test/src/features/agent/data/datasources/claude_code/*`、`mappers/claude_code_*` | claude 私有 | 迁 claude 包 `test/`（WP-C T3） |
| 根 `test/` 中同时触碰多家或 app 组合的（如 `agent_data_provider_contracts_test.dart` 的组合部分） | app 级 | 留根 `test/`，改为经 manifest 聚合断言（WP-D T6） |

---

## 5. 任务分解

### T1 · 建包骨架
**输入**：无
**产出**：目录结构 + pubspec + analysis_options + 空 barrel
1. 按 §3 建目录；pubspec 依赖版本与根 `pubspec.yaml` 的 `acp_sdk` 锁定版对齐。
2. 根 `pubspec.yaml` `workspace:` 列表加 `packages/zeta_agent_provider_sdk`（位置紧随 `zeta_agent_providers` 之后，保持字母序）。
3. `flutter pub get` 通过。
**验收**：`flutter analyze packages/zeta_agent_provider_sdk` 零 issue（空 barrel 状态）。

### T2 · 搬迁 transport 组（#1-3）
**输入**：T1
**产出**：3 文件入 sdk，providers 包改从 sdk barrel 导入
1. `git mv` 三文件到 sdk（保留历史）。
2. 改写三文件内部 import（§3.1 表）。
3. providers 包内引用方（§1.1 表行 1-3 列出的全部 importer 文件）改为 `import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk.dart';`。
4. providers barrel 删除对应 `export`；sdk barrel 新增。
5. `flutter analyze` + `bash tool/test_affected.sh`。
**验收**：`grep -rn "datasources/transport" packages/zeta_agent_providers/lib` 无残留；transport 相关测试绿。

### T3 · 搬迁 ACP codec 组（#4-7）
**输入**：T2
**产出**：4 文件入 sdk
1. 同 T2 流程；引用方为 §1.1 表行 4-7 列出的全部 importer 文件。
2. `acp_session_config_mapper.dart` 随迁其 root 测试到 sdk `test/`，并在文件头 doc 追加一行「当前无生产引用，属前瞻机制」（事实标注，防误删）。
**验收**：`grep -rn "mappers/acp_" packages/zeta_agent_providers/lib` 无残留；G1 自查命令（AGENTS.md §1）对 `packages/zeta_agent_providers/lib/src/mappers/acp_*.dart` 的路径引用更新为 sdk 路径——**该守卫文本在 WP-E T1 统一改**，此处先用 `grep` 手动确认 sdk 内文件无厂商标识。

### T4 · 搬迁 payload/工具组（#8-11、13）
**输入**：T3
**产出**：5 文件入 sdk
1. 同 T2 流程；引用方为 §1.1 表行 8-11、13 列出的全部 importer 文件。
2. **barrel 升格**：`agent_provider_timestamp.dart` 在 providers 包内从未被 barrel 导出（包内相对 import），迁后 codex/grok 两包只能经 sdk barrel 取它——sdk barrel 新增该导出（本 WP 唯一的可见性升格，PR 描述点名）。
**验收**：`grep -rn "agent_provider_payload\|agent_provider_timestamp\|agent_tool_input_detail\|context_window_codec\|agent_ignored_message_logger" packages/zeta_agent_providers/lib` 仅剩 sdk import 行。

### T5 · 搬迁 CLI 组（#12 + cli_process_runner）
**输入**：T4
**产出**：2 文件入 sdk
1. `cli_command_locator.dart`：providers 包内 6 处引用（三个 locator + 三个 starter + metadata probe）改 sdk import。
2. `cli_process_runner.dart`：从 `lib/src/features/agent_management/data/` 迁 sdk `src/cli/`；app 侧引用方（codex/grok 管理仓库、`cli_command_probe.dart` 等）改 sdk import。
3. **注意**：`cli_process_runner.dart` 含 `dart:io`——sdk 因此不是纯 Dart 无 IO 包，pubspec 无需 Flutter 但允许 `dart:io`（桌面插件包的既定事实，与 kernel 的「进程/文件 IO 允许在 data 层」一致；WP-E 守卫只禁 `dart:ui`/`package:flutter/`）。
**验收**：`flutter analyze` 零新增；`bash tool/test_affected.sh` 绿。

### T6 · 契约测试套件骨架
**输入**：T2-T5（套件 import 的机制文件已就位）
**产出**：`src/testing/agent_provider_contract_tests.dart`
1. 按 §4.2 实现四类契约组；端口清单从 `zeta_agent_core/lib/src/domain/agent_provider_bundle.dart` 逐一镜像（20 个可选端口，含注释「唯一真源」指引）。
2. sdk 自测：`test/contract_suite_self_test.dart` 用一个内存 fake fixture 跑套件，断言「全绿 fixture 过、端口/能力不一致的 fixture 挂」。
**验收**：sdk 自身 `flutter test` 绿；套件只经 `import 'package:zeta_agent_provider_sdk/zeta_agent_provider_sdk_testing.dart'` 可用，且主 barrel **不**导出 `src/testing/`（grep 主 barrel 无 `testing` 字样）。

---

## 6. 验收标准（DoD）

- [ ] 13+1 个文件全部入 sdk，providers 包与 app 无残留旧路径 import。
- [ ] sdk 内任意文件 `grep -iE "codex|grok|claude"`（排除注释）无输出。
- [ ] `stream_json_peer.dart`、`grok_models_cli.dart` 未误迁入 sdk（留在 WP-C 归私有）。
- [ ] 契约套件骨架可用，sdk 自测绿。
- [ ] `bash tool/test_affected.sh` 绿；无测试断言被修改（纯搬迁的证据）。
- [ ] root barrel `zeta_agent_providers.dart` 的 export 数从搬迁前基线单调下降（最终由 WP-C 清零）。

## 7. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 搬迁中循环 import（如 payload ↔ acp） | sdk 内全用相对路径；按 T2→T5 顺序搬，被依赖者先走 |
| `cli_process_runner` 的 `dart:io` 污染 sdk 纯度认知 | 文档与守卫明确「禁 Flutter、允许 dart:io」；CI 加 `grep "package:flutter" packages/zeta_agent_provider_sdk/lib` 断言 |
| 契约套件与 core 端口清单漂移 | 套件内注释真源位置 + 漂移时测试失败信息直接提示同步 |
| `acp_session_config_mapper` 无生产引用被误删 | T3 步骤 2 的事实标注；保留决定记录在本文档 |

## 8. 开发记录

| 日期 | 内容 |
|------|------|
| 2026-09-04 | 初稿 |
| 2026-09-04 | 重写：归属表改为 import 反查实证（13 文件逐行引用方）；修正 stream_json_peer→Claude 私有、grok_models_cli→Grok 私有；AcpSessionConfigMapper 标注无生产引用；cli_process_runner 只依赖 ResolvedCliCommand 的事实落表；契约套件映射表补现有测试实例 |
| 2026-09-04 | 完整勘察报告对账：#13 的 Flutter 依赖实测落档并定一行等价替换方案（kReleaseMode→dart.vm.product），sdk 纯 Dart 论断随之成立；#9 未被 barrel 导出、包内测试裸 src import 的处理落档；`agent_core_raw_payload_freeze_test` 的字符串路径引用登记为 WP-E 挂起项；映射表补 4 个测试文件（包内 payload 测试、raw_payload、cli_command_locator、ignored_message_logger）；pubspec 定稿纯 Dart（无 flutter 段、dev 用 test） |
| 2026-09-04 | 终审轮：① **testing 独立 barrel 定稿**（`zeta_agent_provider_sdk_testing.dart`）——套件 import `package:test`，若经主 barrel 导出会把 test 变成主库传递依赖；`test` 因此列为常规 dependencies，主 barrel 不 export `src/testing/`，T6 验收同步改写。② `agent_ignored_message_logger` 从 `payload/` 改归 `diagnostics/`（语义不符修正）。③ 明确 `agent_provider_timestamp` 的 barrel 升格为本 WP 唯一可见性变化（原包内私有，插件包只能经 barrel 取）。④ 删除 T2/T3/T4 里与 §1.1 表对不上的引用方计数（8/6/12 → 改指表行）。 |
