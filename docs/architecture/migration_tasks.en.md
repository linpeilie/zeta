# VGV layered migration task list

[中文](./migration_tasks.md) ｜ English

This document is the **step-by-step execution design** for the 34 steps of P0–P7 defined in [migration_topology.en.md](./migration_topology.en.md): each step gives the concrete class design across the Data / Repository / Bloc / UI layers, plus checkable tasks.

Topology analysis, package partitioning rationale, and risk assessment live in the topology document and are not repeated here.

**Progress overview**

| Phase | Steps | Status |
| --- | --- | --- |
| **Step 0 Cursor retirement** (legacy repo) | 0 | ☐ |
| P0 Engineering foundation | 1–6 | ☐ |
| P1 Data layer contracts | 7–8 | ☐ |
| P2 Data layer implementations | 9–11 | ☐ |
| P3 Repository layer | 12–15 | ☐ |
| P4 Design system | 16–17 | ☐ |
| P5 Blocs and presentation | 18–24 | ☐ |
| P6 Agent conversation | 25–27 | ☐ |
| P7 Shell and wrap-up | 28–33 | ☐ |

---

## 0. Global design conventions

Read this section before starting; every step below assumes it.

### 0.1 Naming

| Role | Convention | Example |
| --- | --- | --- |
| Data layer contract package | `<domain>_api` | `agent_provider_api` |
| Data layer implementation package | `<vendor>_client` | `codex_app_server_client` |
| Repository package | `<domain>_repository` | `agent_conversation_repository` |
| Abstract data source | `XxxApi` | `AppReleaseApi` |
| Concrete implementation | `XxxClient` | `HttpAppReleaseClient` |
| Capability port | **Keep `XxxPort`** | `AgentConversationPort` |
| Repository | `XxxRepository` | `SettingsRepository` |
| State | `XxxState` | `WorkspaceState` |
| Event | `XxxEvent` + concrete event classes | `AppUpdateManualCheckRequested` |

> **Why capability ports are not renamed to `Api`**: the 21 ports on `AgentProviderBundle` are **optional capabilities** (`threadArchival`, `planApproval` and others are null when a provider does not support them). The semantics are capability negotiation, not data sourcing. Renaming to `Api` loses that meaning. The package name follows VGV (`agent_provider_api`); the class names keep `Port`.

### 0.2 DTO strategy

**Do not introduce separate DTO classes for provider protocols.**

The legacy repository maps `Map<String, Object?>` → (29 pure-function mappers, all already tested) → Entity directly. Inserting a DTO layer would double those 29 mappers for no real gain.

**Exception — any persisted structure that is written back must have an explicit codec acting as its DTO.** These already exist in the legacy repository; migrate them as-is:

- [ ] `AgentProviderConfigCodec` (205 lines)
- [ ] `AgentTurnContextCodec` (115 lines)
- [ ] `GeneralSettingsCodec`
- [ ] `AppUpdateStateCodec`
- [ ] `ProjectThreadsSessionSnapshotCodec`
- [ ] `AgentModelCodec` (49 lines)

Every codec's `fromJson` **must decode tolerantly** (ignore unknown fields, default missing fields, fall back on unknown enum values). This is the only guarantee that existing users' data stays readable.

### 0.3 Exception translation

**The Data layer throws protocol/IO exceptions, the Repository translates them into domain exceptions, and the bloc only ever handles domain exceptions.**

Each repository defines a sealed exception family:

```dart
sealed class AgentRepositoryException implements Exception {
  const AgentRepositoryException(this.message, [this.cause, this.stackTrace]);
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;
}
```

Translation happens at the repository boundary and **always carries the original cause and stack trace**:

```dart
try {
  return await _bundle.conversation.sendMessage(...);
} on JsonRpcException catch (e, st) {
  throw AgentTurnRejectedException('turn rejected by provider', e, st);
} on ProcessException catch (e, st) {
  throw AgentProviderUnavailableException('provider process not reachable', e, st);
}
```

**A missing capability always throws `AgentCapabilityUnsupportedException`; silent success is forbidden** — silent success makes users believe an operation took effect when it did not.

### 0.4 Bloc conventions

All of the following comes from the `bloc` skill. Read `.claude/skills/bloc/SKILL.md` before writing code.

- Use `Cubit` for simple state; use `Bloc` when there is an explicit state machine or multiple event sources
- **Blocs must not depend on each other**; bridge them with a `BlocListener` at the app layer
- **Events use `sealed class`**, and so do multi-state types, enabling exhaustive Dart 3 `switch` matching
- Every state and event `extends Equatable` and overrides `props`
- Single-class state shapes must provide `copyWith`
- Every state carries a `status` enum (`initial` / `loading` / `success` / `failure`) rather than a `bool loading` + `String? error` pair
- **Event naming = `BlocSubject` + `Noun` + `VerbPastTense`**, e.g. `TodoListSubscriptionRequested`, `AppUpdateManualCheckRequested`. Shorthand names such as `ThreadSelected` in the steps below must be expanded with their bloc subject (→ `ProjectThreadsThreadSelected`)
- Business logic lives only in the Bloc/Cubit — never in widgets, pages, or views
- Use `context.read` in callbacks and `context.watch` or `BlocBuilder` in `build`; **never use `context.watch` outside `build`**

#### Page / View separation (mandatory)

The `bloc` skill requires each feature's UI to split into two files:

```
lib/<feature>/
├── <feature>.dart          # barrel
├── bloc/                   # or cubit/
│   ├── <feature>_bloc.dart
│   ├── <feature>_event.dart
│   └── <feature>_state.dart
└── view/
    ├── <feature>_page.dart # only creates and provides the Bloc
    └── <feature>_view.dart # only consumes state via BlocBuilder / BlocListener
```

**The Page provides the Bloc; the View consumes state.** Wherever steps P5–P7 below say "view", this is the structure to build.

### 0.5 Definition of done, per step

A step may be checked off only when all of the following hold:

- [ ] **The §0.7 skill mapping was consulted before starting**, and the implementation follows the skill
- [ ] Code migration complete
- [ ] Corresponding tests migrated and gaps filled
- [ ] All four quality gates green (analyze / format / test / coverage)
- [ ] No new cross-layer dependency introduced (the P0 step 6 layer check passes)
- [ ] **The corresponding documentation is updated in both languages** (mapping in §0.6)

**Quality gates run through MCP tools, never Bash** (mandated by the `green-gate` skill; the Bash test path is intercepted by the `block-cli-workarounds.sh` hook):

| Gate | Tool |
| --- | --- |
| analyze | `mcp__dart__analyze_files` (`applyFixes: true`) |
| format | `mcp__dart__dart_format` |
| test + coverage | `mcp__very-good-cli__test`, passing **`coverage: true` + `min_coverage: 100` + `check_ignore: true` together** |

> Omit any one of the three and the gate silently stops working: without `coverage: true` no `lcov.info` is produced; without `check_ignore: true` the `// coverage:ignore` remedy becomes a no-op.
>
> For a single package, pass `directory` (e.g. `directory: 'packages/agent_provider_api'`) and `timeout_seconds` (Flutter tests hang indefinitely on a `pumpAndSettle()` without a timeout).

### 0.6 Documentation convention

#### Directory structure

Mirrors the legacy repository's `docs/` organization:

```
docs/
├── architecture/   Overview, layering design, engineering standards, migration docs
├── guides/         Developer guide, glossary, internationalization guide
├── product/        Product requirements, troubleshooting and data reference
├── protocols/      Provider protocol pinning and adapter designs
├── release/        Release process
├── history/        Retired capabilities and development log, archive only
└── images/         Screenshots and capture checklist
```

#### Bilingual rules

**The legacy repository translated only 5 files; this repository requires full bilingual coverage.**

| Item | Convention |
| --- | --- |
| File naming | `xxx.md` (Chinese) + `xxx.en.md` (English) |
| Chinese header | `中文 ｜ [English](./xxx.en.md)`, one blank line below the H1 |
| English header | `[中文](./xxx.md) ｜ English`, same placement |
| Cross-links | Chinese documents link to Chinese, English to English; index entries carry a link to the other language |
| Index | A new document must be registered in both `docs/README.md` and `docs/README.en.md` |
| Commit granularity | **Both language versions ship in the same commit**; never Chinese first and English later |

> Terminology consistency: class names, package names, method names, and enum values stay in English verbatim in both versions. Keep table and code-block structure aligned so the two versions diff cleanly.

#### Step-to-document mapping

Every migration step updates at least one document. One checkbox per language.

| Step | Target document | ZH | EN |
| --- | --- | :-: | :-: |
| **0 Cursor retirement** | `history/cursor_retirement` — **new**, archive note (written in the **legacy repo**) | ☐ | ☐ |
| 1 Platform matrix | `guides/developer_guide` — environment and build commands | ☐ | ☐ |
| 2 Monorepo skeleton | `architecture/overview` — package structure<br>`guides/developer_guide` — melos commands | ☐ | ☐ |
| 3 l10n baseline | `guides/internationalization` — **new** | ☐ | ☐ |
| 4 CI wiring | `architecture/engineering_standards` — CI gates | ☐ | ☐ |
| 5 Foundation packages | `architecture/overview` — L0 layer | ☐ | ☐ |
| 6 Layer dependency check | `architecture/engineering_standards` — layering rules and registered exceptions | ☐ | ☐ |
| 7 `agent_provider_api` | `architecture/layering` — **new**, Data layer contracts<br>`guides/glossary` — the 21 ports and capability terms | ☐ | ☐ |
| 8 `json_rpc_transport` | `protocols/` — transport layer and exception family | ☐ | ☐ |
| 9 Three provider clients | `protocols/codex_app_server_protocol`<br>`protocols/claude_code_stream_json_protocol`<br>`protocols/grok_acp_protocol` — **new** | ☐ | ☐ |
| 10 `agent_history_client` | `protocols/` — local history format and tolerant parsing | ☐ | ☐ |
| 11 Tests and fixtures | `guides/developer_guide` — testing rules and fixture organization | ☐ | ☐ |
| 12 `agent_conversation_repository` | `architecture/design_document` — event pipeline and session orchestration<br>`architecture/layering` — **the ChangeNotifier→Stream conversion technique** | ☐ | ☐ |
| 13 `agent_provider_repository` | `architecture/design_document` — provider config and catalogs; the one-way edge between the two repositories | ☐ | ☐ |
| 14 settings + workspace + session repos | `architecture/layering` — Repository layer responsibilities | ☐ | ☐ |
| 15 `usage_statistics_repository` | `architecture/design_document` — usage aggregation | ☐ | ☐ |
| 16 `app_ui` | `guides/developer_guide` — UI package usage and component list<br>`guides/internationalization` — string-passing for shared widgets | ☐ | ☐ |
| 17 `app_ui` tests | `guides/developer_guide` — widget testing conventions | ☐ | ☐ |
| 18 `workspace` bloc | `architecture/layering` — Cubit pattern example | ☐ | ☐ |
| 19 `settings` bloc | `architecture/layering` — reverse-edge handling technique | ☐ | ☐ |
| 20 `app_update` bloc | `architecture/layering` — Bloc state machine example | ☐ | ☐ |
| 21 `desktop_notifications` bloc | `architecture/engineering_standards` — **registered layering exception** | ☐ | ☐ |
| 22 threads + session blocs | `architecture/design_document` — two blocs sharing one repository | ☐ | ☐ |
| 23 `agent_management` bloc | `architecture/design_document` — CLI detection and diagnostics | ☐ | ☐ |
| 24 `usage_statistics` bloc | `architecture/design_document` — splitting the two state sets | ☐ | ☐ |
| 25 `AgentConversationBloc` | `architecture/overview` — the full event pipeline<br>`guides/glossary` — the 5 state slices | ☐ | ☐ |
| 26 Presentation widgets | `guides/developer_guide` — `BlocSelector` subscription granularity | ☐ | ☐ |
| 27 Capability rendering tests | `architecture/overview` — capability negotiation and fail-closed | ☐ | ☐ |
| 28 `ide_shell` | `architecture/design_document` — the three-pane workbench | ☐ | ☐ |
| 29 Wiring layer | `architecture/layering` — **injection and bloc scope diagram** | ☐ | ☐ |
| 30 l10n wrap-up | `guides/internationalization` — typed code → ARB mapping, locale freezing | ☐ | ☐ |
| 31 Three flavors | `release/release_guide` — **new**, flavors and build artifacts | ☐ | ☐ |
| 32 Data migration verification | `product/troubleshooting` — **new**, what lives in `~/.zeta`, reset | ☐ | ☐ |
| 33 Documentation wrap-up | Final review of all documents + `docs/README` index audit | ☐ | ☐ |

#### Documentation debt during migration

These are already registered in `docs/README.md` and must be filled in at the listed step:

- [ ] `architecture/overview.md` + `.en.md` — drafted at step 2, finalized at step 27
- [ ] `architecture/layering.md` + `.en.md` — drafted at step 7, finalized at step 29
- [ ] `architecture/engineering_standards.md` + `.en.md` — drafted at step 4
- [ ] `architecture/design_document.md` + `.en.md` — drafted at step 12, finalized at step 28
- [ ] `guides/developer_guide.md` + `.en.md` — drafted at step 1
- [ ] `guides/glossary.md` + `.en.md` — drafted at step 7
- [ ] `guides/internationalization.md` + `.en.md` — drafted at step 3
- [ ] `product/product_requirements.md` + `.en.md` — can be migrated directly from the legacy repository
- [x] `.en.md` versions of this file and the topology document

### 0.7 Skills first

The repository carries 15 official VGV skills under `.claude/skills` (a symlink to `.agents/skills/`), 3,864 lines in total.

**Before writing any code, consult the mapping below and implement to the skill's standard.** Where a skill conflicts with this document, the skill wins — unless the conflict is recorded in the deviation register at the end of this section.

#### Skill inventory

| Skill | Lines | Scope |
| --- | --- | --- |
| `layered-architecture` | 403 | Layer responsibilities, package structure, barrels, path dependencies, constructor injection, anti-pattern table |
| `bloc` | 218 | Cubit/Bloc selection, event and state naming, Page/View separation, `BlocSelector` |
| `testing` | 479 | Test organization, private mocks, `pumpApp`, naming conventions, golden tags |
| `green-gate` | 308 | The four quality gates: tools, arguments, order, coverage target |
| `ui-package` | 101 | UI package structure, `ThemeExtension`, barrels, widget API rules |
| `internationalization` | 156 | ARB, `context.l10n`, **string-passing strategy for shared widgets**, RTL |
| `material-theming` | 233 | `ThemeData`, `ColorScheme`, `TextTheme`, component themes |
| `static-security` | 327 | Secrets, user data, network communication, input validation, dependency vulnerabilities |
| `accessibility` | 318 | WCAG 2.2 across platforms |
| `animations` | 399 | Implicit/explicit animation, page transitions, Material 3 motion tokens |
| `navigation` | 227 | GoRouter routing, deep links, redirects |
| `create-project` | 101 | Very Good CLI template scaffolding |
| `very-good-analysis-upgrade` | 248 | Lint package upgrades |
| `dart-flutter-sdk-upgrade` | 235 | SDK constraint upgrades |
| `license-compliance` | 111 | Dependency license auditing |

#### Step → skill mapping

| Step | Required skills | Key constraints |
| --- | --- | --- |
| 1 Platform matrix | — | |
| 2 Monorepo skeleton | `layered-architecture`, `create-project` | Scaffold with `mcp__very-good-cli__create`, never by hand; local packages always use `path:`, never `git:` or version refs |
| 3 l10n baseline | `internationalization` | ARB is the single source of truth; `context.l10n` extension; **shared widgets take strings as parameters rather than depending on `AppLocalizations`** |
| 4 CI wiring | `green-gate` | The four gates' tools and arguments, see §0.5 |
| 5 Foundation packages | `layered-architecture` | `create dart_package`; barrel exports; `lib/src/` private |
| 6 Layer dependency check | `layered-architecture` | The 8 rows of the anti-pattern table are the check items |
| 7 `agent_provider_api` | `layered-architecture` | Barrel; no Flutter; **see deviation D1** |
| 8 `json_rpc_transport` | `layered-architecture`, `static-security` | Log redaction in the transport layer; exception family |
| 9 Three provider clients | `layered-architecture`, `static-security`, `testing` | Constructor injection; private mocks; no secrets on disk |
| 10 `agent_history_client` | `layered-architecture`, `static-security` | Tolerant parsing; sensitive content never logged |
| 11 Tests and fixtures | `testing` | `_MockX` private mocks; group hierarchy reads as a sentence; `'returns $Type'` interpolation |
| 12 `agent_conversation_repository` | `layered-architecture`, `bloc` | Constructor-inject data clients; convert observer exits to `Stream` (no `flutter/foundation`); domain model transformation |
| 13 `agent_provider_repository` | `layered-architecture` | One repository per domain; **no reverse dependency on the conversation package** |
| 14 settings + workspace + session repos | `layered-architecture` | One repository per domain |
| 14 `project_session_repository` | `layered-architecture` | Same |
| 15 `usage_statistics_repository` | `layered-architecture` | Same |
| 16 `app_ui` | `ui-package`, `material-theming`, `internationalization`, `accessibility` | Barrel with private `lib/src/`; one widget per file; tokens via `ThemeExtension`; `const` constructors; dartdoc on every public member; **see deviations D2, D3** |
| 17 `app_ui` tests | `testing`, `ui-package` | A widget test per component; use the package's own `pumpApp`, never an inline `MaterialApp` |
| 18–24 Feature blocs | `bloc`, `testing` | `sealed` events; `Equatable` states with `copyWith`; **Page/View separation**; `blocTest()`; `mocktail` |
| 25 `AgentConversationBloc` | `bloc`, `testing`, `static-security` | The above plus negative cases for approval-semantics isolation |
| 26 Presentation widgets | `bloc`, `accessibility`, `animations` | `BlocSelector` subscribes per slice; semantic labels; transitions use Material 3 motion tokens |
| 27 Capability rendering tests | `testing` | Widget tests assert the entry point does not appear |
| 28 `ide_shell` | `bloc`, `navigation` | Page/View separation; if GoRouter is introduced, follow the `navigation` skill |
| 29 Wiring layer | `layered-architecture`, `bloc` | `main_<flavor>.dart` creates clients and repositories and injects them; `MultiRepositoryProvider` |
| 30 l10n wrap-up | `internationalization` | Delegate composition; locale freezing |
| 31 Three flavors | `layered-architecture` | Flavors change configuration only; the architecture is identical |
| 32 Data migration verification | `static-security` | No sensitive content persisted |
| 33 Cursor retirement | — | |
| 34 Documentation wrap-up | `license-compliance` | Run a dependency license audit while wrapping up |

#### Package internals (enforced by `layered-architecture`)

Every `packages/*` follows:

```
packages/<name>/
├── lib/
│   ├── <name>.dart          # barrel — the only thing consumers import
│   └── src/                 # private; never imported directly from outside
│       ├── <name>.dart
│       └── models/
│           ├── models.dart  # sub-barrel
│           └── ...
├── test/                    # mirrors lib/
└── pubspec.yaml             # local packages via path: dependencies
```

- [ ] Scaffold every package with `mcp__very-good-cli__create`'s `create dart_package`, never by hand
- [ ] Repositories receive data clients by **constructor injection**, never instantiating them internally
- [ ] The app's `pubspec.yaml` **depends only on repository packages**; data packages are transitive

#### Deviation register

These three knowingly depart from a skill for confirmed reasons. **Do not "correct" them back to the skill's form without discussion.**

**D1 — Domain entities live in a shared contract package in the Data layer**

- Skill position: the `layered-architecture` anti-pattern table lists "Domain models in data layer"; domain models belong in the repository package, data packages hold only response models matching the external shape
- What this project does: roughly 190 neutral domain entities live in `packages/agent_provider_api`
- Rationale: Zeta has **three vendor clients that must all produce the same neutral types**. Putting the entities in the repository layer would force all three clients to depend on the repository, inverting the layer. The skill's model assumes "one data package wraps one external source with its own response models" and does not cover "many sources normalized onto one contract"
- Compensation: `agent_provider_api` contains no vendor fields and no business rules — only contracts and immutable entities. The leakage the anti-pattern actually guards against (external API shape bleeding into the domain) does not occur here
- Review trigger: if only a single provider remains, revert to the skill's standard form

**D2 — `app_ui` is built on shadcn_flutter rather than Material**

- Skill position: `ui-package` requires the `app_ui_package` template, building on `flutter/material.dart`, with the barrel re-exporting `material.dart`
- What this project does: keeps shadcn_flutter and the legacy repository's 49 `Ide*` components
- Rationale: **an explicit user decision** (one of the four migration premises). Swapping the foundation would mean rebuilding 49 components plus every call site, with no way to verify the visual regression automatically
- Skill clauses that still apply: barrel exports, private `lib/src/`, one widget per file, a consistent `Ide*` prefix, tokens via `ThemeExtension`, `const` constructors, dartdoc on public members, a widget test per component, the package's own `pumpApp`

**D3 — l10n converges to a single path (here the skill corrected the original design)**

The original design carried **two parallel localization mechanisms**, violating "if you refactor, refactor completely": an `app_ui`-owned 118-key ARB, plus the TextCatalog abstraction injecting already-localized strings downward. Two skill rules reject both at once:

> Pass localized strings as parameters to reusable widgets — never couple shared widgets directly to `AppLocalizations`
>
> ARB files are the single source of truth

**Revised: the project has exactly one localization path — ARB is the single source of truth, and the app layer is the single localization point.**

| Case | Original design | Revised |
| --- | --- | --- |
| `app_ui` shared widget copy | Its own 118-key ARB | **Constructor parameters**; zero l10n dependency in the package |
| data / repository layer copy | TextCatalog injects localized strings | **Returns `sealed` typed codes**; the app layer `switch`es them onto ARB |
| `Fallback*` hardcoded copy | 395 lines, parallel to ARB | **Withdrawn**; copy folds into ARB |
| shadcn localization | Migrated into `app_ui` | Stays in the app's `lib/l10n/` |

Benefits: no ARB split (all 1,072 keys stay in the app); `app_ui` and every `packages/` entry are reusable without Flutter; `sealed` + exhaustive `switch` turns a new failure type into a compile error, so no translation is missed.

Cost: four interfaces and an 866-line bridge are deleted; 60+ consumption points switch to emitting/receiving typed codes. Spread across P1 (contracts), P3 (repositories), P5–P7 (UI mapping).

Frozen into a check: **no package under `packages/` may reference `AppLocalizations` or emit user-visible strings.**

---

## Step 0 · Cursor retirement, done in the legacy repository

**A precondition for the migration, belonging to no P phase. Do not enter P0 until the exit condition holds.**

The original design put Cursor retirement in P7, but its 5 call sites migrate one by one across P2 / P3 / P5 — meaning the whole migration would carry deprecated code, which is exactly "old and new logic coexisting". **Move the whole thing up into the legacy repository and clear it in one pass.**

The Cursor compatibility code is not dead code; it is the filter layer for existing users' persisted configuration. **The order cannot be reversed.**

#### 1. Data cleanup first

- [ ] Add a one-time migration to the legacy repository's `zeta_storage_migrator`
- [ ] Physically remove cursor entries from persisted provider configuration
- [ ] Rewrite `activeProviderId` to the default provider when it points at cursor
- [ ] Delete or archive `cursor_sessions.json`

#### 2. Then delete the compatibility layer (11 sites)

- [ ] `agent/domain/cursor_retirement_policy.dart` (122 lines)
- [ ] The re-export at `agent/domain/agent_models.dart:8`
- [ ] `agent/data/agent_provider_config_codec.dart:52`
- [ ] `agent/data/default_agent_provider_factory.dart:37,39,52`
- [ ] `agent/data/agent_provider_static_capabilities.dart:92`
- [ ] `agent/application/agent_provider_settings_controller.dart` (8 sites)
- [ ] `agent/application/agent_turn_context_recorder.dart:7,92`
- [ ] `agent_management/application/agent_management_controller.dart:792`
- [ ] `ui/features/ide/views/new_thread_provider_popover.dart:39`
- [ ] `cursorSessionsFile` in `core/storage/zeta_data_paths.dart:86-88`
- [ ] l10n: 8 `cursorRetired` strings each in zh / en
- [ ] **Keep** the `AgentProviderKind.cursorAcp` enum value, or add an unknown-value fallback in `fromJson` — otherwise legacy configuration deserialization throws (G7 tolerant decoding). This fallback migrates into `agent_provider_api` with the contracts

#### 3. Regression check

- [ ] Upgrade a real legacy configuration containing cursor entries: no crash, no cursor in the menu, correct active-provider fallback
- [ ] Legacy repository clean under `flutter analyze`
- [ ] Legacy repository full test suite green

**Exit condition**: all three green. Once met, the legacy repository enters freeze (§5.2) and P0 begins.

---

## P0 · Engineering foundation

### Step 1 — Platform matrix

Desktop only.

- [ ] `flutter create --platforms=linux .` to add `linux/`
- [ ] Delete `android/`, `ios/`, `web/`
- [ ] Correct `pubspec.yaml`: drop mobile-only dependency placeholders
- [ ] Run `flutter build` once per platform to confirm the scaffold compiles

### Step 2 — Monorepo skeleton

- [ ] Introduce melos or a Dart workspace; declare workspace members in the root `pubspec.yaml`
- [ ] Create the `packages/` directory
- [ ] Unify `analysis_options.yaml`: root config includes `package:very_good_analysis/analysis_options.yaml`, each package inherits the root
- [ ] Unify SDK constraints across packages (`sdk: ^3.12.0` / `flutter: ^3.44.0`)

### Step 3 — l10n baseline

See topology document §2.5. ARB is pure data with no code dependencies; migrating it early lets every later phase reference key names directly.

- [ ] Write the merged `l10n.yaml` (keep `header:`, adopt `required-resource-attributes` / `use-escaping`, drop `format: true`)
- [ ] Delete `lib/l10n/arb/app_es.arb`
- [ ] Migrate all 1,072 keys from the legacy `app_en.arb` / `app_zh.arb` (**all stay in the app, no split** — see §0.7 deviation D3)
- [ ] Reserve ARB keys for the `sealed` failure types replacing TextCatalog (filled in during P3)
- [ ] Migrate the `l10n.dart` extension with both the `l10n` and `l10nOrNull` getters
- [ ] `flutter gen-l10n` succeeds; generated files carry `// coverage:ignore-file`
- [ ] Establish the constraint: **no package under `packages/` may reference `AppLocalizations`**; shared widget strings are always constructor parameters

### Step 4 — CI wiring

- [ ] `very_good test --coverage --min-coverage 100`
- [ ] `bloc_lint`
- [ ] `dart format --set-exit-if-changed`
- [ ] `flutter analyze --fatal-infos`
- [ ] melos script: one command runs every package

### Step 5 — Foundation packages

**`packages/zeta_logging`** (493 lines)

- Data layer: no external data source; a pure utility package
- Migrates: `app_logging.dart` (structured logging), `structured_error_logging.dart`, `sensitive_data_redactor.dart`

- [ ] Create the package; `pubspec.yaml` depends only on `logger`
- [ ] Migrate `AppLogging` / structured error logging
- [ ] Migrate `SensitiveDataRedactor` (39 lines) — **every logging exit must pass through it**
- [ ] Migrate `test/src/core/logging/`; fill gaps to 100%

**`packages/zeta_storage`** (268 lines)

- Data layer: `AtomicTextFile` (atomic writes), `ZetaDataPaths` (data path resolution), `PathUtils`, `SystemFileManager`
- **The only low-level package in the project allowed to do file IO directly**

- [ ] Create the package; depends on `zeta_logging`
- [ ] Migrate `AtomicTextFile`, `ZetaDataPaths`, `PathUtils`, `SystemFileManager`
- [ ] Define the exception family: `sealed class StorageException` → `StorageWriteException` / `StorageReadException` / `StoragePathException`
- [ ] Migrate `test/src/core/storage/`; fill gaps to 100%

### Step 6 — Layer dependency check

One test walks every package's `pubspec.yaml` and turns the VGV layering rules into a CI gate.

- [ ] `*_api` packages depend on no `*_repository` or `*_client`
- [ ] `*_client` packages do not depend on each other (`codex` / `claude_code` / `grok` fully isolated)
- [ ] `*_repository` packages do not depend on `flutter` (exception in step 21)
- [ ] `app_ui` depends on no `*_repository`
- [ ] Snapshot the count of `import 'dart:io'` under the app's `lib/` — **establish the baseline; it must be 0 by the end of P3**

---

## P1 · Data layer contracts

### Step 7 — `packages/agent_provider_api`

6,148 lines, 33 files, roughly 190 public types. **The semantic hub of the project.**

#### Data layer: abstract interfaces

Migrate the 21 capability ports of `AgentProviderBundle` as-is. Two required, nineteen optional:

| Category | Ports |
| --- | --- |
| **Required** | `AgentRuntimePort`, `AgentConversationPort` |
| Thread management | `AgentThreadCatalogPort`, `AgentThreadSubscriptionPort`, `AgentThreadNamingPort`, `AgentThreadArchivalPort`, `AgentThreadDeletionPort`, `AgentThreadCompactionPort`, `AgentThreadBranchingPort`, `AgentLocalThreadListPort` |
| Interaction write-back | `AgentPermissionResponsePort`, `AgentQuestionResponsePort`, `AgentDeniedActionOverridePort`, `AgentPlanApprovalPort`, `AgentTurnSteeringPort` |
| Catalog queries | `AgentModelCatalogPort`, `AgentConversationModeCatalogPort`, `AgentSkillsPort` |
| Configuration | `AgentSessionConfigurationPort`, `AgentPermissionPolicyPort`, `AgentUsageQuotaProvider` |

Plus the factory interface `AgentProviderBundleFactory`.

#### Immutable entities, by theme

| Theme | Key entities |
| --- | --- |
| Events | The `AgentEvent` family (827 lines): `AgentTurnStartedEvent`, `AgentTurnCompletedEvent`, `AgentToolCallEvent`, `AgentTokenUsageEvent`, `AgentStatusEvent`, `AgentSystemItemEvent`, the `AgentThread*Event` series |
| Session | `AgentSession`, `AgentTurn`, `AgentContext`, `AgentTurnConfiguration`, `AgentTurnModelConfig` |
| Thread | `AgentThreadSummary`, `AgentThreadPage`, `AgentThreadListQuery`, `AgentThreadHistorySnapshot`, `AgentThreadTurnContext` |
| Tools | `AgentToolCall`, `AgentToolKind`, `AgentToolStatus` |
| File changes | `AgentTextReplacementEvidence`, `AgentWrittenContentEvidence`, `AgentUnifiedPatchEvidence`, `AgentFileChangeKind`, `AgentFileChangeReplayability` |
| Permissions | `AgentPermissionRequestSnapshot`, `AgentPermissionDecision`, `AgentPermissionKind`, `AgentPermissionApplyScope`, `AgentPermissionRequestSource` |
| Plans | `AgentPlanApprovalDecision`, `AgentPlanEntryStatus`, `AgentPlanApprovalContinuation`, `AgentPlanExecutionPermissionOrigin` |
| Usage | `AgentTokenUsage`, `AgentUsageQuotaSnapshot`, `AgentUsageWindow`, `AgentUsageCredits` |
| Capabilities | `AgentProviderCapabilities`, `AgentProviderKind`, `AgentProviderLifecycleState`, `AgentRuntimeCompatibilityStatus` |
| Input | `AgentUserInput`, `AgentTextUserInput`, `AgentSkillUserInput`, `AgentUserInputOption` |
| Failure semantics | The `sealed class AgentProviderFailure` family (**new**, replacing the withdrawn TextCatalog): `AgentCliNotFound`, `AgentCapabilityUnsupported`, `AgentTurnRejected` and friends — semantics and parameters only, never copy |

#### Checklist

- [ ] Create the package; `pubspec.yaml` may depend **only** on `meta` / `collection` — never `flutter`
- [ ] Migrate the 21 capability ports and `AgentProviderBundleFactory`
- [ ] Migrate every entity, verifying file by file: no `dart:io`, no Flutter, no vendor fields
- [ ] **`AgentUiTextCatalog` (260 lines) and `FallbackAgentUiTextCatalog` (395 lines) do not migrate** (§0.7 D3); replace with a `sealed class AgentProviderFailure` family carrying semantics and parameters only
- [ ] Fold the 395 lines of `FallbackAgentUiTextCatalog` copy into the app's ARB line by line; record the mapping table for verification at P7 step 30
- [ ] **Do not migrate** `cursor_retirement_policy.dart` (retired at P7 step 33)
- [ ] Verify the package runs under plain `dart test` with no `flutter_test`
- [ ] Migrate `test/src/features/agent/domain/`; fill gaps to 100%

### Step 8 — `packages/json_rpc_transport`

1,299 lines.

- Data layer: `JsonRpcStdioTransport` (stdio transport), `ProviderOperationScheduler` (operation scheduling), `ProviderRuntimeJsonRpcPeer` (peer lifecycle)
- Exceptions: `sealed class TransportException` → `TransportClosedException` / `TransportTimeoutException` / `TransportProtocolException`

- [ ] Create the package; depends on `zeta_logging` (for log redaction)
- [ ] Migrate the three transport files
- [ ] Define the `TransportException` family, replacing bare `throw`s
- [ ] Migrate `test/src/features/agent/data/datasources/transport/`; fill gaps to 100%

---

## P2 · Data layer implementations

The three client packages **can run in parallel** and do not depend on each other. Each has the same shape: a `<Vendor>AgentProviderBundle` implementing a subset of `AgentProviderBundle`'s ports, with mappers translating protocol fields into neutral entities.

### Step 9 — The three provider clients

#### `packages/codex_app_server_client` (≈6.3k lines)

| Role | Class |
| --- | --- |
| Bundle implementation | `CodexAppServerAgentProvider` (1,253 lines) |
| Transport client | `CodexAppServerClient` |
| Mappers | `CodexNotificationMapper` (983), `CodexAppServerHelpers` (1,447), `CodexApprovalMapper`, `CodexQuestionMapper`, `CodexModelListMapper`, `CodexSkillsMapper`, `CodexFileChangeTracker`, `CodexCollaborationModeMapper`, `CodexTurnStartParamsEncoder` |
| Codecs | `CodexConversationModeCodec`, `CodexPermissionPolicyCodec`, `ContextWindowCodec` |
| CLI locator | `CodexCliLocator` |

#### `packages/claude_code_client` (≈7.4k lines)

| Role | Class |
| --- | --- |
| Bundle implementation | `ClaudeCodeAgentProvider` (1,391 lines) |
| Session history | `ClaudeCodeSessionHistoryReader` (1,242 lines) |
| Adapters | `ClaudeCodeControlRequestHandler`, `ClaudeCodeEventMapper`, `ClaudeCodePermissionPolicyAdapter`, `ClaudeCodePlanApprovalAdapter`, `ClaudeCodeUsageQuotaAdapter` |
| Mappers | `ClaudeCodeInitializeMetadataMapper`, `ClaudeCodeUsageQuotaMapper`, `ClaudeCodeStreamIdentity` |
| Codecs | `ClaudeCodePermissionModeCodec` |
| CLI locator | `ClaudeCodeCliLocator` |

#### `packages/grok_acp_client` (≈6.5k lines)

| Role | Class |
| --- | --- |
| Bundle implementation | `GrokAcpAgentProvider` (2,574 lines) |
| Shared ACP | `AcpContentCodec`, `AcpPermissionMapper`, `AcpSessionConfigMapper`, `AcpSessionUpdateDecoder` |
| Mappers | `GrokAcpNotificationMapper`, `GrokSessionUpdateMapper`, `GrokBillingQuotaMapper`, `GrokQuestionMapper`, `GrokSkillsMapper`, `GrokFileChangeTracker`, `GrokStreamIdentity`, `GrokErrorNormalizer` |
| Codecs | `GrokPermissionModeCodec` |
| CLI locator | `GrokCliLocator` |

> ACP mappers live in the grok package for now (its only consumer). Extract `acp_shared` when a second ACP provider appears.

#### Checklist (repeat per package)

- [ ] Create the package; depends **only** on `agent_provider_api` + `json_rpc_transport` + `zeta_logging` + `zeta_storage`
- [ ] `pubspec.yaml` does not reference the other two client packages
- [ ] Migrate the bundle implementation, filling optional ports according to capability — **an unsupported capability is null and its `capabilities` flag returns false**
- [ ] Migrate every mapper and codec
- [ ] Migrate the CLI locator
- [ ] Route protocol exceptions through a normalization exit like `GrokErrorNormalizer` (add the equivalent for the other two vendors)
- [ ] **Contract tests**: assert that entryId ownership, message segmentation, deduplication, and terminal-state determination are decided by this client (`sourceItemId` is only metadata)

### Step 10 — `packages/agent_history_client`

3,085 lines, local session history reading.

| Role | Class |
| --- | --- |
| Codex | `CodexJsonlHistoryParser`, `CodexThreadHistoryReader` |
| Grok | `GrokUpdatesHistoryParser` |

- [ ] Create the package; depends on `agent_provider_api` + `zeta_storage`
- [ ] Migrate the three parsers / readers
- [ ] Exceptions: `HistoryParseException` carrying file path and line number for locating bad data
- [ ] **Tolerant parsing**: a failed line is skipped and logged rather than failing the whole read

### Step 11 — Tests and fixtures

- [ ] Migrate `test/src/features/agent/data/datasources/{acp,app_server,claude_code,local_history}/`
- [ ] Migrate `test/src/features/agent/data/mappers/`
- [ ] Migrate `test/fixtures/` (`agent_file_change_evidence`, `agent_stream_identity`, `grok/acp`, `grok/local_history`)
- [ ] Fill each package to 100%

**P2 acceptance gate**: the three clients' `pubspec.yaml` files do not reference each other; contract tests green.

---

## P3 · Repository layer

**This phase is the second-largest refactor in the project** (after P6). Three cross-cutting conversions happen at once:

| Conversion | Scale | Objective metric |
| --- | --- | --- |
| `dart:io` sinks into the Data layer | 60+ files | `dart:io` imports on the app side → **0** |
| **Observer mechanism `ChangeNotifier` → `Stream`** | **10,730 lines / 29 files** | `ChangeNotifier` / `ValueNotifier` in repository packages → **0** |
| **TextCatalog withdrawn in favor of typed codes** | 4 interfaces + 866-line bridge + 60+ call sites | `AppLocalizations` references under `packages/` → **0** |

#### Cross-cutting conversion 1: observer mechanism

Every observer exit in the legacy code comes from `package:flutter/foundation.dart`, in hard conflict with "repository packages do not depend on Flutter" — and keeping it would leave ChangeNotifier and Bloc as two parallel state mechanisms.

The uniform conversion:

```dart
// Before
class XxxController extends ChangeNotifier {
  Xxx get value => _value;
  void _update(Xxx next) { _value = next; notifyListeners(); }
}

// After — pure Dart, no Flutter
class XxxController {
  final _controller = StreamController<Xxx>.broadcast();
  Stream<Xxx> get changes => _controller.stream;
  Xxx get value => _value;                       // synchronous snapshot retained
  void _update(Xxx next) { _value = next; _controller.add(next); }
  Future<void> dispose() => _controller.close();
}
```

- [ ] `broadcast` streams (multiple subscribers), and **always expose a synchronous snapshot getter** — a bloc needs the current value at construction and cannot rely on the stream alone
- [ ] Every `StreamController` has a matching `close()`, called from the repository's `dispose()`
- [ ] Subscribers hold their `StreamSubscription` and cancel it on close — **a leaked subscription shows up in P6 as phantom UI rebuilds**
- [ ] Behavioral equivalence: first get the Stream-equivalent of each old assertion passing, **then** add Stream-specific cases (multiple subscribers, late subscription, no delivery after cancel)

#### Cross-cutting conversion 2: TextCatalog → typed codes

- [ ] Failure paths in each repository return or throw `sealed` failure types (see the exception families below)
- [ ] `Fallback*` hardcoded copy folds into ARB; record the mapping table for verification at P7 step 30
- [ ] The four interfaces and the 866-line bridge are deleted with no references left in the repository

---

### Step 12 — `packages/agent_conversation_repository` (≈10k lines)

The rationale and boundary for the split are in topology §2.2. This package owns **the lifecycle of one conversation**.

#### Internal composition

**Event pipeline** (5,349 lines, purely synchronous)

`AgentEventPipeline` → `CoalescingEventBuffer` → `BoundedEventDispatcher` → `AgentConversationEventProcessor` → `AgentConversationReducer` → `AgentConversationTimelineStore` → `AgentConversationEffectRunner`

**Session orchestration** (≈4.7k lines)

`AgentConversationBinding`, `AgentConversationBindingManager`, `AgentProviderRuntimeRegistry`, `AgentProviderGlobalRuntime`, `AgentThreadWorkspaceController`, `AgentPlanExecutionHandoffController`, `AgentTurnContextRecorder` / `AgentTurnContextOverlay`

> ⚠️ **7,446 lines across these two parts depend on `flutter/foundation`**, including `agent_conversation_timeline_store.dart` (2,017 lines). **This is not pure relocation** — every observer exit must be rewritten per cross-cutting conversion 1 above.

#### Public interface design

**Pure-Dart interfaces only; the bloc never sees JSON-RPC, processes, or files.**

```dart
abstract interface class AgentConversationRepository {
  // Session lifecycle
  Stream<AgentTimelineSnapshot> timelineFor(AgentConversationKey key);
  AgentTimelineSnapshot snapshotFor(AgentConversationKey key);   // sync snapshot for bloc init
  Future<void> openThread(AgentConversationKey key, {String? threadId});
  Future<void> closeConversation(AgentConversationKey key);

  // Turns
  Future<void> submitTurn(AgentConversationKey key, AgentTurnRequest request);
  Future<void> steerTurn(AgentConversationKey key, AgentTurnRequest request);
  Future<void> cancelActiveTurn(AgentConversationKey key);

  // Four approval semantics — strictly isolated, each its own method
  Future<void> respondToPermission(AgentConversationKey key, AgentPermissionDecision d);
  Future<void> respondToQuestion(AgentConversationKey key, AgentQuestionResponse r);
  Future<void> respondToPlanApproval(AgentConversationKey key, AgentPlanApprovalDecision d);
  Future<void> startPlanExecution(AgentConversationKey key, AgentPlanExecutionRequest r);

  // Thread operations (throw AgentCapabilityUnsupportedException when unsupported)
  Future<void> renameThread(String threadId, String name);
  Future<void> archiveThread(String threadId);
  Future<void> compactThread(String threadId);
  Future<AgentSession> forkThread(String threadId, AgentForkBoundary boundary);
}
```

> Catalog queries (`listModels` / `listConversationModes` / `listSkills`) are **not in this package** — they belong to `agent_provider_repository` (step 13).

#### Exception family

```dart
sealed class AgentRepositoryException implements Exception { ... }

final class AgentProviderUnavailableException extends AgentRepositoryException {}
final class AgentCapabilityUnsupportedException extends AgentRepositoryException {}
final class AgentTurnRejectedException extends AgentRepositoryException {}
final class AgentThreadNotFoundException extends AgentRepositoryException {}
final class AgentPermissionResponseRejectedException extends AgentRepositoryException {}
final class AgentConfigPersistenceException extends AgentRepositoryException {}
```

Translation points: `TransportException` / `ProcessException` / `FileSystemException` → the domain exceptions above, preserving cause and stack trace.

#### Checklist

- [ ] Create with `create dart_package`; `pubspec.yaml` **must not depend on flutter**
- [ ] Migrate the 14 event pipeline files; **do not touch Bloc in this phase**, but rewrite observer exits per cross-cutting conversion 1
- [ ] Migrate session orchestration (binding / binding_manager / registry / global runtime / workspace controller / turn context)
- [ ] Define the `AgentConversationRepository` interface and default implementation, including the **synchronous snapshot getter**
- [ ] Define the exception family and apply translation at every client call site
- [ ] **live / history / replay each use their own reducer instance** — sharing one cross-contaminates
- [ ] Verify zero occurrences of `ChangeNotifier` / `ValueNotifier` in the package
- [ ] Migrate the pipeline and session parts of `test/src/features/agent/application/`; fill gaps to 100%

### Step 13 — `packages/agent_provider_repository` (≈3.8k lines)

Provider **configuration and catalogs**, unrelated to conversation lifecycle. Consumed by `agent_conversation_repository`, `settings`, and `agent_management` — empirical evidence that it must be its own package.

#### Internal composition

**Provider assembly** (1,944 lines): `DefaultAgentProviderFactory`, `NativeAgentProviderBundles`, `CliCommandLocator`, `CodexCliLocator` / `ClaudeCodeCliLocator` / `GrokCliLocator`, `AgentProviderConfigStore` / `Codec`, `AgentProviderStaticCapabilities`, `AgentModelCatalogCacheStore`, `AgentTurnContextStore`, `AgentIgnoredMessageLogger`

**Catalog and configuration controllers** (≈1.9k lines): `AgentConversationModelSelectionController`, `AgentConversationPermissionSelectionController`, `AgentConversationModeController`, `AgentSkillsCatalogController`, `AgentModelCatalogRepository`, `AgentPermissionCatalogController`, `AgentProviderSettingsController`

#### Public interface design

```dart
abstract interface class AgentProviderRepository {
  // Provider configuration
  Stream<List<AgentProviderConfig>> get configChanges;
  List<AgentProviderConfig> get configs;                        // sync snapshot
  Future<void> setProviderEnabled(String providerId, {required bool enabled});
  Future<AgentProviderBundle> bundleFor(String providerId);

  // Catalog queries (throw AgentCapabilityUnsupportedException when unsupported)
  Future<AgentModelList> listModels(String providerId, {bool forceRefresh = false});
  Future<AgentConversationModeCatalog> listConversationModes(String providerId);
  Future<AgentSkillsCatalog> listSkills(String providerId, {List<String> cwds});
  Future<AgentPermissionCatalog> listPermissionOptions(String providerId);

  // Selection persistence
  Future<void> persistModelSelection(String providerId, AgentModelSelection selection);
  Future<void> persistPermissionPreference(String providerId, AgentPermissionOption option);
}
```

#### Checklist

- [ ] Create with `create dart_package`; **no flutter dependency**, and **no dependency on `agent_conversation_repository`** (the edge is one-way)
- [ ] Migrate provider assembly, CLI locators, stores and codecs
- [ ] Migrate catalog and configuration controllers, converting observer exits to `Stream`
- [ ] **Withdraw `AgentManagementTextCatalog` + fallback** (§0.7 D3): return a `sealed class AgentManagementFailure` instead; fold the fallback copy into ARB
- [ ] Keep the `AgentProviderKind.cursorAcp` unknown-value fallback in `fromJson` (G7 tolerant decoding)
- [ ] Verify zero occurrences of `ChangeNotifier` / `ValueNotifier` in the package
- [ ] Migrate the corresponding tests; fill gaps to 100%

### Step 14 — `settings_repository` + `workspace_repository` + `project_session_repository`

#### `packages/settings_repository` (≈1.2k lines)

- **Data**: `SettingsStorageApi` (abstract) + `FileSettingsStorageClient` (backed by `zeta_storage`); `SystemFontCatalogApi` + `SystemFontCatalogClient`
- **DTO**: `GeneralSettingsCodec`, `AppearanceSettingsStore`
- **Entities**: `GeneralSettings`, `AppearanceSettings`, `AgentNotificationSettings`, `AppearanceFontChoice`, `SystemFontFamily`, `AppLanguage`, `MessageSendShortcut`, `AppearanceFontChoiceKind`
- **Interface**:

```dart
abstract interface class SettingsRepository {
  Future<GeneralSettings> loadGeneral();
  Stream<GeneralSettings> get generalChanges;
  Future<void> setMessageSendShortcut(MessageSendShortcut shortcut);
  Future<GeneralSettingsUpdateResult> setAppLanguage(AppLanguage language);
  Future<void> setNotificationsEnabled({required bool enabled});
  Future<void> setTurnTerminalNotificationsEnabled({required bool enabled});
  Future<void> setActionRequiredNotificationsEnabled({required bool enabled});
  Future<AppearanceSettings> loadAppearance();
  Future<void> setAppearance(AppearanceSettings settings);
  Future<List<SystemFontFamily>> listSystemFonts();
}
```

- **Exceptions**: `SettingsPersistenceException`, `SettingsDecodeException`

> `setAppLanguage` returns `GeneralSettingsUpdateResult` rather than `void` — a language switch has a special consequence (locale freezing, see P7 step 30). Keep that return value.

- [ ] Create with `create dart_package`; no flutter dependency
- [ ] Migrate entities and codecs
- [ ] Convert observer exits to `Stream` (1,031 of this package's 1,333 lines depend on `flutter/foundation`)
- [ ] Move the logic of `GeneralSettingsController` / `AppearanceSettingsController` / `AppLanguageResolver` into the repository
- [ ] Define the interface and exception family
- [ ] Migrate tests; fill gaps to 100%

#### `packages/workspace_repository` (≈0.8k lines)

- **Data**: `WorkspaceFileSystemApi` + `DartIoWorkspaceFileSystemClient`
- **Entities**: `WorkspaceNode`, `WorkspaceNodeType`, `GitignoreMatcher`, `GitignorePattern`, `WorkspaceFileQuery`
- **Interface**:

```dart
abstract interface class WorkspaceRepository {
  Future<List<WorkspaceNode>> indexProject(String root);
  List<WorkspaceNode>? filesFor(String root);
  bool isIndexReady(String root);
  void invalidate(String root);
  Future<List<WorkspaceNode>> buildTree(String root);
  Future<void> revealInSystemFileManager(String path);
}
```

- **Exceptions**: `WorkspaceIndexException`, `WorkspacePathAccessDeniedException`

- [ ] Create with `create dart_package`; no flutter dependency
- [ ] Convert observer exits to `Stream` (272 of 966 lines depend on `flutter/foundation`)
- [ ] Migrate `WorkspaceFileIndexController` / `WorkspaceFileIndexer` / `WorkspaceTreeBuilder`
- [ ] Migrate `GitignoreMatcher` (gitignore semantics need targeted tests)
- [ ] Define the interface and exception family
- [ ] Migrate tests; fill gaps to 100%

#### `packages/project_session_repository` (≈2.1k lines)

**Merges `project_threads` and `ide_session`**, turning the legacy bidirectional cycle into intra-package calls.

- **Data**: `IdeSessionStoreApi` + `FileIdeSessionStoreClient`
- **DTO**: `ProjectThreadsSessionSnapshotCodec`
- **Entities**: `ProjectThreadListState`, `ProjectThreadsSessionSnapshot`, `IdeSessionState`, `IdeWorkbenchLayoutState`, `RecentProjectSummary`
- **Interface**:

```dart
abstract interface class ProjectSessionRepository {
  // Session restore and persistence
  Future<IdeSessionRestoreResult> restore();
  void requestSave(IdeSessionState snapshot);
  Future<void> saveNow(IdeSessionState snapshot);
  void cancelPendingRestore();

  // Thread list
  ProjectThreadListState stateFor(String projectPath);
  Stream<ProjectThreadListState> watchProject(String projectPath);
  Future<void> loadInitial(String projectPath);
  Future<void> loadMore(String projectPath);
  Future<void> setArchivedView(String projectPath, {required bool archived});
  void setSearchTerm(String projectPath, String term);
  Future<void> renameThread(String projectPath, String threadId, String name);
  Future<void> archiveThread(String projectPath, String threadId);
  Future<void> deleteThread(String projectPath, String threadId);
}
```

- **Exceptions**: `SessionRestoreException`, `SessionPersistenceException`, `ThreadListLoadException`

- [ ] Create with `create dart_package`; no flutter dependency
- [ ] **This package has 0 lines depending on Flutter — the only repository that is pure relocation**
- [ ] Migrate `ProjectThreadsController` (1,122 lines), `IdeSessionPersistenceCoordinator`, `IdeSessionStateBuilder`
- [ ] **Dissolve the cycle**: `ProjectThreadsSessionSnapshot` and `IdeSessionState` are now in the same package, so mutual references are legal
- [ ] Define the interface and exception family
- [ ] Migrate tests; fill gaps to 100%

### Step 15 — `packages/usage_statistics_repository` (≈6.5k lines)

- **Data**: `AgentTokenUsageSourceApi` (abstract) plus three implementations
  - `CodexTokenUsageClient` + `CodexUsageLogScanner`
  - `ClaudeCodeTokenUsageClient`
  - `GrokTokenUsageClient` + `GrokUsageLogScanner`
  - `BuiltInAgentTokenUsageSourceRegistry` (registry)
  - `GlobalRuntimeAgentUsageQuotaClient`
- **Entities**: `UsageStatisticsReport`, `UsageOverview`, `UsageTrendPoint`, `UsageTokenBreakdown`, `UsageModelShare`, `UsageProjectRankEntry`, `UsageAgentRankEntry`, `UsageErrorBreakdown`, `UsageMetricComparison`, `UsageDateWindow`, `UsageStatisticsFilter`, `AgentUsageRecord`, `AgentUsageQuery`, `AgentUsageWarning`, `AgentUsagePanelEntry`, `AgentUsageProviderSnapshot`, plus 6 enums
- **Interfaces**:

```dart
abstract interface class UsageStatisticsRepository {
  Future<UsageStatisticsReport> query(AgentUsageQuery query, {bool forceRefresh = false});
  Future<UsageStatisticsSourceSnapshot> sourceSnapshot();
  Future<List<AgentUsageProviderDescriptor>> discoverProviders();
}

abstract interface class AgentUsagePanelRepository {
  Future<AgentUsagePanelProviderResult> loadPanel(String providerId, {bool forceRefresh = false});
  Future<List<AgentUsageProviderDescriptor>> synchronizeProviders();
}
```

- **Exceptions**: `UsageSourceUnavailableException`, `UsageParseException`, `UsageCapabilityUnsupportedException`

- [ ] Create with `create dart_package`; no flutter dependency
- [ ] Convert observer exits to `Stream` (686 of 5,759 lines depend on `flutter/foundation`)
- [ ] Migrate the three providers' usage sources and scanners
- [ ] Migrate the query logic of `UsageStatisticsController` / `AgentUsagePanelController` / `AgentUsageQueryService`
- [ ] **Withdraw `UsageStatisticsTextCatalog` + fallback** (§0.7 D3): enum labels (`UsageTimeRangePreset` / `UsageTaskStatus` etc.) are mapped onto ARB by an app-layer `switch`
- [ ] Define both interfaces and the exception family
- [ ] Migrate `test/src/features/usage_statistics/{application,data,domain}/`; fill gaps to 100%

**P3 acceptance gate (critical, all objectively checkable)**

| Metric | Before | Target |
| --- | --- | --- |
| `flutter` dependencies in repository `pubspec.yaml` | — | **0** |
| `dart:io` imports under the app's `lib/` | 60+ | **0** |
| `ChangeNotifier` / `ValueNotifier` occurrences in repository packages | 29 files / 10,730 lines | **0** |
| `AppLocalizations` references under `packages/` | — | **0** |
| `agent_provider_repository` → `agent_conversation_repository` dependencies | — | **0** (one-way edge) |
| Per-package coverage | — | **100%** |

- [ ] All six rows verified
- [ ] Every `StreamController` has a matching `close()`; no leaked subscriptions

---

## P4 · Design system

### Step 16 — `packages/app_ui` (10,754 lines)

#### Pure view components to keep

**Design tokens** (constants and theme extensions, no business logic)

`IdeColors`, `IdeSpacing`, `IdeTextStyles`, `IdeMetrics`, `IdeMotion`, `IdeEffects`, `AppTypography` (sinking down from core), `AppTheme`

**Base components** (24)

`IdeButton`, `IdeChip`, `IdeChoiceCard`, `IdeCollapsibleCard`, `IdeContextMenu`, `IdeDialog`, `IdeIconBox`, `IdeImagePreview`, `IdePopover`, `IdeResizeHandle`, `IdeSelect`, `IdeSkeleton`, `IdeStatusCard`, `IdeSwitch`, `IdeTabs`, `IdeToast`, `IdeActivityRail`, `IdeStableOverlayHandler`, `WindowFrame`, `PaneWidgets`

**Rows and containers**: `IdeDataRow`, `IdeKeyValueRow`, `IdeListRow`, `IdeRowDivider`, `IdeRowGroup`, `IdeSettingsRow`, `IdeSurface`

**Workbench primitives**: `IdeWorkbenchScaffold`, `IdeToolbar`, `IdeSection`, `IdePageHeader`, `IdePageBody`, `IdeRetainedPageView`

**Virtual scrolling subsystem** (7 files): `IdeDynamicSliverList`, `IdeExtentIndex`, `IdeSmoothScrollController`, `IdeVirtualItem`, `IdeVirtualListController`, `IdeVirtualScrollCoordinator`, `IdeVirtualScrollbar`

**Layout**: `IdeConstraintBucketBuilder`, `CompactMetricBar`

> All of these are **stateless or hold only local UI state** — they own no repository and start no IO. That is the precondition for living in `app_ui`; verify each one during migration.

#### l10n handling (per the `internationalization` skill, see deviation D3)

**`app_ui` has zero l10n dependency and holds no ARB.** The original "split out 118 keys" design is withdrawn.

- [ ] The 11 component strings become **constructor parameters** supplied by the caller: `commonMenu`, `imagePreviewUnavailable`, `imagePreviewView`, `imagePreviewViewLarge`, `tabsLoadingSuffix`, `timelineBackToBottom`, `timelineNewContent`, `timelineScrollToEnd`, `timelineScrollbar`, `workbenchCloseOverlay`, `workbenchLogoSemantics`
- [ ] `ZetaShadcnLocalizations` (384 lines) and the 107 `shadcn*` keys **stay in the app** under `lib/l10n/`, not in `app_ui`
- [ ] `formatInvariantNumber` stays in the app alongside `ZetaShadcnLocalizations`
- [ ] Verify `app_ui` contains no `AppLocalizations` reference

#### Checklist

- [ ] Create the package with `mcp__very-good-cli__create` (the `app_ui_package` template does not apply, see D2; use `flutter_package`)
- [ ] Depends on `flutter` + `shadcn_flutter` + `zeta_logging`
- [ ] **Depends on no `*_repository` package and not on the app's l10n**
- [ ] Migrate all tokens and components; import `shadcn_flutter` uniformly `as sf`
- [ ] **One widget per file**, filename = widget name in snake_case
- [ ] `lib/src/` is private; the `app_ui.dart` barrel exports every public component and token
- [ ] Design tokens go through `ThemeExtension`, registered on `ThemeData.extensions`, read via a `BuildContext` extension
- [ ] `const` constructors wherever feasible; dartdoc on every public member
- [ ] The app-side ARB stays intact at 1,072 keys — **no split required**

### Step 17 — `app_ui` tests

Per the `testing` + `ui-package` skills.

- [ ] Create `test/helpers/pump_app.dart` — the package's own `pumpApp` helper; **never inline `pumpWidget(MaterialApp(...))` in a test**
- [ ] Migrate `test/src/ui/core/` (including the 7 virtual scrolling test files); `test/` mirrors `lib/`
- [ ] **Every public component has a corresponding widget test**, testing behavior rather than static visual properties
- [ ] Static visual properties are covered by golden tests tagged `TestTag.golden` (tags come from `static const` fields on an `abstract class TestTag`, never string literals)
- [ ] Fill gaps to 100%
- [ ] `app_ui` runs standalone via `mcp__very-good-cli__test` (pass `directory: 'packages/app_ui'`)

---

## P5 · Blocs and presentation

**Serial, by feature.** Easy first, to establish the bloc migration technique on small modules.

### Step 18 — `workspace` → `WorkspaceCubit`

Simple state, no multi-source events; use a Cubit.

```dart
enum WorkspaceStatus { initial, indexing, ready, failure }

final class WorkspaceState extends Equatable {
  final WorkspaceStatus status;
  final String? root;
  final List<WorkspaceNode> tree;
  final Set<String> expandedPaths;
  final String? selectedPath;
  final WorkspaceRepositoryException? error;
}
```

Cubit methods: `indexProject(root)`, `invalidate(root)`, `toggleDirectory(path)`, `selectNode(path)`, `revealInFileManager(path)`

- **UI**: file tree view (pure presentation, receives `WorkspaceState`)
- **Injection**: `RepositoryProvider<WorkspaceRepository>` at the app layer, `BlocProvider<WorkspaceCubit>` at the IDE shell layer

- [ ] Create `lib/workspace/{cubit,view}/` and the barrel
- [ ] Implement `WorkspaceCubit` + `WorkspaceState`
- [ ] Convert the view to `BlocBuilder<WorkspaceCubit, WorkspaceState>`
- [ ] `bloc_test` covers every transition across the 4 statuses
- [ ] Fill gaps to 100%

### Step 19 — `settings` → `SettingsCubit`

```dart
enum SettingsStatus { initial, loading, ready, persisting, failure }

final class SettingsState extends Equatable {
  final SettingsStatus status;
  final GeneralSettings general;
  final AppearanceSettings appearance;
  final List<SystemFontFamily> systemFonts;
  final SettingsPersistenceException? error;
  final bool languageChangeRequiresRestart;   // carries GeneralSettingsUpdateResult
}
```

Cubit methods map one-to-one onto `SettingsRepository`.

- **Reverse edges**
  - [ ] **#4**: `settings_page` no longer imports `agent_management`'s presentation directly. Inject a `WidgetBuilder` at the app layer, or reuse `AgentManagementBloc` via `BlocProvider.value` inside the settings route
  - [ ] **#6**: `GeneralSettings` now lives in `settings_repository`; the agent side imports it from the package

- [ ] Create `lib/settings/{cubit,view}/` and the barrel
- [ ] Implement `SettingsCubit` + `SettingsState`
- [ ] Handle reverse edges #4 and #6
- [ ] `bloc_test` coverage including the persistence-failure path
- [ ] Fill gaps to 100%

### Step 20 — `app_update` → `AppUpdateBloc`

Has an explicit state machine (`AppUpdatePhase`); use a Bloc.

**Events**

```dart
sealed class AppUpdateEvent
final class AppUpdateInitialized extends AppUpdateEvent {}
final class AppUpdateStartupCheckRequested extends AppUpdateEvent {}
final class AppUpdateManualCheckRequested extends AppUpdateEvent {}
final class AppUpdateSnoozeRequested extends AppUpdateEvent {}
final class AppUpdateReleasePageOpened extends AppUpdateEvent {}
```

**State**: reuse the existing `AppUpdateState` (carrying `AppUpdatePhase`, `AppReleaseInfo`, `AppInstallationInfo`, `AppUpdateFailureReason`) with `Equatable` added.

- **UI**: update prompt card, manual check entry point
- **Injection**: `BlocProvider<AppUpdateBloc>` at the app top level (the startup check must fire before the shell)

- [ ] Create `lib/app_update/{bloc,view}/` and the barrel
- [ ] Implement handlers for all 5 events
- [ ] `bloc_test` covers every `AppUpdatePhase` transition and every `AppUpdateFailureReason`
- [ ] Fill gaps to 100%

### Step 21 — `desktop_notifications` → `DesktopNotificationsBloc`

> **Layering exception**: this module's data client depends on `flutter_local_notifications` and MethodChannel, so it cannot live in a pure-Dart repository package. The repository stays inside the app at `lib/desktop_notifications/repository/` and is **explicitly registered as an exception** in the P0 step 6 layer check.

**Events**

```dart
final class DesktopNotificationsInitialized extends DesktopNotificationsEvent {}
final class DesktopVisibilityChanged extends DesktopNotificationsEvent {}
final class AgentAttentionReceived extends DesktopNotificationsEvent {}
final class ThreadMarkedRead extends DesktopNotificationsEvent {}
final class NotificationActivated extends DesktopNotificationsEvent {}
```

**State**: `DesktopNotificationsState { unreadCount, visibility, pendingAttentions }`

- **Reverse edge #5**: no longer depends on the `settings` controller. Consume `SettingsRepository` instead, or bridge notification-toggle changes at the app layer with a `BlocListener<SettingsCubit>`

- [ ] Create `lib/desktop_notifications/{bloc,repository}/` and the barrel
- [ ] **Withdraw `DesktopAttentionTextCatalog` + fallback** (§0.7 D3): notification title and body are read from `context.l10n` in the bloc and passed to the repository
- [ ] Handle reverse edge #5
- [ ] Register the Flutter dependency exception in the layer check
- [ ] `bloc_test` coverage; fill gaps to 100%

### Step 22 — `project_threads` + `ide_session`

Two blocs sharing `ProjectSessionRepository`.

**`ProjectThreadsBloc`**

| Event | Source method |
| --- | --- |
| `ProjectActivated` | `activateProject` |
| `ProjectsRetained` | `retainProjects` |
| `ProjectToggled` | `toggleProject` |
| `ArchivedViewChanged` | `setArchivedView` |
| `SearchTermChanged` | `setSearchTerm` |
| `InitialThreadsRequested` | `loadInitial` |
| `MoreThreadsRequested` | `loadMore` |
| `ThreadSelected` / `ThreadSelectionCleared` | `selectThread` / `clearSelectedThread` |
| `ThreadRenamed` / `ThreadArchived` / `ThreadDeleted` | corresponding methods |
| `ThreadRunningChanged` | `setThreadRunning` |
| `CompletedThreadDismissed` | `dismissCompletedThread` |
| `RuntimeSnapshotSynced` | `syncRuntimeSnapshot` |

**State**: `ProjectThreadsState { Map<String, ProjectThreadListState> byProject, activeProjectPath, status, error }`

**`IdeSessionCubit`**: `restore()`, `requestSave(snapshot)`, `saveNow(snapshot)`; state carries `IdeSessionState` + `isRestoring`

- [ ] Create both feature directories and barrels
- [ ] Implement `ProjectThreadsBloc` (15+ events)
- [ ] Implement `IdeSessionCubit`
- [ ] The two blocs **do not depend on each other**; coordinate via a `BlocListener` at the app layer
- [ ] `bloc_test` coverage; fill gaps to 100%

### Step 23 — `agent_management` → `AgentManagementBloc`

**Events**

```dart
final class AgentManagementInitialized      // initialize({autoDetect})
final class AgentDetectionRequested         // detect
final class AgentSelected                   // selectAgent
final class AgentEnabledChanged             // setEnabled
final class ClaudeAccountEnrichmentChanged  // setClaudeCodeAccountDataEnrichmentEnabled
final class AgentConnectionTestRequested    // testConnection
final class AgentConfigurationLoaded        // loadConfiguration
final class AgentConfigurationSaved         // saveConfiguration
final class AgentLogsRequested              // loadLogs
final class AgentRuntimeStateRefreshed      // refreshRuntimeState
```

**State**

```dart
final class AgentManagementState extends Equatable {
  final AgentManagementStatus status;
  final List<ManagedAgent> agents;
  final String? selectedAgentId;
  final AgentDetectionProgress? detection;
  final AgentConnectionTestResult? lastTestResult;
  final AgentConfigurationDocument? configuration;
  final List<AgentLogEntry> logs;
  final AgentRepositoryException? error;
}
```

> `validateConfiguration(content)` is a **synchronous pure function** and does not go through an event — keep it as a synchronous repository method the UI calls directly for live validation.

- **UI**: `agent_management_page.dart` (1,734 lines) — convert to `BlocBuilder` only; **do not split** in this phase (see topology §5.4)
- **Injection**: `BlocProvider<AgentManagementBloc>` at the settings route layer

- [ ] Create `lib/agent_management/{bloc,view,widgets}/` and the barrel
- [ ] Implement handlers for all 10 events
- [ ] Keep `validateConfiguration` as a synchronous call
- [ ] `bloc_test` covers every combination of `AgentInstallationState` / `AgentRuntimeState` / `AgentAccountState`
- [ ] Fill gaps to 100%

### Step 24 — `usage_statistics` → `UsageStatisticsBloc` + `AgentUsagePanelCubit`

Two independent state sets, matching the two legacy controllers.

**`UsageStatisticsBloc`**

| Event | Source |
| --- | --- |
| `UsageStatisticsInitialized` | `initialize` |
| `UsageRefreshRequested` | `refresh` |
| `TimePresetSelected` | `selectTimePreset` |
| `CustomRangeSelected` | `selectCustomRange` |
| `ProjectFilterSelected` | `selectProject` |
| `ProviderFilterSelected` | `selectProvider` |
| `ModelFilterSelected` | `selectModel` |
| `RankSortSelected` | `selectRankSort` |

**State** (consolidating the controller's 13 getters)

```dart
final class UsageStatisticsState extends Equatable {
  final UsageStatisticsStatus status;
  final UsageStatisticsFilter filter;   // preset/customStart/customEnd/project/provider/model/rankSort
  final UsageStatisticsReport? report;
  final UsageStatisticsSourceSnapshot? source;
  final List<String> warnings;
  final DateTime? lastUpdated;
  final UsageSourceUnavailableException? error;
}
```

**`AgentUsagePanelCubit`**: `refresh()`, `synchronizeProviders()`, `selectProvider(id)`, `restorePreferredProviderId(id)`, `selectProviderFromTurn(id)`

State: `{ providers, selectedProviderId, preferredProviderId, entries, lastUpdated, status, error }`

- **UI**: `usage_statistics_page.dart` (1,669 lines), `agent_usage_panel.dart` (1,215 lines) — convert to `BlocBuilder` / `BlocSelector`, do not split
- **Injection**: `UsageStatisticsBloc` at the statistics route layer; `AgentUsagePanelCubit` at the IDE shell layer (the sidebar is always mounted)

- [ ] Create `lib/usage_statistics/{bloc,cubit,view,widgets}/` and the barrel
- [ ] Implement `UsageStatisticsBloc` (8 events)
- [ ] Implement `AgentUsagePanelCubit`
- [ ] Chart components (`fl_chart`) stay pure views, receiving pre-computed entities such as `UsageTrendPoint`
- [ ] `bloc_test` coverage; fill gaps to 100%

---

## P6 · Agent conversation (highest risk, separate work stream)

### Step 25 — `AgentConversationViewModel` (4,190 lines) → `AgentConversationBloc`

#### Key finding: the state slices already exist

`agent_conversation_ui_state.dart` (1,098 lines) already splits state into **5 independent slices**, each exposed as a `ValueListenable`:

| Existing slice | Responsibility |
| --- | --- |
| `AgentHeaderState` | Provider name, capabilities, thread status capsule |
| `AgentComposerState` | Input box, model selection, mode, skills |
| `AgentPendingInteractionState` | The four kinds of pending item: permission / question / plan approval / plan execution |
| `AgentExpansionState` | Expansion state for tool calls, plans, command groups, file edits |
| `AgentConversationHistoryState` | Timeline entries and history turns |

**This split exists for performance** (avoiding whole-tree rebuilds) and **must be preserved**.

**Design decision**: one `AgentConversationBloc` whose state composes these 5 slices; the UI subscribes to individual slices with `BlocSelector`. **Do not split into 5 blocs** — they share one event stream and one reducer, and splitting would introduce bloc-to-bloc dependencies, which VGV forbids.

```dart
final class AgentConversationState extends Equatable {
  final AgentHeaderState header;
  final AgentComposerState composer;
  final AgentPendingInteractionState pending;
  final AgentExpansionState expansion;
  final AgentConversationHistoryState history;
  final AgentConversationStatus status;
  final AgentRepositoryException? error;
}
```

#### 25a — State classes

- [ ] Add `Equatable` to the 5 slice classes and move them into `lib/agent_chat/bloc/`
- [ ] Define the composite `AgentConversationState`
- [ ] Keep `AgentConversationUiStateDiagnostics` (diagnostic fields for debugging coalescing and scheduling)

#### 25b — Event stream wiring

- [ ] Subscribe to `AgentRepository.timelineFor(key)` and convert to `AgentTimelineUpdated` events
- [ ] The reducer and EffectRunner **stay in the Repository layer**; the bloc consumes results only
- [ ] Keep the per-frame coalesced UI update scheduling (`AgentUiUpdateScheduler`, 269 lines)

#### 25c — User action wiring (security critical)

**Four approval semantics, strictly isolated, four independent event types, never pre-authorizing any operation.**

| Semantics | Event | Repository method |
| --- | --- | --- |
| Permission response | `PermissionResponded` | `respondToPermission` |
| Question answer | `QuestionResponded` | `respondToQuestion` |
| Plan approval | `PlanApprovalResponded` | `respondToPlanApproval` |
| Plan execution handoff | `PlanExecutionStarted` / `PlanExecutionRevised` / `PlanExecutionDismissed` | `startPlanExecution` and friends |

Remaining event groups:

| Group | Events |
| --- | --- |
| Session | `ConversationOpened`, `ThreadReopenRetried`, `ContextUpdated` |
| Turn | `MessageSubmitted`, `ActiveTurnCancelled`, `LastUserMessageEdited` |
| Model config | `ModelSelected`, `ReasoningEffortSelected`, `ServiceTierSelected`, `FastEnabledChanged`, `ModelsRefreshRequested`, `ModelCompatibilityConflictResolved`, `ModelConfigurationSaveRetried` |
| Mode and skills | `ConversationModeSelected`, `ConversationModesRetried`, `SkillsCatalogRequested` |
| Thread operations | `CurrentThreadRenamed`, `CurrentThreadArchived`, `CurrentThreadCompacted`, `CurrentThreadForked` |
| Expansion | `ToolCallToggled`, `PlanMessageToggled`, `ActivePlanToggled`, `CommandGroupToggled`, `FileEditItemToggled` |
| Permission preferences | `PermissionOptionSelected`, `PermissionPreferencePersistenceRetried`, `GuardianDeniedActionApproved` |
| Other | `ProviderSwitched`, `SessionConfigOptionSelected`, `ContextPanelToggled` |

- [ ] The four approval semantics each get an independent event and **share no base-class fields**
- [ ] `bloc_test` adds **negative cases**: verify that any one approval event does not incidentally grant permission under another semantics

#### 25d — UI-derived logic

- [ ] Convert derived computations in the view model (`shouldShowActivePlan`, `threadStatusCapsuleLabel`, `canSelectConversationMode`, …) into state getters or standalone selector functions
- [ ] Timeline projection caches (`AgentTimelineProjectionCache`, `AgentFileChangeProjectionCache`, `AgentMarkdownCache`) stay as pure functions plus cache objects; they do not go into the state

### Step 26 — Presentation widgets (18 files / 13,017 lines)

#### Pure view components to keep

| File | Lines | Handling |
| --- | --- | --- |
| `agent_pane_cards.dart` | 2,220 | `BlocSelector<_, AgentConversationHistoryState>`; **split recommended** |
| `agent_model_config.dart` | 1,971 | `BlocSelector<_, AgentComposerState>`; **split recommended** |
| `agent_pane_composer.dart` | 1,607 | `BlocSelector<_, AgentComposerState>`; **split recommended** |
| `agent_pane_sections.dart` | 1,130 | `BlocSelector` |
| `agent_pane_context_panel.dart` | 891 | `BlocSelector` |
| `agent_pane_messages.dart` | 854 | `BlocSelector<_, AgentConversationHistoryState>` |
| `agent_pane_navigation_rail.dart` | 670 | `BlocSelector<_, AgentHeaderState>` |
| `agent_file_change_evidence_views.dart` | 505 | Pure view, no change needed |
| `agent_pane_plan_panel.dart` | 465 | `BlocSelector<_, AgentPendingInteractionState>` |
| `agent_mode_selector.dart` | 442 | `BlocSelector<_, AgentComposerState>` |
| `agent_pane_styles.dart` | 440 | Pure styling, no change needed |
| `agent_slash_command_picker.dart` | 413 | Pure view |
| `agent_pane_header.dart` | 369 | `BlocSelector<_, AgentHeaderState>` |
| `agent_file_change_evidence_card.dart` | 275 | Pure view |
| `agent_mention_file_picker.dart` | 233 | Pure view (consumes `WorkspaceCubit`) |
| `composer_selector_popover.dart` | 229 | Pure view |
| `agent_skill_picker.dart` | 190 | Pure view |
| `agent_provider_icon.dart` | 113 | Pure view |

- [ ] Convert each file to `BlocBuilder` / `BlocSelector`
- [ ] **Each widget subscribes only to the slice it needs** — subscribing to the whole state defeats the performance split
- [ ] Split the three files over 1.5k lines (P6 is the one exception to topology §5.4)
- [ ] Migrate `test/src/features/agent/presentation/harness/` and widget tests

### Step 27 — Capability rendering tests

- [ ] For each of the 19 optional ports, write one widget test: when the port is null or `capability = false`, its UI entry point **does not appear in the menu**
- [ ] Calling an unsupported capability from the application layer throws `AgentCapabilityUnsupportedException` — **verify it is not a silent success**

**P6 acceptance gate**

- [ ] The isolation of the four approval semantics is explicitly asserted in `bloc_test`, including negative cases
- [ ] Real-CLI smoke test across all three providers: Codex + Claude Code + Grok
- [ ] Fill gaps to 100%

---

## P7 · Application shell and wrap-up

### Step 28 — `ide_shell` → `IdeShellBloc`

Merges `ui/features/ide/` (4,059 lines) with `app/shell/ide_shell_controller.dart` (1,467 lines). Reverse edge #2 disappears.

**Events** (consolidated from `IdeShellController`'s public methods)

| Group | Events |
| --- | --- |
| Projects | `ProjectOpenRequested`, `RecentProjectOpened`, `KnownProjectSelected`, `ProjectRemoved`, `ProjectRevealedInFileManager`, `RecentHomeDataRefreshed` |
| Threads | `ProjectThreadSelected`, `AgentThreadActivated`, `NewThreadStarted`, `ProjectThreadRenamed`, `ProjectThreadArchived`, `ProjectThreadUnarchived`, `ProjectThreadDeleted`, `ProjectThreadForked`, `CompletedProjectThreadDismissed`, `MoreThreadsRequested`, `ThreadsRetried` |
| Layout | `LeftSidebarVisibilityChanged`, `LeftSidebarWidthChanged`, `AgentUsageProviderSelected` |
| File tree | `TreeExpansionChanged`, `TreeNodeTapped` |
| Persistence | `SessionSaveRequested` |

**State**

```dart
final class IdeShellState extends Equatable {
  final IdeShellStatus status;
  final List<String> projects;
  final String? activeProjectPath;
  final bool isProjectHomeActive;
  final List<AgentThreadWorkspaceEntry> workspaceEntries;
  final String? selectedWorkspaceEntryId;
  final IdeWorkbenchLayoutState layout;
  final List<RecentProjectSummary> recentProjects;
  final List<AgentThreadSummary> recentThreads;
  final bool initialRestoreCompleted;
  final String? recentHomeRefreshError;
}
```

> **Note**: the legacy `IdeShellController` holds an `AgentConversationViewModel` directly (`selectedAgentViewModel`). Under VGV a bloc must not hold another bloc — the shell instead holds only an `AgentConversationKey`, and the UI layer resolves the matching `BlocProvider` by key.

#### Pure view components to keep

`ide_home.dart` (1,162), `project_list_pane.dart` (1,157), `global_home_page.dart` (702), `project_home_page.dart` (591), `new_thread_provider_popover.dart` (230), `project_agent_sidebar.dart` (81)

- [ ] Create `lib/ide_shell/{bloc,view,widgets}/` and the barrel
- [ ] Implement `IdeShellBloc` (25+ events)
- [ ] **Remove the direct hold on the view model**; index by key instead
- [ ] Migrate the 6 view files and convert to `BlocBuilder` / `BlocSelector`
- [ ] Reverse edge #2 disappears (`menu_action_bridge` and the shell controller are now in the same package)
- [ ] `bloc_test` coverage; fill gaps to 100%

### Step 29 — `lib/app/` wiring layer

**Injection: `RepositoryProvider` at the outermost level, `BlocProvider` layered by scope.**

```
MultiRepositoryProvider           ← every repository, singleton at the app root
  └─ MultiBlocProvider            ← global blocs
       ├─ SettingsCubit           (global: language, appearance, notification toggles)
       ├─ AppUpdateBloc           (global: startup check precedes the shell)
       ├─ DesktopNotificationsBloc(global: tray and badge)
       └─ MaterialApp.router
            └─ IdeShellBloc       (shell scope)
                 ├─ WorkspaceCubit
                 ├─ ProjectThreadsBloc
                 ├─ IdeSessionCubit
                 ├─ AgentUsagePanelCubit
                 └─ AgentConversationBloc  ← one instance per workspace entry, created by key
```

Created on demand inside routes: `AgentManagementBloc` (settings page), `UsageStatisticsBloc` (statistics page).

- [ ] `MultiRepositoryProvider` injects every repository
- [ ] The three global blocs sit above `MaterialApp`
- [ ] Shell-scoped blocs sit below the shell
- [ ] `AgentConversationBloc` is created per `AgentConversationKey` and closed when its entry closes
- [ ] All bloc coordination goes through `BlocListener`; **no direct dependencies**
- [ ] `zeta_startup_bootstrap` plugs into VGV's `bootstrap.dart`

### Step 30 — l10n wrap-up

- [ ] Create `lib/l10n/failure_messages.dart`: the `switch` mapping from every `sealed` failure type onto ARB keys — **the single localization point in the project**
- [ ] Verify all 395 lines of `Fallback*` copy folded into ARB (against the mapping table recorded at P1 step 7), with nothing missing or duplicated
- [ ] Confirm the four TextCatalog interfaces and `ZetaTextCatalogs` (866-line bridge) are fully deleted with no references left
- [ ] `ZetaAppLocalizationsDelegate` (synchronous loading via `SynchronousFuture`, avoiding a blank first frame) is in place
- [ ] `ZetaLocalization.delegates` composes the 5 delegates
- [ ] **Locale freezing**: move the `_frozenDisplayLocale` logic into `bootstrap.dart` + `lib/app/`
- [ ] `supportedLocales` keeps both the `zh-Hans` and `zh` entries

### Step 31 — Three flavors

- [ ] Wire `main_development.dart` / `main_staging.dart` / `main_production.dart` to `bootstrap.dart`
- [ ] Build once per platform × flavor

### Step 32 — Data migration verification

- [ ] Versioned reading and tolerant decoding of legacy provider configuration
- [ ] Session index (`ide_session_store`) upgrade
- [ ] Turn context storage upgrade
- [ ] Run the upgrade against real legacy data files as a regression

> Cursor data cleanup is **not in this step** — it moved up to **step 0** along with the retirement code, completed in the legacy repository. By P7 the new repository carries no trace of cursor.

### Step 33 — Documentation wrap-up

- [ ] Update [migration_topology.en.md](./migration_topology.en.md) as the final architecture description
- [ ] Mark this document fully complete
- [ ] Add VGV layering rules and package boundary notes to `CONTRIBUTING.md`
- [ ] Finalize `docs/architecture/layering.md`: layer responsibilities, injection, bloc scope diagram
- [ ] **Bilingual final review**: every row of the §0.6 mapping table checked; `docs/README.md` and `docs/README.en.md` match the actual files with no dead links
- [ ] Verify every `xxx.md` has an `xxx.en.md` counterpart with the correct language-switch header

**P7 acceptance gate**

- [ ] All three platforms build
- [ ] Full test suite green, 100% coverage
- [ ] Legacy data upgrade regression passes
- [ ] Real-CLI end-to-end smoke test
- [ ] One UI smoke pass per language (locale freezing effective, missing keys fall back to English)

---

## Appendix: cross-phase tracking

These span multiple phases and are listed separately so they are not lost.

### Reverse edges

- [ ] #1 `settings → app` (disappears at step 3)
- [ ] #2 `ui/features → app` (disappears at step 28)
- [ ] #3 `ide_session ↔ project_threads` (dissolved by the merge at step 14)
- [ ] #4 `settings → agent_management/presentation` (step 19)
- [ ] #5 `desktop_notifications → settings/application` (step 21)
- [ ] #6 `agent → settings/domain` (step 19)

### Product requirements the architecture does not guarantee

- [ ] **Four approval semantics isolated, never pre-authorize** (step 25c, including negative cases)
- [ ] **Tolerant decoding of persisted data** (all codecs in §0.2 + step 32)
- [ ] **A missing capability never succeeds silently** (step 27)
- [ ] **entryId ownership decided by each client** (step 9 contract tests)

### Objective metrics

| Metric | Before | Target | Verified at |
| --- | --- | --- | --- |
| `dart:io` imports on the app side | 60+ | **0** | P3 |
| Inter-client package dependencies | — | **0** | P2 |
| Repository packages depending on flutter | — | **0** (1 exception) | P3 |
| **`ChangeNotifier` / `ValueNotifier` in repository packages** | **29 files / 10,730 lines** | **0** | P3 |
| **`AppLocalizations` references under `packages/`** | — | **0** | P3 / P4 |
| **Remaining `TextCatalog` references in the repo** | 4 sets + 866-line bridge | **0** | P7 |
| **Remaining `cursor` identifiers in the repo** | 11 sites | **0** | Step 0 |
| Direct bloc-to-bloc dependencies | — | **0** | P5–P7 |
| Coverage | — | **100%** | Every phase |
