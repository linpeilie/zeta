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
