# Ownership map

[中文](../../zh/architecture/ownership_map.md) ｜ English

This map implements [migration tasks, step 2](./migration_tasks.md): every Controller / Store /
Service / Notifier in the old repository is ruled, one by one, into Data, Repository, Bloc/Cubit or
Presentation.

[Migration topology §5](./migration_topology.md) gives the principles; this map gives the answers.
Use the principles for cases this map does not cover — **where they conflict, this map wins**, because
every ruling here is based on actually reading the source file rather than inferring from directory names.

---

## 1. Decision procedure

For each legacy class, answer in order. The first `yes` decides:

| # | Question | Owner | Basis |
| --- | --- | --- | --- |
| 1 | Does it directly perform process, stdio, file, platform-channel or protocol IO? | **Data** | [topology §3.1](./migration_topology.md) |
| 2 | Must the state it holds still exist and stay correct when no UI is open? | **Repository** | external data and external resource lifecycle |
| 3 | Does its state only describe "what the user currently sees / selected / expanded"? | **Bloc/Cubit** | interaction state |
| 4 | Does it only reshape existing state into pixels, cache render output or schedule frames? | **Presentation** | [topology §5](./migration_topology.md) |

**Question 2 is the decisive test.** For example:

- The provider process is still running and events keep arriving, so reduction must continue even with
  every UI closed → `AgentConversationReducer` is **Repository**.
- Which tool card the user expanded is meaningless once the UI closes → `expandedEntryIds` is **Bloc**.
- The model catalog TTL cache is unrelated to any UI; it caches external data → **Repository**.
- The currently selected item in the model dropdown → **Bloc** (the persisted default still goes through
  the Repository).

### 1.1 `ChangeNotifier` cannot be swapped mechanically

[Topology §5](./migration_topology.md) already warns about this. Concretely:

| What the old `ChangeNotifier` represented | New form |
| --- | --- |
| External data change (process state, file content, directory refresh) | Repository exposes `Stream<T>` + a synchronous `T get snapshot` |
| Interaction state (selection, expansion, loading, error hint) | A field on the Bloc/Cubit `State` |
| Both mixed | **Must be split**, see §5 |

Repositories **must not** depend on Flutter, so any `ChangeNotifier` / `ValueNotifier` / `Listenable`
appearing under `packages/*_repository/` fails the gate ([step 26](./migration_tasks.md)).

---

## 2. Full `ChangeNotifier` / `Listenable` inventory (24)

The old repo's `lib/src` declares 24. **Every one must have a destination here** — one of P4's objective
exit criteria.

| Declaration | Represents | Ruling |
| --- | --- | --- |
| `app/shell/ide_shell_controller.dart:85` | mixed: layout + selection + session restore | **Bloc** `IdeShellBloc` |
| `agent/application/agent_conversation_binding.dart:196` | external: conversation runtime context | **Repository** → Stream |
| `agent/application/agent_conversation_binding_manager.dart:33` | external: binding leases and idle reclamation | **Repository** → Stream |
| `agent/application/agent_conversation_model_selection_controller.dart:53` | mixed: catalog (external) + selection/conflict/save error (interaction) | **split**, see §5.3 |
| `agent/application/agent_conversation_mode_controller.dart:85` | mixed: mode catalog (external) + draft/selection (interaction) | **split**, see §5.3 |
| `agent/application/agent_conversation_permission_selection_controller.dart:43` | mixed: catalog/apply (external) + selection/retry (interaction) | **split**, see §5.3 |
| `agent/application/agent_conversation_timeline_store.dart:1807` (`AgentConversationTurnState`) | mixed: turn grouping (external) + expansion (interaction) | **split**, see §5.1 |
| `agent/application/agent_elapsed_ticker.dart:8` | interaction: 1-second elapsed refresh | **Bloc** timer |
| `agent/application/agent_provider_runtime_registry.dart:18` | external: runtime lease registry | **Repository** → Stream |
| `agent/application/agent_provider_settings_controller.dart:18` | external: provider config persistence | **Repository** → Stream |
| `agent/application/agent_provider_settings_port.dart:10` | port, `implements Listenable` | **Repository public API**, drop Listenable |
| `agent/application/agent_skills_catalog_controller.dart:58` | mixed: skill catalog (external) + load status (interaction) | **split**, see §5.4 |
| `agent/application/agent_thread_workspace_controller.dart:81,197` | interaction: resident threads/drafts and selection | **Bloc** `IdeShellBloc` / agent chat scope |
| `agent/presentation/widgets/agent_mention_file_picker.dart:7` | interaction: private popover list cursor | **Presentation** local state |
| `agent/presentation/widgets/agent_skill_picker.dart:7` | same | **Presentation** local state |
| `agent/presentation/widgets/agent_slash_command_picker.dart:51` | same | **Presentation** local state |
| `agent_management/application/agent_management_controller.dart:21` | mixed | **Bloc** `AgentManagementBloc` + Repository |
| `project_threads/presentation/project_threads_view_model.dart:11` | interaction | **Bloc** `ProjectThreadsBloc` |
| `settings/application/appearance_settings_controller.dart:62` | mixed: font catalog (external) + selection (interaction) | **split**, see §6 |
| `settings/application/general_settings_controller.dart:14` | external: settings persistence | **Repository** + `SettingsCubit` |
| `usage_statistics/application/agent_usage_panel_controller.dart:36` | interaction: tabs + on-demand load state | **Cubit** `AgentUsagePanelCubit` |
| `usage_statistics/application/usage_statistics_controller.dart:14` | interaction: filters + async orchestration | **Bloc** `UsageStatisticsBloc` |
| `workspace/application/workspace_file_index_controller.dart:36` | mixed: index result (external) + index progress (interaction) | **split**, see §6 |

`ValueNotifier` appears in 8 files, all under `presentation/`. They are widget-local state, migrate with
the presentation layer, and do not enter Bloc State.

> **The three pickers keep their private `ChangeNotifier`.** They are widget-private list cursors, not
> shared across widgets and not business state. VGV does not require lifting all widget-local state into
> a Bloc; lifting these would push high-frequency keyboard navigation through the Bloc event loop.

---

## 3. `features/agent/application/` (35) — file-by-file rulings

The highest-risk directory in the migration: 35 `.dart` files, 11,824 lines (plus one `.gitkeep`),
mixing genuine domain orchestration with UI state disguised as "application".

### 3.1 → `agent_conversation_repository` (20)

Question 2 is "yes" for all of these: while the provider process runs, this logic must keep working
correctly even with no UI at all.

| File | Lines | Responsibility | Migration note |
| --- | ---: | --- | --- |
| `agent_conversation_binding.dart` | 647 | stable conversation identity; atomic draft → threadId promotion | drop `ChangeNotifier`, use Stream + synchronous snapshot |
| `agent_conversation_binding_manager.dart` | 276 | unique binding map and idle reclamation | lease release must be provable in the Repository's `close()` |
| `agent_conversation_effect.dart` | 129 | reduction scope enum, effect ordering | `live/history/replay` must each hold their own reducer instance |
| `agent_conversation_effect_runner.dart` | 212 | effect execution with generation/epoch checks | keep protocol effects only; **UI effects move out**, see §5.2 |
| `agent_conversation_event_processor.dart` | 260 | event orchestration | **split**: the UI-request branch moves out, see §5.2 |
| `agent_conversation_mutation.dart` | 395 | typed state change sealed family | migrate as-is |
| `agent_conversation_reducer.dart` | 1,160 | deterministic reduction + local entryId generation | ADR-004 explicitly keeps this in the Repository |
| `agent_conversation_thread_snapshot.dart` | 57 | lightweight thread snapshot | the stable contract for shell and thread list |
| `agent_event_coalescing_policy.dart` | 143 | coalescing key / merge / barrier | performance-critical path for high-frequency events |
| `agent_event_pipeline.dart` | 349 | event pipeline and redacted diagnostics | diagnostics hold counters only, never payload |
| `agent_permission_request_resolver.dart` | 35 | builds a request-scoped snapshot by priority | pure function |
| `agent_provider_event_listener_gate.dart` | 103 | listener generation isolation | prevents ghost events from stale runtimes |
| `agent_provider_runtime_identity.dart` | 30 | stable runtime identity | value type; see §3.5 on placing it in contracts |
| `agent_provider_runtime_registry.dart` | 305 | runtime lease registry | drop `ChangeNotifier` |
| `agent_turn_context_overlay.dart` | 240 | overlays local turn context onto history snapshots | pure function |
| `agent_turn_context_recorder.dart` | 143 | side-channel turn context writes | failures only log diagnostics, never rethrow |
| `bounded_event_dispatcher.dart` | 183 | FIFO bounded dispatch + backpressure | the event-storm acceptance depends on it |
| `coalescing_event_buffer.dart` | 163 | generic coalescing buffer | the generic container, separate from the policy |
| `agent_conversation_permission_state.dart` | 360 | conversation permission facts | **partial**, see §5.3 |
| `agent_conversation_timeline_store.dart` | 2,017 | timeline aggregation | **partial**, see §5.1 |

### 3.2 → `agent_provider_repository` (7)

| File | Lines | Responsibility | Migration note |
| --- | ---: | --- | --- |
| `agent_model_catalog_repository.dart` | 479 | single source of truth for the model catalog TTL cache | fresh 1 hour / stale up to 7 days; see [Claude protocol §7](../protocols/claude_code_stream_json_protocol.md) |
| `agent_permission_catalog_controller.dart` | 101 | permission catalog loading and stale retention | the catalog is external data; **the selection is not here** |
| `agent_provider_config_store.dart` | 8 | config persistence port | IO implementation moves down to `agent_config_client` |
| `agent_provider_global_runtime.dart` | 74 | unified entry point for pre-session operations | global scope never idles out |
| `agent_provider_settings_controller.dart` | 399 | provider config / enablement / defaults persistence | drop `ChangeNotifier` |
| `agent_provider_settings_port.dart` | 51 | settings port | **drop `implements Listenable`**, use Stream |
| `agent_skills_catalog_controller.dart` | 276 | skill catalog stale-while-revalidate | **partial**, see §5.4 |

> **`agent_provider_repository` and `agent_conversation_repository` have zero dependency on each other.**
> `AgentConversationBloc` first fetches an `AgentProviderBundle` from the former, then passes it to the
> latter's `openConversation` ([topology §4.4](./migration_topology.md)). That boundary already holds
> in the §3.1/§3.2 split: there are no direct references between the two groups to break.

### 3.3 → Bloc / Cubit (5)

| File | Lines | Target | Reason |
| --- | ---: | --- | --- |
| `agent_elapsed_ticker.dart` | 42 | `AgentConversationBloc` timer | pure UI refresh; `close()` must cancel it |
| `agent_plan_execution_handoff_controller.dart` | 395 | `AgentConversationBloc` | the handoff is a local business rule; the source already states it "does not depend on widgets, stores or protocols" |
| `agent_conversation_mode_controller.dart` | 629 | **split**, see §5.3 | draft/selection/async races are interaction |
| `agent_conversation_model_selection_controller.dart` | 782 | **split**, see §5.3 | conflict confirmation and save failures are interaction |
| `agent_conversation_permission_selection_controller.dart` | 672 | **split**, see §5.3 | catalog/apply are external data; selection and retry are interaction |

### 3.4 → Other packages / deleted (3)

| File | Lines | Ruling | Reason |
| --- | ---: | --- | --- |
| `agent_thread_workspace_controller.dart` | 516 | **Bloc** (`IdeShellBloc` + agent chat scope) | resident threads/drafts are IDE canvas interaction state; the key types become value objects in contracts |
| `agent_ui_update_port.dart` | 23 | **delete** | Bloc State + `BlocSelector` replace the "UI update port" |
| `agent_ui_update_request.dart` | 170 | **Presentation** (`lib/agent_chat/view/`) | `AgentUiRegion` / urgency still serve the frame scheduler ([topology §5](./migration_topology.md): frame coalescing stays in presentation) |

### 3.5 Where `agent_provider_runtime_identity.dart` belongs

A 30-line pure value type needed by both `agent_conversation_repository` and
`agent_provider_repository`. **Repositories have zero dependencies on each other**, so it cannot live in
either.

- **Ruling**: put it in `agent_provider_contracts`. It is an immutable value object with zero IO and zero
  vendor fields, satisfying ADR-001's admission criteria.
- **Same treatment**: `AgentThreadWorkspaceKey`, `AgentConversationBindingKey` and other cross-package
  sealed key types.
- **Counter-example**: do not push a class with behaviour into contracts just because two packages need
  it. Only **immutable value objects and pure functions** qualify.

---

## 4. The other features' `application/` (22)

22 `.dart` files, 5,263 lines (plus three `.gitkeep`).

| File | Lines | Ruling | Reason |
| --- | ---: | --- | --- |
| `agent_management/agent_management_controller.dart` | 785 | **split**: detect/test/config/log calls → `agent_management_repository`; selected agent, progress, validation and log view state → `AgentManagementBloc` | step 24 explicitly forbids storing "selected agent, progress, loading" |
| `desktop_notifications/desktop_attention_controller.dart` | 302 | **Bloc** `DesktopNotificationsBloc` | merging attention/visibility/unread is cross-repository orchestration → step 29 |
| `ide_session/ide_session_persistence_coordinator.dart` | 128 | **Cubit** `IdeSessionCubit` | restore/persist sequencing and cancellation tokens are interaction orchestration |
| `ide_session/ide_session_restore_result.dart` | 29 | a field on the **Cubit** State | the restore result becomes step 30's initial route input |
| `ide_session/ide_session_state_builder.dart` | 136 | **split**: snapshot building → Cubit; pruning of missing projects/files → `project_session_repository` | existence checks need filesystem facts |
| `project_threads/project_threads_controller.dart` | 1,122 | **split**: aggregate paging/cursors → `project_session_repository`; search debounce, filters, selection → `ProjectThreadsBloc` | search `restartable()`, load more `droppable()` → step 30 |
| `project_threads/project_threads_session_snapshot_codec.dart` | 124 | **Cubit** + `project_session_client` | the codec moves down to Data; the restore plan stays in the Bloc |
| `settings/app_language_resolver.dart` | 38 | **`settings_repository`** | pure function; already declared not to take a Flutter `Locale` |
| `settings/appearance_settings_controller.dart` | 360 | **split**, see §6 | the font catalog is external data, the selection is interaction |
| `settings/general_settings_controller.dart` | 147 | **split**: persistence → `settings_repository`; publish/failure hint → `SettingsCubit` | persistence writes use `sequential()` |
| `settings/general_settings_update_result.dart` | 2 | **`settings_repository`** | typed result; "on failure, the in-memory selection must not be treated as applied" is a domain rule |
| `workspace/workspace_file_index_controller.dart` | 272 | **split**, see §6 | isolate traversal and filesystem event streams → Data/Repository |
| `workspace/workspace_file_indexer.dart` | 121 | **`workspace_client`** | recursive scanning is `dart:io` and must move down (step 19) |
| `workspace/workspace_tree_builder.dart` | 112 | **split**: reading the next directory level → `workspace_client`; `expandedPaths` checks → `WorkspaceCubit` | the source couples expansion state with IO — a textbook split point |
| `usage_statistics/agent_usage_panel_controller.dart` | 467 | **Cubit** `AgentUsagePanelCubit` | tabs, on-demand loading and partial errors are all interaction |
| `usage_statistics/agent_usage_query_service.dart` | 247 | **`usage_statistics_repository`** | progressive query output and out-of-order convergence are domain |
| `usage_statistics/agent_usage_refresh_coordinator.dart` | 76 | **delete** | the hand-rolled event-queue scheduler is replaced by `bloc_concurrency`'s `droppable()`/`restartable()` |
| `usage_statistics/agent_usage_token_aggregation.dart` | 27 | **`usage_statistics_repository`** | pure aggregation function |
| `usage_statistics/query_agent_usage_panel_repository.dart` | 88 | **`usage_statistics_repository`** | projects onto the panel contract |
| `usage_statistics/query_usage_statistics_repository.dart` | 81 | **`usage_statistics_repository`** | same |
| `usage_statistics/usage_statistics_controller.dart` | 219 | **Bloc** `UsageStatisticsBloc` | filter state + async orchestration |
| `usage_statistics/usage_statistics_report_builder.dart` | 380 | **`usage_statistics_repository`** | aggregates into a report domain model |

> **Deleting `agent_usage_refresh_coordinator.dart` is deliberate.** It exists to "avoid idle tasks never
> running while an animation is active". Bloc event transformers do not depend on the Flutter scheduler,
> so the problem does not exist. Keeping it would rebuild a second concurrency mechanism outside Bloc,
> violating [tasks §1.3](./migration_tasks.md) ("every async event explicitly selects a transformer").

---

## 5. Files that must be split (detailed cuts)

Of the 16 split files counted in §8, the 8 conversation-related ones are cut field by field in this
section; the 3 workspace/settings ones are in §6; and the cuts for `ide_session_state_builder`,
`project_threads_controller`, `project_threads_session_snapshot_codec`,
`general_settings_controller` and `agent_management_controller` are already written out per row in §4.

These files hold external data and interaction state at once, so **none of them can move wholesale to
any single layer**.

### 5.1 `agent_conversation_timeline_store.dart` (2,017 lines)

The source states three responsibilities, which straddle two layers exactly:

| Source responsibility | Owner | Target |
| --- | --- | --- |
| unified timeline of messages, tool calls, approval/question cards and history events | Repository | the timeline aggregate in `agent_conversation_repository` |
| live / history / standby turn grouping | Repository | same; grouping is a deterministic result of provider events |
| token totals | Repository | same |
| **UI expansion state** | **Bloc** | `AgentConversationState.expansion` slice |
| `AgentConversationTurnState extends ChangeNotifier` (:1807) | **split** | data fields → an immutable Repository turn snapshot; expansion/selection → Bloc State |

Field-level cuts are in [conversation state design §4](./agent_conversation_state_design.md).

### 5.2 `agent_conversation_event_processor.dart` + `agent_conversation_effect_runner.dart`

The processor's own docs say it applies five kinds of result in a fixed order: **typed state, timeline,
thread snapshot, UI request, application effect**. The first three are Repository, the fourth is Bloc,
and the fifth depends on the effect kind.

| Application order | Owner |
| --- | --- |
| typed state mutation | Repository |
| timeline update | Repository |
| thread snapshot update | Repository |
| **UI request publication** | **delete** — the Repository emits a new domain snapshot; the Bloc subscribes and decides its own State change |
| application effect | **split by kind**, see below |

| Effect kind | Owner | Reason |
| --- | --- | --- |
| write-back to the provider (permission, question, plan, steer, cancel) | Repository | protocol effect |
| persisting turn context | Repository | external storage |
| releasing a lease / closing a runtime | Repository | external resource lifecycle |
| scroll to bottom, focus the composer, expand a card | **Bloc → `BlocListener`** | Flutter side effect |
| show a dialog / snackbar / navigate | **Presentation `BlocListener`** | [tasks §1.4](./migration_tasks.md) |

**Delete `AgentConversationStateMutationTarget`** (the processor's facade interface): it exists so the
application layer can call back into presentation. That direction does not exist under Bloc.

### 5.3 The three selection controllers

`mode` (629), `model_selection` (782), `permission_selection` (672) plus `permission_state` (360) share
a structure: "load a catalog + hold the current selection + persist + guard async races". One cut for all:

| Concern | Owner | Note |
| --- | --- | --- |
| catalog fetch and caching (modes / models / permission options / skills) | `agent_provider_repository` | external data |
| applying a selection to the provider | `agent_provider_repository` | protocol call |
| persisting the default preference | `agent_provider_repository` | external storage |
| **the current selected value** | **Bloc State** | interaction |
| **thread draft (a selection not yet sent)** | **Bloc State** | interaction |
| **load/failure state, save errors, pending conflict confirmation** | **Bloc State** | interaction, expressed as typed failures |
| **async race guards** | **the Bloc's transformer** | `restartable()` replaces hand-written generation counters |
| the immutable snapshot frozen at send time | a Repository method parameter | built by the Bloc and passed in |

`AgentModelCompatibilityConflict` (waiting for the user to confirm after a Fast / reasoning-effort
conflict) is **pure interaction state**; it must live in `AgentConversationState.composer`, never in a
Repository.

Cutting `AgentConversationPermissionState` (360 lines):

| Member | Owner |
| --- | --- |
| `AgentPermissionStateSource` enum, `AgentConversationPermissionValue` | contracts (value objects) |
| applied permission facts, provider apply results | `agent_provider_repository` |
| `AgentPermissionPersistenceFailure` (retryable hint) | **Bloc State** |

### 5.4 `agent_skills_catalog_controller.dart` (276 lines)

| Member | Owner |
| --- | --- |
| stale-while-revalidate catalog reads, invalidation subscription | `agent_provider_repository` |
| `AgentSkillsLoadStatus` enum | **Bloc State** (loading/failure are interaction) |
| `AgentSkillsCatalogState` immutable catalog content | a Repository domain model that Bloc State references |

---

## 6. Other files needing a split

### 6.1 `settings/appearance_settings_controller.dart` (360 lines)

| Member | Owner |
| --- | --- |
| system font catalog reads | `settings_repository` (via the `SystemFontCatalogApi` port) |
| appearance settings persistence | `settings_repository` |
| `AppearanceFontOption` (popover display option) | **`SettingsCubit` State** — it is a display model built for the UI |
| currently selected font/theme | **`SettingsCubit` State** (the persisted default still lives in the Repository) |

### 6.2 `workspace/workspace_file_index_controller.dart` (272 lines)

| Member | Owner |
| --- | --- |
| background isolate traversal, filesystem event stream creation | `workspace_client` (`dart:io`, step 19) |
| index results and queries | `workspace_repository` |
| index progress, cancellation, failure hints | **`WorkspaceCubit` State** |
| the ability to inject fakes to bypass real IO | keep it — Data package tests must not start real IO ([topology §3.1](./migration_topology.md)) |

### 6.3 `workspace/workspace_tree_builder.dart` (112 lines)

The source couples "is this directory expanded" with "should we read the next level" — the most typical
layering violation in the codebase:

```text
old: if (expanded || expandedPaths.contains(path)) { readChildren(); }
new: WorkspaceCubit holds expandedPaths
     -> dispatches WorkspaceNodeExpanded(path)
     -> Cubit calls workspace_repository.loadChildren(path)
     -> Repository calls workspace_client to read the directory
```

The Repository **does not store** `expandedPaths` ([step 25](./migration_tasks.md)).

### 6.4 `app/shell/ide_shell_controller.dart` (1,467 lines)

| Member | Owner |
| --- | --- |
| current page, projectId, threadId | **GoRouter** ([topology §6](./migration_topology.md): the router is the single source of truth) |
| layout sizes, panel visibility, selection | **`IdeShellBloc` State** |
| session restore trigger | **`IdeSessionCubit`** → produces an initial location consumed by a router redirect |
| project/thread data reads | `workspace_repository` / `project_session_repository` |
| native menu command dispatch | `desktop_platform_repository` + typed routes |

**`IdeShellBloc` must not hold a router location**, or it forms a second source of truth alongside
GoRouter ([ADR-003](./architecture_decisions.md)).

---

## 7. What stays in `presentation/`

[Topology §5](./migration_topology.md) keeps Markdown/render caches, frame coalescing and scroll
controllers in presentation. For the 16 non-widget files under `features/agent/presentation/`:

| File | Owner | Reason |
| --- | --- | --- |
| `agent_conversation_view_model.dart` (4,190) | **Bloc** | see the [conversation state design](./agent_conversation_state_design.md) |
| `agent_conversation_ui_state.dart` (1,098) | **Bloc State** | same |
| `agent_markdown_cache.dart` | **Presentation** | render output cache; never in State |
| `agent_timeline_projection.dart` / `_cache.dart` | **Presentation** | domain snapshot → UI slice projection |
| `agent_file_change_projection.dart` / `_cache.dart` | **Presentation** | same |
| `agent_timeline_grouping.dart` | **Presentation** | visual grouping |
| `agent_timeline_extent_descriptor.dart` | **Presentation** | virtual scroll extents |
| `agent_ui_update_scheduler.dart` | **Presentation** | frame coalescing |
| `composer_document.dart` | **Presentation** | rich-text editor document model |
| `model_config_ui_state.dart` | **Bloc State** | it is selection state, not a render intermediate |
| `agent_plan_revision_drafts.dart` | **Bloc State** | uncommitted drafts are interaction state |
| `agent_conversation_navigation.dart` | **`lib/app/router/`** | typed routes |
| `agent_presentation_l10n.dart` | **`lib/l10n/`** | typed code → ARB mapping |

> **Why caches stay out of State**: `AgentConversationState` must be `Equatable` and cheap to compare.
> Putting Markdown render output or projection caches into State makes every `state == state` walk a
> large object graph, which destroys performance under high-frequency deltas. Caches are held by widgets,
> keyed by entryId, and released when the widget is disposed.

---

## 8. Ruling summary

| Target layer | agent | other features | Total | Share |
| --- | ---: | ---: | ---: | ---: |
| Repository (all packages) | 22 | 7 | 29 | 51% |
| Bloc / Cubit | 3 | 5 | 8 | 14% |
| Data package | 0 | 1 | 1 | 2% |
| Presentation | 1 | 0 | 1 | 2% |
| **Split (spans two layers)** | 8 | 8 | **16** | **28%** |
| Deleted | 1 | 1 | 2 | 3% |
| **Total** | **35** | **22** | **57** | **100%** |

Counting basis: the 57 `.dart` files under `features/*/application/` (35 agent + 22 other), excluding the
four `.gitkeep` files. Split files are counted once, under "split" only.

**28% of files need splitting** — the single most important number in this migration. Nearly a third of
the application layer cannot be moved wholesale, so a directory-by-directory bulk migration will
inevitably drag UI state into the Repository. §5 and §6 give field-level cuts for those 16 files; the
remaining 41 can move as a unit.

---

## 9. Gates

These rulings must be machine-checkable, encoded in `.architecture.yaml`:

1. Occurrences of `ChangeNotifier`, `ValueNotifier` or `Listenable` under `packages/*_repository/**` = 0.
2. Declarations under `packages/*_repository/**` whose field name matches
   `expanded|selected|isLoading|loadStatus|errorMessage` = 0.
3. Imports between `packages/*_repository/` = 0.
4. Imports of `BuildContext`, `GoRouter` or `package:flutter/widgets.dart` under `lib/**/bloc/**` and
   `lib/**/cubit/**` = 0.
5. All 24 `ChangeNotifier` declarations from §2 are gone in the new repo, or appear only as private
   classes under `presentation/widgets/`.
6. The 3 file paths marked "delete" in §3.4 and §4 do not exist in the new repo.

Rule 2 is a heuristic and will produce false positives. Exceptions may be registered in
`.architecture.yaml`, **but each one must state why that field represents external data rather than UI
state** — which is precisely a written answer to question 2 of this map's decision procedure.
