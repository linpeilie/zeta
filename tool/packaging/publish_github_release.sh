#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "Usage: publish_github_release.sh <tag> <release-version> <true|false> <dist-directory> <commit-sha> <notes-file>" >&2
  exit 64
fi

tag="$1"
release_version="$2"
prerelease="$3"
dist_directory="$4"
commit_sha="$5"
notes_file="$6"
if [[ ! "${commit_sha}" =~ ^[0-9a-f]{40}$ ]] || [[ ! -s "${notes_file}" ]]; then
  echo "A full commit SHA and nonempty release notes file are required." >&2
  exit 64
fi
if [[ "$(git rev-parse HEAD)" != "${commit_sha}" ]]; then
  echo "Publishing checkout differs from the build commit." >&2
  exit 1
fi
if git show-ref --verify --quiet "refs/tags/${tag}"; then
  if [[ "$(git rev-parse "${tag}^{commit}")" != "${commit_sha}" ]]; then
    echo "Existing tag points to another commit." >&2
    exit 1
  fi
fi
repository="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

if [[ "${tag}" != "v${release_version}" ]]; then
  echo "Tag ${tag} does not match release version ${release_version}." >&2
  exit 64
fi
if [[ "${prerelease}" != 'true' && "${prerelease}" != 'false' ]]; then
  echo "Prerelease must be true or false." >&2
  exit 64
fi
dist_directory="$(cd -- "${dist_directory}" && pwd)"

packages=(
  "zeta-${release_version}-windows-x86_64.zip"
  "zeta-${release_version}-windows-x86_64-setup.exe"
  "zeta-${release_version}-macos-arm64.zip"
  "zeta-${release_version}-macos-arm64.dmg"
  "zeta-${release_version}-macos-x86_64.zip"
  "zeta-${release_version}-macos-x86_64.dmg"
  "zeta-${release_version}-macos-universal.zip"
  "zeta-${release_version}-macos-universal.dmg"
  "zeta-${release_version}-linux-x86_64.tar.gz"
  "zeta-${release_version}-linux-x86_64.deb"
  "zeta-${release_version}-linux-x86_64.rpm"
  "zeta-${release_version}-linux-x86_64.AppImage"
)
expected_assets=()
for package in "${packages[@]}"; do
  expected_assets+=("${package}" "${package}.sha256")
done

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/zeta-release.XXXXXX")"
cleanup() {
  rm -rf -- "${temporary_root}"
}
trap cleanup EXIT

expected_names="${temporary_root}/expected-names"
local_names="${temporary_root}/local-names"
remote_names="${temporary_root}/remote-names"
release_error="${temporary_root}/release-error"
printf '%s\n' "${expected_assets[@]}" | sort >"${expected_names}"
find "${dist_directory}" -maxdepth 1 -type f -printf '%f\n' | sort >"${local_names}"
if ! cmp -s "${expected_names}" "${local_names}"; then
  echo "Local release assets do not match the required 24-file manifest." >&2
  diff -u "${expected_names}" "${local_names}" >&2 || true
  exit 1
fi

(
  cd "${dist_directory}"
  sha256sum --check ./*.sha256
)

asset_paths=()
for name in "${expected_assets[@]}"; do
  asset_paths+=("${dist_directory}/${name}")
done

read_release_json() {
  gh release view "${tag}" \
    --repo "${repository}" \
    --json assets,isDraft,isImmutable,isPrerelease,tagName,url \
    --jq '{
      asset_names: [.assets[].name] | sort,
      draft: .isDraft,
      immutable: .isImmutable,
      prerelease: .isPrerelease,
      tag_name: .tagName,
      url: .url
    }'
}

verify_release_state() {
  local release_json="$1"

  jq -r '.asset_names[]' <<<"${release_json}" | tr -d '\r' >"${remote_names}"
  if [[ "$(jq -rj '.draft' <<<"${release_json}")" != 'false' ]] ||
    [[ "$(jq -rj '.immutable' <<<"${release_json}")" != 'true' ]] ||
    [[ "$(jq -rj '.prerelease' <<<"${release_json}")" != "${prerelease}" ]] ||
    [[ "$(jq -rj '.tag_name' <<<"${release_json}")" != "${tag}" ]] ||
    ! cmp -s "${expected_names}" "${remote_names}"; then
    echo "Published immutable release ${tag} does not match the expected state." >&2
    diff -u "${expected_names}" "${remote_names}" >&2 || true
    return 1
  fi
}

if release_json="$(read_release_json 2>"${release_error}")"; then
  if [[ "$(jq -rj '.draft' <<<"${release_json}")" == 'true' ]]; then
    echo "Draft release remains at $(jq -rj '.url' <<<"${release_json}")." >&2
    echo "Delete that draft manually, then rerun this workflow." >&2
    exit 1
  fi
  verify_release_state "${release_json}"
  gh release verify "${tag}" --repo "${repository}" >/dev/null
  echo "Published GitHub Release ${tag} already has the expected 24 assets and a valid attestation."
  exit 0
elif ! grep -Eqi 'release not found|HTTP 404' "${release_error}"; then
  cat "${release_error}" >&2
  exit 1
fi

# GitHub may expose an unpublished prerelease only through an untagged-* URL.
# Detect it by the exact release title instead of trying to address a draft by tag.
drafts_json="$(
  gh api --paginate "repos/${repository}/releases?per_page=100" |
    jq -s \
      --arg tag "${tag}" \
      --arg title "Zeta ${tag}" \
      'add | map(select(.draft == true and (.tag_name == $tag or .name == $title)))'
)"
if [[ "$(jq -j 'length' <<<"${drafts_json}")" -ne 0 ]]; then
  echo "A draft release for ${tag} already exists:" >&2
  jq -r '.[] | "  \(.html_url)"' <<<"${drafts_json}" >&2
  echo "Delete the stale draft manually, then rerun this workflow." >&2
  exit 1
fi

create_args=(
  "${tag}"
  "${asset_paths[@]}"
  --repo "${repository}"
  --target "${commit_sha}"
  --title "Zeta ${tag}"
  --notes-file "${notes_file}"
)
if [[ "${prerelease}" == 'true' ]]; then
  create_args+=(--prerelease --latest=false)
else
  create_args+=(--latest=true)
fi

# Do not pass --draft. With assets present, GitHub CLI creates a temporary draft,
# uploads every asset through its release ID, and publishes only after success.
gh release create "${create_args[@]}"

release_json="$(read_release_json)"
verify_release_state "${release_json}"
for attempt in 1 2 3 4 5 6; do
  if gh release verify "${tag}" --repo "${repository}" >/dev/null; then
    break
  fi
  if [[ "${attempt}" -eq 6 ]]; then
    echo "Release attestation for ${tag} is not available." >&2
    exit 1
  fi
  echo "Release attestation is not ready; retrying (${attempt}/6)."
  sleep 2
done
for path in "${asset_paths[@]}"; do
  gh release verify-asset "${tag}" "${path}" --repo "${repository}" >/dev/null
done
echo "Published GitHub Release ${tag} with 24 verified assets."
