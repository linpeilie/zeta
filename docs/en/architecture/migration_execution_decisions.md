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
