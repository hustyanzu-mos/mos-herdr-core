#!/usr/bin/env bash
# Build a local MOS plugin .deb for Herdr Core.
#
#   ./build.sh              # version from page/plugin.config.js (0.1.0)
#   ./build.sh 0.1.1        # explicit version
#   SKIP_PAGE=1 ./build.sh  # reuse page/dist
#
# The GitHub Actions workflow builds the same package with dpkg-deb.
# This script falls back to ar+tar when dpkg-deb is unavailable.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

VERSION="${1:-${VERSION:-}}"
if [ -z "$VERSION" ]; then
  VERSION="$(node -e "import('./page/plugin.config.js').then(m => console.log(m.default.version))" 2>/dev/null || echo 0.1.0)"
fi

PKG_NAME="herdr-core-${VERSION}-1+mos-plugin"
PKG_DIR="$ROOT/build/${PKG_NAME}_all"
DEB_FILE="$ROOT/build/${PKG_NAME}_all.deb"
PAGE_DIST="$ROOT/page/dist/herdr-core"

echo "==> Herdr Core MOS plugin ${VERSION}"

if [ "${SKIP_PAGE:-0}" != "1" ]; then
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm is required to build the plugin page" >&2
    exit 1
  fi
  if [ ! -d "$ROOT/page/node_modules" ]; then
    echo "==> npm install"
    ( cd "$ROOT/page" && npm install )
  fi
  echo "==> building plugin page"
  ( cd "$ROOT/page" && PLUGIN_VERSION="$VERSION" npm run build )
fi

if [ ! -f "$PAGE_DIST/remoteEntry.js" ]; then
  echo "page build output missing: $PAGE_DIST/remoteEntry.js" >&2
  exit 1
fi

rm -rf "$ROOT/build"
mkdir -p \
  "$PKG_DIR/DEBIAN" \
  "$PKG_DIR/usr/bin/plugins" \
  "$PKG_DIR/usr/share/herdr-core-plugin" \
  "$PKG_DIR/var/www/mos-plugins/herdr-core"

install -m 0755 "$ROOT/herdr-core-backend" "$PKG_DIR/usr/bin/plugins/herdr-core"
install -m 0755 "$ROOT/herdr-core-wrapper" "$PKG_DIR/usr/bin/hc"
ln -s hc "$PKG_DIR/usr/bin/herdr-core"

install -m 0755 "$ROOT/herdr-core-backend" "$PKG_DIR/usr/share/herdr-core-plugin/herdr-core-backend"
install -m 0755 "$ROOT/herdr-core-wrapper" "$PKG_DIR/usr/share/herdr-core-plugin/herdr-core-wrapper"
install -m 0755 "$ROOT/functions" "$PKG_DIR/usr/share/herdr-core-plugin/functions"
install -m 0644 "$ROOT/settings.json" "$PKG_DIR/usr/share/herdr-core-plugin/settings.json"

cp -a "$PAGE_DIST/." "$PKG_DIR/var/www/mos-plugins/herdr-core/"
install -m 0644 "$ROOT/images/herdr-core.png" "$PKG_DIR/var/www/mos-plugins/herdr-core/icon.png"

cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: herdr-core-plugin
Version: ${VERSION}-1+mos-plugin
Architecture: all
Maintainer: hustyanzu
Section: utils
Priority: optional
Description: Herdr Core plugin for MOS
 Headless terminal runtime for coding agents (Herdr Core / hc).
EOF

cat > "$PKG_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e
PLG=/boot/optional/plugins/herdr-core
SHARE=/usr/share/herdr-core-plugin
mkdir -p "$PLG/bin" "$PLG/config" "$PLG/state"
chmod 0755 /usr/bin/plugins/herdr-core /usr/bin/hc 2>/dev/null || true
if [ ! -e /usr/bin/herdr-core ]; then ln -sf hc /usr/bin/herdr-core; fi
for f in herdr-core-backend herdr-core-wrapper functions; do
  cp -f "$SHARE/$f" "$PLG/$f"
done
chmod 0755 "$PLG/herdr-core-backend" "$PLG/herdr-core-wrapper" "$PLG/functions" 2>/dev/null || true
if [ ! -f "$PLG/settings.json" ]; then
  cp -f "$SHARE/settings.json" "$PLG/settings.json"
fi
if [ -x "$PLG/bin/herdr-core" ]; then
  install -m 0755 "$PLG/bin/herdr-core" /usr/bin/herdr-core.real
  if [ "$(jq -r '.auto_start // true' "$PLG/settings.json" 2>/dev/null)" = "true" ]; then
    /usr/bin/plugins/herdr-core start >/dev/null 2>&1 || true
  fi
fi
exit 0
EOF
chmod 0755 "$PKG_DIR/DEBIAN/postinst"

cat > "$PKG_DIR/DEBIAN/postrm" <<'EOF'
#!/bin/bash
rm -f /usr/bin/herdr-core.real
exit 0
EOF
chmod 0755 "$PKG_DIR/DEBIAN/postrm"

cat > "$PKG_DIR/DEBIAN/prerm" <<'EOF'
#!/bin/bash
if [ -x /usr/bin/plugins/herdr-core ]; then
  /usr/bin/plugins/herdr-core stop >/dev/null 2>&1 || true
fi
exit 0
EOF
chmod 0755 "$PKG_DIR/DEBIAN/prerm"

echo "==> building ${DEB_FILE}"
if command -v dpkg-deb >/dev/null 2>&1; then
  dpkg-deb --build --root-owner-group "$PKG_DIR" "$DEB_FILE"
else
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  printf '2.0\n' > "$WORK/debian-binary"
  ( cd "$PKG_DIR/DEBIAN" && tar --owner=0 --group=0 --numeric-owner -czf "$WORK/control.tar.gz" . )
  ( cd "$PKG_DIR" && tar --owner=0 --group=0 --numeric-owner --exclude=./DEBIAN -czf "$WORK/data.tar.gz" . )
  ( cd "$WORK" && ar rcs "$DEB_FILE" debian-binary control.tar.gz data.tar.gz )
fi

md5sum "$DEB_FILE" | awk '{print $1}' > "$DEB_FILE.md5"

echo
echo "Package: $DEB_FILE"
echo "MD5:     $(cat "$DEB_FILE.md5")"
echo
echo "Install on MOS:  dpkg -i $(basename "$DEB_FILE")"
echo "Then open Plugins -> Herdr Core and click Install."