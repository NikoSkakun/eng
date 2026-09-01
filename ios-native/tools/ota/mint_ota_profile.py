#!/usr/bin/env python3
"""Mint an AD-HOC provisioning profile for OTA installs of eng.

Adapted from namapi's tools/remote-deploy/mint_ota_profile.py. Differences:
  * signs eng, whose bundle id `com.coloristique.eng` is NOT separately
    registered — it uses the team's existing **wildcard App ID** (identifier
    `*`), so nothing new is registered on the account;
  * defaults the device scope to the owner's iPhone only (least exposure);
  * reuses namapi's ASC API key + JWT/api helpers + the keychain distribution
    identity (all on this machine) via NAMAPI_TOOLS.

  python3 tools/ota/mint_ota_profile.py                 # owner's iPhone only
  python3 tools/ota/mint_ota_profile.py --udid <UDID>   # a specific device (repeatable)
  python3 tools/ota/mint_ota_profile.py --all-devices   # every enabled iOS phone on the team
Out: build/ota/Eng_AdHoc.mobileprovision (+ prints SIGN_IDENTITY / PROFILE for build_ipa.sh)
"""
import argparse, base64, hashlib, os, re, subprocess, sys, urllib.parse

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
NAMAPI_TOOLS = os.environ.get("NAMAPI_TOOLS", "/Users/niko/dev/namapi/tools")
sys.path.insert(0, os.path.join(NAMAPI_TOOLS, "testflight"))
import mint_signing as m  # noqa: E402  (namapi's JWT/api helpers)

BUNDLE_ID = os.environ.get("OTA_BUNDLE_ID", "com.coloristique.eng")  # explicit App ID (ad-hoc needs one)
PROFILE_NAME = "Eng OTA AdHoc"
OUT_DIR = os.path.join(REPO, "build", "ota")
OUT_PROFILE = os.path.join(OUT_DIR, "Eng_AdHoc.mobileprovision")
# "Nikolay Skakun's iPhone" — the owner's registered device.
OWNER_UDID = "b12499679ce4f60ad0a68e72da3e594687528ca3"


def load_secrets():
    env = {}
    with open(os.path.join(NAMAPI_TOOLS, "testflight", "secrets.env")) as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip()
    return env


def die(msg, obj=None):
    print(f"[mint-ota] ERROR: {msg}", file=sys.stderr)
    if obj is not None:
        import json
        print(json.dumps(obj, indent=1)[:1500], file=sys.stderr)
    sys.exit(1)


def keychain_cert_sha1():
    out = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        if "Distribution" in line:
            mo = re.search(r"\)\s+([0-9A-Fa-f]{40})\s+", line)
            if mo:
                return mo.group(1).lower(), (line.split('"')[1] if '"' in line else None)
    die("no 'Apple Distribution' identity in the login keychain — import dist.p12 first")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--udid", action="append", help="restrict to these device UDID(s); repeatable")
    ap.add_argument("--all-devices", action="store_true", help="include every enabled iOS phone (default: owner only)")
    a = ap.parse_args()

    s = load_secrets()
    jwt = m.make_jwt(os.path.expanduser(s["ASC_KEY_P8"]), s["ASC_KEY_ID"], s["ASC_ISSUER_ID"])

    # 1. Which team cert matches the private key we hold in the keychain?
    want_sha1, ident_name = keychain_cert_sha1()
    st, certs = m.api(jwt, "GET", "/v1/certificates?limit=200")
    if st != 200:
        die(f"list certificates failed (HTTP {st})", certs)
    cert_id = None
    for c in certs.get("data", []):
        content = c["attributes"].get("certificateContent")
        if content and hashlib.sha1(base64.b64decode(content)).hexdigest() == want_sha1:
            cert_id = c["id"]; break
    if not cert_id:
        die(f"keychain distribution cert (sha1 {want_sha1}) is not on the team")
    print(f"[mint-ota] signing identity: {ident_name}")

    # 2. Bundle id — an EXPLICIT App ID. Ad-hoc (and App Store) distribution
    #    require an explicit App ID: wildcard App IDs are development-only, and a
    #    device refuses to install an ad-hoc build signed against a wildcard
    #    ("integrity could not be verified"). Register it on first run.
    st, bids = m.api(jwt, "GET",
                     "/v1/bundleIds?filter[identifier]=" + urllib.parse.quote(BUNDLE_ID) + "&limit=200")
    match = next((b for b in bids.get("data", []) if b["attributes"].get("identifier") == BUNDLE_ID), None)
    if match:
        bid = match["id"]
        print(f"[mint-ota] using existing App ID {BUNDLE_ID}")
    else:
        print(f"[mint-ota] registering explicit App ID {BUNDLE_ID}…")
        body = {"data": {"type": "bundleIds",
                         "attributes": {"identifier": BUNDLE_ID, "name": "eng", "platform": "IOS"}}}
        st, created = m.api(jwt, "POST", "/v1/bundleIds", body)
        if st not in (200, 201):
            die(f"could not register bundle id {BUNDLE_ID} (HTTP {st})", created)
        bid = created["data"]["id"]
        print(f"[mint-ota] registered {BUNDLE_ID} (id={bid})")

    # 3. Devices.
    st, devs = m.api(jwt, "GET", "/v1/devices?limit=200")
    if a.udid:
        want = {u.lower() for u in a.udid}
    elif a.all_devices:
        want = None
    else:
        want = {OWNER_UDID.lower()}
    picked = []
    for d in devs.get("data", []):
        at = d["attributes"]
        if at.get("status") != "ENABLED" or at.get("platform") != "IOS":
            continue
        udid = (at.get("udid") or "").lower()
        if want is None:
            if at.get("deviceClass") == "IPHONE":
                picked.append(d)
        elif udid in want:
            picked.append(d)
    if not picked:
        die("no matching enabled iOS devices found (is the target iPhone registered?)")
    print(f"[mint-ota] {len(picked)} device(s) in the profile:")
    for d in picked:
        print(f"           - {d['attributes'].get('name')!r}  {d['attributes'].get('udid')}")
    device_ids = [d["id"] for d in picked]

    # 4. Create the ad-hoc profile (delete a stale same-named one first).
    st, existing = m.api(jwt, "GET", "/v1/profiles?filter[name]=" + urllib.parse.quote(PROFILE_NAME))
    for p in existing.get("data", []):
        m.api(jwt, "DELETE", f"/v1/profiles/{p['id']}")
    body = {"data": {"type": "profiles",
            "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_ADHOC"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bid}},
                "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
                "devices": {"data": [{"type": "devices", "id": i} for i in device_ids]}}}}
    st, prof = m.api(jwt, "POST", "/v1/profiles", body)
    if st not in (200, 201):
        die(f"ad-hoc profile creation failed (HTTP {st})", prof)

    os.makedirs(OUT_DIR, exist_ok=True)
    open(OUT_PROFILE, "wb").write(base64.b64decode(prof["data"]["attributes"]["profileContent"]))
    print(f"[mint-ota] ✅ wrote {OUT_PROFILE}")


if __name__ == "__main__":
    main()
