# Contributing

English ｜ [中文](CONTRIBUTING.md)

Integrate daily development into `develop`; `main` always holds the latest production-ready stable version. Read the [engineering standards](docs/zh/architecture/engineering_standards.md) (Chinese) relevant to your change.

## Branch model

The project uses the existing `main` and `develop` as its two long-lived branches; no separate `master` or `dev` is used.

| Branch | Source | Purpose and merge targets |
| --- | --- | --- |
| `main` | Long-lived | Always contains the latest production-ready stable version; receives validated `release/*` and `hotfix/*` PRs. |
| `develop` | Long-lived | Daily integration; every feature and fix must ultimately reach this branch. |
| `feature/*` | `develop` | Features and routine fixes; merge back into `develop` through a PR. |
| `release/*` | `develop` | Final testing, necessary fixes and version updates; merge into `main` through a PR for publication and tagging, and back into `develop` through a separate PR. |
| `hotfix/*` | `main` | Urgent fixes for severe production problems; merge into `main` through a PR for publication and tagging, and back into `develop` through a separate PR. |

Auxiliary branches are temporary. Delete them only after all target PRs have merged; for `release/*` and `hotfix/*`, also confirm publication and tagging succeeded. Do not delete the source after merging only into `main` while its `develop` PR is still pending. Keep both long-lived branches.

Examples: `feature/notification-logo`, `release/0.1.0`, `hotfix/0.1.1`. Review merges through GitHub PRs; opening a PR does not authorize local merges, rebases or automatic PR merging. See the [release guide](docs/en/release/release_guide.md) for publication and tagging.

## Environment

Use the Flutter version in [CI](.github/workflows/ci.yml), the Dart constraint in [pubspec.yaml](pubspec.yaml), and the Flutter Desktop build environment for your platform.

```sh
flutter pub get --enforce-lockfile
flutter run -d windows
```

Use `macos` or `linux` on those systems. Linux build dependencies and other commands are in the [developer guide](docs/zh/development/developer_guide.md) (Chinese).

Assistant integration work needs the corresponding installed, signed-in assistant. Documentation and isolated tests do not need real accounts. Use fakes in tests without accidentally accessing local credentials or starting paid conversations.

## Changes and PRs

1. Create `feature/*` from `develop` for features and routine fixes, then open a PR back to `develop`. Follow the branch model below for releases and urgent fixes. Inspect existing changes and preserve others' work.
2. Keep each PR focused. Define scope, contracts and verification before adding a provider or making a broad architectural change.
3. Add relevant tests and update current documentation. Put user-visible changes in [CHANGELOG.md](CHANGELOG.md).
4. Run applicable checks below. Describe the actual change, results and checks not performed in the PR.

Use Conventional Commits, for example `fix(agent): retain history titles`. Keep the summary within 50 characters and explain the reason in the body when needed.

## Verification

```sh
dart format .                 # After editing Dart
flutter analyze               # Before finishing code changes
bash tool/test_affected.sh     # For behavior changes
```

- Internal package: `bash tool/test_packages.sh --only <package>`.
- Code refactoring, releases or test infrastructure: `bash tool/test_full.sh`, including internal packages.
- UI text: `dart run tool/check_localized_ui_strings.dart --check`.
- Documentation only: check links, heading anchors, facts and translations using the [documentation checklist](docs/zh/development/documentation.md); Flutter tests are not required.

Use targeted or affected tests while developing. Keep concurrency at 2. CI runs every shard and internal package. Register new top-level test directories in `tool/test_shards.dart`. Do not weaken business assertions to make refactoring pass.

The shared lockfile uses `https://pub.dev`. Review changes before submitting and avoid local mirror URLs or unintended upgrades. Record real-CLI and platform checks separately; automated success does not prove real-device behavior.

## Architectural hard lines

- Vendor protocols stay in each plugin's data layer. UI and shared core consume neutral contracts.
- Providers determine message identity and file-change evidence; the shared store does not guess IDs or read raw protocol data.
- Reducers are synchronous and free of side effects. Async operations recheck conversation identity and lifetime.
- Unsupported capabilities hide their controls and fail explicitly.
- Permissions, questions, plan approval and execution handoff remain separate. Accepting a plan grants no advance permission.
- Each state has one application Notifier owner. Page subscriptions do not determine resource lifetime.
- Sensitive bodies and credentials do not enter Zeta settings, statistics, logs or notifications. Reading assistant data does not authorize writing it.
- UI uses the design system and text catalogs rather than duplicating low-level styling in feature pages.

Details and exceptions are maintained in the [engineering standards](docs/zh/architecture/engineering_standards.md). [AGENTS.md](AGENTS.md) is the concise AI development entry point.

## Reports and license

For bugs, provide reproduction steps, versions and observed results. Report vulnerabilities privately using [SECURITY.md](SECURITY.md). Follow the [code of conduct](CODE_OF_CONDUCT.md). Contributions use the project's [GPL-3.0 license](LICENSE).
