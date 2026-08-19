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

## 2026-08-19 — Step 12 hosted-source lockfile portability

**Problem.** The Step 12 `license_check` run `32269642148` failed before license inspection because
`flutter pub get --enforce-lockfile` reported that all 176 hosted dependencies would change.

**Evidence.** Versions and SHA-256 values were unchanged. The only bulk difference was that the local
`PUB_HOSTED_URL=https://pub.flutter-io.cn` environment had rewritten every hosted URL in
`pubspec.lock`, while GitHub Actions intentionally resolves against `https://pub.dev`.

**Decision.** Regenerate and verify the lockfile with scoped official-source environment variables.
Keep the dependency versions and checksums unchanged; do not weaken the lockfile, CI, or license gate.
Future dependency updates must similarly normalize the committed lockfile to `https://pub.dev` even
when the developer machine uses a mirror.

**Impact.** `flutter pub get --enforce-lockfile` now succeeds against the same source used by CI. The
failure was a reproducibility defect in the committed lockfile, not a dependency-license exception.

## 2026-08-19 — Step 12 host-independent coverage

**Problem.** After the lockfile portability fix, `zeta` run `32269931378` passed all 168
`codex_app_server_client` tests on Linux but reported 99.78% coverage. The local Windows run had
reported 100% because two recovery tests returned early on non-Windows hosts.

**Evidence.** The uncovered behavior is Windows CLI discovery and launcher recovery, while
`CodexCliLocator` already exposes explicit environment, platform, and file-existence seams. The
earlier owner instruction exempted coverage only in the legacy repository, not in this VGV target.

**Decision.** Keep the VGV package coverage threshold at 100%. Exercise all Windows PATH,
LOCALAPPDATA, APPDATA, command-wrapper, and UNC-path behavior through the existing pure-Dart seams
on every host. Do not add coverage exclusions or weaken the CI gate.

**Impact.** CLI discovery tests no longer depend on the runner operating system. The Linux result is
validated by the next pushed run while the production API and shared Provider ports remain unchanged.

## 2026-08-20 — Step 13 Claude package boundary and deferred capabilities

**Problem.** The legacy Claude adapter referenced application localization, global logging, the auth
probe, and token-usage sources. A file-for-file copy would cross the new Data-package boundary and
pull Step 16/21 responsibilities into Step 13.

**Evidence.** The frozen `agent_provider_contracts` already expresses conversation, permission,
question, plan, model, quota, and history behavior without another Provider method. The migration plan
assigns the Claude auth probe to `agent_management_client` and Provider token-metering sources to the
usage step.

**Decision.** Limit `claude_code_client` to the stream-JSON runtime, vendor mappers/adapters, history,
quota, read-only credential/keychain sources, and the single CLI locator. Replace application text with
a package-private stable-English catalog and use an injectable scoped logger. Defer the auth probe to
Step 16 and token metering to Step 21. Do not change the shared adaptation layer or Provider ports, and
export only the factory, static capabilities, and locator.

**Impact.** Pubspecs and barrels keep vendor isolation machine-checkable. This package does not write
credentials, and exceptions/logs omit tokens, stderr, paths, and raw protocol bodies. Deferred work
remains explicitly tracked rather than silently omitted.

## 2026-08-20 — Step 13 coverage convergence and state-recovery hardening

**Problem.** The first complete coverage run was 85.51%. Gaps mixed reachable process/stream/filesystem
failures with duplicated branches strictly dominated by earlier session validation, peer cleanup, or
mapper normalization. Fault injection also found that if a new peer failed during a model/permission
switch and restoration failed too, the provider retained a bound but never-started peer.

**Evidence.** The call graph shows that session id and working directory are installed together,
pending registries clear before peer detachment, and the history reader's own mapper/file tracker has
already normalized title, kind, locations, and input before reduction. In contrast, injected stdin,
control-response, filesystem, double-restoration, and concurrent-switch failures were reproducible.

**Decision.** Keep the 100% gate without coverage ignores or threshold reductions. Add internal seams
and real regression tests for reachable I/O and state-machine failures, while removing only duplicated
checks proven unreachable by same-chain invariants. Tear down a failed restoration peer immediately so
the provider returns to an explicit unavailable state instead of retaining a half-initialized transport.

**Impact.** 264 randomized tests cover permissions/questions/plans, identity, history, process
lifecycle, Windows/POSIX locator behavior, and keychain boundaries at 100% hand-written coverage
(2,962 / 2,962). Test seams stay out of the barrel and do not expand shared contracts.

## 2026-08-20 — Step 13 metadata async leak and smoke path

**Problem.** A formal randomized gate found that the metadata probe armed its timeout before process
startup. After startup had already returned a sanitized failure, the orphaned timer later threw into
the test zone. The fixture smoke then falsely rejected the valid fixture because its script still used
the legacy `test/src/features/...` path.

**Evidence.** Shortening the startup-failure timeout reliably reproduced a failure after test
completion. The fixture's current owner is
`packages/claude_code_client/test/src/datasources/claude_code/fixtures/`, and its contract tests pass.

**Decision.** Create the timeout future only after the peer starts and the initialize frame is sent,
so earlier failures leave no async task. Add a regression assertion that waits beyond the timeout.
Point the smoke script at the package-owned fixture instead of copying it. Real smoke remains a
no-prompt, read-only initialize and never runs configuration-changing operations.

**Impact.** Two randomized Very Good test/coverage rounds are stable. Both the fixture smoke and a
real Claude Code 2.1.227 initialize smoke pass, and output is limited to OS/architecture/version,
model/default counts, and a sanitized subscription label.

## 2026-08-20 — Step 13 official-source lockfile verification

**Problem.** `flutter pub get --enforce-lockfile` under the official `pub.dev` environment found that
the working lockfile still carried China-mirror URLs, so it reported 176 dependency changes even
though versions and checksums were not in conflict.

**Decision.** Treat the official source as part of the approved Flutter 3.47.0 / Dart 3.13.0 baseline:
resolve once against the official source, then immediately verify with `--enforce-lockfile`. Never
commit workstation mirror URLs to the repository.

**Impact.** Verification passes with unchanged locked versions and no `flutter-io.cn` entries in
`pubspec.lock`. No shared adaptation layer or Provider port is affected.

## 2026-08-20 — Step 14 Grok contract and sequencing discrepancy

**Problem.** Step 14 requires Grok usage/history contracts, but the shared contracts do not contain
the usage-window types assumed by the plan. The manifest also assigns vendor-specific Grok history
readers/parsers to Step 15 even though Step 14 explicitly requires history contract tests.

**Evidence.** Existing neutral contracts already express quota, token usage, and thread history. The
legacy usage-window labels are vendor-internal and need no Provider method. Step 15 explicitly retains
only cross-provider merge/replay and generic tolerance, forbidding duplicate vendor parsers.

**Decision.** Do not modify the shared adaptation layer or Provider ports. Keep usage-window labels as
a package-private Grok helper. Move Grok-private history readers/parsers with Step 14 and reserve Step
15 for cross-provider aggregation. Keep the barrel limited to factory, static capabilities, and locator.

**Impact.** Step 14 closes its usage/history contract independently, while Step 15 will not duplicate
Grok protocol parsing. The sequencing discrepancy is explicit and the shared API does not expand.

## 2026-08-20 — Step 14 coverage and runtime-invariant convergence

**Problem.** Initial full coverage was 83.01%. Reachable gaps included filesystem failures,
permissions/questions/plans, prompt races, model merging, title polling, and replay prefixes. A few
checks duplicated guarantees already established by `ProviderRuntimeJsonRpcPeer` or pending registries.

**Evidence.** Injected failures reproduce malformed UTF-8, response failure, late prompt errors,
dispose/cancel paths, and offline history. The call chain also proves that successful initialization
has a runtime scope, only permissions with non-empty options enter pending state, and forwarded
notifications/server requests carry the current runtime scope.

**Decision.** Keep the 100% gate with no coverage ignores or threshold reductions. Add contract tests
for real failures and remove only checks strictly dominated by same-chain invariants. Retain async file
I/O and disable `avoid_slow_async_io`; disable internal-symbol `public_member_api_docs` while keeping
documentation on all three barrel exports.

**Impact.** 233 randomized tests reach 100% hand-written coverage (3,257 / 3,257) with zero analyzer issues.
No test-only symbol enters the barrel and no shared Provider port changes.

## 2026-08-20 — Step 14 real Grok recovery smoke race

**Problem.** The first Grok CLI 1.0.4 smoke passed both isolated-process prompts, but immediately
reclaimed the source process after its terminal and timed out under a coarse `recovery/timeout` label.
The CLI also auto-updated to 1.0.5 between runs.

**Evidence.** The harness exposed no session id, content, payload, raw stderr, or credential. After
adding stage-specific recovery labels and a bounded two-second persistence window following source
process shutdown, the CLI 1.0.5 rerun passed both concurrent sessions and the fresh-process
`session/load` prompt with `end_turn`.

**Decision.** Treat the first failure as a race between terminal delivery and asynchronous local
session persistence. Keep the two-second flush window and precise stage labels; do not weaken timeout,
retry prompts, or read a real project. Set the live baseline to Windows 11 / Grok 1.0.5 / 2026-08-20.

**Impact.** AC1 process isolation and post-reclaim recovery now have real-CLI evidence. The smoke still
uses temporary empty directories, Ask defaults, and rejection of reverse requests without changing
user configuration.

## 2026-08-20 — Step 14 workstation mirror rewrote the lockfile again

**Problem.** A focused diagnostic test omitted scoped official-source variables, so Flutter dependency
resolution rewrote 176 hosted URLs to `pub.flutter-io.cn` again.

**Decision.** Mechanically restore `pub.dev` and verify that the final lockfile has no diff. Formal gates
continue to scope official pub and Flutter storage sources. Versions, checksums, and constraints remain
unchanged.

**Impact.** No mirror URL or unrelated lockfile noise enters the Step 14 commit.

## 2026-08-20 — Step 13 desktop-build Linux toolchain timeout

**Problem.** The Step 13 desktop-build run `32277823777` was cancelled at the 30-minute workflow
timeout. All three macOS flavors, all three Windows flavors, and Linux staging succeeded. Linux
development and production remained in `Install Linux desktop toolchain` and never reached Flutter or
the build step.

**Decision.** Classify this as runner apt/toolchain timeout, make no product-code accommodation, and do
not count partial success as a full desktop gate. Require the complete matrix after the Step 14 push;
only optimize workflow installation if the same apt stage times out again.

**Impact.** Step 13 zeta, license, and OSV runs succeeded. Full desktop-matrix evidence carries forward
to Step 14 remote verification.

## 2026-08-20 — Step 14 Linux coverage platform divergence

**Problem.** The local Windows gate reached 100% (3,257 / 3,257), while GitHub Actions zeta run
`32284769504` twice reported 99.79% after all 233 tests passed. On the same commit, desktop-build run
`32284769075` passed all nine OS/flavor jobs, and the Step 13 Linux apt timeout did not recur.

**Evidence.** After retaining a generic uncovered-line diagnostic in CI, run `32285470965` identified
exactly seven lines: Linux did not enter the Windows `APPDATA/npm` locator branch or the history
reader's cross-project recursive fallback. Both are real compatibility paths whose prior coverage
depended on host platform and fixture path encoding.

**Decision.** Keep the 100% threshold and add neither coverage ignores nor exclusions. Add an explicit
Windows-mode APPDATA locator test and a recursive history lookup test with no project/session path, so
every runner verifies both compatibility paths. Retain uncovered file/line output as a generic failure
diagnostic for every package.

**Impact.** The Grok package now has 235 randomized tests and remains at 100% locally
(3,257 / 3,257). The fix changes tests and CI diagnostics only, with no production implementation,
shared adaptation layer, or Provider port change.

## 2026-08-20 — Step 15 has no legacy aggregator and needs explicit merge semantics

**Problem.** The plan calls for a provider-neutral history merge/replay input, but the legacy repository
contains only Codex, Claude, and Grok parser/readers and no cross-provider aggregator to move. The target
package is a template placeholder; copying any vendor parser would violate the Step 15 boundary.

**Decision.** Implement the approved contract as a new generic JSON Lines framing boundary. Callers
inject the whole-input reader and vendor decoder, so this package never understands vendor fields.
Malformed JSON, non-object values, and explicit `HistoryRecordDecodeException` failures skip only that
line and produce a typed warning. Reader IO failures and all other decoder failures escape. Inputs retain
caller order, while a later duplicate turn id replaces content at its first-seen position. Warnings retain
no raw line, exception, or user content.

**Impact.** `agent_history_client` depends only on `agent_provider_contracts`; unused template logging,
storage, and mocking dependencies are removed, and the barrel exports only `history_merge.dart`. It has
no vendor, Flutter, Repository, or UI dependency and changes no shared Provider port. Five randomized
tests reach 100% coverage (41 / 41).

## 2026-08-20 — Step 16 legacy repositories exceed the new Data boundary

**Problem.** The three legacy management repositories mix external IO with runtime-registry access,
model catalog assembly, localized text, latest-version checks, and UI progress state. Copying them
would violate the Step 16 contract. At the same time, each vendor package already owns its only valid
CLI locator, so reimplementing path discovery here would create competing owners.

**Decision.** Implement a fresh `AgentManagementDataSource` boundary rather than copy the legacy
repositories wholesale. Inject vendor-owned path resolution, CLI location, prompt-free protocol
probing, and account-evidence callbacks. Return stable neutral response objects and failure codes;
leave runtime catalogs, localization, repository policy, and UI state for their later layers. Do not
modify the shared adaptation layer or Provider ports.

**Impact.** The three concrete management sources depend on contracts and shared IO utilities only;
they do not import one another, any vendor client, Flutter, Repository, or Presentation code. Step 17
can prove locator ownership without reconciling duplicate implementations.

## 2026-08-20 — Step 16 configuration contract differs from legacy behavior

**Problem.** The Step 16 API explicitly requires read/write configuration with only `contents` on
save. Legacy Codex/Grok saves also accepted an original snapshot for optimistic conflict detection,
while legacy Claude exposed metadata only and rejected every save. Preserving either behavior would
contradict the approved public contract.

**Decision.** Follow the new contract: support current-syntax TOML for Codex/Grok and a JSON object for
Claude, refuse symbolic links, copy an existing backup, and delegate atomic replacement to
`zeta_storage`. Keep the document signature as read evidence but do not invent an unused conflict
exception that the save API cannot enforce. Convert only known parser `FormatException`s to safe typed
validation codes; unexpected parser failures propagate. Retain asynchronous Data IO and disable the
inapplicable `avoid_slow_async_io` lint for this package.

**Impact.** Claude configuration editing becomes available for the current schema as the migration
plan requires. Codex/Grok no longer claim an optimistic-concurrency guarantee absent from the new API;
the later Repository/UI must reread after save and can propose a contract change separately if such a
guarantee is required.

## 2026-08-20 — Step 16 credential and log minimization

**Problem.** The legacy Grok detector infers account state by reading `auth.json`, and raw CLI output,
configuration, or logs can contain credentials. Returning those payloads from a generic management
client would enlarge the secret-handling surface.

**Decision.** Do not read Grok credential-file contents. Inject account evidence, and make the Claude
probe run only `auth status --json`, accepting exit codes zero and one while retaining only four
whitelisted non-secret fields. Bound process output and log tails, refuse unsafe log paths, and redact
common token/key/password patterns before returning log entries. Never log raw auth JSON, stdout,
stderr, configuration, or caught exceptions.

**Impact.** Static security inspection finds no embedded secret, raw credential logging, or dependency
on provider credential storage. Detection remains prompt-free, and unavailable evidence is represented
as a neutral status rather than guessed from a credential filename.

## 2026-08-20 — Step 16 cross-platform process fixture and official sources

**Problem.** The first real-process test invoked `Platform.resolvedExecutable --version`; under
`flutter test` that executable is the Flutter test host, not the Dart CLI, so the success assertion
failed. One earlier `--no-pub` diagnostic also omitted scoped official-source variables and printed the
workstation China-mirror warning, although it did not resolve dependencies or change the lockfile.

**Decision.** Exercise the default process starter with a disposable cross-platform system shell and
a bounded sleep command, while keeping deterministic process behavior behind injected fakes. Remove
an unreachable catch-all parser branch instead of excluding it from coverage. Run final package and
workspace gates with explicit `pub.dev`/Google storage variables, then verify the lockfile with
`flutter pub get --enforce-lockfile`.

**Impact.** The package has 35 randomized tests and reaches 100% CI-counted coverage (329 / 329) on
Windows without coverage ignores. The final workspace iteration passes 1,052 tests at 12,941 / 12,941;
the lockfile retains official sources and no mirror or test-host assumption enters production code.
