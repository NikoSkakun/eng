#!/usr/bin/env bash
# Build a Debian package for eng from the Flutter Linux release bundle.
# Usage: packaging/build_deb.sh [version]
# Assumes `flutter build linux --release` has already run (or run with BUILD=1).
set -euo pipefail

VERSION="${1:-1.0.3}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
OUT="$ROOT/build/dist"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

if [[ "${BUILD:-0}" == "1" ]]; then
  [[ -f "$HOME/devprefix/env.sh" ]] && source "$HOME/devprefix/env.sh"
  flutter build linux --release
fi

[[ -d "$BUNDLE" ]] || { echo "No release bundle at $BUNDLE — run flutter build linux --release first." >&2; exit 1; }

# Payload: app under /opt/eng, launcher symlink, desktop entry, icon.
install -d "$STAGE/opt/eng" "$STAGE/usr/bin" \
  "$STAGE/usr/share/applications" "$STAGE/usr/share/icons/hicolor/256x256/apps"
cp -a "$BUNDLE/." "$STAGE/opt/eng/"
ln -s /opt/eng/eng "$STAGE/usr/bin/eng"

cat > "$STAGE/usr/share/applications/eng.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=eng
Comment=Read foreign-language PDFs with inline translations
Exec=/opt/eng/eng %f
Icon=eng
Terminal=false
Categories=Education;Office;Viewer;
MimeType=application/pdf;
DESKTOP

# Icon: reuse a prior one if present, else synthesize a placeholder.
ICON_DST="$STAGE/usr/share/icons/hicolor/256x256/apps/eng.png"
if [[ -f "$ROOT/packaging/eng.png" ]]; then
  cp "$ROOT/packaging/eng.png" "$ICON_DST"
elif command -v convert >/dev/null 2>&1; then
  convert -size 256x256 xc:'#2d6cdf' -gravity center -pointsize 120 \
    -fill white -annotate 0 'eng' "$ICON_DST"
fi

INSTALLED_KB=$(du -sk "$STAGE" | cut -f1)
install -d "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: eng
Version: $VERSION
Section: education
Priority: optional
Architecture: amd64
Installed-Size: $INSTALLED_KB
Depends: libgtk-3-0t64 | libgtk-3-0, libstdc++6, libc6, zlib1g
Maintainer: Mykola Skakun <m.skakun@kvit.space>
Description: eng — foreign-language PDF reader
 Read foreign-language PDFs with inline translations and a shared
 auto-highlighting dictionary. Select a word or phrase to add a
 translation; it is highlighted everywhere it appears.
CONTROL

mkdir -p "$OUT"
DEB="$OUT/eng_${VERSION}_amd64.deb"
dpkg-deb --build --root-owner-group "$STAGE" "$DEB"
echo "Built $DEB"
