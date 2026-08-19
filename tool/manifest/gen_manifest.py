#!/usr/bin/env python3
"""Generate the source->target migration manifest from the old repo's git index."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

OLD = Path(r"D:\Development\Workspace\zeta")

# (predicate, action, target, note)
# First match wins. Predicates are (kind, pattern):
#   'eq'     exact path
#   'pre'    path prefix
#   'dirfile' directory prefix + filename prefix
#   'suf'    filename suffix within a directory prefix
RULES: list[tuple[str, str, str, str, str]] = []


def rule(kind: str, pattern: str, action: str, target: str, note: str) -> None:
    RULES.append((kind, pattern, action, target, note))


def sub(dirpre: str, fileprefix: str, action: str, target: str, note: str) -> None:
    RULES.append(("dirfile", f"{dirpre}|{fileprefix}", action, target, note))


# ---------------------------------------------------------------- placeholders
rule("suf", "|.gitkeep", "delete", "—", "空目录占位符；新仓库按 VGV 模板重建目录")

# ---------------------------------------------------------------- entrypoint
rule("eq", "lib/main.dart", "delete", "—",
     "单 entrypoint 被 main_development/staging/production 三个 flavor 取代（步骤 3）")

# ---------------------------------------------------------------- app layer
rule("eq", "lib/src/app/app.dart", "rewrite", "lib/app/view/app.dart",
     "拆成 App widget + MultiRepositoryProvider；Bloc 注入下沉到各 Page")
rule("eq", "lib/src/app/app_constants.dart", "rewrite", "lib/app/app_constants.dart",
     "纯 UI 常量移入 packages/app_ui/；应用身份常量留 app")
rule("eq", "lib/src/app/localization/zeta_localization.dart", "rewrite", "lib/l10n/l10n.dart",
     "Locale 冻结逻辑保留；ARB 入口改为 VGV 标准 l10n.dart")
rule("eq", "lib/src/app/localization/zeta_text_catalogs.dart", "delete", "—",
     "TextCatalog 双轨删除（步骤 28）；下层改 typed code + lib/l10n/failure_messages.dart")
rule("eq", "lib/src/app/menu_action_bridge.dart", "rewrite",
     "lib/app/platform/menu_command_adapter.dart + lib/app/router/",
     "原生菜单命令拆成 MenuCommandApi adapter 与 typed route 调用（步骤 34）")
rule("eq", "lib/src/app/shell/ide_shell_controller.dart", "rewrite", "lib/ide_shell/bloc/",
     "1,467 行 Controller → IdeShellBloc；导航状态交给 GoRouter（步骤 34）")
rule("eq", "lib/src/app/window_bootstrap.dart", "rewrite",
     "lib/app/platform/window_command_adapter.dart",
     "window_manager / macos_window_utils 收敛到 WindowCommandApi 实现")
rule("eq", "lib/src/app/zeta_startup_bootstrap.dart", "rewrite", "lib/bootstrap.dart",
     "唯一 composition root；同时可见 Data client、Repository 与 platform adapter")
rule("eq", "lib/src/app/zeta_storage_migrator.dart", "delete", "—",
     "无历史版本兼容；只验证空目录干净安装与当前 schema（拓扑 §1）")

# ---------------------------------------------------------------- core
rule("eq", "lib/src/core/constants/app_typography.dart", "rewrite",
     "packages/app_ui/lib/src/theme/", "设计 token 归 app_ui；不依赖 Repository/Data")
rule("pre", "lib/src/core/logging/", "rewrite", "packages/zeta_logging/lib/src/",
     "结构化日志；所有出口默认脱敏")
rule("pre", "lib/src/core/security/", "rewrite", "packages/zeta_logging/lib/src/",
     "敏感数据脱敏与日志同包，保证日志出口无法绕过 redactor")
rule("pre", "lib/src/core/storage/", "rewrite", "packages/zeta_storage/lib/src/",
     "原子文件操作与数据路径；只支持当前 schema")
rule("eq", "lib/src/core/utils/path_utils.dart", "rewrite", "packages/zeta_storage/lib/src/",
     "路径规范化与 canonical path，是 projectId 派生的基础（步骤 34）")
rule("eq", "lib/src/core/utils/system_file_manager.dart", "rewrite",
     "packages/desktop_platform_api/ + lib/app/platform/",
     "纯 Dart 端口留 desktop_platform_api；file_selector/pasteboard 实现留 app")

# ---------------------------------------------------------------- agent domain
rule("eq", "lib/src/features/agent/domain/agent_ui_text_catalog.dart", "delete", "—",
     "TextCatalog 删除（步骤 7 / 28）")
rule("eq", "lib/src/features/agent/domain/fallback_agent_ui_text_catalog.dart", "delete", "—",
     "Fallback catalog 删除（步骤 7 / 28）")
rule("eq", "lib/src/features/agent/domain/agent_provider_error_presentation.dart", "rewrite",
     "lib/l10n/failure_messages.dart",
     "错误展示映射属于 Presentation；contracts 只保留 typed failure code")
rule("eq", "lib/src/features/agent/domain/agent_usage_window_labels.dart", "rewrite",
     "lib/l10n/ + packages/agent_provider_contracts/",
     "窗口时长 typed code 留 contracts；展示文案入 ARB")
rule("pre", "lib/src/features/agent/domain/", "rewrite",
     "packages/agent_provider_contracts/lib/src/",
     "ADR-001 模型例外：21 个 capability port 与中立不可变模型；零 vendor 字段")

# ---------------------------------------------------------------- agent data: transport
rule("pre", "lib/src/features/agent/data/datasources/transport/", "rewrite",
     "packages/json_rpc_transport/lib/src/",
     "JSON-RPC stdio、operation scheduler、runtime peer；构造注入 process starter/clock/logger")

# ---------------------------------------------------------------- agent data: vendor datasources
rule("pre", "lib/src/features/agent/data/datasources/app_server/", "rewrite",
     "packages/codex_app_server_client/lib/src/", "Codex app-server 适配层")
rule("pre", "lib/src/features/agent/data/datasources/claude_code/", "rewrite",
     "packages/claude_code_client/lib/src/", "Claude Code stream-json 适配层")
rule("pre", "lib/src/features/agent/data/datasources/acp/", "rewrite",
     "packages/grok_acp_client/lib/src/", "Grok ACP 适配层")

# ---------------------------------------------------------------- agent data: local history
sub("lib/src/features/agent/data/datasources/local_history/", "codex_", "rewrite",
    "packages/codex_app_server_client/lib/src/history/",
    "vendor-specific parser 留各 vendor client（步骤 15）")
sub("lib/src/features/agent/data/datasources/local_history/", "grok_", "rewrite",
    "packages/grok_acp_client/lib/src/history/",
    "vendor-specific parser 留各 vendor client（步骤 15）")

# ---------------------------------------------------------------- agent data: mappers
sub("lib/src/features/agent/data/mappers/", "codex_", "rewrite",
    "packages/codex_app_server_client/lib/src/mappers/", "Codex 协议映射")
sub("lib/src/features/agent/data/mappers/", "claude_code_", "rewrite",
    "packages/claude_code_client/lib/src/mappers/", "Claude Code 协议映射")
sub("lib/src/features/agent/data/mappers/", "grok_", "rewrite",
    "packages/grok_acp_client/lib/src/mappers/", "Grok 协议映射")
sub("lib/src/features/agent/data/mappers/", "acp_", "rewrite",
    "packages/grok_acp_client/lib/src/acp/",
    "ACP 当前只有 Grok 一个消费者，不抽公共包（步骤 14）")
rule("eq", "lib/src/features/agent/data/mappers/context_window_codec.dart", "rewrite",
     "packages/agent_provider_contracts/lib/src/codecs/",
     "三方共用的纯函数 codec；无 vendor 字段，符合 ADR-001")

# ---------------------------------------------------------------- agent data: top level
rule("eq", "lib/src/features/agent/data/agent_provider_permission_migration.dart", "delete", "—",
     "旧权限值升级逻辑；无历史数据兼容（拓扑 §1）")
rule("eq", "lib/src/features/agent/data/agent_ignored_message_logger.dart", "rewrite",
     "packages/zeta_logging/lib/src/",
     "未匹配通知的诊断计数；只记 method/type/reason/count")
rule("eq", "lib/src/features/agent/data/agent_provider_static_capabilities.dart", "rewrite",
     "三个 vendor client 各自声明",
     "拆分：每个 client 声明自己的静态能力，消除集中式 kind switch")
rule("eq", "lib/src/features/agent/data/cli_command_locator.dart", "rewrite",
     "packages/agent_provider_contracts/ + 三个 vendor client",
     "ResolvedCliProcessCommand 值类型入 contracts；locate 实现各 vendor 一份（步骤 17）")
rule("eq", "lib/src/features/agent/data/codex_cli_locator.dart", "rewrite",
     "packages/codex_app_server_client/lib/src/", "CLI locator 每个 vendor 恰好一个归属")
rule("eq", "lib/src/features/agent/data/claude_code_cli_locator.dart", "rewrite",
     "packages/claude_code_client/lib/src/", "CLI locator 每个 vendor 恰好一个归属")
rule("eq", "lib/src/features/agent/data/grok_cli_locator.dart", "rewrite",
     "packages/grok_acp_client/lib/src/", "CLI locator 每个 vendor 恰好一个归属")
rule("eq", "lib/src/features/agent/data/default_agent_provider_factory.dart", "rewrite",
     "packages/agent_provider_repository/lib/src/",
     "bundle factory registry 属 Repository；不在 Data 层做 kind 分支")
rule("eq", "lib/src/features/agent/data/native_agent_provider_bundles.dart", "rewrite",
     "packages/agent_provider_repository/lib/src/", "bundle 组装归 provider repository")
rule("pre", "lib/src/features/agent/data/", "rewrite", "packages/agent_config_client/lib/src/",
     "provider config / model catalog cache / turn-context 的当前 schema 持久化（步骤 11）")

# ---------------------------------------------------------------- agent application (ownership map)
APP = "lib/src/features/agent/application/"
for f, tgt, note in [
    ("agent_conversation_binding.dart", "packages/agent_conversation_repository/", "会话聚合根，外部数据编排"),
    ("agent_conversation_binding_manager.dart", "packages/agent_conversation_repository/", "会话生命周期与 lease"),
    ("agent_conversation_effect.dart", "packages/agent_conversation_repository/", "协议 effect 属领域编排"),
    ("agent_conversation_effect_runner.dart", "packages/agent_conversation_repository/", "effect 执行器；UI effect 剥离到 Bloc"),
    ("agent_conversation_event_processor.dart", "packages/agent_conversation_repository/", "Provider 事件归一化"),
    ("agent_conversation_mode_controller.dart", "lib/agent_chat/bloc/", "模式**选择**是交互状态 → Bloc"),
    ("agent_conversation_model_selection_controller.dart", "lib/agent_chat/bloc/", "模型**选择**是交互状态 → Bloc"),
    ("agent_conversation_mutation.dart", "packages/agent_conversation_repository/", "domain snapshot 变更描述"),
    ("agent_conversation_permission_selection_controller.dart", "lib/agent_chat/bloc/", "权限选项**选择** → Bloc"),
    ("agent_conversation_permission_state.dart", "拆分", "pending 请求 → Repository；UI 选中态 → Bloc State"),
    ("agent_conversation_reducer.dart", "packages/agent_conversation_repository/", "确定性归并留 Repository（ADR-004）"),
    ("agent_conversation_thread_snapshot.dart", "packages/agent_conversation_repository/", "domain snapshot"),
    ("agent_conversation_timeline_store.dart", "拆分", "2,017 行：domain aggregate → Repository；UI slice → Bloc State"),
    ("agent_elapsed_ticker.dart", "lib/agent_chat/bloc/", "计时是 UI 派生状态；Bloc 持有 timer 并在 close() 取消"),
    ("agent_event_coalescing_policy.dart", "packages/agent_conversation_repository/", "事件合并属数据管线"),
    ("agent_event_pipeline.dart", "packages/agent_conversation_repository/", "事件管线核心"),
    ("agent_model_catalog_repository.dart", "packages/agent_provider_repository/", "模型目录 TTL 缓存真源"),
    ("agent_permission_catalog_controller.dart", "packages/agent_provider_repository/", "权限目录是外部数据；选中态归 Bloc"),
    ("agent_permission_request_resolver.dart", "packages/agent_conversation_repository/", "pending 权限请求解析"),
    ("agent_plan_execution_handoff_controller.dart", "lib/agent_chat/bloc/", "本地交接是业务规则 → Bloc（步骤 32）"),
    ("agent_provider_config_store.dart", "packages/agent_provider_repository/", "配置编排；IO 下沉 agent_config_client"),
    ("agent_provider_event_listener_gate.dart", "packages/agent_conversation_repository/", "订阅闸门属外部数据生命周期"),
    ("agent_provider_global_runtime.dart", "packages/agent_provider_repository/", "全局 runtime 持有"),
    ("agent_provider_runtime_identity.dart", "packages/agent_conversation_repository/", "runtime generation 判定"),
    ("agent_provider_runtime_registry.dart", "packages/agent_conversation_repository/", "runtime lease 注册表"),
    ("agent_provider_settings_controller.dart", "packages/agent_provider_repository/", "Provider 设置持久化"),
    ("agent_provider_settings_port.dart", "packages/agent_provider_contracts/", "纯端口定义"),
    ("agent_skills_catalog_controller.dart", "packages/agent_provider_repository/", "Skill 目录是外部数据"),
    ("agent_thread_workspace_controller.dart", "packages/project_session_repository/", "thread↔workspace 关联数据"),
    ("agent_turn_context_overlay.dart", "packages/agent_conversation_repository/", "turn context 叠加属领域"),
    ("agent_turn_context_recorder.dart", "packages/agent_conversation_repository/", "turn context 记录"),
    ("agent_ui_update_port.dart", "delete", "UI 更新端口被 Bloc State + BlocSelector 取代"),
    ("agent_ui_update_request.dart", "lib/agent_chat/view/", "AgentUiRegion/urgency 保留给 Presentation 帧调度器（拓扑 §5）"),
    ("bounded_event_dispatcher.dart", "packages/agent_conversation_repository/", "有界事件分发与背压"),
    ("coalescing_event_buffer.dart", "packages/agent_conversation_repository/", "合并缓冲"),
]:
    act = "delete" if tgt == "delete" else "rewrite"
    rule("eq", APP + f, act, "—" if tgt == "delete" else tgt, note)

# ---------------------------------------------------------------- agent presentation
PRE = "lib/src/features/agent/presentation/"
rule("eq", PRE + "agent_conversation_view_model.dart", "rewrite", "lib/agent_chat/bloc/",
     "4,190 行 ViewModel → AgentConversationBloc（见会话状态设计文档）")
rule("eq", PRE + "agent_conversation_ui_state.dart", "rewrite", "lib/agent_chat/bloc/",
     "1,098 行 → AgentConversationState 五个 slice")
rule("eq", PRE + "agent_conversation_navigation.dart", "rewrite", "lib/app/router/",
     "导航改 typed GoRouter route；Bloc 不依赖 GoRouter")
rule("eq", PRE + "agent_presentation_l10n.dart", "rewrite", "lib/l10n/",
     "typed failure/code → ARB 的穷尽映射")
rule("pre", PRE + "widgets/", "rewrite", "lib/agent_chat/widgets/",
     "改 BlocBuilder/BlocSelector；>1.5k 行文件拆分，不做视觉重设计（步骤 33）")
rule("pre", PRE, "rewrite", "lib/agent_chat/view/",
     "Presentation helper：投影、缓存、分组、调度器保持在 Presentation 层")

# ---------------------------------------------------------------- other features
FEAT = "lib/src/features/"
for feat, pkg, blocdir in [
    ("agent_management", "agent_management", "lib/agent_management/"),
    ("desktop_notifications", "desktop_notifications", "lib/desktop_notifications/"),
    ("ide_session", "project_session", "lib/ide_session/"),
    ("project_threads", "project_session", "lib/project_threads/"),
    ("settings", "settings", "lib/settings/"),
    ("usage_statistics", "usage_statistics", "lib/usage_statistics/"),
    ("workspace", "workspace", "lib/workspace/"),
]:
    base = f"{FEAT}{feat}/"
    rule("dirfile", f"{base}domain/|fallback_", "delete", "—", "Fallback TextCatalog 删除（步骤 28）")
    rule("suf", f"{base}domain/|_text_catalog.dart", "delete", "—", "TextCatalog 删除（步骤 28）")
    rule("pre", base + "data/", "rewrite", f"packages/{pkg}_client/lib/src/",
         "外部 IO 与当前 schema 读写下沉 Data 包")
    rule("pre", base + "domain/", "rewrite", f"packages/{pkg}_repository/lib/src/",
         "domain model 归 Repository")
    rule("pre", base + "application/", "rewrite", f"packages/{pkg}_repository/ 或 {blocdir}",
         "逐个裁决见 ownership_map.md：外部数据→Repository，交互状态→Bloc/Cubit")
    rule("pre", base + "presentation/", "rewrite", blocdir + "view/",
         "Page 注入 Bloc，View/Widget 消费 State")

# usage_statistics vendor data overrides (must precede the generic data/ rule -> insert earlier)

# ---------------------------------------------------------------- ui
rule("pre", "lib/src/ui/localization/generated/", "regenerate", "lib/l10n/generated/",
     "由 flutter gen-l10n 重新生成；不手工迁移（步骤 5）")
rule("pre", "lib/src/ui/localization/arb/", "move", "lib/l10n/arb/",
     "en/zh 各 1,035 键；删除脚手架 app_es.arb（步骤 5）")
rule("eq", "lib/src/ui/localization/app_localizations_x.dart", "rewrite", "lib/l10n/l10n.dart",
     "l10n / l10nOrNull 扩展")
rule("eq", "lib/src/ui/localization/zeta_shadcn_localizations.dart", "rewrite", "lib/l10n/",
     "留在 app，不进 app_ui（拓扑 §8）")
rule("eq", "lib/src/ui/localization/relative_time.dart", "rewrite", "lib/l10n/",
     "相对时间文案依赖 ARB，留 app")
rule("pre", "lib/src/ui/features/ide/views/", "rewrite", "lib/ide_shell/view/",
     "IDE shell 页面；导航改 typed route")
rule("pre", "lib/src/ui/core/", "rewrite", "packages/app_ui/lib/src/",
     "设计 token、基础组件、Workbench 原语、虚拟滚动；文案由构造参数传入（步骤 27）")

# ---------------------------------------------------------------- tests
rule("pre", "test/src/architecture/", "rewrite", "test/architecture/ + .architecture.yaml",
     "架构门禁重写为读取 .architecture.yaml 的断言（步骤 6）")
rule("pre", "test/src/features/agent/data/datasources/app_server/", "rewrite",
     "packages/codex_app_server_client/test/", "fixture 按 package 分配，无跨包 import（步骤 17）")
rule("pre", "test/src/features/agent/data/datasources/claude_code/", "rewrite",
     "packages/claude_code_client/test/", "含 fixtures/ 子目录（步骤 17）")
rule("pre", "test/src/features/agent/data/datasources/acp/", "rewrite",
     "packages/grok_acp_client/test/", "fixture 按 package 分配（步骤 17）")
rule("pre", "test/src/features/agent/data/datasources/transport/", "rewrite",
     "packages/json_rpc_transport/test/", "")
rule("pre", "test/src/features/agent/domain/", "rewrite",
     "packages/agent_provider_contracts/test/", "")
rule("pre", "test/src/features/agent/application/", "rewrite",
     "按 ownership_map 分配到 repository 包与 lib/agent_chat/ 的 blocTest", "")
rule("pre", "test/src/features/agent/presentation/", "rewrite",
     "test/agent_chat/ + packages/app_ui/test/", "MockBloc widget test + golden")
rule("pre", "test/src/features/agent/data/", "rewrite", "按 mapper 前缀分配到对应 vendor package", "")
rule("pre", "test/src/features/", "rewrite", "对应 package/test 或 test/<feature>/",
     "测试镜像 lib/；跟随其被测对象的归属")
rule("pre", "test/src/core/", "rewrite", "packages/zeta_logging/test/ 与 packages/zeta_storage/test/", "")
rule("pre", "test/src/app/", "rewrite", "test/app/", "")
rule("pre", "test/src/ui/", "rewrite", "packages/app_ui/test/ 与 test/ide_shell/", "")
rule("pre", "test/src/testing/", "rewrite", "各 package 的 test/helpers/",
     "共享 harness 按包复制；禁止跨包 test import")
rule("pre", "test/fixtures/", "rewrite", "按 Provider 分配到对应 vendor package 的 test/fixtures/", "")
rule("pre", "test/support/", "rewrite", "test/helpers/", "pumpApp 等共享 widget 测试工具")
rule("pre", "test/tool/", "rewrite", "tool/ 的配套测试", "")
rule("eq", "test/flutter_test_config.dart", "rewrite", "test/flutter_test_config.dart",
     "golden 字体加载与全局测试配置；workspace 内每个含 widget test 的包各一份")

# ---------------------------------------------------------------- native
rule("pre", "macos/", "rewrite", "macos/",
     "手写 Runner 与 channel 迁移；bundle ID 统一 cn.easii.zeta，移除 flavor 身份后缀（步骤 3）")
rule("pre", "windows/", "rewrite", "windows/",
     "手写 Runner 与 channel 迁移；application ID 统一 cn.easii.zeta（步骤 3）")
rule("pre", "linux/", "rewrite", "linux/",
     "新仓库缺 Linux scaffold，先由 flutter create 生成再迁入手写部分（步骤 3）")

# ---------------------------------------------------------------- assets / tool / schema
rule("pre", "assets/", "move", "assets/", "Geist / JetBrainsMono / branding / agent icons（步骤 5）")
rule("eq", "tool/gen_codex_schema.sh", "move", "tool/gen_codex_schema.sh", "Codex schema 生成脚本")
rule("eq", "tool/gen_codex_schema.ps1", "move", "tool/gen_codex_schema.ps1", "Codex schema 生成脚本")
rule("dirfile", "tool/|smoke_", "move", "tool/",
     "五个真实 CLI 冒烟脚本；步骤 17/33/36 验收直接依赖（已裁决迁入）")
rule("eq", "tool/check_localized_ui_strings.dart", "rewrite", "tool/",
     "l10n 字面量门禁；TextCatalog 删除后规则需同步更新（步骤 28）")
rule("eq", "tool/localization_literal_allowlist.json", "rewrite", "tool/", "配套 allowlist")
rule("eq", "tool/report_test_timings.dart", "move", "tool/", "测试耗时报告")
rule("dirfile", "tool/|test_", "delete", "—",
     "test_fast/test_full 脚本被 VGV 四门（very_good test）取代")
rule("pre", "tool/__pycache__/", "delete", "—", "Python 构建产物，不应被跟踪")
rule("pre", "tool/packaging/", "out-of-scope", "—", "打包不在本次范围（拓扑 §1）")
rule("pre", "third_party/codex_app_server_schema/", "move", "third_party/codex_app_server_schema/",
     "Codex 协议 pin（0.144.5）；步骤 12 contract test 的基准（已裁决迁入，见 §5）")

# ---------------------------------------------------------------- ci / config
rule("pre", ".github/", "rewrite", ".github/",
     "新仓库已有 VGV workflow；只迁移 OSV / license / 架构门禁增量（步骤 6）")
rule("eq", "analysis_options.yaml", "rewrite", "analysis_options.yaml", "统一 very_good_analysis")
rule("eq", "l10n.yaml", "rewrite", "l10n.yaml", "合并 required attributes / escaping / coverage exclusion")
rule("eq", "pubspec.yaml", "rewrite", "pubspec.yaml", "根 pubspec 声明 Dart workspace members（步骤 4）")
rule("eq", "pubspec.lock", "regenerate", "pubspec.lock", "workspace 解析后重新生成并提交（步骤 4）")
rule("eq", "dart_test.yaml", "rewrite", "dart_test.yaml", "random ordering + golden tag（步骤 6）")
rule("eq", "devtools_options.yaml", "move", "devtools_options.yaml", "")
rule("eq", ".metadata", "regenerate", ".metadata", "由新仓库 flutter create 生成")
rule("eq", ".gitignore", "rewrite", ".gitignore", "合并旧规则；移除 Rust/packaging 相关条目")
rule("eq", "skills-lock.json", "out-of-scope", "—", "旧仓库 agent skill 锁定文件")

# ---------------------------------------------------------------- root docs
rule("eq", "LICENSE", "move", "LICENSE", "")
rule("eq", "README.md", "rewrite", "README.md", "按新架构重写；保留中英双版")
rule("eq", "README.en.md", "rewrite", "README.en.md", "")
rule("eq", "CONTRIBUTING.md", "rewrite", "CONTRIBUTING.md", "按 VGV 四门与架构门禁重写")
rule("eq", "CONTRIBUTING.en.md", "rewrite", "CONTRIBUTING.en.md", "")
rule("eq", "CODE_OF_CONDUCT.md", "move", "CODE_OF_CONDUCT.md", "")
rule("eq", "SECURITY.md", "move", "SECURITY.md", "")
rule("eq", "CHANGELOG.md", "rewrite", "CHANGELOG.md", "新仓库从 1.0.0+1 重新起算")
rule("eq", "AGENTS.md", "rewrite", "AGENTS.md",
     "28KB 旧约束；G1–G8 改写为 .architecture.yaml 可判定的门禁")
rule("eq", "CLAUDE.md", "rewrite", "CLAUDE.md", "指向新仓库文档索引")

# ---------------------------------------------------------------- docs
rule("eq", "docs/protocols/claude_code_stream_json_protocol.md", "move",
     "docs/{zh,en}/protocols/claude_code_stream_json_protocol.md", "**已完成**：中文迁入 + 英文版")
rule("eq", "docs/protocols/codex_app_server_protocol.md", "move",
     "docs/{zh,en}/protocols/codex_app_server_protocol.md", "**已完成**：中文迁入 + 英文版")
rule("eq", "docs/protocols/claude_code_token_metering.md", "move",
     "docs/{zh,en}/protocols/claude_code_token_metering.md", "**已完成**：中文迁入 + 英文版")
rule("eq", "docs/protocols/claude_code_provider_adapter.md", "move",
     "docs/zh/history/claude_code_provider_adapter.md", "**已完成**：归档，中文单语；en/history/ 放指针")
rule("pre", "docs/history/", "out-of-scope", "—", "旧仓库历史归档，不迁入")
rule("pre", "docs/prompts/", "out-of-scope", "—", "旧仓库 agent prompt 模板")
rule("pre", "docs/reference/", "out-of-scope", "—", "外部参考资料")
rule("pre", "docs/images/", "rewrite", "docs/{zh,en}/images/", "截图随 UI 定稿后重拍")
rule("eq", "docs/plan_mode_smoke_test.md", "rewrite", "docs/{zh,en}/protocols/", "并入 Codex 协议文档的 smoke 记录")
rule("pre", "docs/", "rewrite", "docs/{zh,en}/",
     "按新架构重写；overview / layering / engineering_standards / developer_guide / glossary 等")

# ---------------------------------------------------------------- agent tooling
rule("pre", ".claude/", "out-of-scope", "—", "新仓库已自带 .claude/ 与 VGV skills")
rule("pre", ".agents/", "out-of-scope", "—", "新仓库已自带 .agents/skills（16 个 VGV skill）")
rule("pre", ".workflow/", "out-of-scope", "—", "旧仓库流程记录，非迁移输入")


def classify(path: str) -> tuple[str, str, str]:
    for kind, pattern, action, target, note in RULES:
        if kind == "eq" and path == pattern:
            return action, target, note
        if kind == "pre" and path.startswith(pattern):
            return action, target, note
        if kind == "dirfile":
            dirpre, fileprefix = pattern.split("|", 1)
            if path.startswith(dirpre):
                rest = path[len(dirpre):]
                if "/" not in rest and rest.startswith(fileprefix):
                    return action, target, note
        if kind == "suf":
            dirpre, suffix = pattern.split("|", 1)
            if path.startswith(dirpre) and path.endswith(suffix):
                return action, target, note
    return "UNCLASSIFIED", "?", "?"


def main() -> int:
    out = subprocess.run(
        ["git", "ls-files", "-z"], cwd=OLD, capture_output=True, check=True
    )
    files = [f for f in out.stdout.decode("utf-8").split("\0") if f.strip()]
    rows = [(f, *classify(f)) for f in files]

    unclassified = [r for r in rows if r[1] == "UNCLASSIFIED"]
    if unclassified:
        print(f"UNCLASSIFIED: {len(unclassified)}")
        for r in unclassified[:40]:
            print("  ", r[0])
        return 1

    counts: dict[str, int] = {}
    for _, action, _, _ in rows:
        counts[action] = counts.get(action, 0) + 1
    print(f"total={len(rows)}")
    for k in sorted(counts):
        print(f"  {k}: {counts[k]}")

    import json
    Path(sys.argv[1]).write_text(
        json.dumps([{"path": p, "action": a, "target": t, "note": n} for p, a, t, n in rows],
                   ensure_ascii=False, indent=0),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
