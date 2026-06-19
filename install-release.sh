#!/usr/bin/env bash
# Build a RELEASE .deb of eng and install it system-wide (requires sudo).
#
# Ways to start it:
#   • Files → right-click → "Run as a Program"  (re-opens itself in a terminal)
#   • a terminal:  ./install-release.sh
set -euo pipefail

# If we were launched without a terminal (e.g. the file manager's "Run as a
# Program"), re-open inside one — otherwise output is invisible, the sudo
# password prompt has nowhere to go, and the dev PATH isn't loaded. The inner
# `bash -lic` is a login+interactive shell, so your shell profile (and the
# flutter it puts on PATH) is sourced just as in a normal terminal.
if [[ -z "${ENG_REEXEC:-}" && ! -t 1 ]]; then
  self="$(readlink -f "$0")"
  run='ENG_REEXEC=1 exec "$0"'   # mark, then re-run this script in the new shell
  for term in gnome-terminal kgx tilix konsole xfce4-terminal x-terminal-emulator xterm; do
    command -v "$term" >/dev/null 2>&1 || continue
    case "$term" in
      gnome-terminal|kgx|tilix) exec "$term" -- bash -lic "$run" "$self" ;;
      xfce4-terminal)           exec "$term" -x bash -lic "$run" "$self" ;;
      *)                        exec "$term" -e bash -lic "$run" "$self" ;;
    esac
  done
  echo "No terminal emulator found; running without one." >&2
fi

# Operate from the repo root, however we were launched.
cd "$(dirname "$(readlink -f "$0")")"

# Keep the terminal open at the end so the result is visible on double-click.
# `|| true` and the final `exit` keep the script's real exit status intact.
trap 'status=$?
  echo
  [[ $status -eq 0 ]] || echo "✗ Failed (exit $status)."
  read -rp "Press Enter to close… " || true
  exit $status' EXIT

# Pick up a locally-installed Flutter/dev toolchain if one is configured. This
# is a hand-maintained env file not written for `set -eu` (it appends to a
# possibly-unset LD_LIBRARY_PATH), so source it with those guards relaxed.
if [[ -f "$HOME/devprefix/env.sh" ]]; then
  set +eu; source "$HOME/devprefix/env.sh"; set -eu
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "✗ 'flutter' is not on PATH."
  echo "  Add it to ~/.profile (or \$HOME/devprefix/env.sh) so the launcher can find it."
  exit 127
fi

# pdfrx bundles PDFium through Dart native assets — required; harmless to re-run.
flutter config --enable-native-assets

# Version (without the +build suffix) taken straight from pubspec.yaml.
version="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' pubspec.yaml)"
[[ -n "$version" ]] || { echo "Could not read version from pubspec.yaml." >&2; exit 1; }

echo "==> Building eng $version (release)…"
flutter build linux --release

echo "==> Packaging .deb…"
packaging/build_deb.sh "$version"

deb="build/dist/eng_${version}_amd64.deb"
[[ -f "$deb" ]] || { echo "Expected $deb but it was not produced." >&2; exit 1; }

echo "==> Installing $deb (sudo)…"
# dpkg -i installs/overwrites even at the same version (handy when re-running
# without bumping the version); apt then fixes up any missing dependencies.
if ! sudo dpkg -i "$PWD/$deb"; then
  echo "==> Resolving dependencies…"
  sudo apt-get -f install -y
fi

echo "✓ Installed eng $version — launch it from your app menu or run: eng"
