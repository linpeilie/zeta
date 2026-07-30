#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="${1:-$(cd -- "${script_dir}/../.." && pwd)}"
project_root="$(cd -- "${project_root}" && pwd)"

version="$(
  dart run \
    "${script_dir}/pubspec_version.dart" \
    full \
    "${project_root}/pubspec.yaml"
)"
build_directory="${project_root}/build/macos/Build/Products/Release"
app_path="${build_directory}/Zeta.app"
if [[ ! -d "${app_path}" ]]; then
  echo "macOS release bundle not found: ${app_path}" >&2
  exit 1
fi

bundle_executable="$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleExecutable' \
    "${app_path}/Contents/Info.plist"
)"
if [[ ! -x "${app_path}/Contents/MacOS/${bundle_executable}" ]]; then
  echo "macOS bundle executable is missing or not executable." >&2
  exit 1
fi

dist_directory="${project_root}/dist"
mkdir -p -- "${dist_directory}"
portable_package="${dist_directory}/zeta-${version}-macos-universal.zip"
dmg_package="${dist_directory}/zeta-${version}-macos-universal.dmg"
rm -f -- \
  "${portable_package}" \
  "${dmg_package}" \
  "${portable_package}.sha256" \
  "${dmg_package}.sha256"

ditto -c -k --sequesterRsrc --keepParent \
  "${app_path}" \
  "${portable_package}"
unzip -tq "${portable_package}"

staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/zeta-dmg.XXXXXX")"
mount_directory="$(mktemp -d "${TMPDIR:-/tmp}/zeta-mount.XXXXXX")"
mounted_device=''
cleanup() {
  if [[ -n "${mounted_device}" ]]; then
    hdiutil detach "${mounted_device}" >/dev/null 2>&1 || true
  fi
  rm -rf -- "${staging_directory}" "${mount_directory}"
}
trap cleanup EXIT

ditto "${app_path}" "${staging_directory}/Zeta.app"
ln -s /Applications "${staging_directory}/Applications"
hdiutil create \
  -volname Zeta \
  -srcfolder "${staging_directory}" \
  -ov \
  -format UDZO \
  "${dmg_package}"
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
  echo "Could not mount and inspect the generated DMG." >&2
  exit 1
fi
hdiutil detach "${mounted_device}" >/dev/null
mounted_device=''

write_checksum() {
  local package_path="$1"
  local hash
  hash="$(shasum -a 256 "${package_path}" | awk '{ print $1 }')"
  printf '%s  %s\n' \
    "${hash}" \
    "$(basename -- "${package_path}")" \
    >"${package_path}.sha256"
}

write_checksum "${portable_package}"
write_checksum "${dmg_package}"

echo "Created macOS packages in ${dist_directory}"
