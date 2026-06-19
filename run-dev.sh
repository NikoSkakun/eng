#!/usr/bin/env bash
# Build and launch eng on the Linux desktop in DEBUG (dev) mode, with hot reload.
#
# Ways to start it:
#   • Files → right-click → "Run as a Program"  (re-opens itself in a terminal)
#   • a terminal:  ./run-dev.sh
set -euo pipefail

# If we were launched without a terminal (e.g. the file manager's "Run as a
# Program"), re-open inside one — otherwise output is invisible, `flutter run`
# has no TTY to read hot-reload keys from, and the dev PATH isn't loaded. The
# inner `bash -lic` is a login+interactive shell, so your shell profile (and the
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

# Pause on failure so the message is readable when launched by double-click.
# A normal quit ('q', exit 0) or Ctrl-C (130) of `flutter run` is not an error.
# `|| true` and the final `exit` keep the script's real exit status intact.
trap 'status=$?
  if [[ $status -ne 0 && $status -ne 130 ]]; then
    echo; echo "✗ Failed (exit $status)."; read -rp "Press Enter to close… " || true
  fi
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

flutter pub get
echo "==> Launching eng (debug, hot reload — press 'r' to reload, 'q' to quit)…"
flutter run -d linux --debug
