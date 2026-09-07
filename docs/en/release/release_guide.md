# Release Guide

Documentation checked: 2026-09-07. Release operations and remote settings were not reverified for this edit.

> Translated from [the Chinese original](../../zh/release/release_guide.md), which is the source of truth if the two diverge.

## 1. How releases work

Create a PR targeting `main`, review the version and release notes, then merge it to trigger the [release workflow](../../../.github/workflows/release.yml). Closing an unmerged PR does not publish. No manual tag is required. Every stage uses the PR's fixed merge commit, even if main advances later.

Use the project `$zeta-release` Skill to prepare a version, for example `v0.1.0-beta.13`. Human review, committing, and merging remain separate steps.

## 2. Version and release notes

- Root `release.json` contains `schemaVersion: 1` and a `version` of `X.Y.Z` or `X.Y.Z-beta.N`, without a `v` prefix. This determines the release tag and package version.
- `pubspec.yaml` contains `X.Y.Z+BUILD`, with the same core version and a positive build number. Windows/macOS metadata remains numeric; beta sequence and build number are independent.
- Numeric fields cannot have leading zeroes; beta N must be positive. Other prerelease channels and tag build metadata are unsupported.
- The version must exceed every existing valid release tag. PR validation also compares against the target main version. Numeric ordering applies: `0.1.0-beta.9 < 0.1.0-beta.12 < 0.1.0 < 0.1.1-beta.1`. Equal or older versions fail; increasing BUILD alone cannot bypass this.
- Nonempty notes must exist at `docs/zh/release/notes/v<version>.md`. Follow the [changelog conventions (Chinese)](../../zh/development/documentation.md#更新日志规范), read existing drafts before incremental edits, and link the notes from `CHANGELOG.md`. GitHub Release uses this file directly, without generated commit lists.

Example:

```json
{"schemaVersion": 1, "version": "0.1.0-beta.13"}
```

```yaml
version: 0.1.0+2
```

The migration's `release.json` records the existing `0.1.0-beta.12` baseline; it is not a new release request. Before merging with the new workflow, select a higher version and add its notes through the Skill. The baseline cannot be republished.

## 3. Before releasing

1. Fetch full remote history and tags; prepare a higher version on `dev` or the selected release branch.
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
4. Review and edit the notes, commit with the code, push, and create a PR to `main`. PR checks validate version progression and notes.
5. Merge after checks pass. Merging starts publication; do not manually create/push tags or create a GitHub Release beforehand.

## 4. Automated workflow

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
