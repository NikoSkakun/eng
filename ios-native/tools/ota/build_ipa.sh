#!/bin/bash
# build_ipa.sh — hand-rolled device Release .ipa for eng, WITHOUT Xcode reading a
# project. Mirrors namapi's tools/testflight/build_ipa.sh but for a SwiftUI app
# (no storyboards, no Metal): compile every Swift file against the iphoneos SDK in
# Release, compile the asset catalog for the app icon, write the Info.plist,
# ad-hoc code-sign, and package Payload/*.app -> .ipa.
#
#   Env in:
#     BUILD_NUMBER       CFBundleVersion (default: UTC YYYYMMDDHHmmSS)
#     MARKETING_VERSION  CFBundleShortVersionString (default 1.0)
#     DT                 deployment target (default 17.0 — ContentUnavailableView etc.)
#     SIGN_IDENTITY      codesign identity (name or SHA-1). Empty -> UNSIGNED (.app only)
#     PROFILE            path to the ad-hoc .mobileprovision. Empty -> unsigned
#   Out: build/ota/Eng.ipa (signed); build/ota/Eng.app (always)
set -euo pipefail
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

SDK_VER=$(xcrun --sdk iphoneos --show-sdk-version)
DT=${DT:-17.0}
BUILD_NUMBER=${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}
MARKETING_VERSION=${MARKETING_VERSION:-1.0}
BUNDLE_ID=com.coloristique.eng
OUT=build/ota
APP="$OUT/Eng.app"
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)

rm -rf "$APP" "$OUT/Payload" "$OUT/Eng.ipa"
mkdir -p "$APP"

# ── 1. Swift -> arm64 device Mach-O (Release, @main SwiftUI entry) ──────────────
SOURCES=$(find Eng -name '*.swift' | sort)
echo "[build_ipa] swiftc $(echo "$SOURCES" | wc -l | tr -d ' ') files -> $APP (iOS $DT device, Release, build $BUILD_NUMBER)"
# shellcheck disable=SC2086
xcrun -sdk iphoneos swiftc -O -swift-version 5 \
  -target "arm64-apple-ios${DT}" \
  -sdk "$SDK_PATH" \
  $SOURCES \
  -lsqlite3 \
  -o "$APP/Eng"

# ── 2. Asset catalog (app icon) -> Assets.car + partial Info.plist ─────────────
echo "[build_ipa] assets"
xcrun actool --compile "$APP" --platform iphoneos \
  --minimum-deployment-target "$DT" \
  --app-icon AppIcon --include-all-app-icons \
  --output-partial-info-plist "$OUT/assets-info.plist" \
  Eng/Assets.xcassets > /dev/null

# ── 3. Info.plist ─────────────────────────────────────────────────────────────
cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Eng</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>eng</string>
  <key>CFBundleDisplayName</key><string>eng</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>${DT}</string>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
  <key>DTPlatformName</key><string>iphoneos</string>
  <key>DTSDKName</key><string>iphoneos${SDK_VER}</string>
  <key>UIRequiredDeviceCapabilities</key><array><string>arm64</string></array>
  <key>UILaunchScreen</key><dict/>
  <key>UIApplicationSupportsIndirectInputEvents</key><true/>
  <key>UISupportedInterfaceOrientations</key>
  <array><string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
  <key>ITSAppUsesNonExemptEncryption</key><false/>
  <key>UIFileSharingEnabled</key><true/>
  <key>LSSupportsOpeningDocumentsInPlace</key><true/>
</dict></plist>
PLIST
# Merge the actool partial (CFBundleIcons / primary-icon keys) into the Info.plist.
if [ -f "$OUT/assets-info.plist" ]; then
  /usr/libexec/PlistBuddy -c "Merge $OUT/assets-info.plist" "$APP/Info.plist" 2>/dev/null || true
fi
plutil -convert binary1 "$APP/Info.plist"

# ── 4. Code signing ───────────────────────────────────────────────────────────
if [ -z "${SIGN_IDENTITY:-}" ] || [ -z "${PROFILE:-}" ]; then
  echo "[build_ipa] SIGN_IDENTITY/PROFILE not set -> UNSIGNED build (no .ipa produced)"
  echo "[build_ipa] built $(du -sh "$APP" | cut -f1) $(file "$APP/Eng" | sed 's/.*: //')"
  exit 0
fi

echo "[build_ipa] embedding profile + signing with: $SIGN_IDENTITY"
cp "$PROFILE" "$APP/embedded.mobileprovision"
# Entitlements come from the profile — but this profile uses the team's WILDCARD
# App ID, so its application-identifier is "TEAM.*". A code signature carrying a
# wildcard app-id is refused on-device ("integrity could not be verified"): the
# signed entitlements must name the CONCRETE bundle id (the wildcard profile still
# authorizes it). Rewrite the wildcard entries to TEAM.<bundle id>.
security cms -D -i "$PROFILE" > "$OUT/profile.plist"
/usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$OUT/profile.plist" > "$OUT/entitlements.plist"
TEAM_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.team-identifier" "$OUT/profile.plist")
APPID="${TEAM_ID}.${BUNDLE_ID}"
/usr/libexec/PlistBuddy -c "Set :application-identifier $APPID" "$OUT/entitlements.plist"
# keychain-access-groups: rewrite any wildcard (TEAM.*) group to the concrete id,
# leaving com.apple.token and any others intact.
i=0
while grp=$(/usr/libexec/PlistBuddy -c "Print :keychain-access-groups:$i" "$OUT/entitlements.plist" 2>/dev/null); do
  case "$grp" in *'*') /usr/libexec/PlistBuddy -c "Set :keychain-access-groups:$i $APPID" "$OUT/entitlements.plist" ;; esac
  i=$((i+1))
done
echo "[build_ipa] app-id entitlement: $APPID"
codesign --force --sign "$SIGN_IDENTITY" \
  --entitlements "$OUT/entitlements.plist" \
  --timestamp --generate-entitlement-der \
  "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# ── 5. Package Payload/*.app -> .ipa ──────────────────────────────────────────
rm -rf "$OUT/Payload"; mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/"
( cd "$OUT" && /usr/bin/zip -qry Eng.ipa Payload )
rm -rf "$OUT/Payload"
echo "[build_ipa] wrote $OUT/Eng.ipa ($(du -h "$OUT/Eng.ipa" | cut -f1)), build $BUILD_NUMBER"
