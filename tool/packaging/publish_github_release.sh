#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: publish_github_release.sh <tag> <release-version> <true|false> <dist-directory>" >&2
  exit 64
fi

tag="$1"
release_version="$2"
prerelease="$3"
dist_directory="$4"
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
local_manifest="${temporary_root}/local-manifest"
remote_manifest="${temporary_root}/remote-manifest"
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

: >"${local_manifest}"
asset_paths=()
for name in "${expected_assets[@]}"; do
  path="${dist_directory}/${name}"
  size="$(stat --format='%s' "${path}")"
  digest="$(sha256sum "${path}" | awk '{ print $1 }')"
  printf '%s\t%s\t%s\n' "${name}" "${size}" "${digest}" >>"${local_manifest}"
  asset_paths+=("${path}")
done
sort -o "${local_manifest}" "${local_manifest}"

release_endpoint="repos/${repository}/releases/tags/${tag}"
release_error="${temporary_root}/release-error"
if release_json="$(gh api "${release_endpoint}" 2>"${release_error}")"; then
  :
elif grep -q 'HTTP 404' "${release_error}"; then
  create_args=(
    "${tag}"
    --draft
    --verify-tag
    --title "Zeta ${tag}"
    --generate-notes
  )
  if [[ "${prerelease}" == 'true' ]]; then
    create_args+=(--prerelease --latest=false)
  fi
  gh release create "${create_args[@]}"
  release_json="$(gh api "${release_endpoint}")"
else
  cat "${release_error}" >&2
  exit 1
fi

release_id="$(jq -r '.id' <<<"${release_json}")"
is_draft="$(jq -r '.draft' <<<"${release_json}")"
remote_prerelease="$(jq -r '.prerelease' <<<"${release_json}")"
assets_endpoint="repos/${repository}/releases/${release_id}/assets?per_page=100"

write_remote_manifest() {
  gh api "${assets_endpoint}" |
    jq -r '.[] | [.name, (.size | tostring), ((.digest // "") | sub("^sha256:"; ""))] | @tsv' |
    sort >"${remote_manifest}"
}

verify_remote_manifest() {
  local attempt
  for attempt in 1 2 3 4 5 6; do
    write_remote_manifest
    if cmp -s "${local_manifest}" "${remote_manifest}"; then
      return 0
    fi
    if [[ "${attempt}" -lt 6 ]]; then
      echo "Remote asset digests are not ready (attempt ${attempt}/6); retrying."
      sleep 2
    fi
  done

  echo "GitHub Release assets do not match the verified local manifest." >&2
  diff -u "${local_manifest}" "${remote_manifest}" >&2 || true
  return 1
}

if [[ "${is_draft}" != 'true' ]]; then
  if [[ "${remote_prerelease}" != "${prerelease}" ]] ||
    ! verify_remote_manifest; then
    echo "Published release ${tag} is immutable and cannot be repaired; create a new tag." >&2
    exit 1
  fi
  echo "Published release ${tag} already matches the complete asset manifest."
  exit 0
fi

gh api \
  --method PATCH \
  "repos/${repository}/releases/${release_id}" \
  -f name="Zeta ${tag}" \
  -F draft=true \
  -F prerelease="${prerelease}" \
  >/dev/null

is_expected_asset() {
  local candidate="$1"
  local expected
  for expected in "${expected_assets[@]}"; do
    if [[ "${candidate}" == "${expected}" ]]; then
      return 0
    fi
  done
  return 1
}

while IFS=$'\t' read -r asset_id asset_name; do
  if ! is_expected_asset "${asset_name}"; then
    echo "Removing stale draft asset ${asset_name}."
    gh api \
      --method DELETE \
      "repos/${repository}/releases/assets/${asset_id}"
  fi
done < <(
  gh api "${assets_endpoint}" |
    jq -r '.[] | [.id, .name] | @tsv'
)

gh release upload "${tag}" "${asset_paths[@]}" --clobber
verify_remote_manifest

make_latest=true
if [[ "${prerelease}" == 'true' ]]; then
  make_latest=false
fi
gh api \
  --method PATCH \
  "repos/${repository}/releases/${release_id}" \
  -F draft=false \
  -F prerelease="${prerelease}" \
  -f make_latest="${make_latest}" \
  >/dev/null

published_json="$(gh api "${release_endpoint}")"
if [[ "$(jq -r '.draft' <<<"${published_json}")" != 'false' ]] ||
  [[ "$(jq -r '.prerelease' <<<"${published_json}")" != "${prerelease}" ]]; then
  echo "Release ${tag} was not published with the expected state." >&2
  exit 1
fi
verify_remote_manifest
echo "Published GitHub Release ${tag} with 24 verified assets."
