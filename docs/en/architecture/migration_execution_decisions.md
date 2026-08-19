# Migration execution decision log

[中文](../../zh/architecture/migration_execution_decisions.md) | English

Status: **active**. This log records implementation-time mismatches, evidence,
decisions, and their impact after the architecture baseline was frozen. On
2026-08-19 the owner authorized the migration agent to apply its safest
architecture recommendation for later decisions and continue execution.

## 2026-08-19 — Step 10 desktop contract reconciliation

**Problem.** The scaffold-level desktop ports were too narrow to preserve the
legacy product behavior: fonts lost stable family identity; file selection and
clipboard APIs could not represent multiple images/files; and menu, window,
attention, and system-file-manager operations lacked required typed inputs.

**Evidence.** Legacy macOS/Windows/Linux runners and app composition exercised
these behaviors, while the frozen rule still prohibited Flutter/plugin values
from crossing the shared package boundary.

**Decision.** With explicit owner approvals, expand only the pure-Dart value
contracts and keep every concrete plugin/channel implementation in
`lib/app/platform/`. Use structured immutable values and injected facades; do
not expose plugin types.

**Impact.** Step 10 preserved behavior without moving platform IO into Bloc or
Presentation. Native contract tests and a Windows Debug build validated the
result; no Provider port changed.

## 2026-08-19 — Step 11 current-schema failure semantics

**Problem.** The legacy Provider codec accepted settings V1 and V2, migrated
permission fields, and silently returned defaults or empty cache/context values
for malformed files. The Step 11 plan requires current-schema-only persistence
and typed decode failures. The shared `AgentProviderSettings.supportedVersions`
and `AgentModelCatalogCacheStore` documentation still described the legacy
behavior.

**Evidence.** `AgentProviderSettings.supportedVersions` was `{1, 2}` and the
cache port required corrupt/incompatible content to return an empty list,
directly contradicting the Step 11 task and package API contract.

**Decision.** Approved by the owner: support Provider settings V2 only; treat
unknown versions, malformed JSON, invalid shapes, duplicates, and stored thread
identity mismatches as typed decode failures. A missing file remains a normal
first-run state (empty list or `null`). The upper layer, not the Data client,
decides whether to rebuild. Do not persist active Provider selection state and
do not add or change Provider method signatures.

**Impact.** The shared contract documentation and supported-version constant
change to the current schema only. `agent_config_client` fails closed without
historical migration or silent truncation, uses atomic replacement, and keeps
CLI locators, Controllers, and selection state out of the package.

## 2026-08-19 — Step 12 Codex protocol baseline and package boundary

**Problem.** The Step 12 destination package was a placeholder, while the required pinned
Codex `0.144.5` schema snapshot and generation scripts existed only in the legacy repository.
The legacy adapter also depended on application localization and logging globals that cannot cross
the new Data/neutral-contract boundary.

**Evidence.** The legacy snapshot contained exactly 269 files and matched the documented pin. The
frozen package API permits only the bundle factory, static capabilities, and CLI locator in the
barrel, and requires peer, process, logger, and clock seams. No shared Provider signature needed to
change.

**Decision.** Copy the snapshot byte-for-byte, migrate both generation scripts, and contract-test
the file count, version pin, messages, terminal notifications, capabilities, and server requests.
Keep application localization out of the package: neutral status uses typed codes, while the few
protocol items requiring a readable label use a private stable-English fallback catalog. Export only
the three frozen entry points. Keep focused protocol test access under `lib/src/testing/`, omitted
from the barrel.

**Impact.** The Codex implementation and its schema truth source are independently owned and tested
by `codex_app_server_client`; Presentation/localization packages are not imported, and neither the
shared adaptation layer nor Provider ports changed.

## 2026-08-19 — Step 12 CLI path and coverage hardening

**Problem.** Compatibility testing exposed a Unix HOME fallback bug: joining path segments removed
the leading `/`, producing a relative Codex executable path. The first full package coverage run was
87.66%, mostly in tolerant protocol and lifecycle branches inherited from the legacy adapter.

**Evidence.** A Unix HOME locator test reproduced the relative-path result. Coverage reports also
identified duplicated or unreachable defensive branches (including a second patch-output fallback
and an impossible post-validation conversation-mode case), plus reachable malformed/future protocol
shapes without focused tests.

**Decision.** Preserve Unix roots and Windows UNC prefixes in the single CLI locator. Keep the 100%
gate unchanged and add real compatibility/lifecycle tests, an internal non-barrel protocol harness,
and an injected local-file read seam. Remove only branches proven unreachable or duplicated by the
current call graph; do not add coverage ignores or lower the threshold.

**Impact.** Unix fallback resolution is absolute, process recovery is tested on platform/config
environment combinations, and Step 12 reaches 100% hand-written coverage (3,601 / 3,601) across
168 tests. The test seams remain internal and do not expand the supported package API.

## 2026-08-19 — Step 11 desktop run cancellation

**Problem.** The Step 11 desktop-build workflow run `32262347277` completed as cancelled while its
jobs reported no failure.

**Decision.** Treat it as a concurrency cancellation rather than a product failure, record it, and
require the next pushed migration commit to run the complete desktop matrix again.

**Impact.** No code was changed to accommodate an unobserved failure; remote desktop validation is
carried forward to the Step 12 push.
