# Contributing to Zeta

[中文](CONTRIBUTING.md) ｜ English

Thanks for your interest in Zeta. This document covers environment setup, day-to-day commands, the PR process, and the architectural **hard lines** this project enforces.

Reading it once before you start will save you most of the rework.

## Contents

- [Three things first](#three-things-first)
- [Setting up](#setting-up)
- [Everyday commands](#everyday-commands)
- [Before you commit](#before-you-commit)
- [Commit message format](#commit-message-format)
- [Pull request process](#pull-request-process)
- [Architectural hard lines](#architectural-hard-lines)
- [Testing expectations](#testing-expectations)
- [Reporting issues](#reporting-issues)
- [License](#license)

## Three things first

1. **The default branch is `dev`.** Branch from it and target it in PRs.
2. **Keep changes small and focused.** For large refactors, new providers, or changes to event-pipeline contracts, open an issue to discuss the approach first — please don't drop a several-thousand-line PR unannounced.
3. **This project enforces strict layering.** A PR that violates the [hard lines](#architectural-hard-lines) won't be merged even if the feature works. These constraints exist so that multiple providers can coexist without contaminating each other — they aren't box-ticking. The [architecture overview](docs/architecture/overview.en.md) explains why in about 15 minutes.

## Setting up

**Requirements**

- Flutter SDK (stable channel), compatible with the Dart SDK constraint `^3.12.2` in `pubspec.yaml`
- CI builds with **Flutter stable 3.44.4**; a very different local version may produce different analyzer results
- A working Flutter Desktop environment (macOS / Windows / Linux)

**Extra build dependencies on Linux**

```sh
sudo apt-get update && sudo apt-get install --yes \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libfontconfig1-dev
```

**To exercise agent features you also need**

- **Codex** (default provider): `codex app-server` must be runnable locally. Without `--listen` it communicates over stdio. The adapter is developed against a pinned schema — see [Codex app-server protocol pinning](docs/protocols/codex_app_server_protocol.md).
- **Grok** (optional): Grok CLI (grok-build) **0.2.119 or newer**. That's the multi-session compatibility baseline; earlier versions can't correctly isolate session state or turn terminal states when several Grok sessions are open at once.
- **Claude Code** (optional): `claude` must be runnable and already authenticated. The current stream-json sampling baseline is CLI **2.1.224** (not a minimum-version promise); see the [Claude Code stream-json protocol baseline](docs/protocols/claude_code_stream_json_protocol.md) for boundaries and upgrade checks.

For UI-only or docs-only changes you can skip all of these CLIs — the agent panel will simply report nothing detected.

**Run it**

```sh
flutter pub get
flutter run -d macos    # or -d windows / -d linux
```

## Everyday commands

```sh
dart format .           # required after editing Dart files
flutter analyze         # required before wrapping up a change
flutter test            # required when behavior changes
```

Run a single test file:

```sh
flutter test test/src/features/agent/presentation/agent_conversation_widget_test.dart
```

> `dart_test.yaml` pins `concurrency: 2`. A single worker running the large widget tests loads the full IDE shell, and raising concurrency triggers memory spikes. **Please don't change it to speed up local runs.**

**When upgrading the Codex protocol** (before touching the adapter):

```sh
./tool/gen_codex_schema.sh --diff        # Windows: ./tool/gen_codex_schema.ps1 -Diff
```

Diff `third_party/codex_app_server_schema/` first, then change the adapter. Afterwards, smoke against the real CLI:

```sh
python tool/smoke_codex_app_server.py --expected-version 0.144.5
python tool/smoke_codex_plan_mode.py --expected-version 0.144.5
```

The smoke scripts use a temporary read-only workspace and never emit prompts, responses, file contents, credentials, or raw JSONL. See [developer guide §3](docs/guides/developer_guide.md) (Chinese).

## Before you commit

Run all three, in order:

```sh
dart format .
flutter analyze
flutter test
```

CI runs the same checks (plus `dart format --set-exit-if-changed` and `--enforce-lockfile`), so a local pass saves a round trip.

Also:

- If generated platform directories (`linux/`, `macos/`, `windows/`) show unexpected changes, **confirm they came from Flutter tooling** and explain in the PR why you're keeping them.
- Before adding a third-party dependency, confirm the Flutter/Dart built-ins genuinely fall short, and describe what each new dependency is for in the PR description.

## Commit message format

[Conventional Commits](https://www.conventionalcommits.org/), summary under 50 characters:

```
feat: add grok thread archiving
fix: guard stale model catalog overwrite
docs: add bilingual contributing guide
refactor: extract plan handoff controller
chore: bump flutter action pin
```

Common types: `feat` / `fix` / `docs` / `refactor` / `test` / `chore` / `perf`.

## Pull request process

1. Branch from `dev`; `feat/xxx` or `fix/xxx` naming is preferred.
2. Keep history clean and don't mix unrelated changes into one PR.
3. Fill in the PR template, especially the **architecture checklist** — if an item doesn't apply, say why.
4. Make sure CI is green.
5. Wait for review. Changes touching the event pipeline, provider contracts, or persistence formats get reviewed closely.

**Behavior changes require tests.** Untested behavior changes generally won't be merged.

## Architectural hard lines

**Reading the code for the first time? Start with the [architecture overview](docs/architecture/overview.en.md)** (~15 minutes, with diagrams) and the [glossary](docs/guides/glossary.en.md). Full rules live in [engineering standards](docs/architecture/engineering_standards.md) and [developer guide §7](docs/guides/developer_guide.md). These are the ones most often tripped over:

**Layering and dependency direction**

- One-way: `main → app → presentation/application → domain`, `app → data → domain`, `presentation → ui/core`.
- New code goes into the matching `features/<feature>/{domain,application,data,presentation}` — not back into broad top-level directories.
- `main.dart` only bootstraps; `lib/src/app` is the single composition point.

**Provider isolation (the big one)**

- Raw provider protocol **may only exist in the data layer**. UI and application code consume neutral domain events and contracts.
- Shared layers (decoder, CoalescingPolicy/Buffer, Pipeline, TimelineStore) **must contain no provider imports, kind branches, id branches, or raw field reads**.
- File changes must become complete typed snapshots in a provider-local tracker first. The Store only carries them mechanically, the UI never reads raw fields, and a command-only path must not invent a path or diff.
- Adding a provider should touch only its own data files, neutral domain contracts, factory wiring, and contract tests. If you find yourself needing to modify a shared layer, the abstraction is wrong — open an issue first.
- UI renders strictly by **capability**, never hard-coded on provider kind or name. Unsupported capabilities must report `capability = false` and throw `UnsupportedError` — **never succeed silently**.
- Provider processes are created only by `AgentProviderRuntimeRegistry`. Global work uses `AgentProviderGlobalRuntime`; session instances are created lazily only by `AgentConversationBinding.beginTurn()`. View models own no lease/scope/pin, and the binding manager owns idle reclamation.
- A workspace entry binds its thread, binding, and view model once. View models expose no cross-thread switch/restore compatibility API and may update only project/file context. Runtime acquisition must pass an explicit scope.
- A binding attached to a real thread must never be rebound in place. A forked session goes through the shell's standard new-thread registration and selection flow, and later operations target only the fork result.
- `AgentProviderBundle` / `AgentRuntimePort` never expose the raw `AgentProvider`; each binding owns one immutable permission snapshot, with no cross-provider/runtime/thread permission registry.

**Event pipeline**

- Before adding or changing an `AgentEvent`, work through all 16 items of the onboarding checklist in [developer guide §7](docs/guides/developer_guide.md) and pin the behavior with tests.
- Reducers must be purely synchronous: no Flutter scheduler, `Timer`, `Future`, or external callbacks. Side effects go through the scope-aware EffectRunner.
- Live / history / replay must each use a **separate reducer instance**.

**Permission model**

- Permission approval, user questions, and plan approval are **three independent domain semantics** and do not share request/decision models.
- The post-plan "execution confirmation" is a local Zeta workflow, not provider plan approval: it must start an explicit new Default turn and must not pre-authorize commands, files, or network access.
- Execution permission restores only a still-valid pre-Plan user selection from the same binding/thread/runtime; otherwise it uses the provider catalog's conservative default. A card override is turn-only and must not apply or persist. **Changes that auto-upgrade authorization will not be accepted.**

**Theming and UI**

- Import `shadcn_flutter` only `as sf`; semantic tokens go through `IdeThemeScope` / `IdeColors.of(context)` / `IdeTextStyles.of(context)`.
- No Material `ThemeData` / `ColorScheme.fromSeed`, no bare `Color(0x...)`, no hand-written `BoxShadow`, no ad-hoc `BorderRadius.circular(...)`.
- Use `showIdeToast` for notifications; don't call `sf.showToast` directly from features.
- The timeline forbids post-frame measurement, `GlobalKey` height probing, and post-layout `setState` feedback loops.

**Persistence and privacy**

- All Zeta-owned data lives under `~/.zeta/`. JSON must be versioned with tolerant `tryDecode` — missing or corrupt fields must never block startup.
- Provider-owned data adapters may read the corresponding CLI's private data for an explicit feature. Protocol fields, raw content, and paths must not leak into upper layers; read access does not authorize migration, rewriting, or deletion.
- Derived indexes and caches store only normalized allow-listed fields. **Never persist prompts, responses, tool output, file-change evidence bodies, raw error text, environment variables, credentials, or provider raw payloads.**

**Misc**

- No `print`; use `dart:developer` or `lib/src/core/logging`.
- Document public APIs with `///`. New comments are preferably in Chinese, focused on protocol adaptation, state machines, error handling, and non-obvious branches.
- **Cursor is retired.** Cursor-related code will not be reinstated.

## Testing expectations

- Behavior changes must at least cover the riskiest state transitions.
- Prefer fakes/stubs over mocks; follow Arrange / Act / Assert.
- Inject dependencies through constructors.
- Tests for shared layers (decoder, coalescing, TimelineStore) must use **provider-agnostic fixtures** and come with architecture guard tests.
- When changing page-switching behavior, add widget tests against the real `IdeHome` verifying that elements, drafts, scroll positions, and panel widths aren't reset.

## Reporting issues

Before filing, skim [troubleshooting and data reference](docs/product/troubleshooting.en.md) — undetected CLIs, missing notifications, and confusing usage numbers are usually answered there.

Please use the [issue templates](https://github.com/linpeilie/zeta/issues/new/choose). Zeta problems are highly environment-dependent, so try to fill in:

- OS and version
- Zeta version (About page or installer filename)
- `flutter --version` output, if running from source
- Agent CLI and version (`codex --version` / `grok --version`)

**Redact logs before pasting.** Logs under `~/.zeta/logs/` may contain your project paths and filenames. They don't record prompts, response bodies, or credentials, but paths can still be sensitive.

**Do not open public issues for security vulnerabilities.** Use GitHub's private reporting instead (Security → Report a vulnerability).

## License

By participating you also agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

This project is licensed under **GPL-3.0** — see [LICENSE](LICENSE). By contributing you agree to license your work under the same terms.
