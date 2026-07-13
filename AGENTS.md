# Project AI Rules

This is a Flutter project named `zeta`. Follow these rules when making
changes in this repository.

## Project Context

- The app is a Flutter Desktop Agent IDE shell with `lib/main.dart` as the
  entry point and `lib/src/app` as the composition boundary.
- Supported generated platform folders are `linux`, `macos`, and `windows`.
- The project uses `flutter_lints` through `analysis_options.yaml`.
- Dart and Flutter skills are installed under `.agents/skills`; use the
  relevant skill for focused tasks such as widget tests, integration tests,
  static analysis, routing, localization, JSON serialization, responsive
  layout, package conflicts, or coverage.

## Default Workflow

- Prefer small, focused changes that match the current feature-sliced project
  shape.
- Run `dart format .` after editing Dart files.
- Run `flutter analyze` before finishing code changes.
- Run `flutter test` when tests exist or when adding/changing behavior.
- If a generated file or platform file changes unexpectedly, explain why before
  keeping the change.

## Flutter And Dart Style

- Use modern, sound null-safe Dart.
- Favor `const` constructors and immutable widgets wherever possible.
- Compose UI from small widgets; use private widget classes when a `build`
  method becomes large.
- Keep functions short and single-purpose.
- Use descriptive `camelCase` names for members and `PascalCase` for classes.
- Use `snake_case.dart` file names.
- Avoid `print`; use `dart:developer` logging for diagnostics that should stay
  in code.
- Add `///` documentation for public APIs, but avoid comments that merely
  restate obvious code.
- 新实现的代码优先使用中文注释；公共 API、协议适配、状态机、错误处理和不易
  直观看懂的分支应尽可能补充 `///` 或简短行内注释，同时避免只复述代码字面
  行为的空注释。

## Architecture

- Treat the current `lib/src` structure as feature-sliced architecture:
  `app` composes runtime dependencies, `core` holds cross-cutting utilities,
  `features/<feature>` owns domain/application/data/presentation code, and
  `ui/core` holds shared theme and shell widgets.
- Keep dependency direction explicit: presentation depends on application and
  domain contracts; application coordinates workflows; data implements external
  protocols and storage; domain models stay pure and UI-agnostic.
- Do not put new feature code back into broad top-level `data`, `domain`, or
  `ui` buckets when a feature package is the natural owner.
- Keep `main.dart` limited to startup, global error logging, desktop window
  bootstrap, and `runApp`. Put app wiring in `lib/src/app`.
- Keep concrete protocol details such as Codex app-server JSON-RPC, JSONL
  history parsing, and provider configuration inside the agent data layer and
  mappers. UI code should consume neutral domain events and provider contracts.
- For simple local UI state, prefer Flutter built-ins such as `StatefulWidget`,
  `ValueNotifier`, `ValueListenableBuilder`, `FutureBuilder`, and
  `StreamBuilder`.
- When state becomes shared or complex, split responsibilities into:
  immutable domain state, application controllers for async orchestration, and
  presentation view models or listenable signals for rendering.
- Use token/version guards for async loads that can be superseded, and check
  disposed state before notifying listeners.
- Expose collection state as unmodifiable snapshots unless mutation is an
  intentional part of the API.
- Prefer constructor dependency injection for testability.
- Add third-party state management only when explicitly requested or clearly
  justified by the feature.

## Dependencies

- Use `flutter pub add <package>` for runtime dependencies.
- Use `flutter pub add dev:<package>` for development dependencies.
- Before adding a package, check whether Flutter or Dart already provides a
  simple built-in solution.
- Explain the purpose of every new dependency in the final summary.

## UI, Layout, And Accessibility

- Theming is built on `shadcn_flutter` plus design tokens in `lib/src/ui/core/`:
  `IdeColors`, `IdeRadius`/`IdeEffects`, `IdeSpacing`, `IdeTextStyles`, and
  `IdeMotion`. Graphite tokens are the semantic source of truth via
  `IdeThemeScope`; `sf.ThemeData` is only a projection for third-party widgets.
  Do not use Material `ThemeData`/`ColorScheme.fromSeed` styling,
  raw `Color(0x...)` values, hand-written `BoxShadow` lists, or ad-hoc
  `BorderRadius.circular(...)` in feature code.
- Import `shadcn_flutter` only as `sf`
  (`import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;`). Never use bare
  `Shad*` APIs from the removed `shadcn_ui` package.
- Resolve brightness through `IdeThemeScope.of(context).brightness` or
  `sf.Theme.of(context).brightness`. Prefer `IdeColors.of(context)` /
  `IdeTextStyles.of(context)` for semantic tokens.
- Use `showIdeToast` from `lib/src/ui/core/ide_toast.dart` for IDE notifications;
  do not call `sf.showToast` ad hoc from feature pages.
- Build responsive layouts that work on desktop-sized windows as well as narrow
  viewports.
- Use `LayoutBuilder`, `Flexible`, `Expanded`, `Wrap`, scroll views, and builder
  constructors to avoid overflow.
- Reuse `ui/core` primitives such as `Pane`, `PanelCard`,
  `PaneInteractiveSurface`, `IdeChip`, `IdeContextMenu`, `IdeStatusCard`,
  `IdeCollapsibleCard`, and the window frame before introducing feature-local
  visual primitives.
- Keep the IDE UI compact, dense, and scannable. Long file paths, thread titles,
  tool summaries, and status text must use bounded layout and ellipsis.
- Use stable `ValueKey`s for repeated interactive timeline, thread, and file
  tree rows. Add `RepaintBoundary` around expensive or high-frequency regions
  such as streaming turns, highlighted code, and diff details.
- Ensure text remains readable with larger system text sizes.
- Add semantic labels for non-text controls and important custom widgets.

## Navigation

- Keep `Navigator` for simple, short-lived flows.
- Use `go_router` only when the app needs declarative routing, deep links, or
  multiple durable screens.

## Data And Code Generation

- Use plain Dart models for simple local data.
- Keep persisted JSON versioned and tolerant. `tryDecode`-style readers must
  handle missing fields, damaged content, and older versions without blocking
  app startup.
- Keep global provider configuration separate from project/session state.
- Do not leak raw provider payloads into presentation; add mapper or codec
  helpers near the data source instead.
- If JSON models become complex or API-backed, prefer `json_serializable` and
  `json_annotation`.
- When using code generation, ensure `build_runner` is present and run:

```sh
dart run build_runner build --delete-conflicting-outputs
```

## Testing

- Add widget tests with `flutter_test` for UI behavior.
- Add unit tests for non-UI logic.
- Add integration tests only for end-to-end user flows.
- Prefer fakes or stubs over mocks; use mock packages only when they are clearly
  needed.
- Structure tests with Arrange, Act, Assert.

## Repository Hygiene

- Keep platform directories generated by Flutter unless a task explicitly
  targets native desktop behavior.
- Do not commit build outputs or `.dart_tool` contents.
- Update this file when the project adopts routing, localization, app-wide
  state management, networking, assets, or a formal feature/module structure.
- Keep `docs/engineering_standards.md`, `docs/developer_guide.md`, and
  `docs/design_document.md` aligned when architecture boundaries change.

## Git 提交信息
每次你修改或更新完代码后，必须在回复的最后附加一个【Git 提交信息】模块。
该模块要求如下：
1. 使用标准化的 Conventional Commits 格式（如 feat:, fix:, docs:, refactor:, chore: 等）。
2. 用一句简短的中文/英文概括主要修改（不超过 50 个字符）。
3. 如果有必要，换行提供具体的修改点列表（Body）。
4. 使用独立的代码块包裹，确保我可以一键复制直接用于 `git commit -m` 或 Git 提交面板。

输出示例：
### 📝 Git Commit Message
```sh
feat(auth): 优化登录接口的错误处理逻辑

- 增加了对验证码过期的状态码拦截
- 修复了前端重复提交请求的 bug