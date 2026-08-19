# Architecture Decision Records (ADR-001—ADR-004)

[中文](../../zh/architecture/architecture_decisions.md) ｜ English

Status: **all accepted**. Decision date: 2026-08-19. Applicable baseline: legacy commit
`b5c2f3e8a9ac544e9832866e86ff633661c46053`.

This document freezes the four P-1 migration decisions. Machine-checkable rules are mirrored in the
repository-root `.architecture.yaml`; [package API contracts](./package_api_contracts.md) own detailed
signatures, while the [ownership map](./ownership_map.md) owns class and field placement.

## ADR-001: the `agent_provider_contracts` model exception

### Context

Three mutually independent Provider data clients must implement the same neutral capability ports and
exchange identical event, session, permission, plan, and usage values. Placing these models in any one
Repository would force reverse or inter-Repository dependencies.

### Decision

Create the pure-Dart leaf package `agent_provider_contracts` as the only model-ownership exception:

- It may contain the 21 capability ports, `AgentProviderBundle`, immutable neutral values, typed
  failures/codes, pure codecs, and `ResolvedCliProcessCommand`.
- Its only allowed dependencies are the Dart SDK, `collection`, `equatable`, and `meta`; it has no local
  package dependency.
- Flutter, `dart:io`, platform plugins, logging/storage implementations, business state, localized copy,
  and vendor wire fields are forbidden.
- Types are immutable, collections are frozen, and value equality is stable.
- A new type needs at least two independent client consumers; a single-consumer type stays in its vendor
  client.
- A non-null bundle field is the source of truth for operation existence; capability flags only describe
  availability under the current configuration.

### Consequences and review triggers

The clients can implement one contract in parallel, but the contracts package could become a dumping
ground. Re-review ADR-001 before adding a local dependency, IO/Flutter, vendor fields, interaction state
such as `selected`/`expanded`/`isLoading`, a single-consumer type, or changing the port count or event
sealed family. Update both API-contract languages and `.architecture.yaml` before implementation.

## ADR-002: Flutter platform-adapter boundary

### Context

System fonts, notifications, attention, pickers, clipboard, windows, and menus require Flutter plugins or
`MethodChannel`, while Data and Repository packages must remain pure Dart.

### Decision

- Neutral ports live in the pure-Dart `desktop_platform_api` package.
- Flutter concrete adapters live only under `lib/app/platform/**`.
- Adapters may depend only on `desktop_platform_api`, Flutter services, and the matching plugin; they may
  not depend on business data clients, Repositories, Blocs, or Presentation.
- Repositories depend on pure-Dart ports. Blocs never call platform ports directly and use the relevant
  Repository instead.
- `lib/bootstrap.dart` constructs adapters and injects Repositories; it is the sole composition root that
  can see both.
- Native Runners and MethodChannels transport values only; they own no business rules, selection state,
  or localized copy.

### Consequences and review triggers

Platform implementations stay in the app and packages remain independently testable. Adding a plugin,
channel, or platform capability requires reviewing port neutrality and updating the plugin allowlist in
`.architecture.yaml`. Direct MethodChannel/plugin imports in a Bloc, Widget, or Repository are rejected.

## ADR-003: Router is the sole navigation-identity source of truth

### Context

The legacy `IdeShellController` stores pages, project/thread identities, and restoration state, which
would compete with GoRouter location during startup restore, back, menu navigation, and invalid-ID flows.

### Decision

- Typed hierarchical GoRouter routes are the sole source of truth for the page, projectId, and threadId.
- Routes carry stable IDs only; `extra:`, raw path concatenation, and file-path objects are forbidden.
- Session restore produces only an initial-location or redirect input; it does not retain or write ongoing
  navigation state.
- `IdeShellBloc` owns layout, pane visibility, and non-navigation selection, but never mirrors location.
- Blocs do not depend on GoRouter. Presentation `BlocListener`s perform navigation, dialogs/snackbars,
  and back side effects.
- Invalid or stale IDs fail closed to a recoverable parent route.

### Consequences and review triggers

Navigation can be reconstructed from location and does not race Shell restoration. Re-review for external
deep links, multiple windows, side-by-side flavor installation, or shared cross-window navigation; OS
external deep links are explicitly out of scope for this migration.

## ADR-004: Conversation reducer/effect and Bloc boundary

### Context

Provider events must continue reducing in order without a UI, while legacy conversation code also mixes
expansion, selection, loading, drafts, scrolling, and navigation. Moving the whole unit to either a
Repository or Bloc would cross layers.

### Decision

- The Repository owns runtime leases, listener generations, the event pipeline, deterministic reducers,
  timeline/domain snapshots, history/live/replay scopes, and Provider/storage/resource-lifecycle effects.
- It publishes external facts through `Stream<T> changes` plus synchronous `snapshot`, with no Flutter.
- The Bloc owns selections, drafts, expansion, loading/failure, conflict confirmation, and cross-Repository
  business orchestration; every asynchronous event declares a transformer.
- Presentation `BlocListener`s perform scrolling, focus, dialogs/snackbars, and navigation.
- UI-request callback ports are deleted; Repository never calls Presentation or stores UI slices.
- At send time, the Bloc freezes an immutable turn configuration and passes it to the Repository.

### Consequences and review triggers

Provider ordering and resource lifetime no longer depend on Widget lifetime, and UI State remains cheap to
compare. Re-review ADR-004 before changing reducer input/output, effect ordering, scopes, lease ownership,
snapshot publication, or asking a Repository to store interaction state. Keep the state design, ownership
map, and event-storm tests synchronized.

## Open-decision register

**Open items: 0.** A new question must be registered as `OPEN` with an owner, due step, and blocking
scope; P-1 cannot close with an open item.

| Decision | Final ruling | Status |
| --- | --- | --- |
| Desktop platforms | macOS, Windows, and Linux are first-class; all use `cn.easii.zeta` / `Zeta` | RESOLVED |
| Accessibility | WCAG 2.2 AA; VoiceOver on macOS, Narrator/NVDA on Windows, Orca on Linux, plus keyboard-only smoke | RESOLVED |
| Linux limitations | Record Flutter/Orca limitations, but never use them to skip blocking AA findings or manual verification | RESOLVED |
| Motion | Reduced motion is an additional VGV platform gate, not misrepresented as an AA criterion | RESOLVED |
| Flavor identity | All flavors share the app ID and `~/.zeta`; side-by-side installation is unsupported | RESOLVED |
| Legacy coverage | Record 83.97% without gating Step 0; the new VGV workspace still requires 100% hand-written coverage | RESOLVED |
| Codex schema/tooling | Migrate the stable schema pin and required smoke/gate tools; exclude legacy packaging and updater work | RESOLVED |
