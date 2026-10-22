#!/usr/bin/env bash
# Builds DukeBoxarr for Linux and packages it as a .deb (Ubuntu 24.04+).
#
#   ./tool/build_linux.sh
#
# Needs: Flutter, and
#   sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
#     liblzma-dev libstdc++-12-dev libmpv-dev dpkg-dev
#
# Output: installer/Output/dukeboxarr_<version>_amd64.deb
# Installs to /opt/dukeboxarr with a menu entry and a `dukeboxarr` command.
# Installing a newer .deb upgrades in place (sudo apt install ./file.deb).
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' pubspec.yaml)
echo "DukeBoxarr $version"

flutter build linux --release

bundle=build/linux/x64/release/bundle
pkg=build/deb/dukeboxarr_${version}_amd64
rm -rf "$pkg"
mkdir -p "$pkg/DEBIAN" "$pkg/opt/dukeboxarr" "$pkg/usr/bin" \
  "$pkg/usr/share/applications" "$pkg/usr/share/icons/hicolor/256x256/apps"

cp -r "$bundle"/. "$pkg/opt/dukeboxarr/"
ln -s /opt/dukeboxarr/dukeboxarr "$pkg/usr/bin/dukeboxarr"
cp linux/packaging/dukeboxarr.desktop "$pkg/usr/share/applications/"
cp linux/packaging/dukeboxarr.png "$pkg/usr/share/icons/hicolor/256x256/apps/"

cat > "$pkg/DEBIAN/control" <<EOF
Package: dukeboxarr
Version: $version
Section: sound
Priority: optional
Architecture: amd64
Depends: libmpv2, libgtk-3-0t64 | libgtk-3-0
Installed-Size: $(du -sk "$pkg" | cut -f1)
Maintainer: Cd084 <34046207+Cd084@users.noreply.github.com>
Homepage: https://github.com/Cd084/dukeboxarr
Description: Touch-screen jukebox for a Plex music library
 Browse album title strips, tap a song or punch in its number to queue it.
 Random play or an AI DJ (Ollama) keeps the music going when the queue is
 empty. Plays locally or on a Plex player.
EOF

# Refresh the menu and icon caches after install/removal.
cat > "$pkg/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true
EOF
cp "$pkg/DEBIAN/postinst" "$pkg/DEBIAN/postrm"
chmod 755 "$pkg/DEBIAN/postinst" "$pkg/DEBIAN/postrm"

mkdir -p installer/Output
dpkg-deb --build --root-owner-group "$pkg" "installer/Output/dukeboxarr_${version}_amd64.deb" >/dev/null
echo "Package: installer/Output/dukeboxarr_${version}_amd64.deb"
