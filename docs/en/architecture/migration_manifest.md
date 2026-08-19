# Migration manifest (source -> target)

[中文](../../zh/architecture/migration_manifest.md) ｜ English

This manifest implements [migration tasks, step 1](./migration_tasks.md): every Git-tracked file
in the old repository is classified exactly once. Use it together with the
[migration topology](./migration_topology.md), the [ownership map](./ownership_map.md) and the
[package API contracts](./package_api_contracts.md).

---

## 1. Baseline

| Item | Value |
| --- | --- |
| Source repository | `D:\Development\Workspace\zeta` |
| Final migration baseline SHA | `b5c2f3e8a9ac544e9832866e86ff633661c46053` |
| Working tree | tracked clean (the only untracked path, `.workflow/feature/2026-08-18-PC端构建与版本检查/`, is explicitly excluded) |
| Git-tracked files | **1,507** |
| Flutter / Dart | Flutter 3.44.4 stable / Dart 3.12.2 |
| `pubspec.lock` SHA-256 | `70877b47b9097ac3449a5885b83faea073e4688a3c66187941f4bfd02728ec6f` |
| Manifest generated | 2026-08-19 |
| Target repository | `D:\Development\Workspace\vgv\zeta`, version `1.0.0+1` |

> [!IMPORTANT]
> **This is the final migration baseline after Step 0.** The five retired Cursor source, test, and
> fixture files are gone from the Git index and therefore no longer appear in this manifest. The
> migration must not switch to another legacy-repository commit.

## 2. Action definitions

| Action | Meaning | Verification |
| --- | --- | --- |
| `move` | Content unchanged, or only paths/links adjusted; comparable byte-for-byte or line-by-line | diff or checksum |
| `rewrite` | Rewritten for the new architecture; functionally equivalent, structurally different | tests at the target cover the equivalent behaviour |
| `regenerate` | Produced by tooling, never migrated by hand | the generating command is repeatable |
| `delete` | Explicitly dropped; does not enter the new repository | the note column states the reason |
| `out-of-scope` | Not a migration input | the note column states the exclusion basis |

**One-to-many splits**: a target of `split`, or several targets joined by ` + `, means the source file
is divided across multiple destinations. Every such file must have a per-item ruling in the
[ownership map](./ownership_map.md); this manifest only records where the pieces go.

## 3. Overview

| Action | Files | Share |
| --- | ---: | ---: |
| `move` | 300 | 19.9% |
| `rewrite` | 736 | 48.8% |
| `regenerate` | 5 | 0.3% |
| `delete` | 41 | 2.7% |
| `out-of-scope` | 425 | 28.2% |
| **Total** | **1507** | **100%** |

| Area | Files | Actions |
| --- | ---: | --- |
| `lib/` | 377 | rewrite 335, delete 37, regenerate 3, move 2 |
| `test/` | 301 | rewrite 301 |
| `third_party/` | 269 | move 269 |
| `macos/ + windows/ + linux/` | 65 | rewrite 65 |
| `assets/` | 13 | move 13 |
| `tool/` | 19 | move 8, out-of-scope 5, delete 4, rewrite 2 |
| `docs/` | 31 | rewrite 15, out-of-scope 12, move 4 |
| `.github/` | 6 | rewrite 6 |
| `.claude/ + .agents/ + .workflow/` | 407 | out-of-scope 407 |
| `root files` | 19 | rewrite 12, move 4, regenerate 2, out-of-scope 1 |
| **Total** | **1507** | coverage check: 1507 = 1507 |

## 4. Differences from the topology document's counts

[Migration topology §2](./migration_topology.md) counts filesystem entries; this manifest counts
Git-tracked files, so the two differ:

| Item | Topology §2 | This manifest (git-tracked) | Reason |
| --- | ---: | ---: | --- |
| macOS | 33 | 28 | the difference is gitignored build output (plugin registrants, intermediates) |
| Windows | 69 | 22 | the difference is gitignored build output (plugin registrants, intermediates) |
| Linux | 15 | 15 | match |
| assets | 13 | 13 | match |

**Step 1 uses this manifest's git-tracked counting.** Untracked files are not migration inputs;
generated output is handled as `regenerate`.

---

## 5. Scope rulings: two approved adjustments

> **Status: ruled 2026-08-19, already reflected in [migration topology §1](./migration_topology.md)
> and [task list §0](./migration_tasks.md).**

Topology §1 originally listed all of `third_party/` as "explicitly not migrated", alongside
`tool/packaging/`. On review, **the `third_party/` entry was too broad** and the `tool/` exclusion was
imprecise. The two adjustments below must be formally registered in the
[step 2 ADRs](./migration_tasks.md).

### 5.1 `third_party/codex_app_server_schema/` is migrated

- **Content**: 269 files / 2.8 MB — the stable JSON Schema snapshot of Codex CLI `0.144.5`.
- **Rationale**: the [Codex protocol doc](../protocols/codex_app_server_protocol.md) §2 defines it as
  "the human- and CI-diffable source of protocol truth", and [step 12](./migration_tasks.md) requires
  a contract test for `codex_app_server_client`. Dropping the snapshot removes that test's baseline.
- **Ruling**: `move`, same path. It is not a runtime dependency, only a diffable protocol contract, and
  it adds no build-time or runtime cost.
- **Still excluded**: anything else that may later appear under `third_party/` stays out by default;
  this ruling covers `codex_app_server_schema/` only.

### 5.2 The smoke and gate scripts under `tool/` are migrated

The exclusion narrows to `tool/packaging/`. Everything in that directory the acceptance criteria
depend on directly is migrated:

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `tool/check_localized_ui_strings.dart` | rewrite | `tool/` | l10n literal gate; rules must be updated once TextCatalog is removed (step 28) |
| `tool/gen_codex_schema.ps1` | move | `tool/gen_codex_schema.ps1` | Codex schema generation script |
| `tool/gen_codex_schema.sh` | move | `tool/gen_codex_schema.sh` | Codex schema generation script |
| `tool/localization_literal_allowlist.json` | rewrite | `tool/` | Companion allowlist |
| `tool/report_test_timings.dart` | move | `tool/` | Test timing report |
| `tool/smoke_claude_code_metadata.py` | move | `tool/` | Five real-CLI smoke scripts; steps 17/33/36 depend on them directly (ruled in scope) |
| `tool/smoke_claude_code_stream_json.py` | move | `tool/` | Five real-CLI smoke scripts; steps 17/33/36 depend on them directly (ruled in scope) |
| `tool/smoke_codex_app_server.py` | move | `tool/` | Five real-CLI smoke scripts; steps 17/33/36 depend on them directly (ruled in scope) |
| `tool/smoke_codex_plan_mode.py` | move | `tool/` | Five real-CLI smoke scripts; steps 17/33/36 depend on them directly (ruled in scope) |
| `tool/smoke_grok_acp.py` | move | `tool/` | Five real-CLI smoke scripts; steps 17/33/36 depend on them directly (ruled in scope) |
| `tool/test_fast.ps1` | delete | — | The test_fast/test_full scripts are replaced by the four VGV gates (very_good test) |
| `tool/test_fast.sh` | delete | — | The test_fast/test_full scripts are replaced by the four VGV gates (very_good test) |
| `tool/test_full.ps1` | delete | — | The test_fast/test_full scripts are replaced by the four VGV gates (very_good test) |
| `tool/test_full.sh` | delete | — | The test_fast/test_full scripts are replaced by the four VGV gates (very_good test) |

The five `smoke_*.py` scripts back [step 17](./migration_tasks.md) ("read-only capability probe
smoke against the real CLI"), [step 33](./migration_tasks.md) ("real Codex/Claude/Grok CLI session
smoke") and [step 36](./migration_tasks.md) ("three-way real-CLI end-to-end smoke"). Without them
those three steps cannot be checked off.

`check_localized_ui_strings.dart` and `localization_literal_allowlist.json` are the l10n literal gate,
whose rules must be updated once [step 28](./migration_tasks.md) removes TextCatalog;
`gen_codex_schema.{sh,ps1}` are the generation entry points for the §5.1 schema snapshot. The four
`test_fast/test_full` scripts are replaced by the four VGV gates and marked `delete`.

---

## 6. `lib/`, file by file (377)

The `lib/src/` prefix is stripped. `packages/` and `lib/` targets are relative to the new repo root.

### 6.1 Entrypoint and app layer

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `main.dart` | delete | — | The single entrypoint is replaced by the main_development/staging/production flavors (step 3) |
| `src/app/app.dart` | rewrite | `lib/app/view/app.dart` | Split into the App widget + MultiRepositoryProvider; Bloc injection moves down to each Page |
| `src/app/app_constants.dart` | rewrite | `lib/app/app_constants.dart` | Pure UI constants move to packages/app_ui/; app identity constants stay in the app |
| `src/app/bootstrap/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `src/app/composition/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `src/app/localization/zeta_localization.dart` | rewrite | `lib/l10n/l10n.dart` | Locale freezing logic retained; ARB entry point becomes the standard VGV l10n.dart |
| `src/app/localization/zeta_text_catalogs.dart` | delete | — | The dual TextCatalog track is deleted (step 28); lower layers return typed codes mapped in lib/l10n/failure_messages.dart |
| `src/app/menu_action_bridge.dart` | rewrite | `lib/app/platform/menu_command_adapter.dart + lib/app/router/` | Native menu commands split into a MenuCommandApi adapter plus typed route calls (step 34) |
| `src/app/shell/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `src/app/shell/ide_shell_controller.dart` | rewrite | `lib/ide_shell/bloc/` | 1,467-line controller -> IdeShellBloc; navigation state moves to GoRouter (step 34) |
| `src/app/window_bootstrap.dart` | rewrite | `lib/app/platform/window_command_adapter.dart` | window_manager / macos_window_utils converge into the WindowCommandApi implementation |
| `src/app/zeta_startup_bootstrap.dart` | rewrite | `lib/bootstrap.dart` | The single composition root; the only file that sees Data clients, Repositories and platform adapters together |
| `src/app/zeta_storage_migrator.dart` | delete | — | No backward compatibility; only clean install into an empty directory with the current schema is verified (topology §1) |

### 6.2 core

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `core/constants/app_typography.dart` | rewrite | `packages/app_ui/lib/src/theme/` | Design tokens belong to app_ui; no Repository/Data dependency |
| `core/error/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `core/logging/app_logging.dart` | rewrite | `packages/zeta_logging/lib/src/` | Structured logging; every sink redacts by default |
| `core/logging/structured_error_logging.dart` | rewrite | `packages/zeta_logging/lib/src/` | Structured logging; every sink redacts by default |
| `core/result/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `core/security/sensitive_data_redactor.dart` | rewrite | `packages/zeta_logging/lib/src/` | Redaction lives in the same package as logging so no log sink can bypass the redactor |
| `core/storage/atomic_text_file.dart` | rewrite | `packages/zeta_storage/lib/src/` | Atomic file operations and data paths; current schema only |
| `core/storage/zeta_data_paths.dart` | rewrite | `packages/zeta_storage/lib/src/` | Atomic file operations and data paths; current schema only |
| `core/utils/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `core/utils/path_utils.dart` | rewrite | `packages/zeta_storage/lib/src/` | Path normalization and canonical paths, the basis for deriving projectId (step 34) |
| `core/utils/system_file_manager.dart` | rewrite | `packages/desktop_platform_api/ + lib/app/platform/` | The pure Dart ports stay in desktop_platform_api; the file_selector/pasteboard implementations stay in the app |

### 6.3 agent · domain -> `agent_provider_contracts`

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `features/agent/domain/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/agent/domain/agent_attention_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_conversation_mode_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_event_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_file_change_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_message_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_model_catalog_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_model_codec.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_model_selection_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_permission_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_permission_policy_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_plan_approval_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_plan_execution_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_provider_bundle.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_provider_capabilities.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_provider_error_presentation.dart` | rewrite | `lib/l10n/failure_messages.dart` | Error presentation mapping belongs to the presentation layer; contracts keep only typed failure codes |
| `features/agent/domain/agent_provider_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_question_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_runtime_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_session_config_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_session_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_skill_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_thread_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_tool_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_turn_activity_models.dart` | split | `lib/agent_chat/bloc/ + lib/l10n/` | Live activity phase/snapshot are Bloc interaction state; elapsed-time formatting is Presentation copy and is excluded from ADR-001 |
| `features/agent/domain/agent_turn_context_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_turn_history_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_turn_terminal_signal.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_ui_text_catalog.dart` | delete | — | TextCatalog deleted (steps 7 / 28) |
| `features/agent/domain/agent_usage_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/agent_usage_window_labels.dart` | rewrite | `lib/l10n/ + packages/agent_provider_contracts/` | Window-duration typed codes stay in contracts; display copy goes to ARB |
| `features/agent/domain/agent_user_input_models.dart` | rewrite | `packages/agent_provider_contracts/lib/src/` | ADR-001 model exception: 21 capability ports plus neutral immutable models; zero vendor fields |
| `features/agent/domain/fallback_agent_ui_text_catalog.dart` | delete | — | Fallback catalog deleted (steps 7 / 28) |

### 6.4 agent · data · transport and vendor clients

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `features/agent/data/datasources/acp/grok_acp_agent_provider.dart` | rewrite | `packages/grok_acp_client/lib/src/` | Grok ACP adapter layer |
| `features/agent/data/datasources/acp/grok_models_cli.dart` | rewrite | `packages/grok_acp_client/lib/src/` | Grok ACP adapter layer |
| `features/agent/data/datasources/acp/grok_permission_policy_adapter.dart` | rewrite | `packages/grok_acp_client/lib/src/` | Grok ACP adapter layer |
| `features/agent/data/datasources/acp/grok_process_starter.dart` | rewrite | `packages/grok_acp_client/lib/src/` | Grok ACP adapter layer |
| `features/agent/data/datasources/app_server/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/agent/data/datasources/app_server/codex_app_server_agent_provider.dart` | rewrite | `packages/codex_app_server_client/lib/src/` | Codex app-server adapter layer |
| `features/agent/data/datasources/app_server/codex_app_server_client.dart` | rewrite | `packages/codex_app_server_client/lib/src/` | Codex app-server adapter layer |
| `features/agent/data/datasources/app_server/codex_app_server_runtime_info.dart` | rewrite | `packages/codex_app_server_client/lib/src/` | Codex app-server adapter layer |
| `features/agent/data/datasources/app_server/codex_collaboration_mode_catalog_failure.dart` | rewrite | `packages/codex_app_server_client/lib/src/` | Codex app-server adapter layer |
| `features/agent/data/datasources/app_server/codex_permission_policy_adapter.dart` | rewrite | `packages/codex_app_server_client/lib/src/` | Codex app-server adapter layer |
| `features/agent/data/datasources/app_server/codex_process_starter.dart` | rewrite | `packages/codex_app_server_client/lib/src/` | Codex app-server adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_agent_provider.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_anthropic_api_client.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_cli_metadata.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_cli_metadata_coordinator.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_cli_metadata_probe.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_control_request_handler.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_event_mapper.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_file_change_tracker.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_hidden_thread_store.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_macos_keychain_source.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_model_catalog.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_oauth_credentials_reader.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_permission_policy_adapter.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_plan_approval_adapter.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_process_starter.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_question_adapter.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_session_history_reader.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/claude_code_usage_quota_adapter.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/claude_code/stream_json_peer.dart` | rewrite | `packages/claude_code_client/lib/src/` | Claude Code stream-json adapter layer |
| `features/agent/data/datasources/local_history/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/agent/data/datasources/local_history/codex_jsonl_history_parser.dart` | rewrite | `packages/codex_app_server_client/lib/src/history/` | Vendor-specific parsers stay in their own vendor client (step 15) |
| `features/agent/data/datasources/local_history/codex_thread_history_reader.dart` | rewrite | `packages/codex_app_server_client/lib/src/history/` | Vendor-specific parsers stay in their own vendor client (step 15) |
| `features/agent/data/datasources/local_history/grok_chat_history_parser.dart` | rewrite | `packages/grok_acp_client/lib/src/history/` | Vendor-specific parsers stay in their own vendor client (step 15) |
| `features/agent/data/datasources/local_history/grok_session_history_reader.dart` | rewrite | `packages/grok_acp_client/lib/src/history/` | Vendor-specific parsers stay in their own vendor client (step 15) |
| `features/agent/data/datasources/local_history/grok_updates_history_parser.dart` | rewrite | `packages/grok_acp_client/lib/src/history/` | Vendor-specific parsers stay in their own vendor client (step 15) |
| `features/agent/data/datasources/local_history/grok_user_content_parser.dart` | rewrite | `packages/grok_acp_client/lib/src/history/` | Vendor-specific parsers stay in their own vendor client (step 15) |
| `features/agent/data/datasources/transport/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/agent/data/datasources/transport/json_rpc_stdio_transport.dart` | rewrite | `packages/json_rpc_transport/lib/src/` | JSON-RPC stdio, operation scheduler, runtime peer; process starter/clock/logger injected via constructor |
| `features/agent/data/datasources/transport/provider_operation_scheduler.dart` | rewrite | `packages/json_rpc_transport/lib/src/` | JSON-RPC stdio, operation scheduler, runtime peer; process starter/clock/logger injected via constructor |
| `features/agent/data/datasources/transport/provider_runtime_json_rpc_peer.dart` | rewrite | `packages/json_rpc_transport/lib/src/` | JSON-RPC stdio, operation scheduler, runtime peer; process starter/clock/logger injected via constructor |

### 6.5 agent · data · mappers

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `features/agent/data/mappers/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/agent/data/mappers/acp_content_codec.dart` | rewrite | `packages/grok_acp_client/lib/src/acp/` | ACP currently has only one consumer (Grok), so no shared package is extracted (step 14) |
| `features/agent/data/mappers/acp_permission_mapper.dart` | rewrite | `packages/grok_acp_client/lib/src/acp/` | ACP currently has only one consumer (Grok), so no shared package is extracted (step 14) |
| `features/agent/data/mappers/acp_session_config_mapper.dart` | rewrite | `packages/grok_acp_client/lib/src/acp/` | ACP currently has only one consumer (Grok), so no shared package is extracted (step 14) |
| `features/agent/data/mappers/acp_session_update_decoder.dart` | rewrite | `packages/grok_acp_client/lib/src/acp/` | ACP currently has only one consumer (Grok), so no shared package is extracted (step 14) |
| `features/agent/data/mappers/claude_code_initialize_metadata_mapper.dart` | rewrite | `packages/claude_code_client/lib/src/mappers/` | Claude Code protocol mapping |
| `features/agent/data/mappers/claude_code_permission_mode_codec.dart` | rewrite | `packages/claude_code_client/lib/src/mappers/` | Claude Code protocol mapping |
| `features/agent/data/mappers/claude_code_stream_identity.dart` | rewrite | `packages/claude_code_client/lib/src/mappers/` | Claude Code protocol mapping |
| `features/agent/data/mappers/claude_code_usage_quota_mapper.dart` | rewrite | `packages/claude_code_client/lib/src/mappers/` | Claude Code protocol mapping |
| `features/agent/data/mappers/codex_app_server_helpers.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex protocol mapping |
| `features/agent/data/mappers/codex_approval_mapper.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex protocol mapping |
| `features/agent/data/mappers/codex_collaboration_mode_mapper.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex protocol mapping |
| `features/agent/data/mappers/codex_conversation_mode_codec.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex protocol mapping |
| `features/agent/data/mappers/codex_file_change_tracker.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex protocol mapping |
| `features/agent/data/mappers/codex_model_list_mapper.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex protocol mapping |
| `features/agent/data/mappers/codex_notification_mapper.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex protocol mapping |
| `features/agent/data/mappers/codex_permission_policy_codec.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex protocol mapping |
| `features/agent/data/mappers/codex_question_mapper.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex protocol mapping |
| `features/agent/data/mappers/codex_skills_mapper.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex protocol mapping |
| `features/agent/data/mappers/codex_turn_start_params_encoder.dart` | rewrite | `packages/codex_app_server_client/lib/src/mappers/` | Codex protocol mapping |
| `features/agent/data/mappers/context_window_codec.dart` | rewrite | `packages/agent_provider_contracts/lib/src/codecs/` | A pure-function codec shared by all three providers; no vendor fields, satisfies ADR-001 |
| `features/agent/data/mappers/grok_acp_notification_mapper.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok protocol mapping |
| `features/agent/data/mappers/grok_billing_quota_mapper.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok protocol mapping |
| `features/agent/data/mappers/grok_error_normalizer.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok protocol mapping |
| `features/agent/data/mappers/grok_file_change_tracker.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok protocol mapping |
| `features/agent/data/mappers/grok_permission_mode_codec.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok protocol mapping |
| `features/agent/data/mappers/grok_question_mapper.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok protocol mapping |
| `features/agent/data/mappers/grok_session_update_mapper.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok protocol mapping |
| `features/agent/data/mappers/grok_skills_mapper.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok protocol mapping |
| `features/agent/data/mappers/grok_stream_identity.dart` | rewrite | `packages/grok_acp_client/lib/src/mappers/` | Grok protocol mapping |

### 6.6 agent · data · top level

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `features/agent/data/agent_ignored_message_logger.dart` | rewrite | `packages/zeta_logging/lib/src/` | Diagnostic counters for unmatched notifications; records only method/type/reason/count |
| `features/agent/data/agent_model_catalog_cache_store.dart` | rewrite | `packages/agent_config_client/lib/src/` | Current-schema persistence for provider config / model catalog cache / turn context (step 11) |
| `features/agent/data/agent_provider_config_codec.dart` | rewrite | `packages/agent_config_client/lib/src/` | Current-schema persistence for provider config / model catalog cache / turn context (step 11) |
| `features/agent/data/agent_provider_config_store.dart` | rewrite | `packages/agent_config_client/lib/src/` | Current-schema persistence for provider config / model catalog cache / turn context (step 11) |
| `features/agent/data/agent_provider_permission_migration.dart` | delete | — | Legacy permission value upgrade logic; no historical data compatibility (topology §1) |
| `features/agent/data/agent_provider_static_capabilities.dart` | rewrite | declared by each of the three vendor clients | Split: each client declares its own static capabilities, eliminating the centralized kind switch |
| `features/agent/data/agent_turn_context_codec.dart` | rewrite | `packages/agent_config_client/lib/src/` | Current-schema persistence for provider config / model catalog cache / turn context (step 11) |
| `features/agent/data/agent_turn_context_store.dart` | rewrite | `packages/agent_config_client/lib/src/` | Current-schema persistence for provider config / model catalog cache / turn context (step 11) |
| `features/agent/data/claude_code_cli_locator.dart` | rewrite | `packages/claude_code_client/lib/src/` | Exactly one CLI locator owner per vendor |
| `features/agent/data/cli_command_locator.dart` | rewrite | packages/agent_provider_contracts/ + the three vendor clients | The ResolvedCliProcessCommand value type goes to contracts; each vendor keeps its own locate implementation (step 17) |
| `features/agent/data/codex_cli_locator.dart` | rewrite | `packages/codex_app_server_client/lib/src/` | Exactly one CLI locator owner per vendor |
| `features/agent/data/default_agent_provider_factory.dart` | rewrite | `packages/agent_provider_repository/lib/src/` | The bundle factory registry belongs to the Repository; no kind branching in the Data layer |
| `features/agent/data/grok_cli_locator.dart` | rewrite | `packages/grok_acp_client/lib/src/` | Exactly one CLI locator owner per vendor |
| `features/agent/data/native_agent_provider_bundles.dart` | rewrite | `packages/agent_provider_repository/lib/src/` | Bundle assembly belongs to the provider repository |
| `features/agent/data/repositories/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |

### 6.7 agent · application (highest risk, ruled file by file)

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `features/agent/application/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/agent/application/agent_conversation_binding.dart` | rewrite | `packages/agent_conversation_repository/` | Conversation aggregate root; external data orchestration |
| `features/agent/application/agent_conversation_binding_manager.dart` | rewrite | `packages/agent_conversation_repository/` | Conversation lifecycle and leases |
| `features/agent/application/agent_conversation_effect.dart` | rewrite | `packages/agent_conversation_repository/` | Protocol effects are domain orchestration |
| `features/agent/application/agent_conversation_effect_runner.dart` | rewrite | `packages/agent_conversation_repository/` | Effect runner; UI effects are split out to the Bloc |
| `features/agent/application/agent_conversation_event_processor.dart` | rewrite | `packages/agent_conversation_repository/` | Provider event normalization |
| `features/agent/application/agent_conversation_mode_controller.dart` | rewrite | `lib/agent_chat/bloc/` | Mode **selection** is interaction state -> Bloc |
| `features/agent/application/agent_conversation_model_selection_controller.dart` | rewrite | `lib/agent_chat/bloc/` | Model **selection** is interaction state -> Bloc |
| `features/agent/application/agent_conversation_mutation.dart` | rewrite | `packages/agent_conversation_repository/` | Domain snapshot change description |
| `features/agent/application/agent_conversation_permission_selection_controller.dart` | rewrite | `lib/agent_chat/bloc/` | Permission option **selection** -> Bloc |
| `features/agent/application/agent_conversation_permission_state.dart` | rewrite | split | Pending requests -> Repository; UI selection -> Bloc State |
| `features/agent/application/agent_conversation_reducer.dart` | rewrite | `packages/agent_conversation_repository/` | Deterministic reduction stays in the Repository (ADR-004) |
| `features/agent/application/agent_conversation_thread_snapshot.dart` | rewrite | `packages/agent_conversation_repository/` | Domain snapshot |
| `features/agent/application/agent_conversation_timeline_store.dart` | rewrite | split | 2,017 lines: domain aggregate -> Repository; UI slice -> Bloc State |
| `features/agent/application/agent_elapsed_ticker.dart` | rewrite | `lib/agent_chat/bloc/` | Elapsed time is derived UI state; the Bloc owns the timer and cancels it in close() |
| `features/agent/application/agent_event_coalescing_policy.dart` | rewrite | `packages/agent_conversation_repository/` | Event coalescing belongs to the data pipeline |
| `features/agent/application/agent_event_pipeline.dart` | rewrite | `packages/agent_conversation_repository/` | Core of the event pipeline |
| `features/agent/application/agent_model_catalog_repository.dart` | rewrite | `packages/agent_provider_repository/` | Single source of truth for the model catalog TTL cache |
| `features/agent/application/agent_permission_catalog_controller.dart` | rewrite | `packages/agent_provider_repository/` | The permission catalog is external data; the selection belongs to the Bloc |
| `features/agent/application/agent_permission_request_resolver.dart` | rewrite | `packages/agent_conversation_repository/` | Pending permission request resolution |
| `features/agent/application/agent_plan_execution_handoff_controller.dart` | rewrite | `lib/agent_chat/bloc/` | The local handoff is a business rule -> Bloc (step 32) |
| `features/agent/application/agent_provider_config_store.dart` | rewrite | `packages/agent_provider_repository/` | Config orchestration; IO moves down to agent_config_client |
| `features/agent/application/agent_provider_event_listener_gate.dart` | rewrite | `packages/agent_conversation_repository/` | The subscription gate belongs to external-data lifecycle |
| `features/agent/application/agent_provider_global_runtime.dart` | rewrite | `packages/agent_provider_repository/` | Holds the global runtime |
| `features/agent/application/agent_provider_runtime_identity.dart` | rewrite | `packages/agent_conversation_repository/` | Runtime generation checks |
| `features/agent/application/agent_provider_runtime_registry.dart` | rewrite | `packages/agent_conversation_repository/` | Runtime lease registry |
| `features/agent/application/agent_provider_settings_controller.dart` | rewrite | `packages/agent_provider_repository/` | Provider settings persistence |
| `features/agent/application/agent_provider_settings_port.dart` | rewrite | `packages/agent_provider_contracts/` | Pure port definition |
| `features/agent/application/agent_skills_catalog_controller.dart` | rewrite | `packages/agent_provider_repository/` | The skill catalog is external data |
| `features/agent/application/agent_thread_workspace_controller.dart` | rewrite | `packages/project_session_repository/` | Thread-to-workspace association data |
| `features/agent/application/agent_turn_context_overlay.dart` | rewrite | `packages/agent_conversation_repository/` | Turn context overlay is domain logic |
| `features/agent/application/agent_turn_context_recorder.dart` | rewrite | `packages/agent_conversation_repository/` | Turn context recording |
| `features/agent/application/agent_ui_update_port.dart` | delete | — | The UI update port is replaced by Bloc State + BlocSelector |
| `features/agent/application/agent_ui_update_request.dart` | rewrite | `lib/agent_chat/view/` | AgentUiRegion/urgency retained for the presentation frame scheduler (topology §5) |
| `features/agent/application/bounded_event_dispatcher.dart` | rewrite | `packages/agent_conversation_repository/` | Bounded event dispatch and backpressure |
| `features/agent/application/coalescing_event_buffer.dart` | rewrite | `packages/agent_conversation_repository/` | Coalescing buffer |

### 6.8 agent · presentation

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `features/agent/presentation/agent_conversation_navigation.dart` | rewrite | `lib/app/router/` | Navigation moves to typed GoRouter routes; Blocs do not depend on GoRouter |
| `features/agent/presentation/agent_conversation_ui_state.dart` | rewrite | `lib/agent_chat/bloc/` | 1,098 lines -> the five AgentConversationState slices |
| `features/agent/presentation/agent_conversation_view_model.dart` | rewrite | `lib/agent_chat/bloc/` | 4,190-line ViewModel -> AgentConversationBloc (see the conversation state design doc) |
| `features/agent/presentation/agent_file_change_projection.dart` | rewrite | `lib/agent_chat/view/` | Presentation helpers: projection, caches, grouping and scheduler stay in the presentation layer |
| `features/agent/presentation/agent_file_change_projection_cache.dart` | rewrite | `lib/agent_chat/view/` | Presentation helpers: projection, caches, grouping and scheduler stay in the presentation layer |
| `features/agent/presentation/agent_markdown_cache.dart` | rewrite | `lib/agent_chat/view/` | Presentation helpers: projection, caches, grouping and scheduler stay in the presentation layer |
| `features/agent/presentation/agent_pane.dart` | rewrite | `lib/agent_chat/view/` | Presentation helpers: projection, caches, grouping and scheduler stay in the presentation layer |
| `features/agent/presentation/agent_plan_revision_drafts.dart` | rewrite | `lib/agent_chat/view/` | Presentation helpers: projection, caches, grouping and scheduler stay in the presentation layer |
| `features/agent/presentation/agent_presentation_l10n.dart` | rewrite | `lib/l10n/` | Exhaustive typed failure/code -> ARB mapping |
| `features/agent/presentation/agent_timeline_extent_descriptor.dart` | rewrite | `lib/agent_chat/view/` | Presentation helpers: projection, caches, grouping and scheduler stay in the presentation layer |
| `features/agent/presentation/agent_timeline_grouping.dart` | rewrite | `lib/agent_chat/view/` | Presentation helpers: projection, caches, grouping and scheduler stay in the presentation layer |
| `features/agent/presentation/agent_timeline_projection.dart` | rewrite | `lib/agent_chat/view/` | Presentation helpers: projection, caches, grouping and scheduler stay in the presentation layer |
| `features/agent/presentation/agent_timeline_projection_cache.dart` | rewrite | `lib/agent_chat/view/` | Presentation helpers: projection, caches, grouping and scheduler stay in the presentation layer |
| `features/agent/presentation/agent_ui_update_scheduler.dart` | rewrite | `lib/agent_chat/view/` | Presentation helpers: projection, caches, grouping and scheduler stay in the presentation layer |
| `features/agent/presentation/composer_document.dart` | rewrite | `lib/agent_chat/view/` | Presentation helpers: projection, caches, grouping and scheduler stay in the presentation layer |
| `features/agent/presentation/model_config_ui_state.dart` | rewrite | `lib/agent_chat/view/` | Presentation helpers: projection, caches, grouping and scheduler stay in the presentation layer |
| `features/agent/presentation/widgets/agent_file_change_evidence_card.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/agent_file_change_evidence_views.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/agent_mention_file_picker.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/agent_mode_selector.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/agent_model_config.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/agent_pane_cards.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/agent_pane_composer.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/agent_pane_context_panel.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/agent_pane_header.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/agent_pane_messages.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/agent_pane_navigation_rail.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/agent_pane_plan_panel.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/agent_pane_sections.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/agent_pane_styles.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/agent_provider_icon.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/agent_skill_picker.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/agent_slash_command_picker.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |
| `features/agent/presentation/widgets/composer_selector_popover.dart` | rewrite | `lib/agent_chat/widgets/` | Switch to BlocBuilder/BlocSelector; files over 1.5k lines are split, with no visual redesign (step 33) |

### 6.9 agent_management

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `features/agent_management/application/agent_management_controller.dart` | rewrite | packages/agent_management_repository/ or lib/agent_management/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/agent_management/data/claude_code_agent_management_repository.dart` | rewrite | `packages/agent_management_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/agent_management/data/claude_code_auth_status_probe.dart` | rewrite | `packages/agent_management_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/agent_management/data/cli_process_runner.dart` | rewrite | `packages/agent_management_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/agent_management/data/codex_agent_management_repository.dart` | rewrite | `packages/agent_management_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/agent_management/data/grok_agent_management_repository.dart` | rewrite | `packages/agent_management_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/agent_management/domain/agent_cli_management_repository.dart` | rewrite | `packages/agent_management_repository/lib/src/` | Domain models belong to the Repository |
| `features/agent_management/domain/agent_management_models.dart` | rewrite | `packages/agent_management_repository/lib/src/` | Domain models belong to the Repository |
| `features/agent_management/domain/agent_management_text_catalog.dart` | delete | — | TextCatalog deleted (step 28) |
| `features/agent_management/domain/fallback_agent_management_text_catalog.dart` | delete | — | Fallback TextCatalog deleted (step 28) |
| `features/agent_management/presentation/agent_configuration_editor.dart` | rewrite | `lib/agent_management/view/` | Page injects the Bloc; View/Widget consume State |
| `features/agent_management/presentation/agent_log_view.dart` | rewrite | `lib/agent_management/view/` | Page injects the Bloc; View/Widget consume State |
| `features/agent_management/presentation/agent_management_l10n.dart` | rewrite | `lib/agent_management/view/` | Page injects the Bloc; View/Widget consume State |
| `features/agent_management/presentation/agent_management_page.dart` | rewrite | `lib/agent_management/view/` | Page injects the Bloc; View/Widget consume State |

### 6.10 desktop_notifications

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `features/desktop_notifications/application/desktop_attention_controller.dart` | rewrite | packages/desktop_notifications_repository/ or lib/desktop_notifications/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/desktop_notifications/data/flutter_desktop_notification_service.dart` | rewrite | `packages/desktop_notifications_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/desktop_notifications/data/method_channel_desktop_attention_indicator.dart` | rewrite | `packages/desktop_notifications_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/desktop_notifications/domain/desktop_attention_models.dart` | rewrite | `packages/desktop_notifications_repository/lib/src/` | Domain models belong to the Repository |
| `features/desktop_notifications/domain/desktop_attention_text_catalog.dart` | delete | — | TextCatalog deleted (step 28) |
| `features/desktop_notifications/domain/fallback_desktop_attention_text_catalog.dart` | delete | — | Fallback TextCatalog deleted (step 28) |

### 6.11 ide_session

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `features/ide_session/application/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/ide_session/application/ide_session_persistence_coordinator.dart` | rewrite | packages/project_session_repository/ or lib/ide_session/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/ide_session/application/ide_session_restore_result.dart` | rewrite | packages/project_session_repository/ or lib/ide_session/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/ide_session/application/ide_session_state_builder.dart` | rewrite | packages/project_session_repository/ or lib/ide_session/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/ide_session/data/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/ide_session/data/ide_session_store.dart` | rewrite | `packages/project_session_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/ide_session/domain/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/ide_session/domain/ide_session_state.dart` | rewrite | `packages/project_session_repository/lib/src/` | Domain models belong to the Repository |
| `features/ide_session/domain/ide_workbench_layout_state.dart` | rewrite | `packages/project_session_repository/lib/src/` | Domain models belong to the Repository |
| `features/ide_session/domain/recent_project_summary.dart` | rewrite | `packages/project_session_repository/lib/src/` | Domain models belong to the Repository |

### 6.12 project_threads

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `features/project_threads/application/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/project_threads/application/project_threads_controller.dart` | rewrite | packages/project_session_repository/ or lib/project_threads/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/project_threads/application/project_threads_session_snapshot_codec.dart` | rewrite | packages/project_session_repository/ or lib/project_threads/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/project_threads/data/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/project_threads/domain/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/project_threads/domain/project_thread_list_state.dart` | rewrite | `packages/project_session_repository/lib/src/` | Domain models belong to the Repository |
| `features/project_threads/domain/project_threads_session_snapshot.dart` | rewrite | `packages/project_session_repository/lib/src/` | Domain models belong to the Repository |
| `features/project_threads/presentation/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/project_threads/presentation/project_threads_view_model.dart` | rewrite | `lib/project_threads/view/` | Page injects the Bloc; View/Widget consume State |

### 6.13 settings

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `features/settings/application/app_language_resolver.dart` | rewrite | packages/settings_repository/ or lib/settings/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/settings/application/appearance_settings_controller.dart` | rewrite | packages/settings_repository/ or lib/settings/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/settings/application/general_settings_controller.dart` | rewrite | packages/settings_repository/ or lib/settings/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/settings/application/general_settings_update_result.dart` | rewrite | packages/settings_repository/ or lib/settings/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/settings/data/appearance_settings_store.dart` | rewrite | `packages/settings_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/settings/data/general_settings_codec.dart` | rewrite | `packages/settings_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/settings/data/general_settings_store.dart` | rewrite | `packages/settings_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/settings/data/system_font_catalog_service.dart` | rewrite | `packages/settings_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/settings/domain/app_language.dart` | rewrite | `packages/settings_repository/lib/src/` | Domain models belong to the Repository |
| `features/settings/domain/appearance_settings.dart` | rewrite | `packages/settings_repository/lib/src/` | Domain models belong to the Repository |
| `features/settings/domain/general_settings.dart` | rewrite | `packages/settings_repository/lib/src/` | Domain models belong to the Repository |
| `features/settings/domain/system_font_family.dart` | rewrite | `packages/settings_repository/lib/src/` | Domain models belong to the Repository |
| `features/settings/presentation/settings_page.dart` | rewrite | `lib/settings/view/` | Page injects the Bloc; View/Widget consume State |

### 6.14 usage_statistics

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `features/usage_statistics/application/agent_usage_panel_controller.dart` | rewrite | packages/usage_statistics_repository/ or lib/usage_statistics/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/usage_statistics/application/agent_usage_query_service.dart` | rewrite | packages/usage_statistics_repository/ or lib/usage_statistics/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/usage_statistics/application/agent_usage_refresh_coordinator.dart` | rewrite | packages/usage_statistics_repository/ or lib/usage_statistics/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/usage_statistics/application/agent_usage_token_aggregation.dart` | rewrite | packages/usage_statistics_repository/ or lib/usage_statistics/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/usage_statistics/application/query_agent_usage_panel_repository.dart` | rewrite | packages/usage_statistics_repository/ or lib/usage_statistics/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/usage_statistics/application/query_usage_statistics_repository.dart` | rewrite | packages/usage_statistics_repository/ or lib/usage_statistics/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/usage_statistics/application/usage_statistics_controller.dart` | rewrite | packages/usage_statistics_repository/ or lib/usage_statistics/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/usage_statistics/application/usage_statistics_report_builder.dart` | rewrite | packages/usage_statistics_repository/ or lib/usage_statistics/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/usage_statistics/data/built_in_agent_token_usage_source_registry.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/usage_statistics/data/global_runtime_agent_usage_quota_source.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/usage_statistics/data/legacy_usage_statistics_index_decoder.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/usage_statistics/data/providers/claude_code/claude_code_token_usage_source.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/usage_statistics/data/providers/claude_code/claude_code_usage_partition_codec.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/usage_statistics/data/providers/codex/codex_token_usage_source.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/usage_statistics/data/providers/codex/codex_usage_log_scanner.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/usage_statistics/data/providers/codex/codex_usage_partition_codec.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/usage_statistics/data/providers/grok/grok_token_usage_source.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/usage_statistics/data/providers/grok/grok_usage_log_scanner.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/usage_statistics/data/providers/grok/grok_usage_partition_codec.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/usage_statistics/data/providers/usage_scan_cache.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/usage_statistics/data/usage_statistics_partition_store.dart` | rewrite | `packages/usage_statistics_client/lib/src/` | External IO and current-schema reads/writes move down into the Data package |
| `features/usage_statistics/domain/agent_token_usage_source.dart` | rewrite | `packages/usage_statistics_repository/lib/src/` | Domain models belong to the Repository |
| `features/usage_statistics/domain/agent_usage_panel_models.dart` | rewrite | `packages/usage_statistics_repository/lib/src/` | Domain models belong to the Repository |
| `features/usage_statistics/domain/agent_usage_query_models.dart` | rewrite | `packages/usage_statistics_repository/lib/src/` | Domain models belong to the Repository |
| `features/usage_statistics/domain/agent_usage_quota_source.dart` | rewrite | `packages/usage_statistics_repository/lib/src/` | Domain models belong to the Repository |
| `features/usage_statistics/domain/fallback_usage_statistics_text_catalog.dart` | delete | — | Fallback TextCatalog deleted (step 28) |
| `features/usage_statistics/domain/usage_statistics_models.dart` | rewrite | `packages/usage_statistics_repository/lib/src/` | Domain models belong to the Repository |
| `features/usage_statistics/domain/usage_statistics_repository.dart` | rewrite | `packages/usage_statistics_repository/lib/src/` | Domain models belong to the Repository |
| `features/usage_statistics/domain/usage_statistics_text_catalog.dart` | delete | — | TextCatalog deleted (step 28) |
| `features/usage_statistics/presentation/agent_usage_panel.dart` | rewrite | `lib/usage_statistics/view/` | Page injects the Bloc; View/Widget consume State |
| `features/usage_statistics/presentation/agent_usage_quota_gallery.dart` | rewrite | `lib/usage_statistics/view/` | Page injects the Bloc; View/Widget consume State |
| `features/usage_statistics/presentation/usage_statistics_formatters.dart` | rewrite | `lib/usage_statistics/view/` | Page injects the Bloc; View/Widget consume State |
| `features/usage_statistics/presentation/usage_statistics_l10n.dart` | rewrite | `lib/usage_statistics/view/` | Page injects the Bloc; View/Widget consume State |
| `features/usage_statistics/presentation/usage_statistics_page.dart` | rewrite | `lib/usage_statistics/view/` | Page injects the Bloc; View/Widget consume State |
| `features/usage_statistics/presentation/usage_time_range_filter.dart` | rewrite | `lib/usage_statistics/view/` | Page injects the Bloc; View/Widget consume State |

### 6.15 workspace

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `features/workspace/application/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/workspace/application/workspace_file_index_controller.dart` | rewrite | packages/workspace_repository/ or lib/workspace/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/workspace/application/workspace_file_indexer.dart` | rewrite | packages/workspace_repository/ or lib/workspace/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/workspace/application/workspace_tree_builder.dart` | rewrite | packages/workspace_repository/ or lib/workspace/ | Per-file rulings in ownership_map.md: external data -> Repository, interaction state -> Bloc/Cubit |
| `features/workspace/data/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/workspace/domain/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/workspace/domain/workspace_directory_rules.dart` | rewrite | `packages/workspace_repository/lib/src/` | Domain models belong to the Repository |
| `features/workspace/domain/workspace_file_query.dart` | rewrite | `packages/workspace_repository/lib/src/` | Domain models belong to the Repository |
| `features/workspace/domain/workspace_gitignore.dart` | rewrite | `packages/workspace_repository/lib/src/` | Domain models belong to the Repository |
| `features/workspace/domain/workspace_node.dart` | rewrite | `packages/workspace_repository/lib/src/` | Domain models belong to the Repository |
| `features/workspace/presentation/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `features/workspace/presentation/file_tree_pane.dart` | rewrite | `lib/workspace/view/` | Page injects the Bloc; View/Widget consume State |

### 6.16 ui

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `ui/core/app_theme.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_activity_rail.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_button.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_chip.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_choice_card.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_collapsible_card.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_colors.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_context_menu.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_dialog.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_effects.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_icon_box.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_image_preview.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_metrics.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_motion.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_popover.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_resize_handle.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_select.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_skeleton.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_spacing.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_stable_overlay_handler.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_status_card.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_switch.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_tabs.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_text_styles.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/ide_toast.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/layout/ide_constraint_bucket_builder.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/metrics/compact_metric_bar.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/pane_widgets.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/rows/ide_data_row.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/rows/ide_key_value_row.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/rows/ide_list_row.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/rows/ide_row_divider.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/rows/ide_row_group.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/rows/ide_settings_row.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/surfaces/ide_surface.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/virtualization/ide_dynamic_sliver_list.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/virtualization/ide_extent_index.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/virtualization/ide_smooth_scroll_controller.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/virtualization/ide_virtual_item.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/virtualization/ide_virtual_list_controller.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/virtualization/ide_virtual_scroll_coordinator.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/virtualization/ide_virtual_scrollbar.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/window_frame.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/workbench/ide_page_body.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/workbench/ide_page_header.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/workbench/ide_retained_page_view.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/workbench/ide_section.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/workbench/ide_toolbar.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/core/workbench/ide_workbench_scaffold.dart` | rewrite | `packages/app_ui/lib/src/` | Design tokens, base components, Workbench primitives, virtual scrolling; all copy is passed via constructor parameters (step 27) |
| `ui/features/ide/views/global_home_page.dart` | rewrite | `lib/ide_shell/view/` | IDE shell pages; navigation switches to typed routes |
| `ui/features/ide/views/global_home_page_preview.dart` | rewrite | `lib/ide_shell/view/` | IDE shell pages; navigation switches to typed routes |
| `ui/features/ide/views/ide_home.dart` | rewrite | `lib/ide_shell/view/` | IDE shell pages; navigation switches to typed routes |
| `ui/features/ide/views/new_thread_provider_popover.dart` | rewrite | `lib/ide_shell/view/` | IDE shell pages; navigation switches to typed routes |
| `ui/features/ide/views/project_agent_sidebar.dart` | rewrite | `lib/ide_shell/view/` | IDE shell pages; navigation switches to typed routes |
| `ui/features/ide/views/project_home_page.dart` | rewrite | `lib/ide_shell/view/` | IDE shell pages; navigation switches to typed routes |
| `ui/features/ide/views/project_list_pane.dart` | rewrite | `lib/ide_shell/view/` | IDE shell pages; navigation switches to typed routes |
| `ui/localization/app_localizations_x.dart` | rewrite | `lib/l10n/l10n.dart` | The l10n / l10nOrNull extensions |
| `ui/localization/arb/app_en.arb` | move | `lib/l10n/arb/` | 1,035 keys each for en/zh; the scaffold app_es.arb is deleted (step 5) |
| `ui/localization/arb/app_zh.arb` | move | `lib/l10n/arb/` | 1,035 keys each for en/zh; the scaffold app_es.arb is deleted (step 5) |
| `ui/localization/generated/app_localizations.dart` | regenerate | `lib/l10n/generated/` | Regenerated by flutter gen-l10n; not migrated by hand (step 5) |
| `ui/localization/generated/app_localizations_en.dart` | regenerate | `lib/l10n/generated/` | Regenerated by flutter gen-l10n; not migrated by hand (step 5) |
| `ui/localization/generated/app_localizations_zh.dart` | regenerate | `lib/l10n/generated/` | Regenerated by flutter gen-l10n; not migrated by hand (step 5) |
| `ui/localization/relative_time.dart` | rewrite | `lib/l10n/` | Relative-time copy depends on ARB, so it stays in the app |
| `ui/localization/zeta_shadcn_localizations.dart` | rewrite | `lib/l10n/` | Stays in the app, not in app_ui (topology §8) |

**`lib/` coverage check**: 377 / 377

---

## 7. `test/` (301) — grouped by rule

Tests follow the ownership of what they test, so they are grouped by rule rather than listed one by
one; each rule's hit count is verified and the totals equal every tracked file under `test/`.
**Rules match longest-prefix-first**: the more specific rules near the top win, and the generic rules
below only cover what is left.

| Rule | Files | Action | Target | Note |
| --- | ---: | --- | --- | --- |
| `test/src/features/agent/data/datasources/claude_code/**` | 31 | rewrite | `packages/claude_code_client/test/` | Includes the fixtures/ subdirectory (step 17) |
| `test/src/features/agent/data/datasources/app_server/**` | 3 | rewrite | `packages/codex_app_server_client/test/` | Fixtures are assigned per package with no cross-package imports (step 17) |
| `test/src/features/agent/data/datasources/transport/**` | 3 | rewrite | `packages/json_rpc_transport/test/` | — |
| `test/src/features/agent/data/datasources/acp/**` | 2 | rewrite | `packages/grok_acp_client/test/` | Fixtures are assigned per package (step 17) |
| `test/src/features/agent/presentation/**` | 30 | rewrite | `test/agent_chat/ + packages/app_ui/test/` | MockBloc widget tests + goldens |
| `test/tool/report_test_timings_test.dart` | 1 | rewrite | companion tests for tool/ | — |
| `test/src/features/agent/application/**` | 25 | rewrite | assigned per ownership_map to repository packages and blocTests under lib/agent_chat/ | — |
| `test/support/scroll_metrics_trace.dart` | 1 | rewrite | `test/helpers/` | Shared widget test helpers such as pumpApp |
| `test/src/features/agent/domain/**` | 17 | rewrite | `packages/agent_provider_contracts/test/` | — |
| `test/src/features/agent/data/**` | 33 | rewrite | assigned by mapper prefix to the matching vendor package | — |
| `test/flutter_test_config.dart` | 1 | rewrite | `test/flutter_test_config.dart` | Golden font loading and global test config; one copy per workspace package that has widget tests |
| `test/src/architecture/**` | 3 | rewrite | `test/architecture/ + .architecture.yaml` | Step 6 complete: 24 assertions cover configuration, package dependencies, source boundaries, and the CI contract |
| `test/src/features/**` | 55 | rewrite | the matching package/test or test/<feature>/ | Tests mirror lib/ and follow the ownership of what they test |
| `test/src/testing/**` | 13 | rewrite | test/helpers/ of each package | Shared harnesses are copied per package; cross-package test imports are forbidden |
| `test/fixtures/**` | 26 | rewrite | assigned per provider to the matching vendor package's test/fixtures/ | — |
| `test/src/core/**` | 4 | rewrite | packages/zeta_logging/test/ and packages/zeta_storage/test/ | — |
| `test/src/app/**` | 11 | rewrite | `test/app/` | — |
| `test/src/ui/**` | 42 | rewrite | packages/app_ui/test/ and test/ide_shell/ | — |

> **Fixture ownership is a hard constraint.** [Step 17](./migration_tasks.md) requires "existing
> protocol fixtures assigned per package, with no cross-package test imports". The four directories
> under `test/fixtures/` — `agent_file_change_evidence`, `agent_permission_runtime_architecture`,
> `agent_stream_identity` and `grok` — must be split per provider first, then migrate with their
> vendor package. Shared harnesses are copied, never cross-imported.

---

## 8. Desktop platforms (65)

All three platforms unify on `cn.easii.zeta` / product name `Zeta`, with no identity suffix per flavor
([step 3](./migration_tasks.md)). Generated plugin registrants can be regenerated; hand-written
Runners, MethodChannels and icons must be confirmed individually.

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `linux/.gitignore` | rewrite | `linux/` | The new repo has no Linux scaffold; generate it with flutter create first, then migrate the hand-written parts (step 3) |
| `linux/CMakeLists.txt` | rewrite | `linux/` | The new repo has no Linux scaffold; generate it with flutter create first, then migrate the hand-written parts (step 3) |
| `linux/flutter/CMakeLists.txt` | rewrite | `linux/` | The new repo has no Linux scaffold; generate it with flutter create first, then migrate the hand-written parts (step 3) |
| `linux/flutter/generated_plugin_registrant.cc` | rewrite | `linux/` | The new repo has no Linux scaffold; generate it with flutter create first, then migrate the hand-written parts (step 3) |
| `linux/flutter/generated_plugin_registrant.h` | rewrite | `linux/` | The new repo has no Linux scaffold; generate it with flutter create first, then migrate the hand-written parts (step 3) |
| `linux/flutter/generated_plugins.cmake` | rewrite | `linux/` | The new repo has no Linux scaffold; generate it with flutter create first, then migrate the hand-written parts (step 3) |
| `linux/runner/CMakeLists.txt` | rewrite | `linux/` | The new repo has no Linux scaffold; generate it with flutter create first, then migrate the hand-written parts (step 3) |
| `linux/runner/desktop_attention_channel.cc` | rewrite | `linux/` | The new repo has no Linux scaffold; generate it with flutter create first, then migrate the hand-written parts (step 3) |
| `linux/runner/desktop_attention_channel.h` | rewrite | `linux/` | The new repo has no Linux scaffold; generate it with flutter create first, then migrate the hand-written parts (step 3) |
| `linux/runner/main.cc` | rewrite | `linux/` | The new repo has no Linux scaffold; generate it with flutter create first, then migrate the hand-written parts (step 3) |
| `linux/runner/my_application.cc` | rewrite | `linux/` | The new repo has no Linux scaffold; generate it with flutter create first, then migrate the hand-written parts (step 3) |
| `linux/runner/my_application.h` | rewrite | `linux/` | The new repo has no Linux scaffold; generate it with flutter create first, then migrate the hand-written parts (step 3) |
| `linux/runner/resources/app_icon.png` | rewrite | `linux/` | The new repo has no Linux scaffold; generate it with flutter create first, then migrate the hand-written parts (step 3) |
| `linux/runner/system_font_catalog_channel.cc` | rewrite | `linux/` | The new repo has no Linux scaffold; generate it with flutter create first, then migrate the hand-written parts (step 3) |
| `linux/runner/system_font_catalog_channel.h` | rewrite | `linux/` | The new repo has no Linux scaffold; generate it with flutter create first, then migrate the hand-written parts (step 3) |
| `macos/.gitignore` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Flutter/Flutter-Debug.xcconfig` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Flutter/Flutter-Release.xcconfig` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Flutter/GeneratedPluginRegistrant.swift` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner.xcodeproj/project.pbxproj` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner.xcworkspace/contents.xcworkspacedata` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/AppDelegate.swift` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/Base.lproj/MainMenu.xib` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/Configs/AppInfo.xcconfig` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/Configs/Debug.xcconfig` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/Configs/Release.xcconfig` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/Configs/Warnings.xcconfig` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/DebugProfile.entitlements` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/Info.plist` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/MainFlutterWindow.swift` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/Runner/Release.entitlements` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `macos/RunnerTests/RunnerTests.swift` | rewrite | `macos/` | Hand-written Runner and channels migrate; bundle ID unified to cn.easii.zeta with flavor identity suffixes removed (step 3) |
| `windows/.gitignore` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/CMakeLists.txt` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/flutter/CMakeLists.txt` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/flutter/generated_plugin_registrant.cc` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/flutter/generated_plugin_registrant.h` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/flutter/generated_plugins.cmake` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/runner/CMakeLists.txt` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/runner/Runner.rc` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/runner/desktop_attention_channel.cpp` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/runner/desktop_attention_channel.h` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/runner/flutter_window.cpp` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/runner/flutter_window.h` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/runner/main.cpp` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/runner/resource.h` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/runner/resources/app_icon.ico` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/runner/runner.exe.manifest` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/runner/system_font_catalog_channel.cpp` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/runner/system_font_catalog_channel.h` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/runner/utils.cpp` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/runner/utils.h` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/runner/win32_window.cpp` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |
| `windows/runner/win32_window.h` | rewrite | `windows/` | Hand-written Runner and channels migrate; application ID unified to cn.easii.zeta (step 3) |

> **Linux note**: the new repo has **no** `linux/` directory yet. The correct order is to run
> `flutter create --platforms=linux .` to generate the scaffold first, then migrate the hand-written
> parts above — do not copy the old repo's `linux/` wholesale, or Flutter version drift will break the build.

---

## 9. Assets, protocol snapshot and CI

### 9.1 `assets/` (13)

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `assets/branding/zeta_logo.svg` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons (step 5) |
| `assets/fonts/Geist-Bold.ttf` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons (step 5) |
| `assets/fonts/Geist-Medium.ttf` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons (step 5) |
| `assets/fonts/Geist-Regular.ttf` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons (step 5) |
| `assets/fonts/Geist-SemiBold.ttf` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons (step 5) |
| `assets/fonts/JetBrainsMono-Bold.ttf` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons (step 5) |
| `assets/fonts/JetBrainsMono-Medium.ttf` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons (step 5) |
| `assets/fonts/JetBrainsMono-Regular.ttf` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons (step 5) |
| `assets/fonts/OFL-Geist.txt` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons (step 5) |
| `assets/fonts/OFL-JetBrainsMono.txt` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons (step 5) |
| `assets/icons/agents/claude.svg` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons (step 5) |
| `assets/icons/agents/codex.svg` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons (step 5) |
| `assets/icons/agents/grok.svg` | move | `assets/` | Geist / JetBrainsMono / branding / agent icons (step 5) |

### 9.2 `third_party/` (269)

Migrated as a single unit with `move`, same path. Rationale in §5.1.

| Rule | Files | Action | Target |
| --- | ---: | --- | --- |
| `third_party/codex_app_server_schema/**` | 269 | move | `third_party/codex_app_server_schema/` |

### 9.3 `.github/` (6)

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | rewrite | `.github/` | The new repo already has the VGV workflow; only the OSV / license / architecture-gate deltas migrate (step 6) |
| `.github/ISSUE_TEMPLATE/config.yml` | rewrite | `.github/` | The new repo already has the VGV workflow; only the OSV / license / architecture-gate deltas migrate (step 6) |
| `.github/ISSUE_TEMPLATE/feature_request.yml` | rewrite | `.github/` | The new repo already has the VGV workflow; only the OSV / license / architecture-gate deltas migrate (step 6) |
| `.github/PULL_REQUEST_TEMPLATE.md` | rewrite | `.github/` | The new repo already has the VGV workflow; only the OSV / license / architecture-gate deltas migrate (step 6) |
| `.github/workflows/ci.yml` | rewrite | `.github/workflows/main.yaml` | Step 6 complete: 27-root quality matrix, uniform `very_good test`, generated-source coverage exclusion, randomized tests, 100% coverage, and a golden job |
| `.github/workflows/release.yml` | rewrite | `.github/workflows/{desktop_build,osv_scan,license_check}.yaml` | Step 6 complete: three-platform matrix, OSV, license, and explained-exception gates |

---

## 10. Root files (19)

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `.gitignore` | rewrite | `.gitignore` | Merge the old rules; drop the Rust/packaging entries |
| `.metadata` | regenerate | `.metadata` | Generated by flutter create in the new repo |
| `AGENTS.md` | rewrite | `AGENTS.md` | 28 KB of legacy constraints; G1-G8 rewritten as machine-checkable gates in .architecture.yaml |
| `CHANGELOG.md` | rewrite | `CHANGELOG.md` | The new repo restarts from 1.0.0+1 |
| `CLAUDE.md` | rewrite | `CLAUDE.md` | Points at the new repo's documentation index |
| `CODE_OF_CONDUCT.md` | move | `CODE_OF_CONDUCT.md` | — |
| `CONTRIBUTING.en.md` | rewrite | `CONTRIBUTING.en.md` | — |
| `CONTRIBUTING.md` | rewrite | `CONTRIBUTING.md` | Rewritten around the four VGV gates and the architecture gates |
| `LICENSE` | move | `LICENSE` | — |
| `README.en.md` | rewrite | `README.en.md` | — |
| `README.md` | rewrite | `README.md` | Rewritten for the new architecture; both language versions kept |
| `SECURITY.md` | move | `SECURITY.md` | — |
| `analysis_options.yaml` | rewrite | `analysis_options.yaml` | Unified very_good_analysis |
| `dart_test.yaml` | rewrite | `dart_test.yaml + packages/app_ui/dart_test.yaml` | Step 6 complete: randomized ordering + golden tag |
| `devtools_options.yaml` | move | `devtools_options.yaml` | — |
| `l10n.yaml` | rewrite | `l10n.yaml` | Merge required attributes / escaping / coverage exclusion |
| `pubspec.lock` | regenerate | `pubspec.lock` | Regenerated and committed after workspace resolution (step 4) |
| `pubspec.yaml` | rewrite | `pubspec.yaml` | The root pubspec declares the Dart workspace members (step 4) |
| `skills-lock.json` | out-of-scope | — | Old-repo agent skill lock file |

---

## 11. `docs/` (31)

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `docs/README.md` | rewrite | `docs/{zh,en}/` | Rewritten for the new architecture: overview / layering / engineering_standards / developer_guide / glossary etc. |
| `docs/architecture/design_document.md` | rewrite | `docs/{zh,en}/` | Rewritten for the new architecture: overview / layering / engineering_standards / developer_guide / glossary etc. |
| `docs/architecture/desktop_agent_notification_design.md` | rewrite | `docs/{zh,en}/` | Rewritten for the new architecture: overview / layering / engineering_standards / developer_guide / glossary etc. |
| `docs/architecture/engineering_standards.md` | rewrite | `docs/{zh,en}/` | Rewritten for the new architecture: overview / layering / engineering_standards / developer_guide / glossary etc. |
| `docs/architecture/overview.en.md` | rewrite | `docs/{zh,en}/` | Rewritten for the new architecture: overview / layering / engineering_standards / developer_guide / glossary etc. |
| `docs/architecture/overview.md` | rewrite | `docs/{zh,en}/` | Rewritten for the new architecture: overview / layering / engineering_standards / developer_guide / glossary etc. |
| `docs/guides/developer_guide.md` | rewrite | `docs/{zh,en}/` | Rewritten for the new architecture: overview / layering / engineering_standards / developer_guide / glossary etc. |
| `docs/guides/glossary.en.md` | rewrite | `docs/{zh,en}/` | Rewritten for the new architecture: overview / layering / engineering_standards / developer_guide / glossary etc. |
| `docs/guides/glossary.md` | rewrite | `docs/{zh,en}/` | Rewritten for the new architecture: overview / layering / engineering_standards / developer_guide / glossary etc. |
| `docs/history/cursor_acp_release_validation.md` | out-of-scope | — | Old-repo historical archive; not migrated |
| `docs/history/cursor_agent_guide.md` | out-of-scope | — | Old-repo historical archive; not migrated |
| `docs/history/development_log.md` | out-of-scope | — | Old-repo historical archive; not migrated |
| `docs/history/project_memory.md` | out-of-scope | — | Old-repo historical archive; not migrated |
| `docs/images/README.md` | rewrite | `docs/{zh,en}/images/` | Screenshots are retaken once the UI is final |
| `docs/plan_mode_smoke_test.md` | rewrite | `docs/{zh,en}/protocols/` | Folded into the smoke records of the Codex protocol doc |
| `docs/product/product_requirements.md` | rewrite | `docs/{zh,en}/` | Rewritten for the new architecture: overview / layering / engineering_standards / developer_guide / glossary etc. |
| `docs/product/troubleshooting.en.md` | rewrite | `docs/{zh,en}/` | Rewritten for the new architecture: overview / layering / engineering_standards / developer_guide / glossary etc. |
| `docs/product/troubleshooting.md` | rewrite | `docs/{zh,en}/` | Rewritten for the new architecture: overview / layering / engineering_standards / developer_guide / glossary etc. |
| `docs/prompts/README.md` | out-of-scope | — | Old-repo agent prompt templates |
| `docs/prompts/daily.md` | out-of-scope | — | Old-repo agent prompt templates |
| `docs/prompts/performance.md` | out-of-scope | — | Old-repo agent prompt templates |
| `docs/prompts/refactoring.md` | out-of-scope | — | Old-repo agent prompt templates |
| `docs/prompts/snippets.md` | out-of-scope | — | Old-repo agent prompt templates |
| `docs/prompts/workflow.md` | out-of-scope | — | Old-repo agent prompt templates |
| `docs/protocols/claude_code_provider_adapter.md` | move | `docs/zh/history/claude_code_provider_adapter.md` | **Done**: archived, Chinese only; en/history/ carries a pointer |
| `docs/protocols/claude_code_stream_json_protocol.md` | move | `docs/{zh,en}/protocols/claude_code_stream_json_protocol.md` | **Done**: Chinese migrated + English version |
| `docs/protocols/claude_code_token_metering.md` | move | `docs/{zh,en}/protocols/claude_code_token_metering.md` | **Done**: Chinese migrated + English version |
| `docs/protocols/codex_app_server_protocol.md` | move | `docs/{zh,en}/protocols/codex_app_server_protocol.md` | **Done**: Chinese migrated + English version |
| `docs/reference/flutter_ai_create_with_ai_zh.md` | out-of-scope | — | External reference material |
| `docs/reference/flutter_ai_developer_experience_zh.md` | out-of-scope | — | External reference material |
| `docs/release/release_guide.md` | rewrite | `docs/{zh,en}/` | Rewritten for the new architecture: overview / layering / engineering_standards / developer_guide / glossary etc. |

---

## 12. Explicitly excluded (407)

| Rule | Files | Basis |
| --- | ---: | --- |
| `.claude/**` | 178 | The new repo already ships .claude/ and the VGV skills |
| `.agents/**` | 178 | The new repo already ships .agents/skills (16 VGV skills) |
| `.workflow/**` | 51 | Old-repo process records; not a migration input |
| `tool/packaging/**` | 5 | Packaging is out of scope (topology §1) |
| `docs/history/**` | 4 | Old-repo historical archive; not migrated |
| `docs/prompts/**` | 6 | Old-repo agent prompt templates |
| `docs/reference/**` | 2 | External reference material |
| `skills-lock.json` | 1 | Old-repo agent skill lock file |

In addition, the **untracked** `.workflow/feature/2026-08-18-PC端构建与版本检查/` is explicitly not a
migration input per the [topology appendix](./migration_topology.md).

---

## 13. Deletion list (41)

Every entry states a reason and a verification method — a hard requirement of
[step 1](./migration_tasks.md).

| Source | Action | Target | Note |
| --- | --- | --- | --- |
| `lib/main.dart` | delete | — | The single entrypoint is replaced by the main_development/staging/production flavors (step 3) |
| `lib/src/app/bootstrap/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/app/composition/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/app/localization/zeta_text_catalogs.dart` | delete | — | The dual TextCatalog track is deleted (step 28); lower layers return typed codes mapped in lib/l10n/failure_messages.dart |
| `lib/src/app/shell/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/app/zeta_storage_migrator.dart` | delete | — | No backward compatibility; only clean install into an empty directory with the current schema is verified (topology §1) |
| `lib/src/core/error/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/core/result/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/core/utils/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/agent/application/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/agent/application/agent_ui_update_port.dart` | delete | — | The UI update port is replaced by Bloc State + BlocSelector |
| `lib/src/features/agent/data/agent_provider_permission_migration.dart` | delete | — | Legacy permission value upgrade logic; no historical data compatibility (topology §1) |
| `lib/src/features/agent/data/datasources/app_server/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/agent/data/datasources/local_history/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/agent/data/datasources/transport/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/agent/data/mappers/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/agent/data/repositories/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/agent/domain/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/agent/domain/agent_ui_text_catalog.dart` | delete | — | TextCatalog deleted (steps 7 / 28) |
| `lib/src/features/agent/domain/fallback_agent_ui_text_catalog.dart` | delete | — | Fallback catalog deleted (steps 7 / 28) |
| `lib/src/features/agent_management/domain/agent_management_text_catalog.dart` | delete | — | TextCatalog deleted (step 28) |
| `lib/src/features/agent_management/domain/fallback_agent_management_text_catalog.dart` | delete | — | Fallback TextCatalog deleted (step 28) |
| `lib/src/features/desktop_notifications/domain/desktop_attention_text_catalog.dart` | delete | — | TextCatalog deleted (step 28) |
| `lib/src/features/desktop_notifications/domain/fallback_desktop_attention_text_catalog.dart` | delete | — | Fallback TextCatalog deleted (step 28) |
| `lib/src/features/ide_session/application/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/ide_session/data/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/ide_session/domain/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/project_threads/application/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/project_threads/data/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/project_threads/domain/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/project_threads/presentation/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/usage_statistics/domain/fallback_usage_statistics_text_catalog.dart` | delete | — | Fallback TextCatalog deleted (step 28) |
| `lib/src/features/usage_statistics/domain/usage_statistics_text_catalog.dart` | delete | — | TextCatalog deleted (step 28) |
| `lib/src/features/workspace/application/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/workspace/data/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/workspace/domain/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `lib/src/features/workspace/presentation/.gitkeep` | delete | — | Empty-directory placeholder; the new repo recreates directories from the VGV template |
| `tool/test_fast.ps1` | delete | — | The test_fast/test_full scripts are replaced by the four VGV gates (very_good test) |
| `tool/test_fast.sh` | delete | — | The test_fast/test_full scripts are replaced by the four VGV gates (very_good test) |
| `tool/test_full.ps1` | delete | — | The test_fast/test_full scripts are replaced by the four VGV gates (very_good test) |
| `tool/test_full.sh` | delete | — | The test_fast/test_full scripts are replaced by the four VGV gates (very_good test) |

**Verification**: once migration completes, assert path non-existence in the new repo for every row
above, and confirm the corresponding capability either has no UI entry point or is covered by a
replacement. The TextCatalog deletions are additionally asserted by two
[step 28](./migration_tasks.md) metrics: "packages imports of `AppLocalizations` = 0" and
"TextCatalog/Fallback remnants = 0".

---

## 14. Closure check

[Step 36](./migration_tasks.md) requires "every file in the manifest closed out". Closure means:

| Action | Closure condition |
| --- | --- |
| `move` | the target path exists and the diff contains only link/path adjustments |
| `rewrite` | the target path exists and tests there cover the source file's equivalent behaviour |
| `regenerate` | the generating command runs repeatably in CI with stable output |
| `delete` | the path does not exist in the new repo and the reason is recorded here |
| `out-of-scope` | the path does not exist in the new repo |

The generator should run in CI and assert, during P8, that this manifest's row count equals the final
baseline's git-tracked file count with zero `UNCLASSIFIED` entries.

