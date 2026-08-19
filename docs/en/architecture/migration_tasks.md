# VGV Layered Migration Task List

[中文](../../zh/architecture/migration_tasks.md) ｜ English

This checklist turns the [migration topology](./migration_topology.md) into executable steps. A step may be checked only after its code, tests, architecture gates, and both document languages pass in the same iteration.

## 0. Progress Overview

| Phase | Steps | Status |
| --- | --- | --- |
| P-1 Baseline and ADRs | 0–2 | ☑ |
| P0 Engineering foundation | 3–6 | ☑ |
| P1 Shared contracts and infrastructure | 7–10 | ☐ |
| P2 Provider and Management Data | 11–17 | ☐ |
| P3 Remaining Data | 18–21 | ☐ |
| P4 Repository | 22–26 | ☐ |
| P5 app_ui and l10n | 27–28 | ☐ |
| P6 Smaller Feature Blocs/Presentation | 29–31 | ☐ |
| P7 Agent conversation | 32–33 | ☐ |
| P8 Shell, router, and close-out | 34–36 | ☐ |

Explicitly outside every phase: `app_update`, Velopack, updater native channels, the legacy repository's `tool/packaging/`, historical-version data migration, and external OS deep links.

**Explicitly in scope** (ruled 2026-08-19, see [manifest §5](./migration_manifest.md)):
`third_party/codex_app_server_schema/` (269 files, the Codex `0.144.5` stable schema pin, the baseline for the step 12 contract test);
and under `tool/`, the five `smoke_*.py` scripts, `gen_codex_schema.{sh,ps1}`, `check_localized_ui_strings.dart` and its allowlist
(steps 17 / 28 / 33 / 36 depend on them directly).

---

## 1. Global Conventions

### 1.1 Four layers and dependencies

~~~text
Presentation → Bloc/Cubit → Repository → Data
~~~

- Data and Repository live under `packages/` and have no Flutter dependency.
- Repository packages never depend on another Repository package.
- `lib/bootstrap.dart` is the only file that may import Data, Repository, and app platform adapters together; `main_*` only calls bootstrap.
- `lib/app/platform/**` may import only `desktop_platform_api`, Flutter services, and the corresponding plugins—not other Data clients.
- Every other app `lib/**` path imports no Data package, `dart:io`, or `package:flutter/services.dart`.
- Widgets do not call repositories directly. A Page creates/provides a Bloc; Views and Widgets dispatch events and render state.
- Application business code never imports another package's `src/`.

### 1.2 Package structure

Create each package with the corresponding Very Good CLI template and retain this shape:

~~~text
packages/<name>/
├── lib/
│   ├── <name>.dart
│   └── src/
├── test/
└── pubspec.yaml
~~~

- Every local package dependency uses `path:`.
- A package barrel is its only public entry point.
- Response models remain in Data; domain models remain in Repository.
- ADR-001's `agent_provider_contracts` is the sole model-ownership exception.
- Repositories receive Data clients/ports through constructors and never instantiate concrete implementations internally.

### 1.3 Bloc/Cubit

- Use sealed classes for events and multi-form states; Events and States use Equatable.
- A single-state-class design exposes `copyWith` and an explicit status enum.
- Business failures are typed; state never stores localized strings or a raw rendered Exception.
- Blocs have no constructor dependency on another Bloc.
- Every async event explicitly chooses `restartable()`, `droppable()`, or `sequential()`.
- `close()` cancels subscriptions, timers, and leases; generation/key checks reject stale async completions.
- All Bloc tests use `blocTest()`.

### 1.4 GoRouter

- Use `go_router`, `go_router_builder`, and `@TypedGoRoute` / `@TypedShellRoute`.
- Do not navigate with raw path strings or use `extra`.
- Normal navigation uses a generated route's `go()`; use `push()` only when a result is required.
- Route parameters are stable, URL-safe IDs rather than local file paths.
- The router owns page/projectId/threadId; Blocs do not depend on GoRouter.
- This migration implements in-app navigation only and does not register OS deep links.

### 1.5 l10n

- ARB is the only source of truth for Zeta-owned UI copy.
- Packages do not emit Zeta UI copy that needs localization. User content, provider-originated text, and internal diagnostic strings are exempt.
- Packages do not depend on `AppLocalizations`.
- `app_ui` receives copy through constructor parameters.
- Blocs do not use `BuildContext`. Background copy uses an injected app-level resolver without BuildContext.

### 1.6 Tests

- Tests mirror `lib/` and use private mocktail mock classes.
- `setUp`/`tearDown` live inside their group; every test is independent and works under randomized ordering.
- Widget tests use the shared `pumpApp` and MockBloc/MockCubit, not inline `MaterialApp` instances.
- Unit/widget tests verify behavior; goldens tagged with `TestTag.golden` verify static visuals.
- Data/Repository tests cover success, null/empty cases, boundaries, exception translation, cancellation, and resource close.
- Bloc tests cover every handler, transformer ordering, stale results, and negative safety semantics.

### 1.7 Definition of done for every step

The same final iteration must observe all four gates green:

1. Analyze: `mcp__dart__analyze_files` with `applyFixes: true`.
2. Format: `mcp__dart__dart_format`, with `0 changed` in the final pass.
3. Test: `mcp__very-good-cli__test`, passing `directory` for a package and always passing `timeout_seconds`.
4. Coverage: the same test call passes `coverage: true`, `min_coverage: 100`, and `check_ignore: true`.

Generated code is excluded through `exclude_coverage`: `**/*.{g,freezed,gen}.dart` plus generated/l10n directories. The 100% target applies to testable hand-written code. Assertions must not be removed, the threshold must not be lowered, and reachable code must not be ignored merely to pass the gate.

Before checking a step:

- [ ] Its source-to-target manifest entries are updated.
- [ ] Architecture gates pass with no new allowlist entry.
- [ ] Resource-lifecycle tests pass.
- [ ] Chinese and English documents are updated in the same commit.

### 1.8 Security, supply chain, and accessibility

- Real secrets must not enter source, assets, `--dart-define`, or native config; Provider credentials remain managed by Provider CLIs / OS credential storage.
- Start processes with argument lists rather than concatenated shell commands; external IDs, canonical paths, symlinks, and directory boundaries fail closed.
- The final `pubspec.lock` must pass OSV vulnerability and dependency-license checks; every suppression carries an inline applicability rationale.
- The accessibility target is fixed at WCAG 2.2 AA across macOS / Windows / Linux.
- Widget tests and VoiceOver/Narrator/NVDA/Orca manual smoke tests run against AA; reduced motion remains an additional VGV platform gate.

### 1.9 Bilingual documentation layout

- `docs/` is split by language into `docs/zh/` and `docs/en/`.
- Both trees have **identical subdirectory structures and identical filenames**; filenames carry no
  language suffix and the language is determined by the directory.
- When adding or changing a document, both language versions must be updated in the **same commit**.
- The sole exception is `history/`: archived documents keep their original language and the other side
  carries a pointer to them.
- The repository-root `README` / `CONTRIBUTING` keep the `xxx.md` + `xxx.en.md` suffix form and stay
  outside `docs/`.

---

## P-1 · Baseline and ADRs

### Step 0 — Retire Cursor code on the legacy `dev` branch

There are no released users, so no compatibility migration or legacy data upgrade is required. Remove only source, fixtures, and development-data assumptions.

**Status: complete.** Legacy-repository commit: `b5c2f3e8` (2026-08-19). By migration decision, legacy coverage is recorded but not gated: hand-written code coverage is 83.97% (35,075 / 41,771); analyze, format, and test pass. The new VGV workspace remains subject to the 100% coverage gate in §1.7.

- [x] Remove `cursor_retirement_policy.dart` and its barrel export.
- [x] Remove Cursor branches from provider factory, static capabilities, settings, turn context, management, and UI.
- [x] Remove Cursor l10n keys, tests, and fixtures.
- [x] Keep only currently required values in `AgentProviderKind`; do not preserve compatibility values for an unreleased schema.
- [x] Do not modify `zeta_storage_migrator` to process historical Cursor data.
- [x] Commit after legacy analyze, format, and test pass; freeze feature development after this commit. Legacy coverage is exempt under the decision above.

### Step 1 — Freeze the final baseline and source-to-target manifest

**Status: complete.** Final baseline `b5c2f3e8a9ac544e9832866e86ff633661c46053`; all 1,507 tracked files are classified exactly once, the generator reports no `UNCLASSIFIED` entries, and both language renders are idempotent. Gates: zero analyze issues, format 0 changed, 8 tests, and 100% hand-written Dart coverage (30 / 30).

- [x] Record the final legacy commit SHA, clean status, Flutter/Dart versions, and `pubspec.lock` hash.
- [x] Recount hand-written Dart, generated Dart, tests, ARB, native files, and assets.
- [x] Create `docs/zh/architecture/migration_manifest.md` and `docs/en/architecture/migration_manifest.md`.
- [x] Classify every Git-tracked file exactly once as `move`, `rewrite`, `regenerate`, `delete`, or `out-of-scope`.
- [x] Include native Runners, MethodChannels, pubspecs, fonts/icons, and CI files.
- [x] Explicitly exclude the untracked `.workflow/feature/2026-08-18-PC端构建与版本检查/` directory from the input.

### Step 2 — ADRs and business-state ownership

**Status: complete.** ADR-001—004 are accepted; the ownership map is revalidated against all 24 final-baseline `ChangeNotifier/Listenable` declarations and 57 application files; `.architecture.yaml` parses and registers one contracts exception package, 14 Data packages, nine Repository packages, and zero open decisions. Gates: zero analyze issues, format 0 changed, 8 tests, and 100% hand-written Dart coverage (30 / 30).

- [x] ADR-001: the `agent_provider_contracts` model exception, allowed dependencies, and review criteria.
- [x] ADR-002: Flutter platform adapters exist only in `lib/app/platform/`; Repositories depend on pure-Dart ports.
- [x] ADR-003: the router is the navigation-identity source of truth; session restore only produces an initial location/redirect.
- [x] ADR-004: conversation reducer/effect boundary—domain snapshot aggregation remains in Repository; UI/interaction state belongs in Bloc.
- [x] Create a class-level ownership map: legacy Controller/Store/Service → Data/Repository/Bloc/Presentation.
- [x] Create machine-readable `.architecture.yaml` containing package layers, ADR-001, and the composition-root allowlist.
- [x] The open-decision register is empty and records the final WCAG 2.2 AA / macOS / Windows / Linux decision.

**P-1 exit: passed.** The final SHA is frozen, the manifest has no unassigned file, and the bilingual ADRs plus ownership map pass machine validation.

---

## P0 · Engineering Foundation

### Step 3 — Platforms, identity, and version

**Status: complete.** Platform directories, all three desktop identities, flavor names, and the version are complete; local Windows debug/release builds pass, and all nine macOS/Windows/Linux × development/staging/production release builds pass in GitHub Actions `desktop-build` run `32220262496`. Gates: zero analyze issues, format 0 changed, 8 tests, and 100% Dart coverage (30 / 30).

- [x] Remove `android/`, `ios/`, and `web/` from the new repository.
- [x] Add the Linux desktop scaffold.
- [x] Use application/bundle ID `cn.easii.zeta` on macOS, Windows, and Linux.
- [x] Set every flavor product name to `Zeta`; remove `[DEV]` / `[STG]` and `.dev` / `.stg` identity suffixes.
- [x] Remove `my_app` / `com.example.myApp` remnants from `macos/Runner/Configs/AppInfo.xcconfig`.
- [x] Keep version `1.0.0+1`.
- [x] All flavors share `~/.zeta` and one schema; document that they cannot be installed side by side.
- [x] Empty-shell builds pass for three platforms and three entrypoints.
  - [x] Windows: development/staging/production, debug and release.
  - [x] Linux: development/staging/production, GitHub Actions release.
  - [x] macOS: development/staging/production flavors, GitHub Actions release.

### Step 4 — Dart workspace and dependency baseline

**Status: complete.** The root workspace registers 25 migration-target packages plus one development-only Widgetbook tooling package; all use Flutter 3.47.0 / Dart 3.13.0, aligned Very Good Analysis configuration, and local `path:` dependencies. Final gates: workspace `pub get` resolved `test 1.31.1` / `test_api 0.7.12`; analyze reported zero issues; format checked 111 files with 0 changed; 99 tests passed across 26 testable package roots with 100% hand-written Dart coverage (132 / 132); the license gate passed for 168 licenses from 166 packages; and OSV-Scanner plus Very Good CLI versions are pinned in CI.

- [x] Declare native Dart workspace members in the root `pubspec.yaml`; do not add Melos.
- [x] Use the root SDK constraint consistently across all packages.
- [x] Add `go_router`, `go_router_builder`, `build_runner`, and `bloc_concurrency`.
- [x] Bring in dependencies for current features only; add no updater/Velopack dependency.
- [x] Use `path:` for all local packages.
- [x] Align Very Good Analysis across root and packages.
- [x] Commit the final `pubspec.lock` and pin OSV-scanner/license-checker versions in CI.

### Step 5 — Assets and l10n baseline

**Status: complete.** Geist, JetBrainsMono, branding, the three Agent icons, and all three platform application icons were migrated file-for-file from the frozen baseline; all 23 asset-file SHA-256 hashes match the legacy repository. Every macOS configuration now uses the `AppIcon` asset catalog, while the Windows RC and Linux bundle/resource loader reference the migrated icons. The scaffold Spanish ARB is removed; English and Chinese each contain 1,035 message keys with identical metadata/placeholder sets. Required resource attributes, escaping, formatting, and generated-code coverage exclusion are consolidated; `l10n` / `l10nOrNull` are available; and two consecutive localization generations are idempotent. Gates: zero analyze issues, format checked 112 files with 0 changed, 104 tests passed across 26 testable package roots, hand-written Dart coverage is 100% (134 / 134), and the Windows production release build passes.

- [x] Migrate Geist, JetBrainsMono, branding, and agent icons.
- [x] Align application icons and resource manifests on all three platforms.
- [x] Remove scaffold Spanish ARB.
- [x] Migrate the current `dev` English and Chinese ARB files; use the post-Step-0 recount as the baseline.
- [x] Consolidate `l10n.yaml` for required attributes, escaping, and generated-code coverage exclusion.
- [x] Migrate `l10n` / `l10nOrNull` extensions.
- [x] Code generation succeeds and the English/Chinese key sets are identical.

### Step 6 — CI and architecture gates

**Status: complete.** `.architecture.yaml` now explicitly registers the contracts, Data, Repository, presentation, and tooling layers plus the three vendor clients. Twenty-four architecture contract tests cover package/path dependencies, Flutter isolation, the composition root, platform adapters, external `src/` imports, typed navigation, Bloc isolation, `app_ui`, and supply-chain exceptions. CI reports analyze/format independently for all 27 workspace roots and runs randomized tests plus 100% coverage for the 26 roots that contain tests; Widgetbook is explicitly reported as a tooling-only root with no test directory. Every CI test invocation, including the dedicated golden job, uses the Flutter-backed `very_good test` command without `--check-ignore`, which that command does not support; generated `*.g.dart`, `*.freezed.dart`, and `*.gen.dart` sources leave the coverage denominator through `--exclude-coverage`. Agent/MCP green-gate invocations retain `check_ignore: true` as specified in §1.7. The final local gate round observed 27/27 roots with zero analyze issues, 116 formatted files with 0 changed, 128 tests across 26 testable roots, and 100% hand-written Dart coverage (134 / 134). The latest fully green `desktop-build` run `32229542327` proves the production build on all three platforms.

- [x] Run the four gates in §1.7 order and report each workspace package separately.
- [x] Architecture tests read `.architecture.yaml` and enforce the four-layer dependency graph.
- [x] Reject Repository-to-Repository dependencies, vendor-client cross-dependencies, and external `src/` imports.
- [x] Reject Data imports in business code outside `bootstrap.dart`; platform adapters allow only `desktop_platform_api` / Flutter services / their plugin.
- [x] Reject `extra:`, raw-path navigation, and Bloc-to-Bloc constructor dependencies.
- [x] Reject `app_ui` dependencies on Repository, Data, or AppLocalizations.
- [x] Add randomized test ordering and a golden-tag CI job.
- [x] Add `pubspec.lock` OSV scanning, dependency-license checking, and a gate for unexplained advisory suppressions.
- [x] CI builds at least the production entrypoint on all three platforms.

**P0 exit: passed.** Empty shells build on three platforms, identity is uniform, and workspace/architecture gates run in CI.

---

## P1 · Shared Contracts and Infrastructure

### Step 7 — `agent_provider_contracts`

- [x] Create a pure-Dart package implementing ADR-001.
- [x] Migrate 21 capability ports, Provider bundle/factory, and neutral event/session/thread/permission/plan/usage/input models.
- [x] Remove every TextCatalog/Fallback type and add typed failures/codes.
- [x] Verify zero vendor fields, IO, Flutter, or business state.
- [x] Test sealed families, codecs/pure models, Equatable, and `copyWith`.

**Status: complete.** The package freezes 21 Provider ports, 35 `AgentEvent`
subtypes, 27 capability flags, the bundle/factory surface, and
`ResolvedCliProcessCommand`. Public collection fields are defensive immutable
snapshots, including nested diagnostic payloads. Provider-authored content may
remain data, while Zeta-owned status/failure/warning copy is represented by
typed codes and mapped by Presentation. The approved ownership split keeps
attention and terminal signals in contracts, while turn-activity state and
elapsed formatting remain with the later Bloc/Presentation work. Package gates:
zero analyze issues, 52 formatted files with no changes, 85 tests, and 100%
hand-written Dart coverage (1,071 / 1,071). The frozen-baseline reconciliation
corrected the former count of 36 event types to 35; the extra count duplicated
an `AgentTurnStartedEvent` construction path, not a subtype. In the same final
workspace iteration, 27/27 roots passed analyze and formatting checked 165 files
with no changes; 26/26 test roots ran 212 tests at 100% hand-written coverage
(1,204 / 1,204), while Bloc lint reported 0 issues across 164 files.

### Step 8 — `zeta_logging` and `zeta_storage`

- [x] Move structured logging and the sensitive-data redactor to `zeta_logging`.
- [x] Redact every log sink by default; credentials, prompts, and Provider content never enter structured fields.
- [x] `zeta_storage` implements only atomic IO, paths, and typed exceptions for the current schema.
- [x] Do not migrate the historical SharedPreferences bridge or old-version upgrade logic.
- [x] Test temporary directories, atomic replacement, non-overwrite on failure, path errors, and close.

**Status: complete.** `zeta_logging` sanitizes message, error, and stack data
before an event reaches any listener, console, or file sink; the file sink is
private so callers cannot bypass `AppLogger`. Structured prompt/content/payload/
raw fields are masked wholesale, ignored-message diagnostics retain only stable
shape metadata, and broad error categories replace exception text. This closes
the **Critical** legacy risk of raw console/error output. `zeta_storage` now
provides serial atomic UTF-8 replacement, non-overwrite on failure, close
semantics, current-schema paths without migration markers, canonical absolute
directory resolution, and sealed read/write/path/closed exceptions. The legacy
Presentation-only `formatBytes` helper is deliberately excluded. Package gates:
43 tests and 100% hand-written coverage (399 / 399). In the same final workspace
iteration, 27/27 roots passed analyze, format checked 177 files with no changes,
26/26 test roots ran 253 tests at 100% hand-written coverage (1,601 / 1,601),
and Bloc lint reported 0 issues across 176 files.

### Step 9 — `json_rpc_transport`

**Status: complete.** `json_rpc_transport` now owns the bounded JSONL stdio
transport, keyed shared/exclusive operation scheduler, and provider runtime
lifecycle gate. `ProcessStarter`, `Clock`, and the sanitizing `AppLogger` are
injectable; tests never launch a real process. The sealed transport failures
cover malformed and oversized frames, timeouts, process termination, and closed
connections. Stderr is redacted before leaving the package, frame payloads are
never copied into diagnostics, and pending work is deterministically cancelled
on close or process exit. The package depends only on the already-frozen runtime
value types in `agent_provider_contracts` and changes no Provider port. Package
gates: 38 tests and 100% hand-written coverage (540 / 540). In the same final
workspace iteration, 27/27 roots passed analyze, format checked 182 Dart files
with no changes, 26/26 test roots ran 290 tests at 100% hand-written coverage
(2,140 / 2,140), and Bloc lint reported 0 issues across 181 files.

- [x] Migrate stdio transport, operation scheduler, and runtime peer.
- [x] Define a sealed `TransportException` family.
- [x] Constructor-inject process starter, clock, and logger.
- [x] Test partial lines, malformed JSON, timeouts, cancellation, stderr, process exit, and double close.

### Step 10 — `desktop_platform_api` and app adapters

Pure-Dart ports:

- [ ] `SystemFontCatalogApi`.
- [ ] `DesktopNotificationApi` / `DesktopAttentionApi`.
- [ ] `DirectoryPickerApi` / `ClipboardApi`.
- [ ] `WindowCommandApi` / `MenuCommandApi`.

Flutter adapters, only under `lib/app/platform/`:

- [ ] MethodChannel adapters for system fonts, attention, and native menus.
- [ ] A `flutter_local_notifications` adapter.
- [ ] Adapters for `file_selector`, pasteboard, `window_manager`, and `macos_window_utils`.
- [ ] Every adapter constructor-injects its channel/plugin facade; Widgets and Blocs never import plugins directly.
- [ ] Platform ports are consumed only by Repositories; an architecture test rejects any Bloc/Presentation import of `desktop_platform_api`.
- [ ] Add Dart contract tests plus macOS/Windows/Linux native-channel contract tests.

**P1 exit:** shared packages are independently green and platform-plugin imports exist only in the allowlist.

---

## P2 · Provider and Management Data

### Step 11 — `agent_config_client`

- [ ] Migrate provider config store/codec, model-catalog cache, and turn-context store/codec.
- [ ] Support only the current schema; unknown or corrupt current files return a typed decode failure, with no historical upgrade.
- [ ] Exclude CLI locators, selection state, and Controllers.
- [ ] Test every read/write/corruption/atomic-overwrite branch using temporary directories.

### Step 12 — `codex_app_server_client`

- [ ] Migrate the Codex provider, app-server client, mappers/codecs, process starter, and CLI locator.
- [ ] Migrate raw Codex history/usage reads; return only Data models or neutral contracts.
- [ ] Contract-test entryId, message chunks, terminal states, capabilities, and approval mapping.

### Step 13 — `claude_code_client`

- [ ] Migrate the Claude provider, stream-JSON peer, mappers/adapters, process starter, and CLI locator.
- [ ] Migrate history, quota, and credential/keychain probes; credentials never reach disk or logs.
- [ ] Contract-test permissions/questions/plans, identity, history, and process lifecycle.

### Step 14 — `grok_acp_client`

- [ ] Migrate the Grok provider, ACP codecs/mappers, process starter, and CLI locator.
- [ ] ACP currently has one consumer, so do not extract a shared package yet.
- [ ] Contract-test fail-closed permissions, questions/plans, identity, usage/history, and malformed updates.

### Step 15 — `agent_history_client`

- [ ] Retain only cross-provider history merge/replay input and generic fault tolerance.
- [ ] Keep vendor-specific parsers in each vendor client; do not duplicate them.
- [ ] A corrupt record may be skipped with a typed warning; never swallow an overall IO failure.
- [ ] Do not produce UI timeline cards/projections.

### Step 16 — `agent_management_client`

- [ ] Migrate the three Agent management data sources, CLI process runner, and Claude auth probe.
- [ ] Expose Data APIs for detect, test connection, read/write config, and read logs.
- [ ] Do not depend on `agent_provider_repository` or store selected Agent/loading/progress UI state.
- [ ] Test process, file, and credential branches with injected fakes.

### Step 17 — Provider Data integration gate

- [ ] The three vendor packages are mutually absent from one another's pubspecs.
- [ ] Each vendor has exactly one CLI-locator implementation and owner.
- [ ] Allocate existing protocol fixtures by package, with no cross-package test import.
- [ ] Smoke-test read-only capabilities of real CLIs; do not run operations that modify user configuration.
- [ ] Prove that every process, stream, and subscription closes during test teardown.

**P2 exit:** Provider Data contracts are green, and pubspecs plus tests enforce vendor isolation.

---

## P3 · Remaining Data

### Step 18 — `settings_client`

- [ ] Migrate the general/appearance store and codec for the current schema only.
- [ ] Keep concrete system-font implementation out of this package; use `desktop_platform_api`.
- [ ] Test missing, empty, corrupt, permission-denied, and atomic-write-failure cases.

### Step 19 — `workspace_client`

- [ ] Move all `dart:io` file scanning, directory reads, and gitignore input into this package.
- [ ] `WorkspaceNodeResponse` reflects only the external file system and does not store expanded/selected state.
- [ ] Test symlinks, denied access, disappearing files, large-directory cancellation, and gitignore boundaries.

### Step 20 — `project_session_client`

- [ ] Migrate the IDE session store and current snapshot codec.
- [ ] Data models never refer to Bloc State.
- [ ] Test current-schema round trip, corrupt files, debounced-write cancellation, and close-time flush.

### Step 21 — `usage_statistics_storage_client`

- [ ] Migrate the current schema for usage partitions, cache, and index.
- [ ] Keep raw Codex/Claude/Grok readers in their vendor clients.
- [ ] Treat cache as rebuildable derived data; clear and recompute corruption rather than pretending success.
- [ ] Test time boundaries, partitioning, empty sources, scan cancellation, cache invalidation, and large fixtures.

**P3 exit:** no app feature imports `dart:io` and every external data source can be tested with pure-Dart fakes.

---

## P4 · Repository

### Step 22 — `agent_provider_repository`

- [ ] Constructor-inject `agent_config_client` plus the three bundle factory/catalog ports.
- [ ] Expose config snapshot/changes, `bundleFor`, and model/mode/skill/permission catalogs.
- [ ] Do not depend on conversation or management repositories.
- [ ] Keep model/permission/mode UI selection out of Repository; persist only explicit inputs.
- [ ] Translate client exceptions into typed provider domain failures while retaining cause/stackTrace for logging.

### Step 23 — `agent_conversation_repository`

- [ ] Do not accept `agent_provider_repository` in the constructor.
- [ ] `openConversation` accepts the `AgentProviderBundle` / key already resolved by Bloc.
- [ ] Migrate event pipeline, coalescing, dispatcher, domain reducer/effects, timeline aggregate, runtime registry/lease, and turn context.
- [ ] Streams expose domain timeline snapshots only and also provide a synchronous snapshot.
- [ ] Live, history, and replay use separate reducer instances.
- [ ] Test event storms, out-of-order rejection, stale runtime generations, backpressure, close, and lease release.

### Step 24 — `agent_management_repository`

- [ ] Constructor-inject management/config clients without depending on provider repository.
- [ ] Map detect/test/config/log responses to management domain models.
- [ ] Configuration validation is a pure Repository domain method, but UI invokes it only through Bloc events.
- [ ] Do not store selected agent, progress, loading, or localized messages.

### Step 25 — Settings / Workspace / Project Session Repositories

- [ ] `settings_repository`: domain settings, system-font conversion, and current-schema persistence.
- [ ] `workspace_repository`: index/query/tree data; expanded/selected belongs to WorkspaceCubit.
- [ ] `project_session_repository`: session snapshot and thread catalog; search/selection/load status belongs to Bloc.
- [ ] These packages do not depend on one another. They may share Data ports, never a Repository.
- [ ] Test all Data-exception translations and external-data streams.

### Step 26 — Usage / Desktop Notifications / Desktop Platform Repositories

- [ ] `usage_statistics_repository` aggregates the three vendor Data sources and cache into report domain models; filter selection belongs to Bloc.
- [ ] `desktop_notifications_repository` accepts only already-localized copy and neutral notification requests.
- [ ] The notifications repository does not depend on settings repository.
- [ ] `desktop_platform_repository` wraps directory-picker, clipboard, and window/menu ports for Bloc consumption, with zero Flutter.
- [ ] Every package has zero Flutter, ChangeNotifier, or ValueNotifier usage.

**Objective P4 exit:**

- [ ] Repository-to-Repository dependencies = 0.
- [ ] Repository Flutter dependencies = 0.
- [ ] UI selection/loading/expanded state in Repository = 0.
- [ ] Data/IO imports in app business code outside `bootstrap.dart` = 0.
- [ ] Every Repository package independently passes all four gates.

---

## P5 · app_ui and l10n

### Step 27 — `packages/app_ui`

- [ ] The accessibility baseline is fixed at WCAG 2.2 AA / macOS / Windows / Linux.
- [ ] Migrate design tokens, base components, Workbench primitives, virtual scrolling, and the pure-UI part of WindowFrame.
- [ ] Keep `shadcn_flutter` and consistently import it `as sf`.
- [ ] Use one public component per file, barrels, const constructors, and Dartdoc on public APIs.
- [ ] Put tokens in ThemeExtension; never depend on Repository, Data, or AppLocalizations.
- [ ] Receive all component copy through constructors.
- [ ] Give every public component a behavior widget test and tagged goldens for visual properties.
- [ ] AA tests cover semantics, keyboard/focus, async live regions, non-drag alternatives, and unobscured focus.
- [ ] Normal text contrast is ≥4.5:1, large text ≥3:1, and UI/focus indicators ≥3:1; 200% text scaling loses no content.
- [ ] Targets meet the AA 24×24 dp minimum, with VGV 48×48 dp as the design target; reduced motion is an additional platform gate.

### Step 28 — Typed l10n mapping

- [ ] Remove the four TextCatalog/Fallback families and `ZetaTextCatalogs`.
- [ ] Replace lower-layer messages with typed failures/codes; map them exhaustively in `lib/l10n/failure_messages.dart`.
- [ ] Keep `ZetaShadcnLocalizations` and shadcn ARB keys in the app.
- [ ] Create a no-BuildContext `DesktopNotificationCopyResolver`, injected by bootstrap for a frozen Locale.
- [ ] Verify identical English/Chinese keys, placeholder metadata, and escaping.
- [ ] Packages importing `AppLocalizations` = 0.

**P5 exit:** app_ui is independently green, English/Chinese UI smoke tests pass, and no TextCatalog remains.

---

## P6 · Smaller Feature Blocs and Presentation

### Step 29 — Workspace / Settings / Desktop Notifications

**WorkspaceCubit**

- [ ] Expose index/invalidate/toggle/select/reveal; expanded/selected exists only in State.
- [ ] Indexing uses `restartable()`-equivalent cancellation; reveal/directory selection goes through `desktop_platform_repository`.

**SettingsCubit**

- [ ] Handle load/persist/font catalog/language restart result.
- [ ] Serialize persistence writes with `sequential()` and explicitly coalesce rapid appearance changes.

**DesktopNotificationsBloc**

- [ ] Inject settings and notification repositories directly; do not depend on SettingsCubit.
- [ ] Keep attention stream, visibility, read state, and badge in one Bloc.
- [ ] Use a no-BuildContext copy resolver and serialize notification side effects.

- [ ] Create Page/View/barrel, blocTest, and MockBloc widget tests for each feature.

### Step 30 — Project Threads / IDE Session

**ProjectThreadsBloc**

- [ ] Handle project activation, search, archived filter, initial/more loading, rename/archive/delete, and runtime sync.
- [ ] Search is `restartable()`, load-more is `droppable()`, and writes are `sequential()`.

**IdeSessionCubit**

- [ ] Handle restore/save/flush and persist only a business snapshot, never GoRouter objects.
- [ ] Restore produces initial-route input consumed by the app router's redirect.

- [ ] The two Blocs do not depend on each other; coordinate them in app composition/BlocListener.

### Step 31 — Agent Management / Usage Statistics

**AgentManagementBloc**

- [ ] Put selected agent, detection progress, test status, config-editor validation, and logs in State.
- [ ] Detection is `droppable()` or explicitly cancellable; loads after selection changes are `restartable()`; config writes are `sequential()`.
- [ ] UI never calls a Repository validator directly.

**UsageStatisticsBloc / AgentUsagePanelCubit**

- [ ] Put filter/preset/project/provider/model/rank selection in app State.
- [ ] Refresh is `restartable()`, repeated refresh is `droppable()`, and query generations reject stale results.
- [ ] fl_chart widgets receive only precomputed domain points.

**P6 exit:** smaller features establish one migration pattern, with no Bloc-to-Bloc dependency, Widget-to-Repository call, or implicit async concurrency.

---

## P7 · Agent Conversation

### Step 32 — `AgentConversationBloc`

- [ ] State retains five Equatable slices: header, composer, pending, expansion, and history.
- [ ] Inject both provider and conversation repositories; resolve the bundle before opening a conversation.
- [ ] Key/generation-guard the timeline subscription and cancel the old source on switch.
- [ ] Eventize message submit/cancel/steer, model/mode/skill/permission selection, and thread operations.
- [ ] Use distinct events and repository methods for permission response, question response, plan approval, and plan-execution handoff.
- [ ] Process the four safety semantics with `sequential()` and test that none preauthorizes another.
- [ ] Keep expansion and UI-derived getters in Bloc State/selectors; do not store Markdown/render cache in State.
- [ ] `close()` releases subscriptions, conversation key, cache lease, and timers.

### Step 33 — Agent Presentation, capabilities, and performance

- [ ] The Page creates the Bloc; widgets use BlocBuilder/BlocSelector and subscribe only to required slices.
- [ ] File selector, pasteboard, and similar services flow through Bloc events and `desktop_platform_repository`, never direct plugin or Data-port imports.
- [ ] Split the three presentation files larger than 1.5k lines without a visual redesign.
- [ ] Add an “entry is absent” widget test for each of 19 optional capabilities.
- [ ] An unsupported capability invoked erroneously produces a typed fail-closed state.
- [ ] Migrate harness, event-storm, timeline-projection, and virtual-scroll tests.
- [ ] Compare long-timeline frame time, memory peak, and high-frequency-delta coalescing against old `dev`; no regression is allowed.
- [ ] Smoke-test real Codex, Claude, and Grok CLI conversations.

**P7 exit:** approval safety, event ordering, provider switch, long-timeline performance, and resource closure all pass.

---

## P8 · Shell, Router, and Close-out

### Step 34 — `IdeShellBloc` and typed GoRouter

- [ ] `IdeShellBloc` stores shell business state only, never another Bloc or router location.
- [ ] Create `@TypedShellRoute` plus home, project, thread, settings, agent-management, and usage routes.
- [ ] Convert canonical project paths to stable URL-safe projectId values resolved by Repository; URLs never expose file paths.
- [ ] Session restore computes initial location/redirect; invalid IDs redirect to `/home`.
- [ ] Menu-action bridge and UI menus use generated typed routes.
- [ ] Window/menu commands go through `desktop_platform_repository`; Bloc never imports the platform API.
- [ ] Reject `extra`, raw paths, and Navigator push/pop.
- [ ] Test restore, redirect, back, invalid/deleted project/thread, menu navigation, and Page Bloc scope.

### Step 35 — Bootstrap, platform, and flavor composition

- [ ] `bootstrap.dart` constructs all clients, platform adapters, and repositories before passing them to App.
- [ ] `MultiRepositoryProvider` exposes Repositories only; create Blocs at global/shell/route/conversation scope.
- [ ] Use one AgentConversationBloc per workspace entry and close it with that entry.
- [ ] All flavors use the same `cn.easii.zeta` / `Zeta` / `~/.zeta` / schema.
- [ ] Migrate window bootstrap, native menu, fonts, notification/badge, file selector, and clipboard.
- [ ] Close every hand-written macOS/Windows/Linux Runner and channel manifest entry.
- [ ] Include no updater/Velopack channel, dependency, or packaging hook.

### Step 36 — Final verification and documentation close-out

- [ ] All workspace packages pass all four gates in the same final iteration; record test counts and coverage.
- [ ] macOS/Windows/Linux × development/staging/production builds pass; smoke-test production releases.
- [ ] Start clean from an empty `~/.zeta` and create the current schema; run no historical-upgrade fixture.
- [ ] Run English and Chinese UI smoke tests with frozen Locale and no missing key.
- [ ] Complete macOS VoiceOver, Windows Narrator/NVDA, Linux Orca, and keyboard-only smoke tests against WCAG 2.2 AA; record Linux limitations.
- [ ] Run end-to-end smoke tests for all three real CLIs.
- [ ] Accept event-storm, long-timeline, and process/subscription/timer/lease-close tests.
- [ ] All `.architecture.yaml` gates pass with no unregistered exception.
- [ ] OSV vulnerability and dependency-license checks pass with no unexplained advisory/license exception.
- [ ] Secret scan, log redaction, parameterized process launch, and path/symlink negative tests pass.
- [ ] Close every manifest file, with no `app_update`, Velopack, or packaging remnant.
- [ ] Update bilingual `architecture/overview`, `layering`, `engineering_standards`, `design_document`, developer/internationalization/navigation guides, and `CONTRIBUTING.md`.
- [ ] `docs/zh/` and `docs/en/` have identical subdirectory structures with paired same-name files (`history/` excepted), and no dead links.

---

## Appendix: Final Objective Metrics

| Metric | Target |
| --- | ---: |
| Repository-to-Repository dependencies | 0 |
| Data/Repository Flutter dependencies | 0 |
| vendor-client cross-dependencies | 0 |
| business-code imports of Data / `dart:io` / Flutter services outside allowlist | 0 |
| external imports of package `src/` | 0 |
| package imports of `AppLocalizations` | 0 |
| TextCatalog/Fallback remnants | 0 |
| Bloc-to-Bloc constructor dependencies | 0 |
| GoRouter `extra:` / raw-path navigation | 0 |
| migrated app-update/Velopack/packaging files | 0 |
| unexplained vulnerability/license exceptions | 0 |
| WCAG 2.2 AA blocking findings | 0 |
| testable hand-written Dart/Flutter coverage | 100% per package |
| unassigned files in migration manifest | 0 |

Step 36 cannot be completed while any metric misses its target.
