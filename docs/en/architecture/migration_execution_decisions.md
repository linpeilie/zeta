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

## 2026-08-20 — Step 17 was missing two ruled-in Codex smoke harnesses

**Problem.** The migration manifest explicitly assigns five real-CLI smoke scripts to Steps 17/33/36,
but the target repository contained only the two Claude scripts and the Grok script. Both Codex
scripts remained in the legacy repository. The legacy app-server and Grok smokes also proceed into
sessions and Prompts, which is broader than Step 17's read-only capability probe.

**Decision.** Migrate both legacy Codex scripts byte-for-byte before making scoped additions. Add a
`--capabilities-only` mode to the Codex app-server smoke that stops after initialize and `model/list`,
and to the Grok smoke that performs initialize only, without authenticate, session creation, recovery,
or Prompt. Keep the Codex plan-mode harness unexecuted until its later acceptance step. Do not replace
the existing vendor locators or use a configuration-changing command.

**Impact.** All five ruled-in harnesses are present. Step 17 can exercise current wire capabilities
without model work, user content, session persistence, or configuration mutation, while Steps 33/36
retain the full prompt/session harnesses they require.

## 2026-08-20 — Step 17 makes Provider isolation and teardown executable

**Problem.** Pubspec isolation was already covered generically, but the exact locator owners, fixture
allocation, smoke inventory, and teardown evidence existed only as checklist prose. An initial guard
also assumed every provider test must call `subscription.cancel`; Claude instead proves its listener
completion at the `StreamJsonPeer` boundary when the peer closes.

**Decision.** Declare locator owners and the five smoke scripts in `.architecture.yaml`. Add a root
architecture test that finds exactly one class declaration at each owner path, rejects foreign-vendor
package/path references in every vendor test and fixture, and binds lifecycle evidence to the real
tests. Require explicit subscription cancellation for Codex/Grok; for Claude require provider disposal
plus the peer's `emitsDone` and `close` process/stream assertions. This reflects the actual lifecycle
contract instead of forcing a synthetic test-only subscription handle.

**Impact.** Future duplicate locators, cross-package fixtures, missing harnesses, or removed teardown
proof fail the normal root quality job. No production API or Provider port changes.

## 2026-08-20 — Step 17 real capability-smoke baseline

**Problem.** The gate needed fresh evidence from all three installed CLIs without leaking payloads or
changing user state. A first wrapper that created and recursively removed a computed temporary
directory was rejected by execution safety policy.

**Decision.** Run only the bounded capability paths. Codex capability-only initialize and `model/list`
do not inspect or create a thread, so rerun it from the repository cwd without cleanup mutation;
Claude uses its existing temporary, no-Prompt metadata harness; Grok initialize omits authenticate and
session creation. Report only versions and counts, then inspect the process table for residual protocol
children.

**Impact.** Codex 0.144.1 returns 7 models, Claude Code 2.1.227 returns 5 models with one default, and
Grok 1.0.5 returns protocol v1 with 6 capability keys and 2 auth methods. All pass, no raw payload or
identity is printed, and no Codex app-server, Claude stream-json, or Grok stdio child remains.

## 2026-08-20 — Step 18 system-font ownership conflict

**Problem.** The file-by-file migration manifest assigns the legacy Flutter `MethodChannel`-based
`system_font_catalog_service.dart` to `settings_client`. The more specific Step 18 checklist, package
API contract, topology, and ownership map all prohibit a concrete system-font implementation in this
Data package and assign catalog reads to `settings_repository` through the existing
`SystemFontCatalogApi` in `desktop_platform_api`.

**Decision.** Follow the specific layered-architecture contract. Do not copy the legacy service, do
not modify the shared port, and do not add an otherwise-unused `desktop_platform_api` dependency to
`settings_client`. The later `settings_repository` step will consume the existing port and receive a
platform implementation from composition.

**Impact.** `settings_client` remains pure Dart and owns only general/appearance document IO. There is
no duplicated `MethodChannel`, no premature platform implementation, and no shared adapter or Provider
port change.

## 2026-08-20 — Step 18 current-schema and failure policy differs from legacy

**Problem.** The legacy general codec accepted schema versions 1 and 2, and both legacy stores often
converted corrupt files or IO failures into defaults. The appearance store also included
SharedPreferences migration and callback/domain models. Preserving that behavior would violate the
explicit current-schema-only Data contract and make permission or atomic-write failures look like
successful persistence.

**Decision.** Support general schema v3 and appearance schema v1 only. Represent persisted values as
immutable Flutter-free `Response` objects; leave domain conversion, legacy migration, and policy to the
later Repository. Missing, empty, or whitespace-only clean-install documents return an injected
default. Malformed JSON, invalid fields, and unsupported versions throw content-free typed decode
failures. Storage read/permission failures and atomic-write failures propagate unchanged through an
injectable `SettingsDocumentStorage`; the production adapter delegates to `zeta_storage.AtomicTextFile`.
Keep legitimate asynchronous file IO and disable the inapplicable `avoid_slow_async_io` lint locally.

**Impact.** Corruption cannot be mistaken for a clean install, and failed writes cannot be reported as
success. Tests cover both schemas, missing/empty/corrupt input, denied IO, close behavior, and a real
atomic replacement failure that preserves the old document. The package has no Flutter,
SharedPreferences, Repository, Bloc, Cubit, or concrete system-font dependency.

## 2026-08-20 — Step 18 desktop-build runner timeout

**Problem.** Eight of nine desktop matrices passed, while Linux staging spent the entire 30-minute job
limit installing Ubuntu desktop packages. It was cancelled before Flutter setup, dependency resolution,
or project compilation began. The same workflow's other Linux variants and all code-quality jobs were
green.

**Decision.** Treat the first attempt as runner infrastructure delay and rerun failed jobs only. Do not
change project code, widen the workflow timeout, or rerun the eight successful matrices without code or
build evidence requiring it.

**Impact.** Attempt 2 completed the Linux staging job successfully in about two minutes. The Step 18
commit is green in zeta, desktop-build (9/9), OSV, and license workflows; no CI configuration change was
introduced for a one-off apt delay.

## 2026-08-20 — Step 19 separates gitignore input from matching policy

**Problem.** Step 19 and the package API contract assign gitignore input to `workspace_client`, while
the migration manifest assigns the legacy `workspace_gitignore.dart` domain matcher to
`workspace_repository`. Copying the matcher into Data would contradict that ruling; leaving every
gitignore concern in Repository would leave external text IO above the Data boundary.

**Decision.** `GitignoreReader` reads exact, raw root `.git/info/exclude` and directory `.gitignore`
documents. `WorkspaceScanner` maintains their traversal scope and passes an immutable active-document
list to an injected pure `WorkspaceEntryFilter`. Include/skip/prune semantics are neutral; the later
Repository owns pattern parsing, last-match-wins, negation, and Zeta's hard-ignore policy. A linked
`.git`, `info`, or ignore file is never traversed. No shared adapter or Provider port changes.

**Impact.** All `dart:io` ignore input stays in Data without moving domain policy down a layer. Nested
documents do not leak into sibling traversal, ignored directories can either remain traversable for
possible negation or be pruned, and `workspace_client` has no `glob` or Repository dependency.

## 2026-08-20 — Step 19 replaces synchronous isolate walking with cancellable async IO

**Problem.** The legacy corpus builder used synchronous filesystem calls in an isolate, silently
converted access failures to empty/partial results, and stopped only at a file cap. The legacy tree
builder also mixed `expandedPaths` interaction state into directory IO. Step 19 explicitly requires
large-directory cancellation, denied/disappearing-file behavior, and filesystem-only responses.

**Decision.** Use asynchronous `Directory.list`/read/watch primitives behind an injectable
`WorkspaceFileSystem`; async streaming keeps blocking IO off the UI path without retaining a separate
isolate protocol. Add cooperative `WorkspaceScanCancellationToken` checks around every traversal
boundary, a typed cancellation exception, and an explicit `truncated` response at `maxFiles`. Propagate
typed denied/list failures, skip entities that disappear during enumeration, and omit unsupported or
linked children. `readDirectory` is one level only and returns sorted filesystem nodes with no
expanded/selected state. Recursive watch streams remain caller-cancellable and release the underlying
subscription.

**Impact.** Data tests can exercise scans without real IO. Root/requested directories fail closed on
links, lexical escape, or canonical escape; production enumeration never follows child links. The
client exposes file scans, directory reads, gitignore inputs, and external change streams only—index
query policy and interaction progress remain for later Repository/Cubit steps.

## 2026-08-20 — Step 19 final-gate unrelated keychain timing flake

**Problem.** The first final workspace test iteration reported one failure in the unchanged
`claude_code_client` compatibility test `keychain process runner covers success, timeout, and start
failure`. No workspace-client test failed, and the error appeared only under that randomized aggregate
run.

**Decision.** Reproduce the named test in isolation, then rerun the entire owning package with a fresh
random seed and its 100% coverage gate. Both passed (1/1 and 264/264), so do not modify unrelated
keychain code or relax its assertion. Restart the complete 26-root test/coverage iteration because the
green gate requires one final uninterrupted pass.

**Impact.** The second workspace iteration passed all 1,107 tests and 13,380 / 13,380 hand-written lines.
The transient fixture timing issue is recorded without contaminating the Step 19 patch or weakening a
pre-existing security-sensitive timeout test.

## 2026-08-20 — Step 19 desktop-build repeats the isolated apt timeout

**Problem.** Step 19's desktop workflow again reached 8/9 green while Linux production spent the full
30-minute job limit in `Install Linux desktop toolchain`. Flutter setup and repository code never ran;
the other two Linux variants and every Windows/macOS matrix passed.

**Decision.** Apply the existing infrastructure policy: rerun failed jobs only and make no source,
timeout, or workflow change. The affected matrix differs from Step 18's Linux staging occurrence, so
there is still no deterministic project or matrix-specific failure to remediate.

**Impact.** Attempt 2 passed without a code change. Step 19 is green in zeta, desktop-build (9/9), OSV,
and license workflows; both apt incidents remain visible for trend monitoring.

## 2026-08-20 — Step 20 keeps session domain and restore policy above Data

**Problem.** The legacy `IdeSessionState` combines persisted schema fields with domain objects, and the
legacy snapshot helper combines codec projection with `ProjectThreadListState` restore planning. The
manifest and ownership map instead assign the domain models to `project_session_repository`, restore
plans to Cubit/Bloc, and only current-schema IO plus the codec to `project_session_client`.

**Decision.** Define neutral `SessionSnapshotResponse`, `SessionThreadSummaryResponse`, and
`SessionWorkbenchResponse` values in Data. Preserve the current v4 JSON projection, but do not copy
domain conversion, filesystem pruning, selected-thread normalization, or restore sequencing. Accept
v4 only: missing/blank means a clean install; malformed, unsupported, or invalid current documents
raise content-free typed decode failures. No shared adapter or Provider port changes.

**Impact.** The package has no Flutter, Bloc, Cubit, Repository, or provider-contract dependency. The
later Repository can map these persistence responses into its domain without Data importing stateful
application types, and corruption cannot silently become an empty restored session.

## 2026-08-20 — Step 20 makes debounce cancellation and close flushing explicit

**Problem.** The legacy persistence coordinator owns a timer but `dispose()` drops its pending snapshot.
Moving that timer unchanged to a later Cubit would violate the package contract that debounced writes
are cancellable and flush on close. A close-time atomic write can also fail and must not prevent storage
teardown or disappear as an unobserved timer error.

**Decision.** `ProjectSessionStore` coalesces the latest scheduled response, exposes
`cancelScheduledSave()` for writes that have not started, and never interrupts an atomic write already
in flight. Immediate saves cancel a pending debounce. `close()` rejects new work, flushes the latest
pending response, waits for the serial write tail, always closes storage, then propagates any captured
background, flush, or close failure.

**Impact.** Close-time data is not dropped, superseded snapshots do not write, and write failures remain
observable. Package tests separately cover timer-started background failure and a failure initiated by
the close-time flush.

## 2026-08-20 — Step 20 desktop apt stall was retried before the job limit

**Problem.** Step 20's first desktop run reached 8/9 successful matrices while Linux development made
no progress beyond Ubuntu package installation for more than twelve minutes. No Flutter setup,
dependency resolution, or project build had begun, matching the isolated runner-side apt delays already
recorded in Steps 18 and 19.

**Decision.** Cancel only the still-running matrix and rerun failed jobs rather than waiting for the
30-minute limit or rerunning the eight proven matrices. Keep the workflow unchanged: repeated apt delay
has moved between Linux variants and still has no project-code failure signature.

**Impact.** Attempt 2 spent about seven minutes in apt and then built successfully. Step 20 is green in
zeta, desktop-build (9/9), OSV, and license workflows without a source or CI configuration change.

## 2026-08-20 — Step 21 follows the specific storage/vendor topology over the generic manifest

**Problem.** The generic per-file manifest maps every legacy usage data file into a nonexistent
`packages/usage_statistics_client`, but Step 21, the topology, and the package API contract explicitly
place cache/index IO in `usage_statistics_storage_client` and raw Codex/Claude/Grok readers in their
vendor clients. The legacy vendor scanners also total roughly 2,600 lines, materially exceeding the
placeholder package estimate.

**Decision.** Follow the more specific architecture contract. Split the work into one shared-storage
increment plus three independently gated vendor-reader increments. Do not create a fourth shared vendor
client, change the shared adaptation layer, or add Provider ports. Keep repeated response shapes
vendor-owned so one vendor format cannot become a cross-provider contract by accident.

**Impact.** Vendor pubspecs remain mutually isolated, `usage_statistics_storage_client` has no vendor or
provider-contract dependency, and the later Repository is the only place that will aggregate the four
Data inputs. The larger implementation is explicit and testable rather than hidden in one oversized
package change.

## 2026-08-20 — Step 21 treats paths and damaged indexes as rebuildable private inputs

**Problem.** The legacy cache persisted source paths and accepted multiple historical shapes. Copying it
would retain local directory information and blur current-schema corruption with a cache miss. Review
also found that the new root index model initially claimed defensive immutability while retaining the
caller's mutable partition map.

**Decision.** Accept root schema v4 only. Store provider-owned JSON-safe partitions behind a serialized,
atomic `UsagePartitionStore`; on malformed, unsupported, or semantically invalid derived data, atomically
write an empty v4 index and return a miss. Hash normalized source identifiers for cache keys and never
persist the source path. Defensively copy and freeze both the root partition map and nested payloads.
Propagate storage failures rather than reporting a successful clear.

**Impact.** Corruption is recoverable without masquerading as valid cached data, path disclosure is
removed from the index, concurrent writes cannot drop another provider partition, and mutation after
construction cannot alter encoded state. Regression tests cover corruption, immutability, failure queue
recovery, 1,000 concurrent inserts, and real atomic file IO.

## 2026-08-20 — Step 21 reuses vendor history semantics without exposing private Provider code

**Problem.** Claude and Grok already expose package-owned history readers/parsers suitable for a narrow
usage projection. Codex's equivalent parser is a private `part` of the Provider implementation; making
it public would expand the Provider surface. Initial Grok tests also found that a malformed percent-
encoded project directory makes `Uri.decodeComponent` throw `ArgumentError`, and a fallback assertion
incorrectly assumed project-name ordering instead of the documented source-path ordering.

**Decision.** Project Claude and Grok usage from their existing vendor history models. Add a standalone
Codex-owned reader that understands only session metadata, turn lifecycle/context, and token-count
records, preserving exact last-usage, cumulative deltas, duplicate signatures, counter resets, and fork
replay suppression. Do not expose prompt, response, error body, or raw frames. Keep malformed Grok
directory names verbatim, inject file reads to test summary IO failure, and assert fallback values without
overriding deterministic source-path order. All readers use half-open ranges and cooperative cancellation.

**Impact.** No shared or Provider port changed. Large scans cancel at discovery, parse, load, and stat
boundaries; damaged sources are counted without leaking content; and every vendor retains ownership of
its on-disk format. The compatibility defects are covered by regression tests rather than hidden behind
coverage exclusions.

## 2026-08-20 — Step 21 final-gate root discovery excluded generated package assets

**Problem.** The first analyze/format preflight recursively searched for every `pubspec.yaml` and counted
28 roots because Flutter's generated `packages/app_ui/build/unit_test_assets/.../shadcn_flutter` copy
also contains a pubspec. It is not declared by the workspace and carries upstream lint information.

**Decision.** Do not edit or count generated assets. Build the authoritative root set from the root
workspace, immediate `packages/*` members, and the explicitly nested `packages/app_ui/widgetbook`, then
restart the formal analyze/format count.

**Impact.** The formal result is 27/27 real roots and 383 source/test/tool Dart files with zero format
changes. The generated copy remains untouched and cannot inflate later gate counts.

## 2026-08-20 — Step 21 cache privacy is enforced at the write boundary

**Problem.** A pre-commit static-security review found that `usageSourceId(path)` produced a path-free
key, but `UsageScanCacheEntry` still accepted any string. A future caller could therefore pass the raw
path directly and persist it despite the documented privacy contract; arbitrary fingerprint strings and
invalid cache schemas were likewise accepted until a later operation.

**Decision.** Require every persisted source id to be exactly the 16-character lowercase FNV-1a form
and every fingerprint to use the numeric `size:mtime` form. Validate cache source keys and schema
versions at construction, validate read/invalidate inputs, reject empty source paths and negative file
sizes in helpers, and reject blank/whitespace partition keys in both models and decoding.

**Impact.** Path secrecy is now enforced rather than conventional, invalid cache configuration fails at
the API boundary, and malformed persisted identifiers still trigger clear/recompute. The hardened
storage package remains at 100% hand-written coverage (222 / 222).

## 2026-08-20 — Step 22 resolves the asynchronous config / synchronous bundle contract explicitly

**Problem.** The documented constructor receives an asynchronous `ProviderConfigStore`, but the same
public contract requires synchronous `configSnapshot` and `bundleFor` without defining initialization.
Creating a default bundle before disk read completes can start the wrong command and then dispose a
runtime already handed to a consumer. The legacy controller avoided a crash with mutable defaults but
did not provide a race-free readiness boundary. The API example also shortened the already exported
`AgentModelCatalogCacheStore` port name to the nonexistent `ModelCatalogCacheStore`.

**Decision.** Construction immediately starts the config read and exposes an additive `ready` Future.
Async catalog APIs await it; synchronous `bundleFor` returns a typed `repository_not_ready` failure until
it completes. An empty clean-install response expands to the existing Codex/Grok defaults in memory and
does not write them. `persistDefaultModel` is interpreted as an explicit persistence command: the
Repository stores that submitted value but owns no current model, permission, mode, loading, or retry UI
state. The documentation now uses the existing cache-port name; no shared contract or Provider port is
changed.

**Impact.** Bootstrap has a deterministic await point, no provisional process can escape, snapshots only
publish successfully loaded or written external data, and the documented synchronous API remains intact.

## 2026-08-20 — Step 22 serializes global catalog ownership and preserves diagnostic causes

**Problem.** A direct port wrapper would duplicate provider-local cache lifetime and allow concurrent
first reads or full-cache writes to race. A late cache write for one Provider could overwrite a newer
snapshot containing another Provider. Mapping failures to `AgentProviderFailure` alone would also discard
the original cause and stack required for sanitized logging.

**Decision.** Keep one constructor-started cache-read Future, single-flight model refreshes keyed by
canonical provider id plus secret-free config fingerprint, and a serialized queue of complete cache
snapshots. Fresh entries last one hour; last-known-good entries remain eligible for seven days on refresh
failure. Empty refreshes never replace or persist a catalog, and cache read/write failures are best effort.
Repository calls throw `AgentProviderRepositoryException`, which contains the vendor-neutral failure plus
the original cause/stack trace; its string form and `AppLogger` output remain content-free/sanitized.
Both synchronous throws before `runtime.initialize()` returns a Future and post-persistence
`updateModelSelection()` failures are inside the same translation boundary; the latter does not roll back
an already successful atomic config write.

**Impact.** Global runtime/catalog ownership is race-free across Providers, cache persistence cannot
regress through out-of-order completion, and application code receives stable failure codes without
losing diagnostic evidence. Regression tests cover both cache-read and cross-provider write races.

## 2026-08-20 — Step 22 final gate retried the known Claude keychain timing flake

**Problem.** The first 26-root randomized gate failed only the existing Claude keychain process-runner
test under seed `2572682378`; the remaining Claude tests continued successfully. The approved VGC-only
test policy prevents a named-test diagnosis because `very_good test` accepts neither `--plain-name` nor
a positional test path; the attempted command was rejected by argument parsing before any test ran.

**Decision.** Do not bypass the approved runner with `flutter test`, loosen the timeout, or modify
unrelated Claude code. Rerun the complete Claude package through the exact 100%-coverage VGC gate with a
new random seed, then continue the interrupted workspace sequence from the next root.

**Impact.** Seed `1621963295` passed all 270 Claude tests and 3,037 / 3,037 lines without a code change.
The continued workspace gate finished 26/26 roots and, after the final Repository hardening rerun,
14,552 / 14,552 lines; this remains classified as
the already documented Windows child-process timing flake rather than a Step 22 regression.

## 2026-08-20 — Step 22/23 gate tooling uses authoritative roots and native command boundaries

**Problem.** Formatting all authoritative Dart files in one Windows invocation exceeded the command-line
length limit. A later GitHub query embedded a full SHA in a PowerShell-to-`gh --jq` expression and was
rejected by argument parsing. At the start of Step 23, `format` and `analyze` were also mistakenly invoked
as Very Good CLI top-level commands, which do not exist; no source operation ran in either rejected call.

**Decision.** Keep the approved runner split: use Dart directly for analyze/format, process the
authoritative workspace files in bounded chunks, and use `very_good test` for every test execution.
Query Actions with `gh run list --commit <full-sha>` and parse returned JSON outside nested `--jq` shell
quoting. Do not add `--check-ignore` or bypass VGC with `flutter test`.

**Impact.** Tool argument limits cannot change the set of checked files, rejected commands make no
workspace mutation, and Step 22's four workflows were verified successful for commit `8e5485c`.
An initial Step 23 manual total read the stale workspace-root LCOV as 294 / 294; the authoritative
package-local LCOV is 1,096 / 1,096. Only the reported count changed—the 100% package gate did not.
The final analyze pass also surfaced one pre-existing alphabetical dependency-order info in
`app_ui/widgetbook`; dependencies were mechanically reordered without changing versions or topology,
and the isolated rerun reported no issues.
After lifecycle hardening, a combined analyze/test shell block did not stop after analyze found a nullable
promotion error, so VGC predictably reached compilation and failed without running business tests. The
local was made explicitly non-null and all subsequent combined gates short-circuit on every nonzero
preflight exit. Final package evidence supersedes the earlier count at 1,121 / 1,121.
The first compact final-analyze script then enumerated only direct children of `packages/` and therefore
reported 26 roots, omitting nested `app_ui/widgetbook`. The authoritative enumeration now derives every
root from tracked `pubspec.yaml` files; its replacement run passed 27 / 27 roots. Test-root enumeration is
unchanged at 26 because the nested widgetbook has no test directory.

## 2026-08-20 — Step 23 follows completed history/config contracts instead of nonexistent types

**Problem.** The Step 23 constructor sketch named `AgentHistoryClient` and `TurnContextStore`, but Step 15
deliberately exports only `HistoryReplayInput` plus `mergeHistoryInputs`, and Step 17 exports
`AgentTurnContextStore`. Adding the sketched objects would duplicate accepted Data boundaries.

**Decision.** Inject the existing `AgentTurnContextStore` and an optional conversation-owned factory of
neutral `HistoryReplayInput` values. Provider-owned typed history enters through the already available
`bundle.threadCatalog`; generic inputs go through Step 15's merge function. Keep `ConversationKey` and the
timeline aggregate in this Repository package because no current shared consumer requires a Provider
contract change.

**Impact.** The implementation uses every completed lower-layer contract as shipped, changes no shared
adapter or Provider port, and retains vendor parser ownership. The bilingual API sketch now matches the
executable signature.

## 2026-08-20 — Step 23 leases borrowed bundles and rejects unbound identities fail-closed

**Problem.** Step 22 owns and disposes stable global bundles, while the legacy conversation registry owned
the runtimes it created. Copying that ownership would let both Repositories dispose the same runtime.
Initial Step 23 tests also exposed that a draft with no session accepted a thread-scoped status because
there was not yet an expected thread id to compare.

**Decision.** Treat the bundle as borrowed. The conversation registry tracks identity-based lease counts
and monotonic generations, but only cancels its event pipeline, releases its lease, and best-effort
unsubscribes the thread; final runtime disposal stays with Step 22. Before a draft receives
`AgentSessionStartedEvent`, reject every event carrying a session or thread identity. After binding,
require exact session/thread identity and a known or active turn. Coalesce only normalized delta/snapshot
keys; all other events are ordering barriers, and queued events recheck generation at dispatch.

**Impact.** Close and open races cannot create ghost updates or double disposal. Security responses remain
three separate pending registries and methods, event storms retain FIFO barrier order, and failures are
typed while original causes/stacks remain available only to sanitized logging. Error, deprecation, and
reroute timeline records retain only content-free typed signals, never the provider raw event.
Natural completion of the current event stream now publishes a typed conversation failure, and every
session/turn returned by start, resume, or send is identity-checked again before entering the aggregate.

## 2026-08-20 — Step 24 canonicalizes management identity at the Data boundary

**Problem.** The completed management Data client returned `claude-code` from Claude detection, while the
shared Provider contract, persisted configuration, and every runtime route use `claude_code`. A Repository
that copied the response id would silently create a second identity. The same Data implementation already
contained the required pure JSON/TOML syntax validator, but its public barrel hid that function, forcing
Step 24 either to duplicate parsers or import package `src/`.

**Decision.** Configure all three concrete Data sources with the existing Provider-contract id constants,
update the Claude Data test to the canonical value, and export only the existing pure validator from the
management-client barrel. The Repository keys clients by canonical id and rejects any detection response
whose id differs from its route. It exposes validation through its own typed, synchronous domain result;
widgets still may reach that method only through the later Bloc event.

**Impact.** There is one Provider identity from persistence through Data and Repository, cross-Provider
misrouting fails closed, and no parser implementation is duplicated. This is a narrowly scoped Data API
correction; no shared adapter, Provider port, runtime protocol, configuration schema, or vendor parser
changed. The management client remains independently green at 35 tests and 329 / 329 covered lines.

## 2026-08-20 — Step 24 keeps management orchestration stateless

**Problem.** The legacy controller combines external detection/config/log calls with selected Agent,
progress, loading, runtime, editor, log-view, localized-error, and cached-detection state. It also writes a
detection summary back into global Provider configuration. Copying those policies would contradict both
the Step 24 forbidden-state list and Step 31's explicit Bloc ownership. Conversely, the new config store can
legitimately be empty on a clean install.

**Decision.** Retain only an immutable client registry and the injected `ProviderConfigStore`. Resolve
Provider configuration afresh for operations that need it; use the three contract defaults in memory when
the store is empty, without writing. Explicit detection paths bypass the config read; otherwise use a
nonblank stored `cliPath` and then the command. Do not persist detection summaries. Reject duplicate,
non-canonical, wrong-kind, missing, and blank-command configurations. Merge redacted per-path log results
sequentially, sort by timestamp/id, and enforce one global line bound. Translate exceptions to typed safe
failures while retaining cause/stack only for sanitized diagnostics.

**Impact.** Step 31 can own cancellation, selection, progress, editor validation state, runtime
composition, and localized copy without competing Repository state. Clean install remains usable, failed
or partial operations cannot mutate global configuration, and output ordering/resource bounds are
deterministic. The Repository has 28 randomized tests and 290 / 290 covered hand-written lines.

## 2026-08-20 — Step 25 gives Settings single-document commit semantics

**Problem.** General v3 and Appearance v1 are separate files. Pretending that one settings update is a
cross-file transaction would make the in-memory snapshot lie after a partial write failure. The legacy
controller also mixed system-font display options, current selection, and prompt state into persistence.

**Decision.** Accept only a `GeneralSettingsUpdate` or `AppearanceSettingsUpdate` document replacement.
Increment revision and publish the complete snapshot only after the corresponding store succeeds. Map the
existing `SystemFontCatalogApi` into pure domain families, and keep locale resolution string-only. Change no
desktop port and retain no UI options, loading state, or error copy.

**Impact.** Failed writes never become effective settings, and the two schemas retain their real atomic
boundaries. Settings is independently green with 23 tests and 262 / 262 covered lines.

## 2026-08-20 — Step 25 corrects ancestor-ignore semantics for lazy directories

**Problem.** Step 19 recursive scans carried root-to-current `.gitignore` documents, but `readDirectory`
read only the target directory. Expanding a nested directory therefore missed root and ancestor rules. The
migrated matcher also appended an extra level to `**/cache/**`, preventing deep matches.

**Decision.** Keep `WorkspaceScanner` and `GitignoreReader` signatures unchanged. Build the full ancestor
document chain inside the Data implementation, and add the correct full-relative-path glob for a leading
`**/` in the Repository's pure matcher. The Repository owns immutable indices and shared watches and
serializes scans per root; expansion, selection, loading, progress, and debounce orchestration remain in
WorkspaceCubit.

**Impact.** Recursive indexing and lazy tree reads now share ignore semantics. Workspace is green at 17
tests and 330 / 330 lines, and the corrected client at 30 tests and 255 / 255. No port or shared adapter changed.

## 2026-08-20 — Step 25 gives Project Session one aggregate cursor

**Problem.** The legacy project-threads controller mixed search/selection/loading state with cross-Provider
collection, deduplication, sorting, and paging. A Provider-native cursor cannot represent the merged catalog.
Session schema v4 also must round-trip completely rather than preserving only navigation fields.

**Decision.** Map all schema-v4 fields and publish a snapshot only after Data save succeeds. Inject an
immutable `providerId → AgentThreadCatalogPort` registry, collect at most 50 entries per Provider, deduplicate
ids within that Provider, sort globally by recency/provider/id, and page through `agg:<offset>`. Return
content-free typed evidence for partial Provider failures; isolate identity mismatches and repeated cursors
as invalid Data. Search text, selection, loading, and failure presentation stay in Bloc.

**Impact.** Provider cursors do not escape the aggregation boundary, partial success remains usable, and
ordering is reproducible. No shared thread port changed. Project Session is independently green with 17
tests and 275 / 275 covered lines.

## 2026-08-20 — Step 25 contains a Windows keychain-test cleanup race

**Problem.** The first final matrix run reached the Claude keychain runner's success/timeout/start-failure
assertions, but Windows still held the temporary directory handle during deletion and raised
`PathAccessException` (errno 32). Very Good CLI 1.4.0 accepts neither a test path nor `--plain-name`, so a
named-only reproduction is unavailable while preserving the unified runner rule.

**Decision.** Do not bypass `very_good test`, modify untouched Claude source, or relax timeout/coverage.
Rerun the complete Claude package with a new random seed, then resume the matrix at the next root, recording
the CLI filtering limitation as evidence.

**Impact.** The Claude rerun passes 270 tests at 100%. The final result is 27/27 green roots, 16,840 / 16,840
covered lines, and Bloc lint at 405 files / zero issues. This is classified as transient Windows handle
cleanup, not a Step 25 product regression.

## 2026-08-20 — Step 26 keeps vendor usage shapes private and caches report projections

**Problem.** The three completed vendor readers deliberately expose different response shapes, and the
shared usage store accepts only provider-owned JSON partitions. Introducing a common Data model or a new
Provider port would contradict Step 21. A cache entry is also fingerprint-specific but not query-specific;
reusing it for another time window would return incomplete records. The real aggregation, cache codec,
partial-failure, and cancellation work is materially larger than the original placeholder estimate.

**Decision.** Keep every vendor response private to `usage_statistics_repository`; map it directly into
content-free domain records and store only a Repository-owned projection. Persist the half-open query
bounds in every entry and reuse a fingerprint hit only when both bounds match; force refresh, a different
window, malformed payload, or storage failure rebuilds from the current scan. Run all vendors in parallel,
isolate unexpected provider failures as typed warnings, translate cooperative cancellation, deduplicate
Codex replay samples, and resolve quota capabilities independently. Accept the larger Step 26 increment
under the user's delegated decision authority rather than weakening the contract or modifying shared ports.

**Impact.** Filter selection and loading remain Bloc state, local source paths are hashed by the existing
storage boundary, a broken vendor/cache cannot erase peer results, and no cross-vendor Data contract was
created. Cross-source fork replay uses the Provider sample key at the aggregate boundary. The package is
independently green with 13 randomized tests and 348 / 348 covered lines.

## 2026-08-20 — Step 26 exposes desktop capabilities through Repository facades

**Problem.** Passing `desktop_platform_api` objects through a Repository would still let later Blocs depend
on Data ports, while putting notification enablement or localized copy in the notification Repository would
create either a Repository-to-Repository edge or a second settings state source.

**Decision.** Wrap directory/file selection, clipboard, file-manager, window lifecycle/commands, and native
menu commands in pure-Dart Repository methods/facades with typed, content-free failures. The notification
Repository accepts only `NotificationRequest` values whose title/body are already localized, validates a
non-negative badge, and forwards notification/attention operations. It never reads settings and neither
package depends on another Repository.

**Impact.** Later Blocs can consume one domain boundary without importing the platform API, adapters remain
in `lib/app/platform`, and presentation policy has no duplicate owner. Notifications passes 6 randomized
tests at 21 / 21 lines; Desktop Platform passes 7 at 44 / 44 lines.

## 2026-08-20 — Step 26 retries the known Claude keychain cleanup race

**Problem.** The first authoritative matrix again completed the keychain runner assertions but failed while
Windows removed its temporary directory. The failing file and handle-sharing error match the Step 25 event;
all roots before Claude and all Step 26 isolated gates were green.

**Decision.** Preserve the unified `very_good test` runner, timeout, randomization, and coverage threshold.
Do not modify unrelated Claude production/test code in this migration increment. Rerun the complete Claude
package with a new seed, then resume the authoritative matrix from Codex rather than discarding proven roots.

**Impact.** The unchanged Claude package passed all 270 tests and 100% coverage on rerun. The resumed matrix
then completed 27/27 roots; this remains the documented Windows cleanup race, not a Step 26 regression.

## 2026-08-20 — Step 27 is delivered as five independently gated UI increments

**Problem.** The migration checklist describes `app_ui` as one step, but the legacy `ui/core` surface is
48 Dart files and roughly ten thousand lines spanning theme tokens, base controls, WindowFrame,
Workbench layout, and virtualization. Treating that volume as one unreviewable change is materially larger
than the placeholder estimate and would make regressions difficult to isolate.

**Decision.** Preserve the Step 27 contract and split its implementation into five reversible increments:
27A tokens/theme, 27B base components plus the pure-UI WindowFrame, 27C Workbench primitives, 27D
virtualization, and 27E accessibility/golden total acceptance. Each increment receives its own focused
tests and local gate before the final Step 27 workspace matrix. No shared adapter or Provider port changes.

**Impact.** The user-visible objective and exit criteria do not change, while review, rollback, coverage,
and failure attribution become bounded. The migration status remains Step 27 in progress until all five
increments and the final remote gates pass.

## 2026-08-20 — Step 27A adds semantic typography without breaking the scaffold API

**Problem.** The VGV scaffold already exposes and exhaustively tests `AppTextStyles`, while the legacy
desktop surface needs a much richer, color-aware semantic typography table. Replacing the scaffold type in
the token increment would force unrelated Widgetbook and component churn before their scheduled increment.

**Decision.** Add `AppTypography` as the migrated `ThemeExtension` and keep `AppTextStyles` as a temporary
public compatibility extension. `AppTheme` installs both, while all migrated components use
`AppTypography`. Material and shadcn projections, semantic colors, spacing, metrics, radii, effects, and
motion now share the same extension-backed source; shadcn imports remain consistently qualified `as sf`.

**Impact.** Existing VGV consumers remain source-compatible and later UI increments can migrate one
component at a time. Step 27A passes app_ui analyze, 86 randomized tests, and 100% hand-written coverage;
Widgetbook analyze and the 72-test root architecture gate also pass with no forbidden lower-layer import.

## 2026-08-20 — Step 27B makes image and window effects app-owned inputs

**Problem.** The legacy image preview performs `dart:io` file reads and obtains copy through
`AppLocalizations`; the legacy WindowFrame calls `window_manager`, owns the Zeta SVG asset, detects
maximize state, and embeds English caption labels. Copying either implementation would violate the
documented pure-UI `app_ui` boundary even though their visual layout belongs in the package.

**Decision.** `IdeImageThumbnail` and `showIdeImagePreview` accept an `ImageProvider` plus all visible and
semantic copy; file validation/read failures stay in the later app adapter. `WindowFrame` accepts a visual
platform, an app-owned logo widget, localized labels, a drag-region wrapper, window state, and minimize /
maximize / restore / close callbacks. It contains no platform channel, application asset path, Repository,
Data client, or `AppLocalizations` import. Dense controls enforce the WCAG 2.2 AA 24 dp target floor,
icon-only actions require accessible names, progress/toast output uses live regions, resize handles expose
arrow-key alternatives, and motion respects the platform reduction setting.

**Impact.** The shared package owns deterministic rendering and behavior while bootstrap/presentation will
compose OS effects and localized copy in later steps. The API is testable on every host without
`window_manager` or filesystem fakes, and no Provider port or shared domain adapter changed.

## 2026-08-20 — Step 27B contains shadcn 0.0.53 overlay quirks inside the UI package

**Problem.** The legacy project already works around a `shadcn_flutter 0.0.53` anchor-follow transform
failure. Component tests also showed that the same release leaves a toast auto-close timer pending after
programmatic close, and its test overlay can position toast paint beyond the synthetic viewport. Removing
the compatibility layer would reintroduce a desktop MouseTracker failure; patching the dependency would
expand this migration into a vendor change.

**Decision.** Migrate `IdeStablePopoverOverlayHandler` unchanged in responsibility: it delegates overlay
lifecycle while forcing anchor following off both at open and on live configuration updates. Popover and
toast wrappers hide third-party handles from normal consumers. Toast tests advance a short configured
auto-close clock and assert the public overlay state instead of patching shadcn internals; toast semantics
use explicit child nodes so the live message and localized close action remain distinct.

**Impact.** The known vendor behavior is isolated and exhaustively covered without changing a Provider
port or vendored source. Widgetbook now applies both Material and shadcn projections from `AppTheme` and
declares the same direct shadcn version for its generated component galleries. Step 27B finishes with zero
app_ui analyze findings, 192 randomized tests, and 100% hand-written coverage; Widgetbook also analyzes
cleanly.

## 2026-08-20 — Step 27B's Widgetbook dependency adds no new license class

**Problem.** Applying the shadcn projection inside Widgetbook requires a direct `shadcn_flutter`
declaration. A dependency-manifest change must be evaluated from the resolved tree, not assumed safe from
the package name or from app_ui's existing declaration.

**Decision.** Run Very Good CLI license scans from the Pub workspace root for direct-main, direct-dev, and
transitive dependencies. The requested MCP scanner was unavailable and the installed CLI no longer accepts
the skill's obsolete `--licenses` flag, so the current `--reporter text` interface was used for all three
resolved sets. Do not change unrelated dependencies in this UI increment.

**Impact.** All 28 direct-main and 10 direct-dev packages are MIT, BSD, or Apache; `shadcn_flutter` is
BSD-3-Clause and adds no resolved package. The full 138-package transitive scan retains two pre-existing
review items: `dbus` (MPL-2.0, medium/weak-copyleft) and `pubspec_lock_parse` (unknown, high/manual review).
Neither was introduced by 27B; they remain visible supply-chain observations rather than being silently
classified compliant.

## 2026-08-20 — Step 27C injects Workbench copy and keeps layout state caller-owned

**Problem.** The legacy Workbench primitives are otherwise pure UI, but `IdeWorkbenchScaffold` reads the
overlay-dismiss label from `AppLocalizations`. Copying that dependency would violate the `app_ui`
contract. The increment also spans responsive rails, panes, modal overlays, retained page state, compact
rows, metric bars, surfaces, and page composition; these behaviors need to remain independent from Bloc,
Repository, and Provider ports.

**Decision.** Make `closeOverlaySemanticLabel` a required non-empty constructor input and keep overlay
visibility, pane widths, dismissal, and focus restoration caller-owned. Migrate the remaining Workbench
primitives as one-public-component files with const constructors, public Dartdoc, barrel exports, and
ThemeExtension-backed tokens. Non-interactive metric/data rows no longer advertise a button role;
decorative dividers are excluded from semantics; page and group titles expose heading semantics; modal
overlays retain a localized scrim action, Escape dismissal, and trigger-focus restoration. No shared
adapter or Provider port changes.

**Impact.** `app_ui` remains free of `AppLocalizations`, app assets, IO, repositories, and Data clients.
The responsive Workbench is now available in Widgetbook. Step 27C passes app_ui analysis, 215 randomized
tests, and 100% hand-written coverage; Widgetbook analysis and the root 72-test/100%-coverage architecture
gate also pass.

## 2026-08-20 — Step 27C verification separates harness faults from product behavior

**Problem.** The first responsive tests requested 900–1400 px widgets inside a helper that always created
an 800 px surface, so nominal wide/medium cases actually exercised compact mode. Retained-page probes also
reused the same keys as PageView wrappers, making state lookups ambiguous. After correcting those tests,
coverage reached 99.77%; the only structural gap was a second index clamp that cannot run because
`didUpdateWidget` resolves the index before every non-empty build. The installed build runner also reports
that `--delete-conflicting-outputs` is obsolete and ignores it.

**Decision.** Add an optional surface size to the shared test pump, give probes distinct keys, and assert
actual responsive geometry. Remove the unreachable duplicate clamp instead of suppressing coverage or
writing a test that violates the widget's state invariants. Keep using the current build-runner behavior;
generation completed normally and refreshed the Widgetbook directory output.

**Impact.** The final tests prove real wide, medium, compact, keyboard, focus, identity-retention, RTL-safe
inset, and semantic paths without weakening the 100% gate. Production behavior changed only by deleting
dead defensive code; no package boundary or public port changed.

## 2026-08-20 — Step 27D keeps virtual scrolling as pure UI/render infrastructure

**Problem.** The legacy virtualization directory contains about 2,180 production lines and 2,133 test
lines. Its extent index, RenderSliver, list controller, and scroll coordinator fit the `app_ui` boundary,
but the scrollbar reads `AppLocalizations` directly and one file exposes the scrollbar, scroll-to-end
button, and composition shell together. The old shell's `coordinator` argument is never read; copying it
would preserve a misleading API and import localization into the shared UI package.

**Decision.** Migrate the pure algorithms and render infrastructure. Split the scrollbar, scroll-to-end
button, and shell into separate files, with callers providing scrollbar, action, and visible-state copy.
Remove the unused coordinator field from the shell; upper-layer state continues to decide button
visibility. Add a bridge that accepts only a Flutter notification, controller, and generic coordinator.
Resolve styling, radii, spacing, and motion from ThemeExtensions, use `PositionedDirectional`, and honor
reduced motion through the motion tokens. Do not change a shared adapter, Repository, Data client, or
Provider port.

**Impact.** app_ui now owns stable-ID extent indexing, anchor correction, a dynamic-height RenderSliver,
smooth desktop wheel input, the follow/free coordinator, and accessible scroll composition. Widgetbook
adds a 200-item dynamic-conversation example. Step 27D passes app_ui analysis, 284 randomized tests, and
100% hand-written coverage; Widgetbook also analyzes cleanly.

## 2026-08-20 — Step 27D closes legacy coverage gaps through invariant review

**Problem.** Moving the legacy implementation under VGV lint first produced 38 style findings;
`dart fix --apply` mechanically fixed 15, with the remaining findings involving cascades, parameter
assignment, public documentation, and import boundaries. The migrated behavior tests passed, but the
first complete package run covered only 96.75%. Gaps included real driver lifecycle/notification-bridge
contracts and redundant fallbacks made unreachable by Fenwick lower-bound, the non-empty-index epoch
invariant, and pre-layout garbage collection. Reverse-sliver error detail lives in a debug-only assert;
repeatedly pumping an invalid render tree causes recurring layout exceptions.

**Decision.** Preserve the unified `very_good test` runner, randomization, and 100% threshold. Add
contracts for value equality, pending sequences, anchor fallback, attached/detached drivers, default frame
scheduling, animated offsets, the user-notification bridge, smooth-scroll correction, empty data,
controller replacement, and missing delegate children. Remove provably unreachable epoch/index/trailing-
garbage fallbacks. Apply one local coverage ignore only to the debug-only invalid-direction diagnostics
while retaining the runtime assert; do not widen file or package exclusions.

**Impact.** Coverage rises from 96.75% to 100% while every virtualization production file stays in the
denominator. The cleanup removes only defenses duplicated by established invariants; valid layout,
scroll-state behavior, public component behavior, and package boundaries do not change.

## 2026-08-20 — Step 27E closes WCAG 2.2 AA gaps with executable acceptance

**Problem.** The first total acceptance put semantic colors, desktop controls, and 200% text scaling under
one AA contract. It found that an actionable `IdeChip` had only a 20 dp hit height, below the 24 dp floor,
and that the fixed 44 dp `IdePageHeader` overflowed downward by 21 px at 200% scaling with a subtitle.
Both faults were internal to `app_ui`; neither involved a shared adapter or Provider port.

**Decision.** Give only chips with press or delete actions a hit box constrained by
`AppMetrics.minimumInteractiveTarget`, preserving the density of static labels. Treat `pageHeaderHeight`
as a minimum so scaled content may grow naturally. Add executable acceptance for 4.5:1 normal text on
every light/dark content surface, 3:1 focus rings, four 24×24 dp interactive-control classes, 200% text,
and reduced motion. Existing component tests continue to prove semantics, keyboard/focus, live regions,
arrow-key drag alternatives, and overlay focus restoration.

**Impact.** Production code fixes both real AA gaps without weakening assertions or tokens. All seven new
AA checks pass; the complete randomized app_ui suite grows to 293 tests and retains 100% hand-written
coverage.

## 2026-08-20 — Step 27E fixes golden discovery, layout, and Very Good execution semantics

**Problem.** Dart's test metadata parser rejects the constant in `@Tags([TestTag.golden])` and requires a
string literal. The first gallery also placed a stretched Row inside a vertical `SingleChildScrollView`,
creating infinite-height constraints. After those fixes and baseline generation, Very Good's default test
optimizer dropped the file-level tag while merging suites, so a normal `--tags golden` reported no matching
tests; golden updates had hidden the fault by disabling optimization automatically. The current Very Good
CLI also has no `analyze` command. The first Flutter analysis reported 13 const hints in the test fixture,
which `dart fix --apply` consolidated into eight safe mechanical fixes.

**Decision.** Keep parser-compatible `@Tags(['golden'])` metadata and reference `TestTag.golden` in the test
body, satisfying both real tagging and workflow file discovery. Use token padding directly inside the fixed
desktop canvas instead of stretching inside an unbounded scroll axis. Pass `--no-optimization` in the
golden job and lock it with an architecture test; declare golden, perf, and slow package tags. Continue to
run tests through `very_good test` and use the official `flutter analyze` for static analysis.

**Impact.** Two candidate light/dark baselines come from a fixed 760×560, device-pixel-ratio-1 component
gallery and pass visual inspection. The non-update gate passes three consecutive randomized runs on Windows
and can no longer succeed with zero tests. The workflow change affects discovery only, with no production
dependency or architectural-boundary change; remote revalidation determines the authoritative Linux images.

## 2026-08-20 — Step 27E isolates goldens from the normal matrix and freezes the renderer

**Problem.** The first remote revalidation ran Windows/Flutter 3.47.0 baselines inside the normal app_ui
quality job on Ubuntu/Flutter 3.47.1. The dark and light images differed by 0.95% and 0.96%, respectively,
so normal tests failed and the dependent dedicated golden job was skipped. The three earlier passes proved
Windows stability only; they did not establish Linux baselines. The installed Very Good CLI also has no
top-level `analyze` command, so static analysis cannot be routed through that executable.

**Decision.** Add `--exclude-tags golden` to the normal analyze/format/test/coverage matrix and run visual
tests only in the dedicated Ubuntu 24.04 job. Pin that job alone to the approved Flutter 3.47.0 so normal
`3.47.x` patch movement cannot silently alter pixels. On failure, retain Flutter's feedback images through
`actions/upload-artifact@v7` so the authoritative Ubuntu baseline can be bootstrapped once. Architecture
tests lock the separation, exact renderer version, and artifact evidence. Keep static analysis on the
official `flutter analyze` command while all test gates continue to use `very_good test`.

**Impact.** Behavior/coverage and platform visual gates now have distinct responsibilities. Normal matrix
tests cannot be contaminated by a developer-host baseline, while golden mismatches remain hard failures
with auditable image evidence rather than being hidden by tag exclusion.

**Follow-up evidence.** The first isolation run showed that the Very Good optimizer also discards file-level
metadata when `--exclude-tags golden` is used: the normal app_ui job still executed both visual tests and
failed before the dedicated job could start. Attach `tags: TestTag.golden` directly to every `testWidgets`
case while retaining the literal file annotation for direct Flutter discovery. Per-test metadata survives
optimization, so the normal job can remain optimized and the dedicated job remains explicit and auditable.

**Final evidence.** Run 32333147922 passed all 29 normal quality jobs and the dedicated Ubuntu golden job.
The existing images matched pixel-for-pixel on Ubuntu 24.04 once that job used Flutter 3.47.0, so no baseline
replacement was necessary. Runs 32333147860 and 32333147698 also passed OSV scanning and all nine desktop
build variants. The observed 0.95%/0.96% mismatch was therefore a Flutter 3.47.1 renderer drift, not an
intrinsic Windows-versus-Linux difference.

## 2026-08-20 — Step 28 is split around the actual interim localization boundary

**Problem.** The migration plan names four legacy TextCatalog/Fallback families plus `ZetaTextCatalogs`, but
those legacy app files were already absent after the package extraction. The current code instead contains
three interim provider-local English catalogs in the Codex, Claude, and Grok clients. Keeping or merely
renaming them would violate the step's zero-TextCatalog exit criterion and the rule that packages do not
author localizable Zeta UI copy. Removing them will require targeted changes to shared neutral model fields,
which is a real provider-contract adjustment rather than the literal deletion described by the plan.

**Decision.** Treat the mismatch as an evolved intermediate state and execute step 28 in four independently
gated increments: 28A app-owned shadcn localization, 28B exhaustive typed failure mapping, 28C frozen-locale
desktop notification copy, and 28D removal of every provider-local catalog with typed or provider-authored
neutral data in its place. Do not move `AppLocalizations` into a package and do not preserve an English
fallback catalog under another name.

**28A evidence.** `ZetaShadcnLocalizations` now lives under `lib/l10n`, is first in the app and test delegate
chains, and resolves all shadcn copy from the existing 1,035-key en/zh ARB pair. The legacy smoke suite alone
left the adapter at 62.93% root coverage because it sampled only a few overrides; a complete surface-contract
test now executes every getter, parameterized formatter, and delegate branch. Analyze and 77 randomized root
tests pass with 100% hand-written coverage.

**28B boundary correction.** The source guard originally allowed Repository imports only from bootstrap,
Bloc/Cubit, and Page files, which directly contradicted the planned app-owned Repository-code mapping in
`lib/l10n/failure_messages.dart`. Add only that exact file to the allowlist and lock the exception in the
architecture configuration test; no other Presentation path gains Repository access. The imported zh ARB
also contains an existing English value for `agentRequestTimedOut`. Preserve the approved 1,035-key baseline
instead of silently rewriting translation data, record the value in tests, and prove bilingual behavior with
other translated mappings.

**28B coverage correction.** The first 79-test run executed every new mapping branch (103/103 lines) but
reported 4.23% because importing eight workspace package barrels made `--report-on lib` include thousands of
unexecuted sibling-package lines in the root app denominator. Those packages already run their own isolated
100% jobs. Exclude only `packages/**` from the root aggregation while retaining generated-source exclusion;
the same glob is inert when the matrix working directory is an individual package. Do not use external `src`
imports to manipulate instrumentation. The corrected root run passes all 79 randomized tests at 100%.

**28C locale and boundary decision.** Freeze the first platform locale in bootstrap through the existing
settings-repository D1/D7 resolver: supported Simplified Chinese becomes `zh-Hans`; English, unsupported
languages, and Traditional Chinese variants fall back to English. Construct `FailureMessages` and
`DesktopNotificationCopyResolver` from the same synchronous `AppLocalizations` instance, inject the resulting
`AppDependencies` into every flavor before `runApp`, and pin `MaterialApp.locale` to that value for process
stability. The first resolver implementation returned Repository `NotificationRequest` directly, which the
source guard correctly rejected. Replace that coupling with an app-owned immutable `DesktopNotificationCopy`;
the Step 29 Bloc will translate it at its already-approved Repository boundary. No Repository port or shared
adapter changes. Tests cover all seven attention kinds in both languages, Windows/POSIX/empty project paths,
safe bodies, stable tags, Linux action copy, sync/async bootstrap builders, observer/error hooks, and both
explicit and platform locale paths. Analyze and 85 randomized root tests pass at 100% coverage.

**28D1 neutral-code adjustment.** Claude's catalog did not import Flutter, but it still authored Zeta copy for
permission presets, permission-request descriptions, plan approval, quota labels, and locally synthesized
failures. Preserve protocol-authored strings as optional data and add narrowly scoped presentation codes to
the existing neutral value models. A permission option, plan/question title, or quota label must now contain
either provider-authored text or an app-owned code; `AgentErrorEvent` similarly accepts provider text or an
`AgentProviderFailureCode`. Claude supplies codes, provider/tool template values, and duration evidence rather
than English. This is a shared immutable-contract adjustment, not a new capability method or a localization
dependency. Delete `claude_text_catalog.dart` and all constructor plumbing instead of renaming it. The contract
package passes analyze, 85 randomized tests, and 100% coverage; Claude passes analyze, 269 randomized tests,
and 100% coverage. Root, Grok, and Codex analysis also remain clean against the compatible model defaults.

**28D2 Grok neutral-data adjustment.** Grok's catalog and usage-window helper synthesized English permission
labels, quota labels, tool titles, and failures inside the provider package. Delete both files instead of
moving the strings. Permission modes now carry stable copy codes; quota snapshots carry a typed duration or
daily/weekly/plan/on-demand code; and tool calls retain an informative provider title only, otherwise exposing
their existing `AgentToolKind` and evidence for app presentation. Locally synthesized prompt/startup failures
now use `AgentProviderFailureCode`, while a non-empty JSON-RPC server message remains provider-authored
diagnostic data. Extend only the compatible immutable value enums with Grok's `auto`, `alwaysApprove`, and
one-day cases; no capability method, adapter, or Repository port changes. Contracts pass analyze, 85 randomized
tests, and 100% coverage; Grok passes analyze, 242 randomized tests, and 100% coverage, with zero Grok catalog
or constructor-plumbing remnants.

**28D3 Codex catalog removal and history-event codes.** Codex's `_AgentUiTextCatalog` and additional
English literals on JSONL/live paths authored Zeta copy for system history cards, quota windows,
question titles, tool cards, and failures. With owner approval, follow the 28D1/28D2 pattern:
add `titleCode` / `descriptionCode` / `duration` to `AgentHistoryEventEntry` so a title is either
provider-authored or an app-owned code. No capability method, adapter, or Repository port changes.
Tool cards keep informative protocol titles, otherwise an empty title plus `AgentToolKind`; quota
windows prefer the `duration` label code; questions reuse `AgentQuestionTitleCode.agentRequestsInput`;
locally synthesized failures use `AgentProviderFailureCode`. Leftover Claude/Grok `'Thinking'` titles
become empty titles. Six permission-option label ARB keys were added, so English and Chinese each have
1,041 matching keys. `FailureMessages` now maps the 28D presentation codes exhaustively. Contracts:
85 tests, 1,078 / 1,078; Codex: 178 tests, 3,765 / 3,765; Claude: 269 tests, 2,994 / 2,994; Grok:
242 tests, 3,307 / 3,307; conversation repository: 27 tests, 1,121 / 1,121; root: 85 tests at 100%
after excluding `packages/**`. Packages contain neither a TextCatalog nor an `AppLocalizations` import.

## 2026-08-20 — Step 29 Workspace / Settings / Desktop Notifications

**Problem.** Cubits cannot use `bloc_concurrency` transformers, and
`WorkspaceScanCancellationToken` is a Data type, so WorkspaceCubit must not
import `workspace_client`. Desktop notifications must read both the settings and
notifications repositories without depending on SettingsCubit. Views must not
import `*_repository` packages. The four repository types were `final class`,
so root-app mocktail `Mock implements` did not compile.

**Decision.** Workspace index/children use generation counters to drop stale
results as the Cubit equivalent of `restartable()`; the Repository cancel API
is unchanged. Settings persist through a private `_writeQueue`; appearance
writes land in `_pendingAppearance` and coalesce in that queue.
DesktopNotificationsBloc injects both repositories plus the frozen-locale
`DesktopNotificationCopyResolver`, and turns `settingsChanges` into separate
`sequential()` events instead of wrapping a long-lived subscription in a
sequential transformer. Views re-export domain types from state files. Remove
`final` only from the four Repository classes consumed by this step
(`SettingsRepository`, `WorkspaceRepository`,
`DesktopNotificationsRepository`, `DesktopPlatformRepository`); no method
signatures, adapters, or Provider ports change. App/router wiring stays in
steps 34/35.

**Evidence.** `flutter analyze lib test` reports 0 issues; `dart format` reports
72 files / 0 changed; `bloc lint .` reports 0 issues; the root `very_good test`
run passes 167 randomized tests at 100% hand-written coverage after excluding
`packages/**`.

## 2026-08-20 — Step 30 Project Threads / IDE Session

**Problem.** The plan asks ProjectThreadsBloc to rename/archive/delete, but the
frozen `project_session_repository` only exposes `restore` / `save` /
`threadCatalog` / `threadPage`. Writes live on `AgentProviderBundle` naming,
archival, and deletion ports. The ownership map assigned missing-project
pruning to the Repository, but step 25 never added existence checks, and the
Cubit cannot use `dart:io`.

**Decision.** With the owner's dual-repository choice, the Bloc injects
`project_session_repository` for paging and `agent_provider_repository.bundleFor`
for write ports; a missing capability fails closed with
`AgentProviderFailure.unavailable`. No Repository method or Provider port
changes. The two units do not depend on each other; selected-thread sync uses
`snapshotChanges`, and app composition stays in steps 34/35. Restore does not
prune the filesystem in this step; it maps a business
`ProjectSessionSnapshot` into `IdeSessionInitialRoute`. Drop `final` on the two
consumed repository classes so mocktail can implement them, following step 29.

**Evidence.** `flutter analyze lib test` reports 0 issues; `dart format`
reports 87 files / 0 changed; `bloc lint .` reports 0 issues; the root
`very_good test` run passes 215 randomized tests at 100% hand-written coverage
after excluding `packages/**`.

## 2026-08-20 — Step 31 Agent Management / Usage Statistics

**Problem.** The plan puts selection / detect / test / editor / logs in
AgentManagementBloc, filter / preset / rank and query generation in
UsageStatisticsBloc, and independent quota loading in AgentUsagePanelCubit.
Frozen repository APIs match the plan, so no port change is required. Both
repository classes were `final class`, so root-app mocktail `Mock implements`
did not compile. Creating a `TextEditingController` in `build` leaks.

**Decision.** Do not change Repository methods or Provider ports. Drop `final`
only on `AgentManagementRepository` and `UsageStatisticsRepository`, following
steps 29/30. AgentManagementBloc uses `restartable()` for Started and
selection loads, `droppable()` for detect/test, and `sequential()` for config
edit/save; validation reaches the repository only through a Bloc event.
UsageStatisticsBloc and AgentUsagePanelCubit each inject the same repository
and do not depend on each other. Refresh is `restartable()`, repeated refresh
is `droppable()`, and `report` carries a query generation plus `isCancelled`.
Chart points are app-owned `UsageChartPoint` doubles; the View maps them to
`FlSpot`. Config editing uses a `TextFormField` keyed by document signature
and labeled with the existing `mgmtConfigFile` string. State `toString`
omits raw configuration so `AppBlocObserver` cannot log secrets. The quota
switch sits in `IdeSettingsRow`; the trend chart uses existing
`usageTrendSemantic`. App/router wiring stays in steps 34/35.

**Evidence.** `flutter analyze lib test` reports 0 issues; `dart format`
reports 105 files / 0 changed; `bloc lint .` reports 0 issues; the root
`very_good test` run passes 267 randomized tests at 100% hand-written coverage
after excluding `packages/**`.

## 2026-08-20 — Step 32 AgentConversationBloc

**Problem.** State design §5.1 marks `AgentConversationOpened` as
`sequential()`, while §8.1 requires `restartable()` so a thread switch cancels
an in-flight open. Thread rename / archive / fork / compact and
`approveDeniedAction` live on bundle ports in the frozen repositories, not on
`agent_conversation_repository`. Both conversation types were `final class`,
so root-app mocktail `Mock implements` did not compile.

**Decision.** Do not change Repository methods or Provider ports. Open uses
`restartable()` plus a generation guard per §8.1: `bundleFor` then
`openConversation`. The four safety semantics each have a `sequential()` event
and repository method: permission / question / plan approval on the
conversation repository, plan execution via `submit()`, and the local handoff
only in Bloc State. Thread writes and denied-action approval use ports on the
resolved bundle and fail closed with `operationUnsupported` when missing.
The elapsed ticker stays out of the Bloc. Drop `final` only on
`AgentConversationRepository` and `ConversationHandle`. Markdown cache is not
in State. Full presentation and the 19 capability widget tests stay in step
33; app/router wiring stays in 34/35.

**Evidence.** `flutter analyze lib test` reports 0 issues; `dart format`
reports 113 files / 0 changed; `bloc lint .` reports 0 issues; the root
`very_good test` run passes 291 randomized tests at 100% hand-written coverage
after excluding `packages/**`.
