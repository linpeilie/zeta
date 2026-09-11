# Release Guide

Documentation checked: 2026-09-07. Release operations and remote settings were not reverified for this edit.

> Translated from [the Chinese original](../../zh/release/release_guide.md), which is the source of truth if the two diverge.

## 1. How releases work

Prepare versions and notes on `develop`; do not create a `release/*` branch. Use `hotfix/*` from `main` only for urgent production fixes. After stable-version acceptance, create a PR from `develop` to `main`, review the version and release notes, then merge it to trigger the [release workflow](../../../.github/workflows/release.yml). Closing an unmerged PR does not publish. No manual tag is required. Every stage uses the PR's fixed merge commit, even if main advances later.

Use the project `$zeta-release` Skill with an explicit version or just a beta/stable channel to select the next version automatically. The Skill prepares in place on the checked-out `develop` branch and does not create or switch to `release/*`. Human review, committing, and merging remain separate steps.

The Skill creates the GitHub PR through `gh`. Fetching main is for comparison and validation only; do not automatically merge, pull with a merge, or rebase. Report PR conflicts; branch synchronization and conflict resolution require separate explicit instructions.

### Branch flow and current automation limits

See the [branch model](../../../CONTRIBUTING.en.md#branch-model). The `$zeta-release` path prepares versions and notes on `develop` and does not create `release/*`. Only ready stable versions enter `main`. Prepare beta on `develop`; do not merge a prerelease into `main` to publish it.

The current workflow still triggers only after a PR merges into `main` and accepts beta metadata. Publishing beta from `develop` is not implemented yet. This update does not mean that automation exists. Beta version and notes preparation can continue, but publication requires adapting the workflow first; the previous beta-to-main route must not be used.

## 2. Version and release notes

- Root `release.json` contains `schemaVersion: 1` and a `version` of `X.Y.Z` or `X.Y.Z-beta.N`, without a `v` prefix. This determines the release tag and package version.
- `pubspec.yaml` contains `X.Y.Z+BUILD`, with the same core version and a positive build number. Windows/macOS metadata remains numeric; beta sequence and build number are independent.
- Numeric fields cannot have leading zeroes; beta N must be positive. Other prerelease channels and tag build metadata are unsupported.
- The version must exceed every existing valid release tag. Local release preparation also compares against the target main version. Numeric ordering applies: `0.1.0-beta.9 < 0.1.0-beta.12 < 0.1.0 < 0.1.1-beta.1`. Equal or older versions fail; increasing BUILD alone cannot bypass this.
- Nonempty notes must exist at `docs/zh/release/notes/v<version>.md`. Follow the [changelog conventions (Chinese)](../../zh/development/documentation.md#更新日志规范), read existing drafts before incremental edits, and link the notes from `CHANGELOG.md`. GitHub Release uses this file directly, without generated commit lists.

Example:

```json
{"schemaVersion": 1, "version": "0.1.0-beta.13"}
```

```yaml
version: 0.1.0+2
```

The migration's `release.json` records the existing `0.1.0-beta.12` baseline; it is not a new release request. Before merging with the new workflow, automatically select or explicitly specify a higher version and add its notes through the Skill. The baseline cannot be republished.

### Automatic next-version selection

Example requests:

```text
Use $zeta-release to publish a beta version.
Use $zeta-release to publish a stable version.
Use $zeta-release to prepare v0.2.0-beta.1.
```

A channel-only request does not require a version-number follow-up. Fetch complete history, current remote main and tags, then take the numeric maximum across all valid local/remote release tags, main's release version and the current `release.json` version. Do not restrict this baseline to one channel. An explicit version takes precedence; equal or older versions are rejected, not silently replaced.

| Highest known version | Publish beta | Publish stable |
| --- | --- | --- |
| `0.1.0-beta.12` | `0.1.0-beta.13` | `0.1.0` |
| `0.1.0` | `0.1.1-beta.1` | `0.1.1` |
| `0.2.0-beta.9` | `0.2.0-beta.10` | `0.2.0` |

From a beta baseline, increment its beta sequence or remove the suffix for stable. From a stable baseline, increment the patch number and append `-beta.1` for beta. Major/minor upgrades require an explicit full version; they are not inferred from commits.

When continuing the same unpublished draft, reuse its version and BUILD if same-channel version changes, versioned notes or an existing PR establish that the target was already selected, and it remains above all tags and main's version. A configuration value alone is not draft evidence. Repeated preparation must not keep incrementing or reuse a published version.

Only when complete history contains no valid release tags, main has no release version, and the current branch has no `release.json`, initialize from the `pubspec.yaml` core: `X.Y.Z-beta.1` for beta or `X.Y.Z` for stable. Invalid configuration, unavailable remotes and incomplete history require a reported pause, not first-release fallback. If neither channel nor version is given and context is unclear, ask only for the channel.

Before editing, report the baseline and selected version, then continue without an extra confirmation step. Strict progression checks still apply. A new preparation uses the highest confirmed BUILD plus one; continuing a draft preserves it. Selection happens in the Skill, which writes the version files; CI reads the committed version without incrementing again. If new remote versions invalidate an automatic choice, refresh and recalculate; pause on persistent remote changes rather than retrying indefinitely.

## 3. Before releasing

1. Fetch full remote history and tags; prepare the next version on the current `develop` branch without creating or switching to `release/*`. Preserve the worktree. If the checkout is not `develop`, do not switch branches for the user.
2. Update `release.json`, `pubspec.yaml`, versioned notes and the `CHANGELOG.md` link together.
3. Run validation and the full gate:

   ```sh
   git fetch origin --tags
   dart tool/packaging/release_plan.dart --previous-ref origin/main
   flutter pub get --enforce-lockfile
   flutter analyze
   bash tool/test_full.sh
   ```

   Use CI's `PUB_HOSTED_URL=https://pub.dev` to avoid lockfile changes from local mirrors.
4. Review and edit the notes, commit with the code, and push `develop`. Check for an existing PR with `gh pr list --base main --head develop --state open`, then create it on GitHub with `gh pr create --base main --head develop --title <title> --body-file <body-file>`, or update the existing PR with `gh pr edit`. Verify branches and status with `gh pr view` and return the PR URL. Run local version and notes validation before committing. PRs targeting `main` run standalone CI; release preflight validates the version and notes again after merging.
5. After checks pass, the user merges the PR on GitHub to start publication. “Commit and open a PR” does not include a local merge or `gh pr merge`; the Skill does not automatically resolve PR conflicts. Do not manually create/push tags or create a GitHub Release beforehand.

## 4. Automated workflow

Standalone CI runs for PRs targeting `develop` or `main`, with no push or manual trigger. `workflow_call` remains available: release calls still run all checks at the merge commit passed through `checkout-ref`. PR branch filters do not restrict this call.

PR checks also compile a universal macOS release to catch Swift and native API
errors that Dart analysis cannot detect. Release calls through `workflow_call`
skip this duplicate build; the release workflow's macOS job still builds with
the same configuration and creates the packages afterward.

1. Process merged PRs to main only; pin their merge SHA and verify main ancestry.
2. Read the version and notes from that commit and validate progression, numeric metadata, and notes availability.
3. Run reusable CI at the same commit, then build Windows, macOS and Linux packages.
4. Serialize publication, fetch remote tags again, and recheck progression so an older concurrent build cannot supersede a newer release.
5. Verify the 24-file manifest and SHA-256, then use `gh release create --target <merge-SHA> --notes-file <versioned-notes>` to create the tag and publish. Beta is Pre-release and not Latest; stable is Latest.
6. Verify published state, assets, Release attestation, and each uploaded file.
7. After publication, fetch the version tag from the remote, resolve its commit (supporting lightweight and annotated tags), verify it matches the merge SHA, and record it in the Actions summary. A missing or mismatched tag fails the workflow; tags are never overwritten or moved.

Only publication has `contents: write`. An existing tag must point to the same merge SHA; reusing a version on another commit fails. Published versions are never rewritten.

With attachments, GitHub CLI creates a temporary draft, uploads assets, and publishes; the script does not pass `--draft`. See the [GitHub CLI documentation](https://cli.github.com/manual/gh_release_create) for automatic tag targeting and notes input.

## 5. Packages and platform acceptance

A successful release contains 12 packages and their `.sha256` files, totaling 24 assets:

| Platform | Packages |
| --- | --- |
| Windows x86_64 | ZIP, Inno Setup EXE |
| macOS arm64 / x86_64 / universal | ZIP and DMG for each |
| Linux x86_64 | tar.gz, DEB, RPM, AppImage |

Asset versions include the beta suffix but exclude BUILD. Linux beta package metadata uses `X.Y.Z~beta.N`; Windows/macOS use numeric app versions.

Windows code signing and macOS notarization are not enabled; derived macOS apps are ad-hoc signed again. First launch may show SmartScreen or Gatekeeper prompts. macOS builds universal apps before deriving single-architecture packages. Linux packages share one staging tree, and downloaded AppImage tools/runtime use pinned SHA-256 checks. Automation does not replace real installation and startup acceptance.

### macOS DMG tooling

DMGs use the original default background, window and icon layout from
[sindresorhus/create-dmg 8.1.0](https://github.com/sindresorhus/create-dmg/tree/v8.1.0).
CI uses Node.js 22.23.2; use the same version locally where possible (the tool
requires Node.js >=20). Install the same npm tool version, not the similarly
named Homebrew shell tool:

```sh
npm install --global create-dmg@8.1.0
create-dmg --version
```

Build the universal app as in the release workflow, then run
`bash tool/packaging/package_macos.sh <release-version>`. The script generates
`Zeta.dmg` in a separate temporary working directory for each architecture, then
renames it to include the release version and architecture. This prevents output
collisions and implicit inclusion of a working-directory `license.txt` or
`license.rtf`. Images use the tool's default APFS / ULFO format. `--no-code-sign`
only skips DMG signing; app ad-hoc signing and architecture/signature checks of
the ZIP and DMG contents still run. Packaging also verifies the Applications
symlink and Finder layout file before writing SHA-256 checksums.

On initial adoption and tool upgrades, manually verify the default background,
icons and window layout in Finder, then drag the app into Applications and launch
it. Script checks do not replace visual and installation acceptance.

## 6. Verifying after release

1. On the GitHub Actions page, confirm the pre-check, quality gate, three build jobs and the publish job all succeeded.
2. On the Releases page, confirm the title, tag, release notes and release type are correct.
3. Confirm the release contains 12 distribution packages and 12 `.sha256` files.
4. Download the package for your platform and verify its SHA-256:

   ```sh
   sha256sum --check zeta-0.2.0-beta.1-linux-x86_64.AppImage.sha256
   shasum -a 256 --check zeta-0.2.0-beta.1-macos-universal.dmg.sha256
   ```

   On Windows PowerShell:

   ```powershell
   $file = '.\zeta-0.2.0-beta.1-windows-x86_64.zip'
   $expected = (Get-Content "$file.sha256").Split()[0]
   $actual = (Get-FileHash $file -Algorithm SHA256).Hash
   $actual.ToLowerInvariant() -eq $expected.ToLowerInvariant()
   ```

5. Verify the actual architectures of all three macOS packages, and run an install-and-launch smoke test on the target platform.

## 7. Recovery and immutable releases

- Build or quality failure: publication does not run. Retry the same merged commit; code fixes require a new PR with a higher release version.
- Upload failure: the CLI does not publish incomplete assets. Retry the failed job.
- A cancelled run may leave a draft. The script reports its URL and stops; inspect and remove the draft manually before retrying.
- A valid already-published immutable release can be verified on retry only when its tag still points to the original merge commit. State, assets and attestation must match.
- Incorrect published releases cannot be repaired or have assets appended. Fix through a new PR and higher version. Never rewrite or delete and reuse public tags/releases.

## 8. Checklist

- [ ] `release.json`, the numeric `pubspec.yaml` version and positive BUILD agree.
- [ ] Notes were reviewed and the version strictly exceeds previous versions.
- [ ] Version and notes merged through a PR to main; publication pins that merge commit.
- [ ] Analysis and the full test gate pass.
- [ ] The automatically created tag has the expected version and merge SHA.
- [ ] GitHub Actions succeeds; release type, Latest status, notes and all 24 assets are correct.
- [ ] Attestation, SHA-256, macOS architectures and target-platform installation/startup acceptance pass.
