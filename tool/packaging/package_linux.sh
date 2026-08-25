#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: package_linux.sh <release-version> [project-root]" >&2
  exit 64
fi

release_version="$1"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="${2:-$(cd -- "${script_dir}/../.." && pwd)}"
project_root="$(cd -- "${project_root}" && pwd)"

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/zeta-linux.XXXXXX")"
cleanup() {
  rm -rf -- "${temporary_root}"
}
trap cleanup EXIT

metadata_json="$(dart "${script_dir}/release_metadata.dart" \
  --tag "v${release_version}" \
  --pubspec "${project_root}/pubspec.yaml")"
linux_package_version="$(
  jq -er '.linux_package_version | strings' <<<"${metadata_json}"
)"
rpm_release="$(jq -er '.rpm_release | strings' <<<"${metadata_json}")"

bundle_directory="${project_root}/build/linux/x64/release/bundle"
executable="${bundle_directory}/zeta"
if [[ ! -x "${executable}" ]]; then
  echo "Linux release executable not found: ${executable}" >&2
  exit 1
fi
if ! file -b "${executable}" | grep -q 'x86-64'; then
  echo "Linux release executable is not x86_64: $(file -b "${executable}")" >&2
  exit 1
fi

dist_directory="${project_root}/dist"
mkdir -p -- "${dist_directory}"
portable_package="${dist_directory}/zeta-${release_version}-linux-x86_64.tar.gz"
deb_package="${dist_directory}/zeta-${release_version}-linux-x86_64.deb"
rpm_package="${dist_directory}/zeta-${release_version}-linux-x86_64.rpm"
appimage_package="${dist_directory}/zeta-${release_version}-linux-x86_64.AppImage"
for package_path in \
  "${portable_package}" \
  "${deb_package}" \
  "${rpm_package}" \
  "${appimage_package}"; do
  rm -f -- "${package_path}" "${package_path}.sha256"
done

tar -C "${bundle_directory}" -czf "${portable_package}" .
archive_listing="${temporary_root}/tar-listing"
tar -tzf "${portable_package}" >"${archive_listing}"
if ! grep -qx './zeta' "${archive_listing}"; then
  echo "The Linux portable package does not contain zeta." >&2
  exit 1
fi

package_root="${temporary_root}/package"
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

desktop_file="${package_root}/usr/share/applications/io.github.linpeilie.zeta.desktop"
cat >"${desktop_file}" <<'EOF'
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
Version: ${linux_package_version}
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
if [[ "$(dpkg-deb --field "${deb_package}" Package)" != 'zeta' ]] ||
  [[ "$(dpkg-deb --field "${deb_package}" Version)" != "${linux_package_version}" ]]; then
  echo "The generated DEB has unexpected package metadata." >&2
  exit 1
fi
deb_listing="${temporary_root}/deb-listing"
dpkg-deb --contents "${deb_package}" >"${deb_listing}"
if ! grep -q './opt/zeta/zeta' "${deb_listing}" ||
  ! grep -q './usr/share/applications/io.github.linpeilie.zeta.desktop' "${deb_listing}"; then
  echo "The generated DEB is missing required application files." >&2
  exit 1
fi

rpm_root="${temporary_root}/rpmbuild"
mkdir -p -- \
  "${rpm_root}/BUILD" \
  "${rpm_root}/BUILDROOT" \
  "${rpm_root}/RPMS" \
  "${rpm_root}/SOURCES" \
  "${rpm_root}/SPECS" \
  "${rpm_root}/SRPMS"
rpmbuild \
  --define "_topdir ${rpm_root}" \
  --define "_build_id_links none" \
  --define "zeta_version ${linux_package_version}" \
  --define "zeta_release ${rpm_release}" \
  --define "zeta_source ${package_root}" \
  -bb "${script_dir}/zeta.spec"
generated_rpm="$(find "${rpm_root}/RPMS" -type f -name 'zeta-*.rpm' -print -quit)"
if [[ -z "${generated_rpm}" ]]; then
  echo "rpmbuild did not generate a Zeta RPM." >&2
  exit 1
fi
cp -- "${generated_rpm}" "${rpm_package}"
rpm_metadata="$(rpm -qp --qf '%{NAME}\n%{VERSION}\n%{RELEASE}\n%{ARCH}\n' "${rpm_package}")"
expected_rpm_metadata="$(
  printf 'zeta\n%s\n%s\nx86_64' "${linux_package_version}" "${rpm_release}"
)"
if [[ "${rpm_metadata}" != "${expected_rpm_metadata}" ]]; then
  echo "The generated RPM has unexpected package metadata." >&2
  printf 'Expected:\n%s\nActual:\n%s\n' "${expected_rpm_metadata}" "${rpm_metadata}" >&2
  exit 1
fi
rpm_listing="${temporary_root}/rpm-listing"
rpm -qlp "${rpm_package}" >"${rpm_listing}"
if ! grep -qx '/opt/zeta/zeta' "${rpm_listing}" ||
  ! grep -qx '/usr/share/applications/io.github.linpeilie.zeta.desktop' "${rpm_listing}"; then
  echo "The generated RPM is missing required application files." >&2
  exit 1
fi

download_verified() {
  local url="$1"
  local expected_sha256="$2"
  local destination="$3"
  curl \
    --fail \
    --location \
    --retry 3 \
    --silent \
    --show-error \
    --output "${destination}" \
    "${url}"
  local actual_sha256
  actual_sha256="$(sha256sum "${destination}" | awk '{ print $1 }')"
  if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
    echo "SHA-256 mismatch for ${url}." >&2
    echo "Expected ${expected_sha256}, got ${actual_sha256}." >&2
    exit 1
  fi
  chmod +x "${destination}"
}

appimage_tools="${temporary_root}/appimage-tools"
mkdir -p -- "${appimage_tools}"
linuxdeploy="${appimage_tools}/linuxdeploy-x86_64.AppImage"
gtk_plugin="${appimage_tools}/linuxdeploy-plugin-gtk.sh"
appimage_runtime="${appimage_tools}/runtime-x86_64"
download_verified \
  'https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage' \
  'c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d' \
  "${linuxdeploy}"
download_verified \
  'https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/7a3fbc31a9e5075073ff8790f26effbac5f84453/linuxdeploy-plugin-gtk.sh' \
  'b0f4cbc684a0103a9651f0955b635eaea0096b3a66c0f5a2c2aa337960375171' \
  "${gtk_plugin}"
download_verified \
  'https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64' \
  '2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d' \
  "${appimage_runtime}"

appdir="${temporary_root}/Zeta.AppDir"
appimage_desktop="${temporary_root}/io.github.linpeilie.zeta.desktop"
install -d \
  "${appdir}/usr/lib/zeta" \
  "${appdir}/usr/bin" \
  "${appdir}/usr/share/applications" \
  "${appdir}/usr/share/icons/hicolor/512x512/apps"
cp -a "${bundle_directory}/." "${appdir}/usr/lib/zeta/"
ln -s ../lib/zeta/zeta "${appdir}/usr/bin/zeta"
cat >"${appimage_desktop}" <<'EOF'
[Desktop Entry]
Name=Zeta
Comment=Desktop Agent IDE
Exec=zeta
Icon=io.github.linpeilie.zeta
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=io.github.linpeilie.zeta
EOF
install -m 0644 "${appimage_desktop}" "${appdir}/usr/share/applications/"
install -m 0644 \
  "${project_root}/linux/runner/resources/app_icon.png" \
  "${appdir}/usr/share/icons/hicolor/512x512/apps/io.github.linpeilie.zeta.png"

LDAI_OUTPUT="${appimage_package}" \
LDAI_RUNTIME_FILE="${appimage_runtime}" \
LINUXDEPLOY_OUTPUT_VERSION="${release_version}" \
DEPLOY_GTK_VERSION=3 \
ARCH=x86_64 \
  "${linuxdeploy}" \
  --appdir "${appdir}" \
  --executable "${appdir}/usr/lib/zeta/zeta" \
  --desktop-file "${appimage_desktop}" \
  --icon-file "${appdir}/usr/share/icons/hicolor/512x512/apps/io.github.linpeilie.zeta.png" \
  --plugin gtk \
  --output appimage
if [[ ! -x "${appimage_package}" ]]; then
  echo "linuxdeploy did not generate the AppImage." >&2
  exit 1
fi

appimage_extract="${temporary_root}/appimage-extract"
mkdir -p -- "${appimage_extract}"
(
  cd "${appimage_extract}"
  "${appimage_package}" --appimage-extract >/dev/null
)
if [[ ! -x "${appimage_extract}/squashfs-root/AppRun" ]] ||
  [[ ! -x "${appimage_extract}/squashfs-root/usr/lib/zeta/zeta" ]]; then
  echo "The generated AppImage is missing AppRun or the Zeta executable." >&2
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
write_checksum "${rpm_package}"
write_checksum "${appimage_package}"

asset_count="$(
  find "${dist_directory}" -maxdepth 1 -type f \
    -name "zeta-${release_version}-linux-x86_64*" |
    wc -l |
    tr -d ' '
)"
if [[ "${asset_count}" -ne 8 ]]; then
  echo "Expected 8 Linux assets, found ${asset_count}." >&2
  exit 1
fi

echo "Created Linux packages in ${dist_directory}"
