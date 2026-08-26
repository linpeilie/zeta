# Development Log

> Translated from [the Chinese original](../../zh/history/development_log.md), which is the source of truth if the two diverge.
>
> **Archive.** Entries are point-in-time records and are not updated when later work supersedes them.

## 2026-07-21

### Tightened vertical spacing in the Projects list

- Project rows and project thread rows dropped vertical padding on both the outer container and the interaction surface, keeping horizontal padding only.
- Loading, empty and error state rows adopted horizontal-only padding to match, with widget regression assertions and a Projects sidebar UI spec added.

## 2026-07-16

### Aligned the sidebar's running indicator with the detail runtime

- **Root cause**: paths such as `turn/completed` only went through `_flushStreamChangesNow` and never pushed `threadSnapshotListenable`, so the detail view was already idle while the list still reported `isTurnRunning: true`.
- **Fix**: stream flush now synchronises the snapshot; sticky `active` collapses when a turn ends; `syncRuntimeSnapshot` and `setThreadRunning(false)` guard against false-positive `isBusy` in the list.
- **Docs**: `plan/agent_running_status_ux_plan.md` §2.5, plus the synchronisation contract described in the design document, developer guide and project memory.

### Turn footer shows the turn's model configuration

- In addition to elapsed time and tokens, the terminal-state turn footer now shows the model, the reasoning effort (where present), and Fast (where present and enabled).
- Added `AgentTurnModelConfig`: historical turns parse it from `model` / `turnContext`; live turns freeze the current composer selection at send time.
- Covered by domain parsing, timeline mounting and footer widget tests.

### Removed the ActivityRail selection indicator bar

- `IdeActivityRail` no longer draws the `accent` indicator bar or square next to the icon in the selected state. Only the neutral `selectedSurface` background and `accentForeground` icon colour remain.
- Deleted `IdeActivityRailIndicatorSide` and the `indicatorSide` API, and cleaned up the corresponding arguments in `IdeHome` and the golden tests.
- Updated the state visuals sections of the unified design system implementation document and the UI modernisation blueprint.

## 2026-07-09

### Codex app-server Phase 1 wrap-up

- Phase 1 (core streaming experience) is complete in the adaptation plan: reasoning and plan streams, turn diffs, thread waiting states, `serverRequest/resolved`, MCP progress, model reroutes and deprecation notices, 18 `ThreadItem` kinds, `thread/unsubscribe`, and local image input.
- Refreshed the protocol coverage table at the top of `plan/codex_app_server_adaptation_plan.md` and the §1 adapted list; updated the agent design section of the design document.
- Real app-server smoke (`tool/smoke_codex_app_server.py`, CLI `0.142.5`) passed 17/17: `initialize` / `model/list` / `thread/start`; `turn/start` accepting `text` + `localImage` with the image visible in item notifications; `thread/status/changed`; `thread/tokenUsage/updated` (`modelContextWindow=258400`); agent message streaming; `turn/interrupt` → `interrupted`; `thread/unsubscribe`. The short replies in this run did not trigger reasoning/plan or `turn/diff` (the script records these as optional). Resolving an approval from another client requires two clients and was not covered by the single-process smoke.
- Next: Phase 2 (thread management and deeper approvals).

### Codex app-server protocol synchronisation

- Added `tool/gen_codex_schema.sh` and `tool/gen_codex_schema.ps1` to export the JSON Schema from the locally installed Codex CLI.
- Committed the pinned snapshot to `third_party/codex_app_server_schema/` (currently `0.144.5`), excluding the v2 aggregate files whose key order is unstable.
- Added the Codex app-server protocol document recording the pinned version, the regeneration command and the upgrade diff process; updated the developer guide, design document and engineering standards entry points to match.
- Phase 0 (protocol alignment audit) is complete in the adaptation plan.

## 2026-07-07

### Extracted engineering standards after the refactor

- Scanned the current `lib/` structure and confirmed the project had evolved from broad layering into a lightweight feature-sliced architecture.
- Added the app/core/features/ui boundaries, dependency direction, state splitting, protocol isolation, persistence tolerance and UI performance constraints to `AGENTS.md`.
- Added an engineering standards document centralising code organisation, state orchestration, provider protocol boundaries, persistence, UI, file system and test review rules.
- Updated the developer guide, design document and project memory, correcting an outdated directory structure and the ProjectThreads controller / view model split.

## 2026-07-04

### Initialised the project documentation

- Established the documentation set: product requirements, design document, developer guide, development log and project memory.
- Surveyed the state of the code: Zeta had evolved from the default Flutter sample into a desktop agent IDE shell.
- Recorded the core capabilities at that point: three-column IDE layout, local project file tree, Codex CLI provider, agent thread restore, tool timeline, permission approval and session persistence.
- Kept the existing Flutter AI reference material and linked it from the documentation index.

### Baseline at the time

- Application entry point: `lib/main.dart`.
- Root widget: `MainApp`.
- Core screen: `IdeHome`.
- Default agent provider: Codex CLI app-server.
- Session state version: 2.
- Supported platform directories: `linux`, `macos`, `windows`.

### Suggested follow-ups at the time

- Replace the default Flutter README with a Zeta project description.
- Define the product scope for provider configuration management.
- Decide whether to add a built-in file preview or editor.
- Add widget or integration tests for the key user flows.
