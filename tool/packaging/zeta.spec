Name: zeta
Version: %{zeta_version}
Release: %{zeta_release}
Summary: Zeta desktop Agent IDE
License: GPL-3.0-only
URL: https://github.com/linpeilie/zeta
BuildArch: x86_64
Requires: gtk3
Requires: fontconfig
Requires: util-linux-libs
Requires: xz-libs

%description
Zeta provides a desktop shell for working with coding agents.

%prep

%build

%install
rm -rf "%{buildroot}"
mkdir -p "%{buildroot}/opt" "%{buildroot}/usr"
cp -a "%{zeta_source}/opt/zeta" "%{buildroot}/opt/"
cp -a "%{zeta_source}/usr/bin" "%{buildroot}/usr/"
cp -a "%{zeta_source}/usr/share" "%{buildroot}/usr/"

%files
/opt/zeta
/usr/bin/zeta
/usr/share/applications/io.github.linpeilie.zeta.desktop
/usr/share/icons/hicolor/512x512/apps/io.github.linpeilie.zeta.png

%changelog
