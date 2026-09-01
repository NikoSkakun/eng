#!/bin/bash
# deploy-ota.sh — one-command OTA install of eng from this Mac, over Tailscale.
#
# Mirrors namapi's tools/remote-deploy/deploy-ota-local.sh (the Xcode-15 / no-Homebrew
# path) but for eng: mint an AD-HOC profile against the team's wildcard App ID
# (mint_ota_profile.py), import the distribution identity (namapi's setup_signing.sh),
# build a signed IPA (tools/ota/build_ipa.sh — swiftc), assemble an itms-services
# install site, serve it on the private tailnet with `tailscale serve`, and print
# the install URL. On a REGISTERED iPhone (Tailscale VPN on) open it in Safari.
#
#   tools/ota/deploy-ota.sh                 # mint + build + serve
#   tools/ota/deploy-ota.sh --skip-build    # re-serve the existing IPA
#   tools/ota/deploy-ota.sh --status | --stop
#
# Reuses namapi's ASC key + distribution .p12 via NAMAPI_TOOLS (default
# /Users/niko/dev/namapi/tools). NB: this takes over this Mac's `tailscale serve`.
set -euo pipefail
cd "$(dirname "$0")/../.."

NAMAPI_TOOLS=${NAMAPI_TOOLS:-/Users/niko/dev/namapi/tools}
export NAMAPI_TOOLS
BUNDLE_ID=com.coloristique.eng
APP_NAME=eng
OUT=build/ota
SITE="$OUT/site"
IPA="$OUT/Eng.ipa"
PROFILE="$OUT/Eng_AdHoc.mobileprovision"
PORT=8477
HTTP_PID=/tmp/eng-ota-http.pid

# tailscale CLI (Homebrew, or the GUI app bundle).
TS=${TS:-$(command -v tailscale || true)}
for C in /opt/homebrew/bin/tailscale /usr/local/bin/tailscale \
         /Applications/Tailscale.app/Contents/MacOS/Tailscale; do
  [ -n "$TS" ] && break; [ -x "$C" ] && TS=$C
done
ts() { "$TS" "$@"; }

stop_all() {
  [ -f "$HTTP_PID" ] && kill "$(cat "$HTTP_PID")" 2>/dev/null || true; rm -f "$HTTP_PID"
  [ -n "$TS" ] && ts serve reset >/dev/null 2>&1 || true
}

case "${1:-}" in
  --stop)   stop_all; echo "[ota] stopped"; exit 0 ;;
  --status) [ -n "$TS" ] && ts serve status 2>/dev/null || true; exit 0 ;;
esac

[ -n "$TS" ] || { echo "[ota] no tailscale CLI found" >&2; exit 1; }
ts status >/dev/null 2>&1 || { echo "[ota] tailscale is not up — open the Tailscale app and sign in" >&2; exit 1; }

# ── 1. Mint / refresh the ad-hoc profile ────────────────────────────────────────
# Device scope: OTA_MINT_ARGS forwards flags to mint_ota_profile.py, e.g.
#   OTA_MINT_ARGS="--udid <UDID>"  (one device) or "--all-devices" (every phone).
# The target device MUST be in the profile or the install fails with
# "integrity could not be verified".
if [ "${1:-}" != "--skip-build" ]; then
  echo "[ota] minting ad-hoc profile…"; python3 tools/ota/mint_ota_profile.py ${OTA_MINT_ARGS:-} >&2
fi
[ -f "$PROFILE" ] || { echo "[ota] no ad-hoc profile at $PROFILE — run without --skip-build" >&2; exit 1; }

# ── 2. Import the signing identity (reuses namapi's dedicated keychain setup) ────
set -a; . "$NAMAPI_TOOLS/testflight/secrets.env"; set +a
export PROFILE_PATH="$PWD/$PROFILE"
eval "$(bash "$NAMAPI_TOOLS/testflight/setup_signing.sh")"   # sets SIGN_IDENTITY (+ PROFILE)
PROFILE="$PROFILE_PATH"
[ -n "${SIGN_IDENTITY:-}" ] || { echo "[ota] no signing identity after setup_signing.sh" >&2; exit 1; }

# ── 3. Build + ad-hoc-sign the IPA (swiftc) ─────────────────────────────────────
if [ "${1:-}" != "--skip-build" ]; then
  echo "[ota] building IPA…"
  SIGN_IDENTITY="$SIGN_IDENTITY" PROFILE="$PROFILE" tools/ota/build_ipa.sh >&2
fi
[ -f "$IPA" ] || { echo "[ota] no IPA at $IPA" >&2; exit 1; }

# ── 4. Assemble the OTA site + loopback static server ───────────────────────────
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "?")
BUILD_NUMBER=$(/usr/bin/unzip -p "$IPA" 'Payload/Eng.app/Info.plist' | plutil -extract CFBundleVersion raw - 2>/dev/null || echo "?")
MARKETING=$(/usr/bin/unzip -p "$IPA" 'Payload/Eng.app/Info.plist' | plutil -extract CFBundleShortVersionString raw - 2>/dev/null || echo 1.0)
CHANGELOG_HTML=$(git log --no-merges --format=%s -6 2>/dev/null | python3 -c '
import html, sys
for l in [x.strip() for x in sys.stdin if x.strip()][:6]:
    if len(l) > 84: l = l[:83].rstrip(" ,;:—-") + "…"
    print("<li style=\"margin:.28em 0\">" + html.escape(l) + "</li>")
' || true)

# Build-stamped, UNIQUE filenames every deploy + a no-cache server, so iOS can
# never re-install a stale IPA/manifest from a previous (failed) attempt — the
# #1 cause of a wedged "eng" placeholder that keeps failing after a fix.
STAMP="$BUILD_NUMBER"
IPA_NAME="Eng-$STAMP.ipa"
MANIFEST_NAME="manifest-$STAMP.plist"
rm -rf "$SITE"; mkdir -p "$SITE"; cp "$IPA" "$SITE/$IPA_NAME"
stop_all
python3 tools/ota/nocache_server.py "$PORT" "$SITE" >/dev/null 2>&1 &
echo $! > "$HTTP_PID"
for _ in $(seq 1 20); do curl -s -m 2 -o /dev/null "http://127.0.0.1:$PORT/$IPA_NAME" && break; sleep 0.5; done

# ── 5. Publish over the private tailnet (valid ts.net cert) ─────────────────────
HOST=$(ts status --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
BASE="https://$HOST"
ts serve reset >/dev/null 2>&1 || true
ts serve --bg "http://127.0.0.1:$PORT" >/dev/null   # prompts once to enable tailnet HTTPS certs

# ── 6. itms-services manifest + one-tap install page ───────────────────────────
cat > "$SITE/$MANIFEST_NAME" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>items</key><array><dict>
    <key>assets</key><array><dict>
      <key>kind</key><string>software-package</string>
      <key>url</key><string>$BASE/$IPA_NAME</string>
    </dict></array>
    <key>metadata</key><dict>
      <key>bundle-identifier</key><string>$BUNDLE_ID</string>
      <key>bundle-version</key><string>$MARKETING</string>
      <key>kind</key><string>software</string>
      <key>title</key><string>$APP_NAME</string>
    </dict>
  </dict></array>
</dict></plist>
PLIST
cat > "$SITE/index.html" <<HTML
<!doctype html><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>eng OTA</title>
<body style="font-family:-apple-system;display:flex;flex-direction:column;align-items:center;
             justify-content:center;min-height:90vh;gap:14px;background:#0b0e14;color:#e6e6e6">
  <h1 style="margin:0">eng</h1>
  <p style="margin:0;opacity:.7">$COMMIT · build $BUILD_NUMBER · ad-hoc · tailscale</p>
  <a href="itms-services://?action=download-manifest&amp;url=$BASE/$MANIFEST_NAME"
     style="background:#ff8f00;color:#fff;text-decoration:none;font-size:22px;
            padding:16px 44px;border-radius:14px">Install</a>
  <div style="max-width:30em;width:88%;background:#131822;border:1px solid #232b3a;
              border-radius:12px;padding:12px 18px">
    <div style="font-size:12px;letter-spacing:.08em;text-transform:uppercase;opacity:.45;
                margin-bottom:6px">What's new</div>
    <ul style="margin:0;padding-left:1.1em;font-size:14px;line-height:1.35;opacity:.9">
$CHANGELOG_HTML
    </ul>
  </div>
  <p style="opacity:.5;font-size:13px;max-width:28em;text-align:center">Tap Install, confirm, then wait
  on the Home Screen. First install only: Settings › General › VPN &amp; Device Management › trust the developer.</p>
</body>
HTML

# Keep the Mac awake while it is serving (the phone arrives minutes after the URL is printed).
if [ -f "$HTTP_PID" ] && command -v caffeinate >/dev/null; then
  caffeinate -dimsu -w "$(cat "$HTTP_PID")" >/dev/null 2>&1 &
fi

echo
echo "[ota] ✅ serving via tailscale — on the REGISTERED iPhone (Tailscale VPN ON) open in Safari:"
echo "      $BASE/"
echo "[ota] commit $COMMIT · build $BUILD_NUMBER · IPA $(du -h "$IPA" | cut -f1)"
echo "[ota] stop with: tools/ota/deploy-ota.sh --stop"
