# Migration Topology Analysis

[中文](../../zh/architecture/migration_topology.md) ｜ English

This document defines the migration boundary, target topology, and execution order from the current `dev` branch of `D:\Development\Workspace\zeta` to the new VGV repository. See the [migration task list](./migration_tasks.md) for the executable checklist.

## 0. Conclusion

Migration may start only after P-1 freezes the baseline and produces the architecture manifest. The target strictly follows the VGV four-layer flow:

```text
Presentation → Business Logic (Bloc/Cubit) → Repository → Data
```

ADR-001, the provider-neutral contracts package, is the only model-ownership exception:

- Data and Repository are independent Dart packages under `packages/` and have no Flutter SDK dependency.
- Repositories never depend on other repositories; Bloc/Cubit performs cross-domain orchestration.
- Business and interaction state lives only in Bloc/Cubit. Repository streams represent external data changes only.
- Widgets do not call repositories or platform plugins. They read Bloc state and dispatch events.
- Flutter plugin and MethodChannel implementations live only at the app composition boundary under `lib/app/platform/` and implement pure-Dart ports.
- GoRouter is the only navigation mechanism. Routes are typed and never use `extra`.

Zeta has not been released, so this migration does not support historical releases, the old bundle ID, legacy SharedPreferences, or old/new application coexistence. The goal is behavioral parity with the current `dev` branch and a clean installation.

---

## 1. Confirmed Preconditions

| Dimension | Decision |
| --- | --- |
| Migration source | Current `dev` of the old repository; analysis baseline `bfd42412c9c3a0b39bb93598f93f9e5eca471236`; pin the final migration SHA after Cursor removal |
| State management | Migrate all application state to Bloc/Cubit |
| Architecture | Strict VGV four-layer architecture; zero repository-to-repository dependencies |
| Provider contracts | Accept ADR-001: `agent_provider_contracts` owns provider-neutral contracts and immutable models shared by multiple providers |
| Platforms | macOS / Windows / Linux |
| UI foundation | Keep `shadcn_flutter`; shared design system is `packages/app_ui` |
| Navigation | Introduce typed GoRouter routes; app-internal navigation only, with no OS deep-link registration in this migration |
| Monorepo | Native Dart workspace; no Melos at the start of migration |
| App identity | Every flavor uses `cn.easii.zeta`, product name `Zeta`, and `~/.zeta`; flavors are not isolated |
| Version | Use the new repository version `1.0.0+1` |
| Data compatibility | No historical-version compatibility; validate clean installation and the current schema only |
| Accessibility target | WCAG 2.2 AA across macOS / Windows / Linux |
| Explicitly excluded | `app_update`, Velopack, and the old repository's `tool/packaging/` |
| Explicitly migrated (ruled 2026-08-19) | `third_party/codex_app_server_schema/` and the smoke/gate scripts under `tool/`; rationale in [manifest §5](./migration_manifest.md) |
| Old repository | Freeze after Cursor removal; no parallel feature work |

No flavor isolation means development, staging, and production cannot be installed side by side and share the same local data. Entrypoints may change runtime configuration and logging level only; they must not change schema, application ID, or directories.

Product, migration scope, and accessibility targets are all confirmed; no product-decision blocker remains.

---

## 2. Current `dev` Baseline

Measured on 2026-08-19. Generated localization Dart is listed separately and excluded from manual migration size.

| Scope | Files | Lines |
| --- | ---: | ---: |
| Manual Dart under `lib/src` | 348 | 101,599 |
| Generated l10n Dart | 3 | 10,318 |
| Dart tests | 265 | 86,910 |
| `package:zeta/src/...` imports | 1,165 | — |
| en / zh ARB | 1,040 keys per locale | — |

Old-repository features:

| Feature | Files | Lines | Target |
| --- | ---: | ---: | --- |
| `agent` | 184 | 62,822 | Provider Data, Conversation/Provider repositories, `agent_chat` Bloc/UI |
| `agent_management` | 14 | 6,449 | `agent_management_client`, repository, Bloc/UI |
| `desktop_notifications` | 6 | 494 | Platform ports, repository, Bloc |
| `ide_session` | 7 | 659 | Session client, repository, Cubit |
| `project_threads` | 5 | 1,689 | Shared repository with IDE session; state moves to Bloc |
| `settings` | 13 | 2,047 | Settings client, repository, Cubit/UI |
| `usage_statistics` | 35 | 8,785 | Provider data sources, storage client, repository, Bloc/UI |
| `workspace` | 8 | 1,067 | File-system client, repository, Cubit/UI |

Platform and asset files are migration inputs too: Linux has 15 files, macOS 33, Windows 69, and assets 13. Generated plugin registrants may be regenerated; handwritten runners, MethodChannels, icons, and fonts must appear in the source-to-target manifest.

These numbers are an analysis snapshot. P-1 must regenerate the final counts and SHA after step 0 changes the old repository.

---

## 3. Layer Classification Rules

### 3.1 Data

Data owns external communication and external formats: processes, stdio, provider protocols, files, platform channels, system fonts, notifications, file selection, and clipboard access.

- Return typed response models; never leak raw JSON into repositories.
- Do not contain filtering, selection, expansion, loading state, or user-operation rules.
- Data packages contain no Flutter. Flutter adapters live in `lib/app/platform/` and implement pure-Dart ports.
- App Blocs and Presentation do not consume Data ports directly; platform capabilities must also pass through a Repository.
- Vendor clients never depend on one another.
- All collaborators are constructor-injectable; tests do not start real processes or write the user's real data directory.

### 3.2 Repository

Repositories compose Data, transform models, cache results, and own external-resource lifecycles.

- A repository never imports another repository.
- Repositories contain no Flutter and do not author localizable Zeta UI copy.
- They may expose external-data streams and synchronous snapshots, but not UI selection or page-loading state.
- Provider event normalization, conversation aggregation, runtime leases, and protocol effects may remain in a repository as domain-data orchestration.
- Search terms, selected items, expansion state, loading/failure status, navigation targets, and interaction rules belong to Bloc.

### 3.3 Business Logic

Bloc/Cubit owns business rules, cross-repository orchestration, and all interaction state.

- Blocs never depend directly on other Blocs. UI `BlocListener`s or shared external-data streams coordinate them.
- Every asynchronous event declares a transformer. Default concurrency must not be an implicit choice.
- A Bloc never owns `BuildContext`, GoRouter, widgets, MethodChannels, or Data clients.
- Typed failures enter state; Presentation maps them to ARB messages.

### 3.4 Presentation

- Page creates and provides a Bloc; View/Widget consumes state.
- Callbacks use `context.read`; builds use `BlocBuilder` / `BlocSelector`.
- Navigation uses generated typed routes. Standard transitions use `go()`; `push()` is reserved for destinations returning a result.
- Route parameters carry stable IDs only; never pass path objects or use `extra`.
- Rendering, navigation, dialogs, snackbars, and other Flutter side effects run through `BlocListener`.

### 3.5 Composition Root

`bootstrap.dart` is the only file allowed to see Data clients, Repositories, and app platform adapters together. `main_<flavor>.dart` only selects flavor configuration and calls bootstrap; it does not import Data packages.

The allowlist is dependency-specific:

- `lib/bootstrap.dart` may import Data, Repository, and app platform adapters.
- `lib/app/platform/**` may import only `desktop_platform_api`, Flutter services, and the corresponding plugins—not vendor/settings/workspace Data clients.
- Every other `lib/**` path may import only Repository public barrels and no Data package.

---

## 4. Target Package Topology

### 4.1 Shared Contracts and Infrastructure

| Package | Source | Responsibility |
| --- | --- | --- |
| `agent_provider_contracts` | `features/agent/domain/` | ADR-001; 21 capability ports and neutral provider/session/event/permission/plan/usage models; no vendor fields |
| `json_rpc_transport` | `agent/data/datasources/transport/` | JSON-RPC stdio, operation scheduler, peer lifecycle |
| `zeta_logging` | `core/logging/` + `core/security/` | Structured logging and sensitive-data redaction |
| `zeta_storage` | `core/storage/` + path utilities | Atomic file operations, current-schema data paths, storage errors |
| `desktop_platform_api` | New pure-Dart ports | Neutral ports for fonts, notifications, attention, directory selection, clipboard, windows, and menu commands |

ADR-001 is the only model-ownership exception. It solves the need for three independent Data clients to implement the same neutral capability ports. The package may contain immutable contracts, typed codes, and pure functions only—never business state, vendor fields, IO, or Flutter.

### 4.2 Provider Data

| Package | Source | Responsibility |
| --- | --- | --- |
| `codex_app_server_client` | Codex datasource, mappers, codecs, CLI locator | Codex capability ports plus Codex history/usage reads |
| `claude_code_client` | Claude datasource, mappers, codecs, CLI locator | Claude capability ports, history, quota, and credential probes |
| `grok_acp_client` | ACP/Grok datasource, mappers, codecs, CLI locator | Grok capability ports plus Grok history/usage reads |
| `agent_history_client` | Provider-neutral history merge/replay input | Format reading and tolerance only; no UI timeline projection |
| `agent_config_client` | Provider config/cache/turn-context stores and codecs | Current-schema provider configuration, catalog cache, and turn-context persistence |
| `agent_management_client` | Three management data sources, CLI runner, auth probe | Detection, connection tests, configuration/log IO, neutral responses |

Each CLI locator has exactly one owner: its vendor client. `agent_config_client` and repositories do not duplicate locators.

### 4.3 Other Data

| Package | Source | Responsibility |
| --- | --- | --- |
| `settings_client` | Settings stores/codecs | Current-schema general and appearance settings IO |
| `workspace_client` | IO boundary from workspace indexing | File scans, gitignore inputs, directory reads |
| `project_session_client` | IDE session store + snapshot codec | Current session-schema IO |
| `usage_statistics_storage_client` | Usage partitions/cache/index | Statistics cache and derived index; provider raw data comes from vendor clients |

Concrete adapters for fonts, notifications, windows/menus, file selection, and clipboard live in `lib/app/platform/` and implement `desktop_platform_api`.

### 4.4 Repositories

| Package | Data dependencies | Responsibility |
| --- | --- | --- |
| `agent_provider_repository` | Contracts, agent config, three vendor clients | Provider configuration, bundle-factory registry, model/mode/skill/permission catalogs |
| `agent_conversation_repository` | Contracts, history, config, storage/logging | Conversation aggregation, event pipeline, runtime leases, timeline snapshots; no provider-repository dependency |
| `agent_management_repository` | Management client, config client, contracts | Domain conversion for detection, diagnostics, configuration, and logs |
| `settings_repository` | Settings client, desktop-platform port | Settings domain models, system-font conversion, persistence |
| `workspace_repository` | Workspace client | File-tree/query data; no selection or expansion state |
| `project_session_repository` | Project-session client, vendor thread ports | Session snapshots and thread-catalog data; no search/selection UI state |
| `usage_statistics_repository` | Three vendor clients, usage storage | Provider usage aggregation, caching, report domain models |
| `desktop_notifications_repository` | Desktop notification ports | Send already-localized notification copy, badges, and attention; no settings-repository dependency |
| `desktop_platform_repository` | Desktop directory/clipboard/window/menu ports | Domain wrapper for directory selection, clipboard, window, and menu commands; prevents Bloc from bypassing Repository |

Bloc composes cross-domain use cases:

- `AgentConversationBloc` gets a bundle from `agent_provider_repository` and passes it to `agent_conversation_repository`.
- `AgentConversationBloc` requests file selection and clipboard operations through `desktop_platform_repository`, never a platform port.
- `DesktopNotificationsBloc` consumes settings and notification repositories.
- `IdeShellBloc` consumes workspace, project-session, and desktop-platform repositories.

### 4.5 Shared UI

`packages/app_ui` keeps shadcn_flutter and contains tokens, base components, Workbench primitives, and virtualization. It may depend on Flutter, shadcn_flutter, and pure UI utilities, but never on repositories, Data clients, or `AppLocalizations`.

### 4.6 App Features

```text
lib/
├── app/
│   ├── app.dart
│   ├── router/                  # typed GoRouter + generated routes
│   ├── platform/                # Flutter/MethodChannel adapters
│   └── view/
├── l10n/
├── agent_chat/{bloc,view,widgets}/
├── agent_management/{bloc,view,widgets}/
├── desktop_notifications/bloc/
├── ide_session/cubit/
├── project_threads/{bloc,view}/
├── settings/{cubit,view}/
├── usage_statistics/{bloc,cubit,view,widgets}/
├── workspace/{cubit,view}/
└── ide_shell/{bloc,view,widgets}/
```

`app_update` is absent from the target topology.

---

## 5. Business-State Ownership

| Old-code category | Target |
| --- | --- |
| Provider JSON/stdio/process/CLI locator | Vendor Data client |
| File store/codec, directory scan, native channel | Data client / app platform adapter |
| Response-to-domain transformation, cache, conversation aggregate, runtime lease | Repository |
| Search, filters, selection, expansion, loading/failure, retry policy | Bloc/Cubit |
| Timeline UI slices, composer state, pending-interaction state | `AgentConversationState` |
| Markdown/render caches, frame coalescing, scroll controllers | Presentation helpers |
| Localized copy | App `lib/l10n/` |
| Navigation location | GoRouter; Bloc stores business IDs and loaded results only |

Do not mechanically replace every repository `ChangeNotifier` with a stream. Classify each one first: external-data change becomes a repository stream; UI/business state becomes Bloc state.

Conversation boundary: deterministic provider-event-to-domain-snapshot aggregation remains in the repository. UI slices, expansion/selection rules, navigation, and localization move to the app.

---

## 6. GoRouter Topology

Use `go_router` + `go_router_builder` for app-internal navigation only; do not configure OS deep links in this migration.

```text
/home
/projects/:projectId
/projects/:projectId/threads/:threadId
/settings
/settings/agents
/settings/agents/:agentId
/usage-statistics
```

- Use `@TypedShellRoute` for the IDE shell.
- `projectId` is a stable URL-safe ID derived from the canonical path and resolvable by a repository; URLs never expose file paths directly.
- Router is the only source of truth for the current page, projectId, and threadId.
- Session restore computes only an initial location or redirect. `IdeShellBloc` must not drive the same navigation state back into the router.
- Invalid IDs redirect to `/home` and surface a typed failure.
- Native and Flutter menus call typed routes. Bloc does not depend on GoRouter.

---

## 7. Bloc Concurrency and Lifecycle

| Event category | Default transformer | Reason |
| --- | --- | --- |
| Search/filter and refresh after provider/model selection | `restartable()` | New input supersedes stale work |
| Load-more and repeated refresh clicks | `droppable()` | Prevent duplicate concurrency |
| Permission/question/plan responses, persistence writes, conversation open/close | `sequential()` | Preserve order and prevent duplicate effects |
| Provider/timeline external stream | Restartable subscription | Cancel the old source on switch |
| Pure synchronous expansion/selection | Synchronous handler | No async race |

Every Bloc/Cubit must cancel subscriptions, timers, and cache leases in `close()`, reject stale async completions with generation/key checks, test ordering/cancellation/duplicates/failures with `blocTest()`, and store typed failures rather than displayable exception text.

---

## 8. Internationalization

- Import the current `dev` en/zh ARB with 1,040 keys as the temporary baseline; recount after Cursor removal.
- ARB is the only source of Zeta-authored UI copy.
- `app_ui` receives copy through constructor parameters.
- Packages do not author localizable Zeta UI strings. User content, provider text, and internal diagnostics remain valid string data.
- Remove TextCatalog/Fallback dual tracks. Lower layers return typed codes; `lib/l10n/` maps them exhaustively.
- `ZetaShadcnLocalizations` stays in the app.
- Bloc never uses `BuildContext`. Desktop notifications use an injected, BuildContext-free app copy resolver.
- Display locale remains frozen at startup and behaves identically in every flavor.

---

## 9. Automated Architecture Gates

CI must assert:

1. Data and Repository packages do not depend on Flutter.
2. No repository depends on another repository.
3. Vendor clients do not depend on one another.
4. Feature code does not import clients, `dart:io`, or `package:flutter/services.dart`.
5. App-side Data/client imports are restricted to the composition-root allowlist.
6. `app_ui` does not depend on repositories, Data, or AppLocalizations.
7. Packages never import app `lib/` code.
8. Consumers never import package `src/` paths.
9. Feature widgets do not call repositories; Pages only provide Blocs.
10. Blocs have no constructor dependency on another Bloc.
11. GoRouter routes are typed and hierarchical; the repository contains no `extra:` or raw-path navigation.
12. Every StreamController, subscription, timer, and runtime lease has a close path.
13. `pubspec.lock` passes an OSV vulnerability scan; every ignored advisory has an inline applicability justification.
14. WCAG 2.2 AA widget tests cover semantics, keyboard focus, target size, text scaling, contrast, and non-drag alternatives; reduced motion remains an additional VGV platform gate.

ADR-001 and the composition-root allowlist must be machine-readable, not implicit comments.

---

## 10. Execution Roadmap

| Phase | Goal | Risk | Parallelism |
| --- | --- | --- | --- |
| P-1 | Remove Cursor code, pin final SHA, source-to-target manifest, ADR | Medium | No |
| P0 | Desktop skeleton, unified identity, Dart workspace, assets/l10n/CI/gates | Medium | No |
| P1 | Shared contracts, logging/storage, transport, platform ports | Medium | Partial |
| P2 | Provider and management Data clients | Medium | Three vendor clients in parallel |
| P3 | Settings/workspace/session/usage Data | Low | Yes |
| P4 | All repositories; remove business state from them | High | By dependency group |
| P5 | app_ui and typed l10n mappings | Medium | Partial overlap with P2/P3 |
| P6 | Smaller feature Blocs and Presentation | Medium | Serial to establish the pattern |
| P7 | AgentConversationBloc and high-frequency UI | High | No |
| P8 | IdeShellBloc, GoRouter, bootstrap, three-platform closure | High | No |

P4 and P7 carry the central risk. P4 proves that business state truly leaves repositories; P7 proves event ordering, performance, and approval safety under high-frequency provider streams.

---

## 11. Final Acceptance

### Code Quality

- Analyze, format, test, and coverage gates pass; manually maintained Dart/Flutter code reaches 100% coverage.
- Every package tests independently.
- All automated architecture gates pass.

### Functionality and Safety

- Real-CLI smoke tests pass for Codex, Claude Code, and Grok.
- Permission response, question response, plan approval, and plan execution handoff remain isolated, including negative no-preauthorization tests.
- Unsupported capabilities hide their UI entry and fail closed if invoked.
- Credentials and provider content never leak into logs.
- Real secrets are not stored or compiled into Zeta files, assets, `--dart-define` values, or native config; Provider credentials remain owned by Provider CLIs / OS credential storage.
- Process launch never concatenates shell commands; project/file ID resolution, path boundaries, and symlink behavior have negative tests.
- The `pubspec.lock` OSV scan and dependency-license check pass, with no advisory/license exception lacking a written rationale.

### Desktop and Navigation

- macOS, Windows, and Linux debug and release builds pass.
- Every platform uses `cn.easii.zeta` / `Zeta`; flavors have no identity suffix.
- Fonts, notifications, badges, windows/menus, directory selection, and clipboard contracts pass on all platforms.
- GoRouter startup restoration, redirects, back navigation, invalid IDs, and menu navigation tests pass.

### Accessibility

- Run macOS VoiceOver, Windows Narrator/NVDA, Linux Orca, and keyboard-only smoke tests against WCAG 2.2 AA.
- Every interaction is keyboard-operable with visible focus; icon-only controls have semantics; asynchronous status is announced.
- Normal text reaches 4.5:1 contrast, large text 3:1, and UI components/focus indicators 3:1; 200% text scaling loses no content.
- Targets meet the AA 24×24 dp minimum, with VGV's 48×48 dp size as the design target; every drag action has an on-screen non-drag alternative.
- Unobscured-focus, high-contrast, and reduced-motion tests pass; reduced motion is an additional platform quality gate, not claimed as an AA criterion.
- Record known Flutter/Linux/Orca limitations; automated tests do not replace manual verification.

### Performance and Lifecycle

- Event-storm fixtures show no reordering, ghost updates from stale subscriptions, or duplicate effects.
- Long-timeline scrolling and high-frequency deltas do not regress recorded `dev` frame time or peak memory.
- Closing a workspace or app releases provider processes, subscriptions, timers, and leases.

### Scope Confirmation

- No `app_update`, Velopack, updater native channel, or packaging work is migrated.
- Distribution signing, notarization, and installer packaging are out of scope; a release-build smoke test is not release-process acceptance.
- No historical data-upgrade tests run; a clean directory validates installation and the current schema.
- Chinese/English documentation, README indexes, and the source-to-target manifest agree.

---

## Appendix: Measurement Method

- The source baseline is Git-tracked content on the old repository's current `dev`. The untracked `.workflow/feature/2026-08-18-PC端构建与版本检查/` directory is not a migration input.
- Dart line counts include comments and blank lines; generated l10n is separate.
- The feature dependency graph counts `package:zeta/src/...` imports. The final manifest must also cover relative imports, native runners, assets, pubspecs, and platform configuration.
- Every in-scope source file appears exactly once in the source-to-target manifest. Every deletion records its reason and verification method.
