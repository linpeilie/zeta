# Project Memory

Last updated: 2026-08-11

> Translated from [the Chinese original](../../zh/history/project_memory.md), which is the source of truth if the two diverge.

This page records project facts, decisions and constraints worth keeping across tasks. When a fact changes, update this page too.

## 1. Project identity

- Name: Zeta.
- Type: Flutter Desktop local application.
- Current positioning: a local AI IDE shell built around project context, agent threads and an auditable conversation timeline.
- Entry point: `lib/main.dart`.
- Active providers are Codex, Grok and Claude Code. Cursor is retired; Codex remains the default active provider.

## 2. Technology stack

- Flutter and Dart.
- `shadcn_flutter: 0.0.52` plus a home-grown Graphite design token set (light and dark themes). `IdeThemeScope` is the source of truth for tokens; the third-party theme is only a projection of it.
- `multi_split_view` for the resizable three-column layout.
- `flutter_treeview` for the file tree.
- `window_manager` for the desktop window experience (hidden native title bar, custom title bar).
- The native macOS "File → Open project" menu is bridged to Flutter through the `zeta/menu` MethodChannel.
- `file_selector` for picking local directories.
- Zeta no longer uses `shared_preferences`. Its own configuration, session state and derived indexes are versioned JSON files under Zeta's data directory (a `.zeta` folder inside the platform documents directory).
- A single `AppLogger` writes both developer logs and `logs/zeta-YYYY-MM-DD.log` in that directory. Application code obtains an instance through `loggerFor(scope)`.

## 3. Architectural decisions

- Keep the lightweight feature-sliced layering; do not introduce a heavyweight architecture framework prematurely.
- Inside a feature, split into domain, application, data and presentation. New functionality goes into the corresponding feature first.
- UI and application layers depend on the domain-layer agent abstractions, `AgentProviderBundle` and `AgentProviderCapabilities`. They never handle raw provider protocol.
- The data layer maps provider protocol into neutral domain events.
- Agent context currently carries only the project path and the current file path; file contents are never read automatically. Users may attach local images (`localImage`).
- The default Codex approval policy stays `on-request` and never auto-authorises commands or file modifications.
- Cursor was retired for lack of a verifiable, stable protocol contract. Its synthetic fixtures and compatibility code have been deleted; the old integration plan exists only in Git history, and the release gate document is retained purely as historical evidence.
- The file tree is lazy-loaded and never recursively scans a whole repository.
- Session restore must fail leniently and must never block application startup.
- `core` centralises resolution of Zeta's data directory and atomic writes; feature data stores receive files injected by the app layer. Zeta's own storage never reads or rewrites agent CLI configuration or session history.

## 4. Key modules

- `MainApp` supports test injection of the directory picker, session store and agent provider factory.
- `IdeShellController` coordinates project selection, file tree state, session restore, agent workspace synchronisation and the project threads controller, and syncs each workspace entry's `threadSnapshot` into `ProjectThreadsController`.
- `IdeHome` composes the three-column UI and keeps page-level responsibilities thin.
- `AgentConversationViewModel` exposes agent panel state and delegates to the timeline store, UI signals and model selection controller. Both `_publishUiChanges` and `_flushStreamChangesNow` must refresh `threadSnapshotListenable`.
- `ProjectThreadsController` handles thread pagination, restore, cached snapshots, provider interaction and race isolation within a project. The busy state of an open thread is determined by `syncRuntimeSnapshot`.
- `ProjectThreadsViewModel` is a pure state container for the project thread list, including `runningThreadIds` / `completedThreadIds` and sticky-active collapsing.
- During the current migration, `AgentProviderBundle` is the application-layer capability entry point and `AgentProvider` is the provider-neutral compatibility façade. Capabilities remain the source of truth for showing entry points and validating execution.
- `CodexAppServerAgentProvider` is the current default provider implementation; the protocol pin lives in `third_party/codex_app_server_schema`.
- The current provider schema, configuration, catalog, factory, deep links, restore and management paths contain no Cursor.
- `JsonRpcPeer` handles stdio JSON-RPC communication.
- `IdeSessionState` is currently at version 4.
- The agent timeline already consumes streaming reasoning and plans, turn diffs, waiting states, system prompts and local image bubbles.

## 5. Development constraints

- Run `dart format .` after changing Dart files.
- Run `flutter analyze` before finishing a code change.
- Run the tests when changing behaviour or adding logic.
- Prefer Chinese `///` comments for new public APIs, protocol adaptation, state machines and error handling.
- Async pagination, restore and streaming should use tokens/versions, partitioned listenables or throttled signals to isolate races and limit rebuild scope.
- Do not commit build output or `.dart_tool`.
- Changes to platform directories need a confirmed origin; unexplained generated changes must not be left in place.

## 6. Design constraints

- This is a tool-shaped desktop application. The interface should stay restrained, dense and scannable.
- Avoid turning features into marketing pages or decorative layouts.
- The three columns have clear responsibilities: Projects for projects and threads, Agent for conversation, Files for file context.
- Non-textual buttons need tooltips.
- File and project path display must handle very long text with ellipsis.

## 7. Risks

- A Codex app-server protocol change can break provider mapping. Before upgrading, diff against `third_party/codex_app_server_schema` with `tool/gen_codex_schema.* --diff` (the process is in the Codex app-server protocol document).
- Request, notification and server-request handling over JSON-RPC stdio needs strict test coverage.
- Re-integrating Cursor requires a fresh proposal and newly collected real protocol fixtures. The pre-retirement synthetic fixtures must not be used to infer protocol semantics.
- Session restore touches the real file system; missing paths and permission failures must be handled leniently.
- Switching threads while an agent is running invites state races. Keep isolating stale results with tokens or state checks.
- If the file tree is ever changed back to a recursive scan, opening large projects will get noticeably slower.

## 8. Open directions

- Whether to add a built-in file preview or editor.
- Whether to re-evaluate Cursor support once there is an independent proposal and real protocol evidence.
- Whether to support parallel agent sessions across multiple projects.
- Whether agent execution records need auditing and export.
- Whether project sessions need to sync across devices.
