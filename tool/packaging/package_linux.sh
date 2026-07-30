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
bundle_directory="${project_root}/build/linux/x64/release/bundle"
executable="${bundle_directory}/zeta"
if [[ ! -x "${executable}" ]]; then
  echo "Linux release executable not found: ${executable}" >&2
  exit 1
fi

dist_directory="${project_root}/dist"
mkdir -p -- "${dist_directory}"
portable_package="${dist_directory}/zeta-${version}-linux-x64.tar.gz"
deb_package="${dist_directory}/zeta_${version}_amd64.deb"
rm -f -- \
  "${portable_package}" \
  "${deb_package}" \
  "${portable_package}.sha256" \
  "${deb_package}.sha256"

tar -C "${bundle_directory}" -czf "${portable_package}" .

package_root="$(mktemp -d "${TMPDIR:-/tmp}/zeta-deb.XXXXXX")"
archive_listing="$(mktemp "${TMPDIR:-/tmp}/zeta-tar.XXXXXX")"
deb_listing="$(mktemp "${TMPDIR:-/tmp}/zeta-deb-list.XXXXXX")"
cleanup() {
  rm -rf -- "${package_root}"
  rm -f -- "${archive_listing}" "${deb_listing}"
}
trap cleanup EXIT

tar -tzf "${portable_package}" >"${archive_listing}"
if ! grep -qx './zeta' "${archive_listing}"; then
  echo "The Linux portable package does not contain zeta." >&2
  exit 1
fi

install -d \
  "${package_root}/DEBIAN" \
  "${package_root}/opt/zeta" \
  "${package_root}/usr/bin" \
  "${package_root}/usr/share/applications" \
  "${package_root}/usr/share/icons/hicolor/512x512/apps"
cp -a "${bundle_directory}/." "${package_root}/opt/zeta/"
ln -s /opt/zeta/zeta "${package_root}/usr/bin/zeta"
install -m 0644 \
  "${project_root}/linux/runner/resources/app_icon.png" \
  "${package_root}/usr/share/icons/hicolor/512x512/apps/io.github.linpeilie.zeta.png"

cat >"${package_root}/usr/share/applications/io.github.linpeilie.zeta.desktop" <<'EOF'
[Desktop Entry]
Name=Zeta
Comment=Desktop Agent IDE
Exec=/opt/zeta/zeta
Icon=io.github.linpeilie.zeta
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=io.github.linpeilie.zeta
EOF

installed_size="$(du -sk "${package_root}" | awk '{ print $1 }')"
cat >"${package_root}/DEBIAN/control" <<EOF
Package: zeta
Version: ${version}
Section: devel
Priority: optional
Architecture: amd64
Installed-Size: ${installed_size}
Maintainer: linpeilie <linpeilie@users.noreply.github.com>
Depends: libgtk-3-0 | libgtk-3-0t64, libfontconfig1, libblkid1, liblzma5
Description: Zeta desktop Agent IDE
 Zeta provides a desktop shell for working with coding agents.
EOF

dpkg-deb --build --root-owner-group "${package_root}" "${deb_package}"
if [[ "$(dpkg-deb --field "${deb_package}" Package)" != 'zeta' ]]; then
  echo "The generated DEB has an unexpected package name." >&2
  exit 1
fi
dpkg-deb --contents "${deb_package}" >"${deb_listing}"
if ! grep -q './opt/zeta/zeta' "${deb_listing}" ||
  ! grep -q './usr/share/applications/io.github.linpeilie.zeta.desktop' "${deb_listing}"; then
  echo "The generated DEB is missing required application files." >&2
  exit 1
fi

write_checksum() {
  local package_path="$1"
  local hash
  hash="$(sha256sum "${package_path}" | awk '{ print $1 }')"
  printf '%s  %s\n' \
    "${hash}" \
    "$(basename -- "${package_path}")" \
    >"${package_path}.sha256"
}

write_checksum "${portable_package}"
write_checksum "${deb_package}"

echo "Created Linux packages in ${dist_directory}"
