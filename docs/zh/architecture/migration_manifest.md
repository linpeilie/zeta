# 迁移逐文件清单（source→target manifest）

中文 ｜ [English](../../en/architecture/migration_manifest.md)

本清单执行[迁移任务清单 步骤 1](./migration_tasks.md)：旧仓库每个 Git 跟踪文件恰好归类一次。
它与[迁移拓扑](./migration_topology.md)、[归属映射表](./ownership_map.md)、[包 API 契约](./package_api_contracts.md)配套使用。

---

## 1. 基线

| 项 | 值 |
| --- | --- |
| 源仓库 | `D:\Development\Workspace\zeta` |
| 分析基线 SHA | `bfd42412c9c3a0b39bb93598f93f9e5eca471236` |
| 工作区状态 | clean（唯一未跟踪项：`.workflow/feature/2026-08-18-PC端构建与版本检查/`） |
| Git 跟踪文件总数 | **1,512** |
| 清单生成日期 | 2026-08-19 |
| 目标仓库 | `D:\Development\Workspace\vgv\zeta`，版本 `1.0.0+1` |

> [!IMPORTANT]
> **本清单基于分析基线 `bfd4241`，不是最终迁移基线。** [步骤 0](./migration_tasks.md) 的 Cursor
> 清退会改变旧仓库内容。执行 [步骤 1](./migration_tasks.md) 时必须：
> 
> 1. 重新运行本清单的生成脚本，得到清退后的最终 SHA 与文件数；
> 2. 记录最终的 Flutter/Dart 版本与 `pubspec.lock` hash；
> 3. 确认标记为 `delete` 的 Cursor 相关文件已在旧仓库消失（届时它们不再出现在本清单中）。

## 2. 动作定义

| 动作 | 含义 | 验证方式 |
| --- | --- | --- |
| `move` | 内容不变或仅改路径/链接，逐字节或逐行可比 | diff 或 checksum |
| `rewrite` | 内容按新架构重写，功能等价但结构改变 | 目标位置的测试覆盖等价行为 |
| `regenerate` | 由工具重新生成，不手工迁移 | 生成命令可重复执行 |
| `delete` | 明确删除，不进入新仓库 | 说明列写明删除理由 |
| `out-of-scope` | 不属于本次迁移输入 | 说明列写明排除依据 |

**一对多拆分的表达约定**：目标列写 `拆分` 或用 ` + ` 连接多个目标时，表示该源文件被拆到多处。
这类文件必须在[归属映射表](./ownership_map.md)中有逐项裁决，本清单只记录去向。

## 3. 总览

| 动作 | 文件数 | 占比 |
| --- | ---: | ---: |
| `move` | 300 | 19.8% |
| `rewrite` | 740 | 48.9% |
| `regenerate` | 5 | 0.3% |
| `delete` | 42 | 2.8% |
| `out-of-scope` | 425 | 28.1% |
| **合计** | **1512** | **100%** |

| 区域 | 文件数 | 主要动作 |
| --- | ---: | --- |
| `lib/` | 378 | rewrite 335, delete 38, regenerate 3, move 2 |
| `test/` | 305 | rewrite 305 |
| `third_party/` | 269 | move 269 |
| `macos/ + windows/ + linux/` | 65 | rewrite 65 |
| `assets/` | 13 | move 13 |
| `tool/` | 19 | move 8, out-of-scope 5, delete 4, rewrite 2 |
| `docs/` | 31 | rewrite 15, out-of-scope 12, move 4 |
| `.github/` | 6 | rewrite 6 |
| `.claude/ + .agents/ + .workflow/` | 407 | out-of-scope 407 |
| `根目录文件` | 19 | rewrite 12, move 4, regenerate 2, out-of-scope 1 |
| **合计** | **1512** | 覆盖校验：1512 = 1512 |

## 4. 与拓扑文档的数字差异

[迁移拓扑 §2](./migration_topology.md) 的平台文件数是文件系统快照，本清单统计 Git 跟踪文件，两者不同：

| 项 | 拓扑 §2 | 本清单（git 跟踪） | 差异原因 |
| --- | ---: | ---: | --- |
| macOS | 33 | 28 | 差额为 gitignore 的生成产物（plugin registrant、构建中间件） |
| Windows | 69 | 22 | 差额为 gitignore 的生成产物（plugin registrant、构建中间件） |
| Linux | 15 | 15 | 一致 |
| assets | 13 | 13 | 一致 |

**执行步骤 1 时以本清单的 git 跟踪口径为准**：未跟踪文件不是迁移输入，生成产物按 `regenerate` 处理。

---

## 5. 范围裁决：两项已批准的调整

> **状态：已裁决（2026-08-19），已同步到[迁移拓扑 §1](./migration_topology.md) 与[任务清单 §0](./migration_tasks.md)。**

拓扑 §1 原本把 `third_party/` 整体列入「明确不迁移」，与 `tool/packaging/` 并列。核查后确认
**`third_party/` 这一条过宽**，且 `tool/` 的排除范围写得不够精确。两项调整如下，需在
[步骤 2 的 ADR](./migration_tasks.md)中正式登记。

### 5.1 `third_party/codex_app_server_schema/` 迁入

- **内容**：269 个文件 / 2.8 MB，Codex CLI `0.144.5` 的 stable JSON Schema 快照。
- **理由**：[Codex 协议文档](../protocols/codex_app_server_protocol.md) §2 把它定义为「人工与 CI 可 diff 的协议真相源」，
  而[步骤 12](./migration_tasks.md) 要求 `codex_app_server_client` 有 contract test。删除快照 = 删除 contract test 的基准。
- **裁决**：`move`，路径不变。它不是运行时依赖，只是可 diff 的协议契约，不引入任何构建期或运行期负担。
- **仍然排除**：`third_party/` 下若将来出现其他内容，默认不迁移；本裁决只覆盖 `codex_app_server_schema/`。

### 5.2 `tool/` 的冒烟与门禁脚本迁入

排除范围收窄为 `tool/packaging/`。同目录下验收标准直接依赖的脚本一律迁入：

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `tool/check_localized_ui_strings.dart` | rewrite | `tool/` | l10n 字面量门禁；TextCatalog 删除后规则需同步更新（步骤 28） |
| `tool/gen_codex_schema.ps1` | move | `tool/gen_codex_schema.ps1` | Codex schema 生成脚本 |
| `tool/gen_codex_schema.sh` | move | `tool/gen_codex_schema.sh` | Codex schema 生成脚本 |
| `tool/localization_literal_allowlist.json` | rewrite | `tool/` | 配套 allowlist |
| `tool/report_test_timings.dart` | move | `tool/` | 测试耗时报告 |
| `tool/smoke_claude_code_metadata.py` | move | `tool/` | 五个真实 CLI 冒烟脚本；步骤 17/33/36 验收直接依赖（已裁决迁入） |
| `tool/smoke_claude_code_stream_json.py` | move | `tool/` | 五个真实 CLI 冒烟脚本；步骤 17/33/36 验收直接依赖（已裁决迁入） |
| `tool/smoke_codex_app_server.py` | move | `tool/` | 五个真实 CLI 冒烟脚本；步骤 17/33/36 验收直接依赖（已裁决迁入） |
| `tool/smoke_codex_plan_mode.py` | move | `tool/` | 五个真实 CLI 冒烟脚本；步骤 17/33/36 验收直接依赖（已裁决迁入） |
| `tool/smoke_grok_acp.py` | move | `tool/` | 五个真实 CLI 冒烟脚本；步骤 17/33/36 验收直接依赖（已裁决迁入） |
| `tool/test_fast.ps1` | delete | — | test_fast/test_full 脚本被 VGV 四门（very_good test）取代 |
| `tool/test_fast.sh` | delete | — | test_fast/test_full 脚本被 VGV 四门（very_good test）取代 |
| `tool/test_full.ps1` | delete | — | test_fast/test_full 脚本被 VGV 四门（very_good test）取代 |
| `tool/test_full.sh` | delete | — | test_fast/test_full 脚本被 VGV 四门（very_good test）取代 |

`smoke_*.py` 五个脚本对应[步骤 17](./migration_tasks.md)「真实 CLI 的只读 capability probe 冒烟」、
[步骤 33](./migration_tasks.md)「Codex/Claude/Grok 真实 CLI 会话冒烟」和[步骤 36](./migration_tasks.md)
「三路真实 CLI 端到端冒烟」。没有它们，这三个步骤无法勾选。

`check_localized_ui_strings.dart` 与 `localization_literal_allowlist.json` 是 l10n 字面量门禁，
[步骤 28](./migration_tasks.md) 删除 TextCatalog 后规则需同步更新；`gen_codex_schema.{sh,ps1}` 是 §5.1
schema 快照的生成入口。`test_fast/test_full` 四个脚本被 VGV 四门取代，标记 `delete`。

---

## 6. `lib/` 逐文件（378）

路径已去掉 `lib/src/` 前缀。目标列的 `packages/` 与 `lib/` 都相对新仓库根目录。

### 6.1 入口与 app 层

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `main.dart` | delete | — | 单 entrypoint 被 main_development/staging/production 三个 flavor 取代（步骤 3） |
| `src/app/app.dart` | rewrite | `lib/app/view/app.dart` | 拆成 App widget + MultiRepositoryProvider；Bloc 注入下沉到各 Page |
| `src/app/app_constants.dart` | rewrite | `lib/app/app_constants.dart` | 纯 UI 常量移入 packages/app_ui/；应用身份常量留 app |
| `src/app/bootstrap/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `src/app/composition/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `src/app/localization/zeta_localization.dart` | rewrite | `lib/l10n/l10n.dart` | Locale 冻结逻辑保留；ARB 入口改为 VGV 标准 l10n.dart |
| `src/app/localization/zeta_text_catalogs.dart` | delete | — | TextCatalog 双轨删除（步骤 28）；下层改 typed code + lib/l10n/failure_messages.dart |
| `src/app/menu_action_bridge.dart` | rewrite | `lib/app/platform/menu_command_adapter.dart + lib/app/router/` | 原生菜单命令拆成 MenuCommandApi adapter 与 typed route 调用（步骤 34） |
| `src/app/shell/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `src/app/shell/ide_shell_controller.dart` | rewrite | `lib/ide_shell/bloc/` | 1,467 行 Controller → IdeShellBloc；导航状态交给 GoRouter（步骤 34） |
| `src/app/window_bootstrap.dart` | rewrite | `lib/app/platform/window_command_adapter.dart` | window_manager / macos_window_utils 收敛到 WindowCommandApi 实现 |
| `src/app/zeta_startup_bootstrap.dart` | rewrite | `lib/bootstrap.dart` | 唯一 composition root；同时可见 Data client、Repository 与 platform adapter |
| `src/app/zeta_storage_migrator.dart` | delete | — | 无历史版本兼容；只验证空目录干净安装与当前 schema（拓扑 §1） |

### 6.2 core

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `core/constants/app_typography.dart` | rewrite | `packages/app_ui/lib/src/theme/` | 设计 token 归 app_ui；不依赖 Repository/Data |
| `core/error/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `core/logging/app_logging.dart` | rewrite | `packages/zeta_logging/lib/src/` | 结构化日志；所有出口默认脱敏 |
| `core/logging/structured_error_logging.dart` | rewrite | `packages/zeta_logging/lib/src/` | 结构化日志；所有出口默认脱敏 |
| `core/result/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `core/security/sensitive_data_redactor.dart` | rewrite | `packages/zeta_logging/lib/src/` | 敏感数据脱敏与日志同包，保证日志出口无法绕过 redactor |
| `core/storage/atomic_text_file.dart` | rewrite | `packages/zeta_storage/lib/src/` | 原子文件操作与数据路径；只支持当前 schema |
| `core/storage/zeta_data_paths.dart` | rewrite | `packages/zeta_storage/lib/src/` | 原子文件操作与数据路径；只支持当前 schema |
| `core/utils/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `core/utils/path_utils.dart` | rewrite | `packages/zeta_storage/lib/src/` | 路径规范化与 canonical path，是 projectId 派生的基础（步骤 34） |
| `core/utils/system_file_manager.dart` | rewrite | `packages/desktop_platform_api/ + lib/app/platform/` | 纯 Dart 端口留 desktop_platform_api；file_selector/pasteboard 实现留 app |

### 6.3 agent · domain → `agent_provider_contracts`

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `features/agent/domain/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/agent/domain/agent_attention_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_conversation_mode_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_event_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_file_change_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_message_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_model_catalog_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_model_codec.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_model_selection_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_permission_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_permission_policy_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_plan_approval_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_plan_execution_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_provider_bundle.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_provider_capabilities.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_provider_error_presentation.dart` | rewrite | `lib/l10n/failure_messages.dart` | 错误展示映射属于 Presentation；contracts 只保留 typed failure code |
| `features/agent/domain/agent_provider_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_question_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_runtime_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_session_config_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_session_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_skill_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_thread_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_tool_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_turn_activity_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_turn_context_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_turn_history_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_turn_terminal_signal.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_ui_text_catalog.dart` | delete | — | TextCatalog 删除（步骤 7 / 28） |
| `features/agent/domain/agent_usage_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/agent_usage_window_labels.dart` | rewrite | `lib/l10n/ + packages/agent_provider_contracts/` | 窗口时长 typed code 留 contracts；展示文案入 ARB |
| `features/agent/domain/agent_user_input_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段 |
| `features/agent/domain/cursor_retirement_policy.dart` | delete | — | Cursor 清退（步骤 0），迁移前在旧仓库删除 |
| `features/agent/domain/fallback_agent_ui_text_catalog.dart` | delete | — | Fallback catalog 删除（步骤 7 / 28） |

### 6.4 agent · data · transport 与 vendor client

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `features/agent/data/datasources/acp/grok_acp_agent_provider.dart` | rewrite | `packages/grok_acp_client/lib/src/` | Grok ACP 适配层 |
| `features/agent/data/datasources/acp/grok_models_cli.dart` | rewrite | `packages/grok_acp_client/lib/src/` | Grok ACP 适配层 |
| `features/agent/data/datasources/acp/grok_permission_policy_adapter.dart` | rewrite | `packages/grok_acp_client/lib/src/` | Grok ACP 适配层 |
| `features/agent/data/datasources/acp/grok_process_starter.dart` | rewrite | `packages/grok_acp_client/lib/src/` | Grok ACP 适配层 |
| `features/agent/data/datasources/app_server/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/agent/data/datasources/app_server/codex_app_server_agent_provider.dart` | rewrite | `packages/codex_app_server_client/lib/src/` | Codex app-server 适配层 |
| `features/agent/data/datasources/app_server/codex_app_server_client.dart` | rewrite | `packages/codex_app_server_client/lib/src/` | Codex app-server 适配层 |
| `features/agent/data/datasources/app_server/codex_app_server_runtime_info.dart` | rewrite | `packages/codex_app_server_client/lib/src/` | Codex app-server 适配层 |
| `features/agent/data/datasources/app_server/codex_collaboration_mode_catalog_failure.dart` | rewrite | `packages/codex_app_server_client/lib/src/` | Codex app-server 适配层 |
| `features/agent/data/datasources/app_server/codex_permission_policy_adapter.dart` | rewrite | `packages/codex_app_server_client/lib/src/` | Codex app-server 适配层 |
| `features/agent/data/datasources/app_server/codex_process_starter.dart` | rewrite | `packages/codex_app_server_client/lib/src/` | Codex app-server 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_agent_provider.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_anthropic_api_client.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_cli_metadata.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_cli_metadata_coordinator.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_cli_metadata_probe.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_control_request_handler.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_event_mapper.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_file_change_tracker.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_hidden_thread_store.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_macos_keychain_source.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_model_catalog.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_oauth_credentials_reader.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_permission_policy_adapter.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_plan_approval_adapter.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_process_starter.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_question_adapter.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_session_history_reader.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/claude_code_usage_quota_adapter.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/claude_code/stream_json_peer.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json 适配层 |
| `features/agent/data/datasources/local_history/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/agent/data/datasources/local_history/codex_jsonl_history_parser.dart` | rewrite | `packages/codex_app_server_client/lib/src/history/` | vendor-specific parser 留各 vendor client（步骤 15） |
| `features/agent/data/datasources/local_history/codex_thread_history_reader.dart` | rewrite | `packages/codex_app_server_client/lib/src/history/` | vendor-specific parser 留各 vendor client（步骤 15） |
| `features/agent/data/datasources/local_history/grok_chat_history_parser.dart` | rewrite | `packages/grok_acp_client/lib/src/history/` | vendor-specific parser 留各 vendor client（步骤 15） |
| `features/agent/data/datasources/local_history/grok_session_history_reader.dart` | rewrite | `packages/grok_acp_client/lib/src/history/` | vendor-specific parser 留各 vendor client（步骤 15） |
| `features/agent/data/datasources/local_history/grok_updates_history_parser.dart` | rewrite | `packages/grok_acp_client/lib/src/history/` | vendor-specific parser 留各 vendor client（步骤 15） |
| `features/agent/data/datasources/local_history/grok_user_content_parser.dart` | rewrite | `packages/grok_acp_client/lib/src/history/` | vendor-specific parser 留各 vendor client（步骤 15） |
| `features/agent/data/datasources/transport/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/agent/data/datasources/transport/json_rpc_stdio_transport.dart` | rewrite | `packages/json_rpc_transport/lib/src/` | JSON-RPC stdio、operation scheduler、runtime peer；构造注入 process starter/clock/logger |
| `features/agent/data/datasources/transport/provider_operation_scheduler.dart` | rewrite | `packages/json_rpc_transport/lib/src/` | JSON-RPC stdio、operation scheduler、runtime peer；构造注入 process starter/clock/logger |
| `features/agent/data/datasources/transport/provider_runtime_json_rpc_peer.dart` | rewrite | `packages/json_rpc_transport/lib/src/` | JSON-RPC stdio、operation scheduler、runtime peer；构造注入 process starter/clock/logger |

### 6.5 agent · data · mappers

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `features/agent/data/mappers/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/agent/data/mappers/acp_content_codec.dart` | rewrite | `packages/grok_acp_client/lib/src/acp/` | ACP 当前只有 Grok 一个消费者，不抽公共包（步骤 14） |
| `features/agent/data/mappers/acp_permission_mapper.dart` | rewrite | `packages/grok_acp_client/lib/src/acp/` | ACP 当前只有 Grok 一个消费者，不抽公共包（步骤 14） |
| `features/agent/data/mappers/acp_session_config_mapper.dart` | rewrite | `packages/grok_acp_client/lib/src/acp/` | ACP 当前只有 Grok 一个消费者，不抽公共包（步骤 14） |
| `features/agent/data/mappers/acp_session_update_decoder.dart` | rewrite | `packages/grok_acp_client/lib/src/acp/` | ACP 当前只有 Grok 一个消费者，不抽公共包（步骤 14） |
| `features/agent/data/mappers/claude_code_initialize_metadata_mapper.dart` | rewrite | `packages/claude_code_client/lib/src/mappers/` | Claude Code 协议映射 |
| `features/agent/data/mappers/claude_code_permission_mode_codec.dart` | rewrite | `packages/claude_code_client/lib/src/mappers/` | Claude Code 协议映射 |
| `features/agent/data/mappers/claude_code_stream_identity.dart` | rewrite | `packages/claude_code_client/lib/src/mappers/` | Claude Code 协议映射 |
| `features/agent/data/mappers/claude_code_usage_quota_mapper.dart` | rewrite | `packages/claude_code_client/lib/src/mappers/` | Claude Code 协议映射 |
| `features/agent/data/mappers/codex_app_server_helpers.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex 协议映射 |
| `features/agent/data/mappers/codex_approval_mapper.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex 协议映射 |
| `features/agent/data/mappers/codex_collaboration_mode_mapper.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex 协议映射 |
| `features/agent/data/mappers/codex_conversation_mode_codec.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex 协议映射 |
| `features/agent/data/mappers/codex_file_change_tracker.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex 协议映射 |
| `features/agent/data/mappers/codex_model_list_mapper.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex 协议映射 |
| `features/agent/data/mappers/codex_notification_mapper.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex 协议映射 |
| `features/agent/data/mappers/codex_permission_policy_codec.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex 协议映射 |
| `features/agent/data/mappers/codex_question_mapper.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex 协议映射 |
| `features/agent/data/mappers/codex_skills_mapper.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex 协议映射 |
| `features/agent/data/mappers/codex_turn_start_params_encoder.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex 协议映射 |
| `features/agent/data/mappers/context_window_codec.dart` | rewrite | `packages/agent_provider_contracts/lib/src/codecs/` | 三方共用的纯函数 codec；无 vendor 字段，符合 ADR-001 |
| `features/agent/data/mappers/grok_acp_notification_mapper.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok 协议映射 |
| `features/agent/data/mappers/grok_billing_quota_mapper.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok 协议映射 |
| `features/agent/data/mappers/grok_error_normalizer.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok 协议映射 |
| `features/agent/data/mappers/grok_file_change_tracker.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok 协议映射 |
| `features/agent/data/mappers/grok_permission_mode_codec.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok 协议映射 |
| `features/agent/data/mappers/grok_question_mapper.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok 协议映射 |
| `features/agent/data/mappers/grok_session_update_mapper.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok 协议映射 |
| `features/agent/data/mappers/grok_skills_mapper.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok 协议映射 |
| `features/agent/data/mappers/grok_stream_identity.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok 协议映射 |

### 6.6 agent · data · 顶层

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `features/agent/data/agent_ignored_message_logger.dart` | rewrite | `packages/zeta_logging/lib/src/` | 未匹配通知的诊断计数；只记 method/type/reason/count |
| `features/agent/data/agent_model_catalog_cache_store.dart` | rewrite | `packages/agent_config_client/lib/src/` | provider config / model catalog cache / turn-context 的当前 schema 持久化（步骤 11） |
| `features/agent/data/agent_provider_config_codec.dart` | rewrite | `packages/agent_config_client/lib/src/` | provider config / model catalog cache / turn-context 的当前 schema 持久化（步骤 11） |
| `features/agent/data/agent_provider_config_store.dart` | rewrite | `packages/agent_config_client/lib/src/` | provider config / model catalog cache / turn-context 的当前 schema 持久化（步骤 11） |
| `features/agent/data/agent_provider_permission_migration.dart` | delete | — | 旧权限值升级逻辑；无历史数据兼容（拓扑 §1） |
| `features/agent/data/agent_provider_static_capabilities.dart` | rewrite | 三个 vendor client 各自声明 | 拆分：每个 client 声明自己的静态能力，消除集中式 kind switch |
| `features/agent/data/agent_turn_context_codec.dart` | rewrite | `packages/agent_config_client/lib/src/` | provider config / model catalog cache / turn-context 的当前 schema 持久化（步骤 11） |
| `features/agent/data/agent_turn_context_store.dart` | rewrite | `packages/agent_config_client/lib/src/` | provider config / model catalog cache / turn-context 的当前 schema 持久化（步骤 11） |
| `features/agent/data/claude_code_cli_locator.dart` | rewrite | `packages/claude_code_client/lib/src/` | CLI locator 每个 vendor 恰好一个归属 |
| `features/agent/data/cli_command_locator.dart` | rewrite | packages/agent_provider_contracts/ + 三个 vendor client | ResolvedCliProcessCommand 值类型入 contracts；locate 实现各 vendor 一份（步骤 17） |
| `features/agent/data/codex_cli_locator.dart` | rewrite | `packages/codex_app_server_client/lib/src/` | CLI locator 每个 vendor 恰好一个归属 |
| `features/agent/data/default_agent_provider_factory.dart` | rewrite | `packages/agent_provider_repository/lib/src/` | bundle factory registry 属 Repository；不在 Data 层做 kind 分支 |
| `features/agent/data/grok_cli_locator.dart` | rewrite | `packages/grok_acp_client/lib/src/` | CLI locator 每个 vendor 恰好一个归属 |
| `features/agent/data/native_agent_provider_bundles.dart` | rewrite | `packages/agent_provider_repository/lib/src/` | bundle 组装归 provider repository |
| `features/agent/data/repositories/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |

### 6.7 agent · application（最高风险，逐个裁决）

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `features/agent/application/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/agent/application/agent_conversation_binding.dart` | rewrite | `packages/agent_conversation_repository/` | 会话聚合根，外部数据编排 |
| `features/agent/application/agent_conversation_binding_manager.dart` | rewrite | `packages/agent_conversation_repository/` | 会话生命周期与 lease |
| `features/agent/application/agent_conversation_effect.dart` | rewrite | `packages/agent_conversation_repository/` | 协议 effect 属领域编排 |
| `features/agent/application/agent_conversation_effect_runner.dart` | rewrite | `packages/agent_conversation_repository/` | effect 执行器；UI effect 剥离到 Bloc |
| `features/agent/application/agent_conversation_event_processor.dart` | rewrite | `packages/agent_conversation_repository/` | Provider 事件归一化 |
| `features/agent/application/agent_conversation_mode_controller.dart` | rewrite | `lib/agent_chat/bloc/` | 模式**选择**是交互状态 → Bloc |
| `features/agent/application/agent_conversation_model_selection_controller.dart` | rewrite | `lib/agent_chat/bloc/` | 模型**选择**是交互状态 → Bloc |
| `features/agent/application/agent_conversation_mutation.dart` | rewrite | `packages/agent_conversation_repository/` | domain snapshot 变更描述 |
| `features/agent/application/agent_conversation_permission_selection_controller.dart` | rewrite | `lib/agent_chat/bloc/` | 权限选项**选择** → Bloc |
| `features/agent/application/agent_conversation_permission_state.dart` | rewrite | 拆分 | pending 请求 → Repository；UI 选中态 → Bloc State |
| `features/agent/application/agent_conversation_reducer.dart` | rewrite | `packages/agent_conversation_repository/` | 确定性归并留 Repository（ADR-004） |
| `features/agent/application/agent_conversation_thread_snapshot.dart` | rewrite | `packages/agent_conversation_repository/` | domain snapshot |
| `features/agent/application/agent_conversation_timeline_store.dart` | rewrite | 拆分 | 2,017 行：domain aggregate → Repository；UI slice → Bloc State |
| `features/agent/application/agent_elapsed_ticker.dart` | rewrite | `lib/agent_chat/bloc/` | 计时是 UI 派生状态；Bloc 持有 timer 并在 close() 取消 |
| `features/agent/application/agent_event_coalescing_policy.dart` | rewrite | `packages/agent_conversation_repository/` | 事件合并属数据管线 |
| `features/agent/application/agent_event_pipeline.dart` | rewrite | `packages/agent_conversation_repository/` | 事件管线核心 |
| `features/agent/application/agent_model_catalog_repository.dart` | rewrite | `packages/agent_provider_repository/` | 模型目录 TTL 缓存真源 |
| `features/agent/application/agent_permission_catalog_controller.dart` | rewrite | `packages/agent_provider_repository/` | 权限目录是外部数据；选中态归 Bloc |
| `features/agent/application/agent_permission_request_resolver.dart` | rewrite | `packages/agent_conversation_repository/` | pending 权限请求解析 |
| `features/agent/application/agent_plan_execution_handoff_controller.dart` | rewrite | `lib/agent_chat/bloc/` | 本地交接是业务规则 → Bloc（步骤 32） |
| `features/agent/application/agent_provider_config_store.dart` | rewrite | `packages/agent_provider_repository/` | 配置编排；IO 下沉 agent_config_client |
| `features/agent/application/agent_provider_event_listener_gate.dart` | rewrite | `packages/agent_conversation_repository/` | 订阅闸门属外部数据生命周期 |
| `features/agent/application/agent_provider_global_runtime.dart` | rewrite | `packages/agent_provider_repository/` | 全局 runtime 持有 |
| `features/agent/application/agent_provider_runtime_identity.dart` | rewrite | `packages/agent_conversation_repository/` | runtime generation 判定 |
| `features/agent/application/agent_provider_runtime_registry.dart` | rewrite | `packages/agent_conversation_repository/` | runtime lease 注册表 |
| `features/agent/application/agent_provider_settings_controller.dart` | rewrite | `packages/agent_provider_repository/` | Provider 设置持久化 |
| `features/agent/application/agent_provider_settings_port.dart` | rewrite | `packages/agent_provider_contracts/` | 纯端口定义 |
| `features/agent/application/agent_skills_catalog_controller.dart` | rewrite | `packages/agent_provider_repository/` | Skill 目录是外部数据 |
| `features/agent/application/agent_thread_workspace_controller.dart` | rewrite | `packages/project_session_repository/` | thread↔workspace 关联数据 |
| `features/agent/application/agent_turn_context_overlay.dart` | rewrite | `packages/agent_conversation_repository/` | turn context 叠加属领域 |
| `features/agent/application/agent_turn_context_recorder.dart` | rewrite | `packages/agent_conversation_repository/` | turn context 记录 |
| `features/agent/application/agent_ui_update_port.dart` | delete | — | UI 更新端口被 Bloc State + BlocSelector 取代 |
| `features/agent/application/agent_ui_update_request.dart` | rewrite | `lib/agent_chat/view/` | AgentUiRegion/urgency 保留给 Presentation 帧调度器（拓扑 §5） |
| `features/agent/application/bounded_event_dispatcher.dart` | rewrite | `packages/agent_conversation_repository/` | 有界事件分发与背压 |
| `features/agent/application/coalescing_event_buffer.dart` | rewrite | `packages/agent_conversation_repository/` | 合并缓冲 |

### 6.8 agent · presentation

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `features/agent/presentation/agent_conversation_navigation.dart` | rewrite | `lib/app/router/` | 导航改 typed GoRouter route；Bloc 不依赖 GoRouter |
| `features/agent/presentation/agent_conversation_ui_state.dart` | rewrite | `lib/agent_chat/bloc/` | 1,098 行 → AgentConversationState 五个 slice |
| `features/agent/presentation/agent_conversation_view_model.dart` | rewrite | `lib/agent_chat/bloc/` | 4,190 行 ViewModel → AgentConversationBloc（见会话状态设计文档） |
| `features/agent/presentation/agent_file_change_projection.dart` | rewrite | `lib/agent_chat/view/` | Presentation helper：投影、缓存、分组、调度器保持在 Presentation 层 |
| `features/agent/presentation/agent_file_change_projection_cache.dart` | rewrite | `lib/agent_chat/view/` | Presentation helper：投影、缓存、分组、调度器保持在 Presentation 层 |
| `features/agent/presentation/agent_markdown_cache.dart` | rewrite | `lib/agent_chat/view/` | Presentation helper：投影、缓存、分组、调度器保持在 Presentation 层 |
| `features/agent/presentation/agent_pane.dart` | rewrite | `lib/agent_chat/view/` | Presentation helper：投影、缓存、分组、调度器保持在 Presentation 层 |
| `features/agent/presentation/agent_plan_revision_drafts.dart` | rewrite | `lib/agent_chat/view/` | Presentation helper：投影、缓存、分组、调度器保持在 Presentation 层 |
| `features/agent/presentation/agent_presentation_l10n.dart` | rewrite | `lib/l10n/` | typed failure/code → ARB 的穷尽映射 |
| `features/agent/presentation/agent_timeline_extent_descriptor.dart` | rewrite | `lib/agent_chat/view/` | Presentation helper：投影、缓存、分组、调度器保持在 Presentation 层 |
| `features/agent/presentation/agent_timeline_grouping.dart` | rewrite | `lib/agent_chat/view/` | Presentation helper：投影、缓存、分组、调度器保持在 Presentation 层 |
| `features/agent/presentation/agent_timeline_projection.dart` | rewrite | `lib/agent_chat/view/` | Presentation helper：投影、缓存、分组、调度器保持在 Presentation 层 |
| `features/agent/presentation/agent_timeline_projection_cache.dart` | rewrite | `lib/agent_chat/view/` | Presentation helper：投影、缓存、分组、调度器保持在 Presentation 层 |
| `features/agent/presentation/agent_ui_update_scheduler.dart` | rewrite | `lib/agent_chat/view/` | Presentation helper：投影、缓存、分组、调度器保持在 Presentation 层 |
| `features/agent/presentation/composer_document.dart` | rewrite | `lib/agent_chat/view/` | Presentation helper：投影、缓存、分组、调度器保持在 Presentation 层 |
| `features/agent/presentation/model_config_ui_state.dart` | rewrite | `lib/agent_chat/view/` | Presentation helper：投影、缓存、分组、调度器保持在 Presentation 层 |
| `features/agent/presentation/widgets/agent_file_change_evidence_card.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/agent_file_change_evidence_views.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/agent_mention_file_picker.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/agent_mode_selector.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/agent_model_config.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/agent_pane_cards.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/agent_pane_composer.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/agent_pane_context_panel.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/agent_pane_header.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/agent_pane_messages.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/agent_pane_navigation_rail.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/agent_pane_plan_panel.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/agent_pane_sections.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/agent_pane_styles.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/agent_provider_icon.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/agent_skill_picker.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/agent_slash_command_picker.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |
| `features/agent/presentation/widgets/composer_selector_popover.dart` | rewrite | `lib/agent_chat/widgets/` | 改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33） |

### 6.9 agent_management

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `features/agent_management/application/agent_management_controller.dart` | rewrite | packages/agent_management_repository/ 或 lib/agent_management/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/agent_management/data/claude_code_agent_management_repository.dart` | rewrite | `packages/agent_management_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/agent_management/data/claude_code_auth_status_probe.dart` | rewrite | `packages/agent_management_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/agent_management/data/cli_process_runner.dart` | rewrite | `packages/agent_management_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/agent_management/data/codex_agent_management_repository.dart` | rewrite | `packages/agent_management_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/agent_management/data/grok_agent_management_repository.dart` | rewrite | `packages/agent_management_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/agent_management/domain/agent_cli_management_repository.dart` | rewrite | `packages/agent_management_repository/lib/src/` | domain model 归 Repository |
| `features/agent_management/domain/agent_management_models.dart` | rewrite | `packages/agent_management_repository/lib/src/` | domain model 归 Repository |
| `features/agent_management/domain/agent_management_text_catalog.dart` | delete | — | TextCatalog 删除（步骤 28） |
| `features/agent_management/domain/fallback_agent_management_text_catalog.dart` | delete | — | Fallback TextCatalog 删除（步骤 28） |
| `features/agent_management/presentation/agent_configuration_editor.dart` | rewrite | `lib/agent_management/view/` | Page 注入 Bloc，View/Widget 消费 State |
| `features/agent_management/presentation/agent_log_view.dart` | rewrite | `lib/agent_management/view/` | Page 注入 Bloc，View/Widget 消费 State |
| `features/agent_management/presentation/agent_management_l10n.dart` | rewrite | `lib/agent_management/view/` | Page 注入 Bloc，View/Widget 消费 State |
| `features/agent_management/presentation/agent_management_page.dart` | rewrite | `lib/agent_management/view/` | Page 注入 Bloc，View/Widget 消费 State |

### 6.10 desktop_notifications

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `features/desktop_notifications/application/desktop_attention_controller.dart` | rewrite | packages/desktop_notifications_repository/ 或 lib/desktop_notifications/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/desktop_notifications/data/flutter_desktop_notification_service.dart` | rewrite | `packages/desktop_notifications_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/desktop_notifications/data/method_channel_desktop_attention_indicator.dart` | rewrite | `packages/desktop_notifications_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/desktop_notifications/domain/desktop_attention_models.dart` | rewrite | `packages/desktop_notifications_repository/lib/src/` | domain model 归 Repository |
| `features/desktop_notifications/domain/desktop_attention_text_catalog.dart` | delete | — | TextCatalog 删除（步骤 28） |
| `features/desktop_notifications/domain/fallback_desktop_attention_text_catalog.dart` | delete | — | Fallback TextCatalog 删除（步骤 28） |

### 6.11 ide_session

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `features/ide_session/application/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/ide_session/application/ide_session_persistence_coordinator.dart` | rewrite | packages/project_session_repository/ 或 lib/ide_session/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/ide_session/application/ide_session_restore_result.dart` | rewrite | packages/project_session_repository/ 或 lib/ide_session/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/ide_session/application/ide_session_state_builder.dart` | rewrite | packages/project_session_repository/ 或 lib/ide_session/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/ide_session/data/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/ide_session/data/ide_session_store.dart` | rewrite | `packages/project_session_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/ide_session/domain/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/ide_session/domain/ide_session_state.dart` | rewrite | `packages/project_session_repository/lib/src/` | domain model 归 Repository |
| `features/ide_session/domain/ide_workbench_layout_state.dart` | rewrite | `packages/project_session_repository/lib/src/` | domain model 归 Repository |
| `features/ide_session/domain/recent_project_summary.dart` | rewrite | `packages/project_session_repository/lib/src/` | domain model 归 Repository |

### 6.12 project_threads

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `features/project_threads/application/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/project_threads/application/project_threads_controller.dart` | rewrite | packages/project_session_repository/ 或 lib/project_threads/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/project_threads/application/project_threads_session_snapshot_codec.dart` | rewrite | packages/project_session_repository/ 或 lib/project_threads/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/project_threads/data/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/project_threads/domain/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/project_threads/domain/project_thread_list_state.dart` | rewrite | `packages/project_session_repository/lib/src/` | domain model 归 Repository |
| `features/project_threads/domain/project_threads_session_snapshot.dart` | rewrite | `packages/project_session_repository/lib/src/` | domain model 归 Repository |
| `features/project_threads/presentation/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/project_threads/presentation/project_threads_view_model.dart` | rewrite | `lib/project_threads/view/` | Page 注入 Bloc，View/Widget 消费 State |

### 6.13 settings

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `features/settings/application/app_language_resolver.dart` | rewrite | packages/settings_repository/ 或 lib/settings/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/settings/application/appearance_settings_controller.dart` | rewrite | packages/settings_repository/ 或 lib/settings/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/settings/application/general_settings_controller.dart` | rewrite | packages/settings_repository/ 或 lib/settings/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/settings/application/general_settings_update_result.dart` | rewrite | packages/settings_repository/ 或 lib/settings/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/settings/data/appearance_settings_store.dart` | rewrite | `packages/settings_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/settings/data/general_settings_codec.dart` | rewrite | `packages/settings_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/settings/data/general_settings_store.dart` | rewrite | `packages/settings_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/settings/data/system_font_catalog_service.dart` | rewrite | `packages/settings_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/settings/domain/app_language.dart` | rewrite | `packages/settings_repository/lib/src/` | domain model 归 Repository |
| `features/settings/domain/appearance_settings.dart` | rewrite | `packages/settings_repository/lib/src/` | domain model 归 Repository |
| `features/settings/domain/general_settings.dart` | rewrite | `packages/settings_repository/lib/src/` | domain model 归 Repository |
| `features/settings/domain/system_font_family.dart` | rewrite | `packages/settings_repository/lib/src/` | domain model 归 Repository |
| `features/settings/presentation/settings_page.dart` | rewrite | `lib/settings/view/` | Page 注入 Bloc，View/Widget 消费 State |

### 6.14 usage_statistics

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `features/usage_statistics/application/agent_usage_panel_controller.dart` | rewrite | packages/usage_statistics_repository/ 或 lib/usage_statistics/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/usage_statistics/application/agent_usage_query_service.dart` | rewrite | packages/usage_statistics_repository/ 或 lib/usage_statistics/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/usage_statistics/application/agent_usage_refresh_coordinator.dart` | rewrite | packages/usage_statistics_repository/ 或 lib/usage_statistics/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/usage_statistics/application/agent_usage_token_aggregation.dart` | rewrite | packages/usage_statistics_repository/ 或 lib/usage_statistics/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/usage_statistics/application/query_agent_usage_panel_repository.dart` | rewrite | packages/usage_statistics_repository/ 或 lib/usage_statistics/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/usage_statistics/application/query_usage_statistics_repository.dart` | rewrite | packages/usage_statistics_repository/ 或 lib/usage_statistics/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/usage_statistics/application/usage_statistics_controller.dart` | rewrite | packages/usage_statistics_repository/ 或 lib/usage_statistics/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/usage_statistics/application/usage_statistics_report_builder.dart` | rewrite | packages/usage_statistics_repository/ 或 lib/usage_statistics/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/usage_statistics/data/built_in_agent_token_usage_source_registry.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/usage_statistics/data/global_runtime_agent_usage_quota_source.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/usage_statistics/data/legacy_usage_statistics_index_decoder.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/usage_statistics/data/providers/claude_code/claude_code_token_usage_source.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/usage_statistics/data/providers/claude_code/claude_code_usage_partition_codec.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/usage_statistics/data/providers/codex/codex_token_usage_source.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/usage_statistics/data/providers/codex/codex_usage_log_scanner.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/usage_statistics/data/providers/codex/codex_usage_partition_codec.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/usage_statistics/data/providers/grok/grok_token_usage_source.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/usage_statistics/data/providers/grok/grok_usage_log_scanner.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/usage_statistics/data/providers/grok/grok_usage_partition_codec.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/usage_statistics/data/providers/usage_scan_cache.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/usage_statistics/data/usage_statistics_partition_store.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | 外部 IO 与当前 schema 读写下沉 Data 包 |
| `features/usage_statistics/domain/agent_token_usage_source.dart` | rewrite | `packages/usage_statistics_repository/lib/src/` | domain model 归 Repository |
| `features/usage_statistics/domain/agent_usage_panel_models.dart` | rewrite | `packages/usage_statistics_repository/lib/src/` | domain model 归 Repository |
| `features/usage_statistics/domain/agent_usage_query_models.dart` | rewrite | `packages/usage_statistics_repository/lib/src/` | domain model 归 Repository |
| `features/usage_statistics/domain/agent_usage_quota_source.dart` | rewrite | `packages/usage_statistics_repository/lib/src/` | domain model 归 Repository |
| `features/usage_statistics/domain/fallback_usage_statistics_text_catalog.dart` | delete | — | Fallback TextCatalog 删除（步骤 28） |
| `features/usage_statistics/domain/usage_statistics_models.dart` | rewrite | `packages/usage_statistics_repository/lib/src/` | domain model 归 Repository |
| `features/usage_statistics/domain/usage_statistics_repository.dart` | rewrite | `packages/usage_statistics_repository/lib/src/` | domain model 归 Repository |
| `features/usage_statistics/domain/usage_statistics_text_catalog.dart` | delete | — | TextCatalog 删除（步骤 28） |
| `features/usage_statistics/presentation/agent_usage_panel.dart` | rewrite | `lib/usage_statistics/view/` | Page 注入 Bloc，View/Widget 消费 State |
| `features/usage_statistics/presentation/agent_usage_quota_gallery.dart` | rewrite | `lib/usage_statistics/view/` | Page 注入 Bloc，View/Widget 消费 State |
| `features/usage_statistics/presentation/usage_statistics_formatters.dart` | rewrite | `lib/usage_statistics/view/` | Page 注入 Bloc，View/Widget 消费 State |
| `features/usage_statistics/presentation/usage_statistics_l10n.dart` | rewrite | `lib/usage_statistics/view/` | Page 注入 Bloc，View/Widget 消费 State |
| `features/usage_statistics/presentation/usage_statistics_page.dart` | rewrite | `lib/usage_statistics/view/` | Page 注入 Bloc，View/Widget 消费 State |
| `features/usage_statistics/presentation/usage_time_range_filter.dart` | rewrite | `lib/usage_statistics/view/` | Page 注入 Bloc，View/Widget 消费 State |

### 6.15 workspace

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `features/workspace/application/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/workspace/application/workspace_file_index_controller.dart` | rewrite | packages/workspace_repository/ 或 lib/workspace/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/workspace/application/workspace_file_indexer.dart` | rewrite | packages/workspace_repository/ 或 lib/workspace/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/workspace/application/workspace_tree_builder.dart` | rewrite | packages/workspace_repository/ 或 lib/workspace/ | 逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit |
| `features/workspace/data/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/workspace/domain/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/workspace/domain/workspace_directory_rules.dart` | rewrite | `packages/workspace_repository/lib/src/` | domain model 归 Repository |
| `features/workspace/domain/workspace_file_query.dart` | rewrite | `packages/workspace_repository/lib/src/` | domain model 归 Repository |
| `features/workspace/domain/workspace_gitignore.dart` | rewrite | `packages/workspace_repository/lib/src/` | domain model 归 Repository |
| `features/workspace/domain/workspace_node.dart` | rewrite | `packages/workspace_repository/lib/src/` | domain model 归 Repository |
| `features/workspace/presentation/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `features/workspace/presentation/file_tree_pane.dart` | rewrite | `lib/workspace/view/` | Page 注入 Bloc，View/Widget 消费 State |

### 6.16 ui

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `ui/core/app_theme.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_activity_rail.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_button.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_chip.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_choice_card.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_collapsible_card.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_colors.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_context_menu.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_dialog.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_effects.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_icon_box.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_image_preview.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_metrics.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_motion.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_popover.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_resize_handle.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_select.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_skeleton.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_spacing.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_stable_overlay_handler.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_status_card.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_switch.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_tabs.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_text_styles.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/ide_toast.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/layout/ide_constraint_bucket_builder.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/metrics/compact_metric_bar.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/pane_widgets.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/rows/ide_data_row.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/rows/ide_key_value_row.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/rows/ide_list_row.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/rows/ide_row_divider.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/rows/ide_row_group.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/rows/ide_settings_row.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/surfaces/ide_surface.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/virtualization/ide_dynamic_sliver_list.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/virtualization/ide_extent_index.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/virtualization/ide_smooth_scroll_controller.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/virtualization/ide_virtual_item.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/virtualization/ide_virtual_list_controller.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/virtualization/ide_virtual_scroll_coordinator.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/virtualization/ide_virtual_scrollbar.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/window_frame.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/workbench/ide_page_body.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/workbench/ide_page_header.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/workbench/ide_retained_page_view.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/workbench/ide_section.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/workbench/ide_toolbar.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/core/workbench/ide_workbench_scaffold.dart` | rewrite | `packages/app_ui/lib/src/` | 设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27） |
| `ui/features/ide/views/global_home_page.dart` | rewrite | `lib/ide_shell/view/` | IDE shell 页面；导航改 typed route |
| `ui/features/ide/views/global_home_page_preview.dart` | rewrite | `lib/ide_shell/view/` | IDE shell 页面；导航改 typed route |
| `ui/features/ide/views/ide_home.dart` | rewrite | `lib/ide_shell/view/` | IDE shell 页面；导航改 typed route |
| `ui/features/ide/views/new_thread_provider_popover.dart` | rewrite | `lib/ide_shell/view/` | IDE shell 页面；导航改 typed route |
| `ui/features/ide/views/project_agent_sidebar.dart` | rewrite | `lib/ide_shell/view/` | IDE shell 页面；导航改 typed route |
| `ui/features/ide/views/project_home_page.dart` | rewrite | `lib/ide_shell/view/` | IDE shell 页面；导航改 typed route |
| `ui/features/ide/views/project_list_pane.dart` | rewrite | `lib/ide_shell/view/` | IDE shell 页面；导航改 typed route |
| `ui/localization/app_localizations_x.dart` | rewrite | `lib/l10n/l10n.dart` | l10n / l10nOrNull 扩展 |
| `ui/localization/arb/app_en.arb` | move | `lib/l10n/arb/` | en/zh 各 1,040 键；删除脚手架 app_es.arb（步骤 5） |
| `ui/localization/arb/app_zh.arb` | move | `lib/l10n/arb/` | en/zh 各 1,040 键；删除脚手架 app_es.arb（步骤 5） |
| `ui/localization/generated/app_localizations.dart` | regenerate | `lib/l10n/generated/` | 由 flutter gen-l10n 重新生成；不手工迁移（步骤 5） |
| `ui/localization/generated/app_localizations_en.dart` | regenerate | `lib/l10n/generated/` | 由 flutter gen-l10n 重新生成；不手工迁移（步骤 5） |
| `ui/localization/generated/app_localizations_zh.dart` | regenerate | `lib/l10n/generated/` | 由 flutter gen-l10n 重新生成；不手工迁移（步骤 5） |
| `ui/localization/relative_time.dart` | rewrite | `lib/l10n/` | 相对时间文案依赖 ARB，留 app |
| `ui/localization/zeta_shadcn_localizations.dart` | rewrite | `lib/l10n/` | 留在 app，不进 app_ui（拓扑 §8） |

**`lib/` 覆盖校验**：378 / 378

---

## 7. `test/`（305）— 按规则分组

测试跟随其被测对象的归属，因此按规则分组而非逐文件列举；每条规则的命中数已核对，合计等于 `test/` 的全部跟踪文件。**规则按最长前缀优先匹配**：表中靠上的更具体规则先生效，靠下的通用规则只覆盖剩余文件。

| 规则命中 | 文件数 | 动作 | 目标 | 说明 |
| --- | ---: | --- | --- | --- |
| `test/src/features/agent/data/datasources/claude_code/**` | 31 | rewrite | `packages/claude_code_client/test/` | 含 fixtures/ 子目录（步骤 17） |
| `test/src/features/agent/data/datasources/app_server/**` | 3 | rewrite | `packages/codex_app_server_client/test/` | fixture 按 package 分配，无跨包 import（步骤 17） |
| `test/src/features/agent/data/datasources/transport/**` | 3 | rewrite | `packages/json_rpc_transport/test/` | — |
| `test/src/features/agent/data/datasources/acp/**` | 2 | rewrite | `packages/grok_acp_client/test/` | fixture 按 package 分配（步骤 17） |
| `test/src/features/agent/presentation/**` | 30 | rewrite | `test/agent_chat/ + packages/app_ui/test/` | MockBloc widget test + golden |
| `test/tool/report_test_timings_test.dart` | 1 | rewrite | tool/ 的配套测试 | — |
| `test/src/features/agent/application/**` | 25 | rewrite | 按 ownership_map 分配到 repository 包与 lib/agent_chat/ 的 blocTest | — |
| `test/support/scroll_metrics_trace.dart` | 1 | rewrite | `test/helpers/` | pumpApp 等共享 widget 测试工具 |
| `test/src/features/agent/domain/**` | 18 | rewrite | `packages/agent_provider_contracts/test/` | — |
| `test/src/features/agent/data/**` | 33 | rewrite | 按 mapper 前缀分配到对应 vendor package | — |
| `test/flutter_test_config.dart` | 1 | rewrite | `test/flutter_test_config.dart` | golden 字体加载与全局测试配置；workspace 内每个含 widget test 的包各一份 |
| `test/src/architecture/**` | 3 | rewrite | `test/architecture/ + .architecture.yaml` | 架构门禁重写为读取 .architecture.yaml 的断言（步骤 6） |
| `test/src/features/**` | 55 | rewrite | 对应 package/test 或 test/<feature>/ | 测试镜像 lib/；跟随其被测对象的归属 |
| `test/src/testing/**` | 13 | rewrite | 各 package 的 test/helpers/ | 共享 harness 按包复制；禁止跨包 test import |
| `test/fixtures/**` | 29 | rewrite | 按 Provider 分配到对应 vendor package 的 test/fixtures/ | — |
| `test/src/core/**` | 4 | rewrite | packages/zeta_logging/test/ 与 packages/zeta_storage/test/ | — |
| `test/src/app/**` | 11 | rewrite | `test/app/` | — |
| `test/src/ui/**` | 42 | rewrite | packages/app_ui/test/ 与 test/ide_shell/ | — |

> **fixture 归属是硬约束**：[步骤 17](./migration_tasks.md) 要求「现有协议 fixture 按 package 分配，
> 无跨包 test import」。`test/fixtures/` 下的 `agent_file_change_evidence`、
> `agent_permission_runtime_architecture`、`agent_stream_identity`、`grok` 四个目录必须先按 Provider
> 拆分，再随对应 vendor package 迁移。共享 harness 采用复制而非跨包引用。

---

## 8. 桌面平台（65）

三平台统一 `cn.easii.zeta` / 产品名 `Zeta`，三个 flavor 不加身份后缀（[步骤 3](./migration_tasks.md)）。
生成的 plugin registrant 可重新生成；手写 Runner、MethodChannel、图标必须逐个确认。

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `linux/.gitignore` | rewrite | `linux/` | 新仓库缺 Linux scaffold，先由 flutter create 生成再迁入手写部分（步骤 3） |
| `linux/CMakeLists.txt` | rewrite | `linux/` | 新仓库缺 Linux scaffold，先由 flutter create 生成再迁入手写部分（步骤 3） |
| `linux/flutter/CMakeLists.txt` | rewrite | `linux/` | 新仓库缺 Linux scaffold，先由 flutter create 生成再迁入手写部分（步骤 3） |
| `linux/flutter/generated_plugin_registrant.cc` | rewrite | `linux/` | 新仓库缺 Linux scaffold，先由 flutter create 生成再迁入手写部分（步骤 3） |
| `linux/flutter/generated_plugin_registrant.h` | rewrite | `linux/` | 新仓库缺 Linux scaffold，先由 flutter create 生成再迁入手写部分（步骤 3） |
| `linux/flutter/generated_plugins.cmake` | rewrite | `linux/` | 新仓库缺 Linux scaffold，先由 flutter create 生成再迁入手写部分（步骤 3） |
| `linux/runner/CMakeLists.txt` | rewrite | `linux/` | 新仓库缺 Linux scaffold，先由 flutter create 生成再迁入手写部分（步骤 3） |
| `linux/runner/desktop_attention_channel.cc` | rewrite | `linux/` | 新仓库缺 Linux scaffold，先由 flutter create 生成再迁入手写部分（步骤 3） |
| `linux/runner/desktop_attention_channel.h` | rewrite | `linux/` | 新仓库缺 Linux scaffold，先由 flutter create 生成再迁入手写部分（步骤 3） |
| `linux/runner/main.cc` | rewrite | `linux/` | 新仓库缺 Linux scaffold，先由 flutter create 生成再迁入手写部分（步骤 3） |
| `linux/runner/my_application.cc` | rewrite | `linux/` | 新仓库缺 Linux scaffold，先由 flutter create 生成再迁入手写部分（步骤 3） |
| `linux/runner/my_application.h` | rewrite | `linux/` | 新仓库缺 Linux scaffold，先由 flutter create 生成再迁入手写部分（步骤 3） |
| `linux/runner/resources/app_icon.png` | rewrite | `linux/` | 新仓库缺 Linux scaffold，先由 flutter create 生成再迁入手写部分（步骤 3） |
| `linux/runner/system_font_catalog_channel.cc` | rewrite | `linux/` | 新仓库缺 Linux scaffold，先由 flutter create 生成再迁入手写部分（步骤 3） |
| `linux/runner/system_font_catalog_channel.h` | rewrite | `linux/` | 新仓库缺 Linux scaffold，先由 flutter create 生成再迁入手写部分（步骤 3） |
| `macos/.gitignore` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Flutter/Flutter-Debug.xcconfig` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Flutter/Flutter-Release.xcconfig` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Flutter/GeneratedPluginRegistrant.swift` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner.xcodeproj/project.pbxproj` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner.xcworkspace/contents.xcworkspacedata` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/AppDelegate.swift` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/Base.lproj/MainMenu.xib` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/Configs/AppInfo.xcconfig` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/Configs/Debug.xcconfig` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/Configs/Release.xcconfig` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/Configs/Warnings.xcconfig` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/DebugProfile.entitlements` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/Info.plist` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/MainFlutterWindow.swift` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/Runner/Release.entitlements` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `macos/RunnerTests/RunnerTests.swift` | rewrite | `macos/` | 手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3） |
| `windows/.gitignore` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/CMakeLists.txt` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/flutter/CMakeLists.txt` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/flutter/generated_plugin_registrant.cc` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/flutter/generated_plugin_registrant.h` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/flutter/generated_plugins.cmake` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/runner/CMakeLists.txt` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/runner/Runner.rc` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/runner/desktop_attention_channel.cpp` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/runner/desktop_attention_channel.h` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/runner/flutter_window.cpp` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/runner/flutter_window.h` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/runner/main.cpp` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/runner/resource.h` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/runner/resources/app_icon.ico` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/runner/runner.exe.manifest` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/runner/system_font_catalog_channel.cpp` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/runner/system_font_catalog_channel.h` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/runner/utils.cpp` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/runner/utils.h` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/runner/win32_window.cpp` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |
| `windows/runner/win32_window.h` | rewrite | `windows/` | 手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3） |

> **Linux 注意**：新仓库当前**没有** `linux/` 目录。正确顺序是先 `flutter create --platforms=linux .`
> 生成 scaffold，再把上表手写部分迁入——不要直接复制旧仓库的 `linux/`，否则 Flutter 版本差异会导致构建失败。

---

## 9. assets、协议快照与 CI

### 9.1 `assets/`（13）

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `assets/branding/zeta_logo.svg` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons（步骤 5） |
| `assets/fonts/Geist-Bold.ttf` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons（步骤 5） |
| `assets/fonts/Geist-Medium.ttf` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons（步骤 5） |
| `assets/fonts/Geist-Regular.ttf` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons（步骤 5） |
| `assets/fonts/Geist-SemiBold.ttf` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons（步骤 5） |
| `assets/fonts/JetBrainsMono-Bold.ttf` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons（步骤 5） |
| `assets/fonts/JetBrainsMono-Medium.ttf` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons（步骤 5） |
| `assets/fonts/JetBrainsMono-Regular.ttf` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons（步骤 5） |
| `assets/fonts/OFL-Geist.txt` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons（步骤 5） |
| `assets/fonts/OFL-JetBrainsMono.txt` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons（步骤 5） |
| `assets/icons/agents/claude.svg` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons（步骤 5） |
| `assets/icons/agents/codex.svg` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons（步骤 5） |
| `assets/icons/agents/grok.svg` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons（步骤 5） |

### 9.2 `third_party/`（269）

整体作为一个单元 `move`，路径不变。裁决理由见 §5.1。

| 规则 | 文件数 | 动作 | 目标 |
| --- | ---: | --- | --- |
| `third_party/codex_app_server_schema/**` | 269 | move | `third_party/codex_app_server_schema/` |

### 9.3 `.github/`（6）

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | rewrite | `.github/` | 新仓库已有 VGV workflow；只迁移 OSV / license / 架构门禁增量（步骤 6） |
| `.github/ISSUE_TEMPLATE/config.yml` | rewrite | `.github/` | 新仓库已有 VGV workflow；只迁移 OSV / license / 架构门禁增量（步骤 6） |
| `.github/ISSUE_TEMPLATE/feature_request.yml` | rewrite | `.github/` | 新仓库已有 VGV workflow；只迁移 OSV / license / 架构门禁增量（步骤 6） |
| `.github/PULL_REQUEST_TEMPLATE.md` | rewrite | `.github/` | 新仓库已有 VGV workflow；只迁移 OSV / license / 架构门禁增量（步骤 6） |
| `.github/workflows/ci.yml` | rewrite | `.github/` | 新仓库已有 VGV workflow；只迁移 OSV / license / 架构门禁增量（步骤 6） |
| `.github/workflows/release.yml` | rewrite | `.github/` | 新仓库已有 VGV workflow；只迁移 OSV / license / 架构门禁增量（步骤 6） |

---

## 10. 根目录文件（19）

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `.gitignore` | rewrite | `.gitignore` | 合并旧规则；移除 Rust/packaging 相关条目 |
| `.metadata` | regenerate | `.metadata` | 由新仓库 flutter create 生成 |
| `AGENTS.md` | rewrite | `AGENTS.md` | 28KB 旧约束；G1–G8 改写为 .architecture.yaml 可判定的门禁 |
| `CHANGELOG.md` | rewrite | `CHANGELOG.md` | 新仓库从 1.0.0+1 重新起算 |
| `CLAUDE.md` | rewrite | `CLAUDE.md` | 指向新仓库文档索引 |
| `CODE_OF_CONDUCT.md` | move | `CODE_OF_CONDUCT.md` |  |
| `CONTRIBUTING.en.md` | rewrite | `CONTRIBUTING.en.md` |  |
| `CONTRIBUTING.md` | rewrite | `CONTRIBUTING.md` | 按 VGV 四门与架构门禁重写 |
| `LICENSE` | move | `LICENSE` |  |
| `README.en.md` | rewrite | `README.en.md` |  |
| `README.md` | rewrite | `README.md` | 按新架构重写；保留中英双版 |
| `SECURITY.md` | move | `SECURITY.md` |  |
| `analysis_options.yaml` | rewrite | `analysis_options.yaml` | 统一 very_good_analysis |
| `dart_test.yaml` | rewrite | `dart_test.yaml` | random ordering + golden tag（步骤 6） |
| `devtools_options.yaml` | move | `devtools_options.yaml` |  |
| `l10n.yaml` | rewrite | `l10n.yaml` | 合并 required attributes / escaping / coverage exclusion |
| `pubspec.lock` | regenerate | `pubspec.lock` | workspace 解析后重新生成并提交（步骤 4） |
| `pubspec.yaml` | rewrite | `pubspec.yaml` | 根 pubspec 声明 Dart workspace members（步骤 4） |
| `skills-lock.json` | out-of-scope | — | 旧仓库 agent skill 锁定文件 |

---

## 11. `docs/`（31）

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `docs/README.md` | rewrite | `docs/{zh,en}/` | 按新架构重写；overview / layering / engineering_standards / developer_guide / glossary 等 |
| `docs/architecture/design_document.md` | rewrite | `docs/{zh,en}/` | 按新架构重写；overview / layering / engineering_standards / developer_guide / glossary 等 |
| `docs/architecture/desktop_agent_notification_design.md` | rewrite | `docs/{zh,en}/` | 按新架构重写；overview / layering / engineering_standards / developer_guide / glossary 等 |
| `docs/architecture/engineering_standards.md` | rewrite | `docs/{zh,en}/` | 按新架构重写；overview / layering / engineering_standards / developer_guide / glossary 等 |
| `docs/architecture/overview.en.md` | rewrite | `docs/{zh,en}/` | 按新架构重写；overview / layering / engineering_standards / developer_guide / glossary 等 |
| `docs/architecture/overview.md` | rewrite | `docs/{zh,en}/` | 按新架构重写；overview / layering / engineering_standards / developer_guide / glossary 等 |
| `docs/guides/developer_guide.md` | rewrite | `docs/{zh,en}/` | 按新架构重写；overview / layering / engineering_standards / developer_guide / glossary 等 |
| `docs/guides/glossary.en.md` | rewrite | `docs/{zh,en}/` | 按新架构重写；overview / layering / engineering_standards / developer_guide / glossary 等 |
| `docs/guides/glossary.md` | rewrite | `docs/{zh,en}/` | 按新架构重写；overview / layering / engineering_standards / developer_guide / glossary 等 |
| `docs/history/cursor_acp_release_validation.md` | out-of-scope | — | 旧仓库历史归档，不迁入 |
| `docs/history/cursor_agent_guide.md` | out-of-scope | — | 旧仓库历史归档，不迁入 |
| `docs/history/development_log.md` | out-of-scope | — | 旧仓库历史归档，不迁入 |
| `docs/history/project_memory.md` | out-of-scope | — | 旧仓库历史归档，不迁入 |
| `docs/images/README.md` | rewrite | `docs/{zh,en}/images/` | 截图随 UI 定稿后重拍 |
| `docs/plan_mode_smoke_test.md` | rewrite | `docs/{zh,en}/protocols/` | 并入 Codex 协议文档的 smoke 记录 |
| `docs/product/product_requirements.md` | rewrite | `docs/{zh,en}/` | 按新架构重写；overview / layering / engineering_standards / developer_guide / glossary 等 |
| `docs/product/troubleshooting.en.md` | rewrite | `docs/{zh,en}/` | 按新架构重写；overview / layering / engineering_standards / developer_guide / glossary 等 |
| `docs/product/troubleshooting.md` | rewrite | `docs/{zh,en}/` | 按新架构重写；overview / layering / engineering_standards / developer_guide / glossary 等 |
| `docs/prompts/README.md` | out-of-scope | — | 旧仓库 agent prompt 模板 |
| `docs/prompts/daily.md` | out-of-scope | — | 旧仓库 agent prompt 模板 |
| `docs/prompts/performance.md` | out-of-scope | — | 旧仓库 agent prompt 模板 |
| `docs/prompts/refactoring.md` | out-of-scope | — | 旧仓库 agent prompt 模板 |
| `docs/prompts/snippets.md` | out-of-scope | — | 旧仓库 agent prompt 模板 |
| `docs/prompts/workflow.md` | out-of-scope | — | 旧仓库 agent prompt 模板 |
| `docs/protocols/claude_code_provider_adapter.md` | move | `docs/zh/history/claude_code_provider_adapter.md` | **已完成**：归档，中文单语；en/history/ 放指针 |
| `docs/protocols/claude_code_stream_json_protocol.md` | move | `docs/{zh,en}/protocols/claude_code_stream_json_protocol.md` | **已完成**：中文迁入 + 英文版 |
| `docs/protocols/claude_code_token_metering.md` | move | `docs/{zh,en}/protocols/claude_code_token_metering.md` | **已完成**：中文迁入 + 英文版 |
| `docs/protocols/codex_app_server_protocol.md` | move | `docs/{zh,en}/protocols/codex_app_server_protocol.md` | **已完成**：中文迁入 + 英文版 |
| `docs/reference/flutter_ai_create_with_ai_zh.md` | out-of-scope | — | 外部参考资料 |
| `docs/reference/flutter_ai_developer_experience_zh.md` | out-of-scope | — | 外部参考资料 |
| `docs/release/release_guide.md` | rewrite | `docs/{zh,en}/` | 按新架构重写；overview / layering / engineering_standards / developer_guide / glossary 等 |

---

## 12. 明确排除（407）

| 规则 | 文件数 | 排除依据 |
| --- | ---: | --- |
| `.claude/**` | 178 | 新仓库已自带 .claude/ 与 VGV skills |
| `.agents/**` | 178 | 新仓库已自带 .agents/skills（16 个 VGV skill） |
| `.workflow/**` | 51 | 旧仓库流程记录，非迁移输入 |
| `tool/packaging/**` | 5 | 打包不在本次范围（拓扑 §1） |
| `docs/history/**` | 4 | 旧仓库历史归档，不迁入 |
| `docs/prompts/**` | 6 | 旧仓库 agent prompt 模板 |
| `docs/reference/**` | 2 | 外部参考资料 |
| `skills-lock.json` | 1 | 旧仓库 agent skill 锁定文件 |

此外，**未跟踪**的 `.workflow/feature/2026-08-18-PC端构建与版本检查/` 按[拓扑附录](./migration_topology.md)明确不属于迁移输入。

---

## 13. 删除清单（42）

每一项都必须写明删除理由与验证方式，这是[步骤 1](./migration_tasks.md) 的硬要求。

| 源文件 | 动作 | 目标 | 说明 |
| --- | --- | --- | --- |
| `lib/main.dart` | delete | — | 单 entrypoint 被 main_development/staging/production 三个 flavor 取代（步骤 3） |
| `lib/src/app/bootstrap/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/app/composition/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/app/localization/zeta_text_catalogs.dart` | delete | — | TextCatalog 双轨删除（步骤 28）；下层改 typed code + lib/l10n/failure_messages.dart |
| `lib/src/app/shell/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/app/zeta_storage_migrator.dart` | delete | — | 无历史版本兼容；只验证空目录干净安装与当前 schema（拓扑 §1） |
| `lib/src/core/error/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/core/result/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/core/utils/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/agent/application/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/agent/application/agent_ui_update_port.dart` | delete | — | UI 更新端口被 Bloc State + BlocSelector 取代 |
| `lib/src/features/agent/data/agent_provider_permission_migration.dart` | delete | — | 旧权限值升级逻辑；无历史数据兼容（拓扑 §1） |
| `lib/src/features/agent/data/datasources/app_server/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/agent/data/datasources/local_history/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/agent/data/datasources/transport/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/agent/data/mappers/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/agent/data/repositories/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/agent/domain/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/agent/domain/agent_ui_text_catalog.dart` | delete | — | TextCatalog 删除（步骤 7 / 28） |
| `lib/src/features/agent/domain/cursor_retirement_policy.dart` | delete | — | Cursor 清退（步骤 0），迁移前在旧仓库删除 |
| `lib/src/features/agent/domain/fallback_agent_ui_text_catalog.dart` | delete | — | Fallback catalog 删除（步骤 7 / 28） |
| `lib/src/features/agent_management/domain/agent_management_text_catalog.dart` | delete | — | TextCatalog 删除（步骤 28） |
| `lib/src/features/agent_management/domain/fallback_agent_management_text_catalog.dart` | delete | — | Fallback TextCatalog 删除（步骤 28） |
| `lib/src/features/desktop_notifications/domain/desktop_attention_text_catalog.dart` | delete | — | TextCatalog 删除（步骤 28） |
| `lib/src/features/desktop_notifications/domain/fallback_desktop_attention_text_catalog.dart` | delete | — | Fallback TextCatalog 删除（步骤 28） |
| `lib/src/features/ide_session/application/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/ide_session/data/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/ide_session/domain/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/project_threads/application/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/project_threads/data/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/project_threads/domain/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/project_threads/presentation/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/usage_statistics/domain/fallback_usage_statistics_text_catalog.dart` | delete | — | Fallback TextCatalog 删除（步骤 28） |
| `lib/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart` | delete | — | TextCatalog 删除（步骤 28） |
| `lib/src/features/workspace/application/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/workspace/data/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/workspace/domain/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `lib/src/features/workspace/presentation/.gitkeep` | delete | — | 空目录占位符；新仓库按 VGV 模板重建目录 |
| `tool/test_fast.ps1` | delete | — | test_fast/test_full 脚本被 VGV 四门（very_good test）取代 |
| `tool/test_fast.sh` | delete | — | test_fast/test_full 脚本被 VGV 四门（very_good test）取代 |
| `tool/test_full.ps1` | delete | — | test_fast/test_full 脚本被 VGV 四门（very_good test）取代 |
| `tool/test_full.sh` | delete | — | test_fast/test_full 脚本被 VGV 四门（very_good test）取代 |

**验证方式**：迁移完成后，对上表每个路径在新仓库执行路径存在性断言（应全部不存在），并确认对应能力的 UI 入口不存在或已由替代实现覆盖。TextCatalog 相关删除另由
[步骤 28](./migration_tasks.md)「packages 的 `AppLocalizations` import = 0」与「TextCatalog/Fallback remnants = 0」两个指标共同断言。

---

## 14. 闭环检查

[步骤 36](./migration_tasks.md) 要求「manifest 每个文件已闭环」。闭环定义：

| 动作 | 闭环条件 |
| --- | --- |
| `move` | 目标路径存在，且内容 diff 只含链接/路径调整 |
| `rewrite` | 目标路径存在，且该位置的测试覆盖源文件的等价行为 |
| `regenerate` | 生成命令在 CI 中可重复执行且输出稳定 |
| `delete` | 新仓库不存在该路径，且删除理由在本文有记录 |
| `out-of-scope` | 新仓库不存在该路径 |

生成脚本应纳入 CI，在 P8 阶段断言：本清单的行数 = 最终基线的 git 跟踪文件数，且无 `UNCLASSIFIED`。

