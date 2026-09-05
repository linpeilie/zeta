# Release Guide

Last updated: 2026-09-05

> Translated from [the Chinese original](../../zh/release/release_guide.md), which is the source of truth if the two diverge.

## 1. How releases work

Zeta uses a [GitHub Actions release workflow](../../../.github/workflows/release.yml) to build and publish desktop packages for Windows, macOS and Linux. The workflow only listens for `v*` tags pushed to GitHub. A tag must point at a commit reachable from `main` and pass the version pre-check described below.

The repository has GitHub immutable releases enabled. The publish job hands every asset to the GitHub CLI, which internally creates a temporary draft, uploads the assets, and publishes the release once all uploads succeed. Do not create a release manually beforehand.

Releases still do not perform Windows code signing or Apple notarization. macOS derived packages are re-signed ad-hoc so the split-architecture app bundles remain structurally valid, but users may still see SmartScreen or Gatekeeper prompts on first run.

## 2. Before releasing

1. Confirm the code to be released is merged into `main` and your working tree is clean.
2. Update `version` in `pubspec.yaml`:

   ```yaml
   version: 0.2.0+2
   ```

   `0.2.0` is the numeric application version and must match the tag's core version. `2` is a positive integer build number. Windows and macOS application metadata use these two numeric fields and never carry a beta suffix.
3. Commit the version change and push it to `main`.
4. Run the full release gate before creating the tag:

   ```sh
   flutter pub get --enforce-lockfile
   flutter analyze
   bash tool/test_full.sh
   ```

## 3. Tag rules

The workflow accepts only these two forms:

| `pubspec.yaml` | Valid tag | Release type |
| --- | --- | --- |
| `version: 0.2.0+2` | `v0.2.0` | Stable release, marked Latest |
| `version: 0.2.0+2` | `v0.2.0-beta.1` | Pre-release, not Latest |

No numeric segment may carry a leading zero, and the beta ordinal must be a positive integer without leading zeros. These tags are rejected by the pre-check:

- `v0.3.0` — core version does not match `pubspec.yaml`.
- `v0.2.0-beta.0` or `v0.2.0-beta.01` — invalid beta ordinal.
- `v0.2.0-rc.1` — the release channel currently supports stable and beta only.
- `0.2.0` — missing the `v` prefix.
- `v0.2.0+2` — tags do not accept build metadata.
- Any tag pointing at a commit outside `main`'s history.

You can check the metadata locally on its own:

```sh
dart tool/packaging/release_metadata.dart \
  --tag v0.2.0-beta.1 \
  --pubspec pubspec.yaml
```

The command prints JSON; CI additionally passes `--github-output` to write the GitHub Actions output file.

## 4. Creating and pushing the tag

A beta release, for example:

```sh
git switch main
git pull --ff-only
git tag -a v0.2.0-beta.1 -m "Zeta v0.2.0-beta.1"
git push origin v0.2.0-beta.1
```

For a stable release, use `v0.2.0` instead. The tag must point at a commit that already carries the correct `pubspec.yaml` version. After pushing, no manual GitHub Release is needed.

## 5. What the automation does

Once the tag is pushed:

1. `Validate release metadata` checks the tag format, `pubspec.yaml`, and reachability from `main`.
2. The release workflow calls the reusable CI from the same commit, running formatting, analysis, the six test shards and the internal package gate. Once all pass, Windows, macOS and Linux build in parallel. Ordinary CI only watches branches and pull requests, so a tag push does not start a second independent CI run.
3. The publish job collects the assets and verifies them against an exact 24-item manifest plus local SHA-256 sums.
4. A single `gh release create <tag> <24 assets>` call runs, without an explicit `--draft`. The GitHub CLI handles the temporary draft, uploads every asset, and publishes — which is what immutable releases require.
5. After publishing, the release status and the 24 asset names are verified, along with the GitHub Release attestation and `gh release verify-asset` for every local file uploaded in this run.

Only the final publish job holds `contents: write`. Betas are automatically marked pre-release and are never set as Latest.

Every successful release contains 12 distribution packages plus a `.sha256` for each — 24 assets in total:

| Platform | Packages |
| --- | --- |
| Windows x86_64 | ZIP, Inno Setup EXE |
| macOS arm64 | ZIP, DMG |
| macOS x86_64 | ZIP, DMG |
| macOS universal | ZIP, DMG |
| Linux x86_64 | `tar.gz`, DEB, RPM, AppImage |

`<version>` in an asset name is the tag with the leading `v` removed, without the build number. For example, `v0.2.0-beta.1` produces `zeta-0.2.0-beta.1-linux-x86_64.AppImage`. Linux beta packages use `0.2.0~beta.1` internally for correct ordering semantics; Windows and macOS application metadata still use the numeric version from `pubspec.yaml`.

macOS builds the universal app first and verifies that every Mach-O binary contains both arm64 and x86_64, then derives the two single-architecture apps, re-signs them ad-hoc, and verifies each ZIP and DMG separately. All four Linux packages come from the same staging tree. The download commit and SHA-256 of the AppImage tooling and runtime are pinned, and a verification mismatch fails the build outright.

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

## 7. Failure recovery and immutability constraints

- **Build or quality gate failed** — the release job never runs. Fix the code and version, then create a new tag.
- **Asset upload failed** — the GitHub CLI will not publish an incomplete release. Re-run the failed job.
- **A draft was left behind after the workflow was force-cancelled** — the publish script prints the draft URL and fails closed. Confirm and delete that draft manually, then re-run. The script never guesses at or auto-deletes a remote draft.
- **Already published, with correct release type, tag, 24 asset names and attestation** — a re-run counts as success and does not modify the release again.
- **Already published, but status, asset manifest or attestation do not match** — the workflow fails explicitly. An immutable release cannot be repaired or topped up; fix the problem and cut a new tag.
- A tag or release that is already public must never be rewritten, or deleted and reused. The existing immutable `v0.1.0-beta.4`, which has no assets, stays as it is. Beta 6/7 drafts left behind by the old workflow are not deleted automatically by CI; after merging these changes, use a new tag `v0.1.0-beta.8` for end-to-end acceptance.
- If the tag pre-check fails and no public release was produced, you may delete the bad tag once you have confirmed nothing external is using it. For anything already public, always increment the version and cut a new tag.

## 8. Release checklist

- [ ] The numeric version and positive integer build number in `pubspec.yaml` are updated.
- [ ] The version commit is merged and pushed to `main`.
- [ ] `flutter analyze` and `bash tool/test_full.sh` pass.
- [ ] The tag is `vX.Y.Z` or `vX.Y.Z-beta.N`, and its core version matches the application version.
- [ ] All GitHub Actions jobs succeeded.
- [ ] Release type, Latest status, release notes and all 24 assets are correct.
- [ ] Release attestation, local SHA-256 sums, macOS architectures and the target-platform launch smoke test all pass.
