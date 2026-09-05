#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: package_macos.sh <release-version> [project-root]" >&2
  exit 64
fi

release_version="$1"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="${2:-$(cd -- "${script_dir}/../.." && pwd)}"
project_root="$(cd -- "${project_root}" && pwd)"

dart "${script_dir}/release_metadata.dart" \
  --tag "v${release_version}" \
  --pubspec "${project_root}/pubspec.yaml" \
  >/dev/null

create_dmg="$(command -v create-dmg || true)"
if [[ -z "${create_dmg}" ]] || [[ "$("${create_dmg}" --version)" != '8.1.0' ]]; then
  echo "Install sindresorhus/create-dmg with Node.js >=20: npm install --global create-dmg@8.1.0" >&2
  exit 1
fi

build_directory="${project_root}/build/macos/Build/Products/Release"
universal_app="${build_directory}/Zeta.app"
if [[ ! -d "${universal_app}" ]]; then
  echo "macOS release bundle not found: ${universal_app}" >&2
  exit 1
fi

dist_directory="${project_root}/dist"
mkdir -p -- "${dist_directory}"

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/zeta-macos.XXXXXX")"
mounted_device=''
cleanup() {
  if [[ -n "${mounted_device}" ]]; then
    hdiutil detach "${mounted_device}" >/dev/null 2>&1 || true
  fi
  rm -rf -- "${temporary_root}"
}
trap cleanup EXIT

mach_o_files() {
  local app_path="$1"
  local candidate
  while IFS= read -r -d '' candidate; do
    if file -b "${candidate}" | grep -q 'Mach-O'; then
      printf '%s\0' "${candidate}"
    fi
  done < <(find "${app_path}" -type f -print0)
}

verify_architectures() {
  local app_path="$1"
  shift
  local expected=("$@")
  local candidate
  local count=0
  while IFS= read -r -d '' candidate; do
    count=$((count + 1))
    local actual
    actual="$(lipo -archs "${candidate}")"
    local architecture
    for architecture in "${expected[@]}"; do
      if [[ " ${actual} " != *" ${architecture} "* ]]; then
        echo "Missing ${architecture} slice in ${candidate}: ${actual}" >&2
        exit 1
      fi
    done
    if [[ ${#expected[@]} -eq 1 && "${actual}" != "${expected[0]}" ]]; then
      echo "Unexpected extra architecture in ${candidate}: ${actual}" >&2
      exit 1
    fi
  done < <(mach_o_files "${app_path}")
  if [[ ${count} -eq 0 ]]; then
    echo "No Mach-O binaries found in ${app_path}." >&2
    exit 1
  fi
}

verify_bundle_executable() {
  local app_path="$1"
  local bundle_executable
  bundle_executable="$(
    /usr/libexec/PlistBuddy \
      -c 'Print :CFBundleExecutable' \
      "${app_path}/Contents/Info.plist"
  )"
  if [[ ! -x "${app_path}/Contents/MacOS/${bundle_executable}" ]]; then
    echo "macOS bundle executable is missing or not executable." >&2
    exit 1
  fi
}

thin_app() {
  local source_app="$1"
  local destination_app="$2"
  local architecture="$3"
  ditto "${source_app}" "${destination_app}"

  local candidate
  while IFS= read -r -d '' candidate; do
    local mode
    local thinned
    mode="$(stat -f '%Lp' "${candidate}")"
    thinned="$(mktemp "${temporary_root}/thin.XXXXXX")"
    lipo "${candidate}" -thin "${architecture}" -output "${thinned}"
    chmod "${mode}" "${thinned}"
    mv -f -- "${thinned}" "${candidate}"
  done < <(mach_o_files "${destination_app}")

  codesign --force --deep --sign - "${destination_app}"
  codesign --verify --deep --strict "${destination_app}"
  verify_architectures "${destination_app}" "${architecture}"
}

write_checksum() {
  local package_path="$1"
  local hash
  hash="$(shasum -a 256 "${package_path}" | awk '{ print $1 }')"
  printf '%s  %s\n' \
    "${hash}" \
    "$(basename -- "${package_path}")" \
    >"${package_path}.sha256"
}

verify_variant_app() {
  local app_path="$1"
  local variant="$2"
  verify_bundle_executable "${app_path}"
  codesign --verify --deep --strict "${app_path}"
  case "${variant}" in
    arm64)
      verify_architectures "${app_path}" arm64
      ;;
    x86_64)
      verify_architectures "${app_path}" x86_64
      ;;
    universal)
      verify_architectures "${app_path}" arm64 x86_64
      ;;
    *)
      echo "Unknown macOS package variant: ${variant}" >&2
      exit 64
      ;;
  esac
}

package_variant() {
  local app_path="$1"
  local variant="$2"
  local portable_package="${dist_directory}/zeta-${release_version}-macos-${variant}.zip"
  local dmg_package="${dist_directory}/zeta-${release_version}-macos-${variant}.dmg"
  local dmg_work_directory="${temporary_root}/dmg-${variant}"
  local mount_directory="${temporary_root}/mount-${variant}"
  local zip_directory="${temporary_root}/zip-${variant}"

  rm -f -- \
    "${portable_package}" \
    "${dmg_package}" \
    "${portable_package}.sha256" \
    "${dmg_package}.sha256"

  ditto -c -k --sequesterRsrc --keepParent \
    "${app_path}" \
    "${portable_package}"
  unzip -tq "${portable_package}"
  mkdir -p -- "${zip_directory}"
  ditto -x -k "${portable_package}" "${zip_directory}"
  if [[ ! -d "${zip_directory}/Zeta.app" ]]; then
    echo "The ZIP package does not contain Zeta.app: ${portable_package}" >&2
    exit 1
  fi
  verify_variant_app "${zip_directory}/Zeta.app" "${variant}"

  mkdir -p -- "${dmg_work_directory}" "${mount_directory}"
  (
    # Isolate the output name and prevent implicit license.txt/license.rtf pickup.
    cd "${dmg_work_directory}"
    "${create_dmg}" \
      --no-version-in-filename \
      --no-code-sign \
      --dmg-title=Zeta \
      "${app_path}" \
      "${dmg_work_directory}"
  )
  if [[ ! -f "${dmg_work_directory}/Zeta.dmg" ]]; then
    echo "create-dmg did not produce Zeta.dmg for ${variant}." >&2
    exit 1
  fi
  mv -- "${dmg_work_directory}/Zeta.dmg" "${dmg_package}"
  hdiutil verify "${dmg_package}"

  mounted_device="$(
    hdiutil attach \
      -readonly \
      -nobrowse \
      -mountpoint "${mount_directory}" \
      "${dmg_package}" |
      awk '/^\/dev\// && !found { print $1; found = 1 }'
  )"
  if [[ -z "${mounted_device}" || ! -d "${mount_directory}/Zeta.app" ]]; then
    echo "Could not mount and inspect ${dmg_package}." >&2
    exit 1
  fi
  if [[ ! -L "${mount_directory}/Applications" ]] ||
    [[ "$(readlink "${mount_directory}/Applications")" != '/Applications' ]] ||
    [[ ! -s "${mount_directory}/.DS_Store" ]]; then
    echo "The DMG is missing its Applications link or Finder layout: ${dmg_package}" >&2
    exit 1
  fi
  verify_variant_app "${mount_directory}/Zeta.app" "${variant}"
  hdiutil detach "${mounted_device}" >/dev/null
  mounted_device=''

  write_checksum "${portable_package}"
  write_checksum "${dmg_package}"
}

verify_bundle_executable "${universal_app}"
codesign --force --deep --sign - "${universal_app}"
codesign --verify --deep --strict "${universal_app}"
verify_architectures "${universal_app}" arm64 x86_64

arm64_app="${temporary_root}/arm64/Zeta.app"
x86_64_app="${temporary_root}/x86_64/Zeta.app"
mkdir -p -- "$(dirname -- "${arm64_app}")" "$(dirname -- "${x86_64_app}")"
thin_app "${universal_app}" "${arm64_app}" arm64
thin_app "${universal_app}" "${x86_64_app}" x86_64

package_variant "${arm64_app}" arm64
package_variant "${x86_64_app}" x86_64
package_variant "${universal_app}" universal

asset_count="$(
  find "${dist_directory}" -maxdepth 1 -type f \
    -name "zeta-${release_version}-macos-*" |
    wc -l |
    tr -d ' '
)"
if [[ "${asset_count}" -ne 12 ]]; then
  echo "Expected 12 macOS assets, found ${asset_count}." >&2
  exit 1
fi

echo "Created macOS packages in ${dist_directory}"
