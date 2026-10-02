#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
: "${NOTARY_KEYCHAIN_PROFILE:?Set the existing notarytool Keychain profile name}"
: "${APPLE_SIGNING_IDENTITY:?Set the Developer ID Application identity}"
export LIGHTMARK_DIST_DIR="$project_root/dist/release"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_root/Resources/Info.plist")"
if [[ -n "${RELEASE_TAG:-}" && "$RELEASE_TAG" != "v$version" ]]; then
  print -u2 'Release tag does not match Info.plist version'; exit 1
fi
# Credentials are checked before the expensive build; passwords stay in Keychain.
xcrun notarytool history --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --output-format json > /dev/null
"$project_root/scripts/build-app.sh" release
# Fail before notarization if this machine cannot sign trusted native updates.
sparkle_public="$("$project_root/.build/artifacts/sparkle/Sparkle/bin/generate_keys" --account lightmark-updates -p)"
expected_public="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$project_root/Resources/Info.plist")"
[[ "$sparkle_public" == "$expected_public" ]] || { print -u2 'Sparkle signing key does not match Info.plist.'; exit 1; }
app_path="$LIGHTMARK_DIST_DIR/Lightmark.app"
codesign --verify --deep --strict --verbose=2 "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$LIGHTMARK_DIST_DIR/notarization.zip"
xcrun notarytool submit "$LIGHTMARK_DIST_DIR/notarization.zip" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait --output-format json > "$LIGHTMARK_DIST_DIR/notarization.json"
python3 - "$LIGHTMARK_DIST_DIR/notarization.json" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Apple did not accept notarization. Inspect dist/release/notarization.json and retrieve the submission log.')
PY
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$LIGHTMARK_DIST_DIR/Lightmark.zip"
"$project_root/scripts/create-dmg.sh" "$app_path" "$LIGHTMARK_DIST_DIR/Lightmark.dmg"
codesign --force --sign "$APPLE_SIGNING_IDENTITY" --timestamp "$LIGHTMARK_DIST_DIR/Lightmark.dmg"
xcrun notarytool submit "$LIGHTMARK_DIST_DIR/Lightmark.dmg" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait --output-format json > "$LIGHTMARK_DIST_DIR/dmg-notarization.json"
python3 - "$LIGHTMARK_DIST_DIR/dmg-notarization.json" <<'PYDMG'
import json,sys
if json.load(open(sys.argv[1])).get('status') != 'Accepted':
    raise SystemExit('Apple did not accept the disk image. Inspect dmg-notarization.json.')
PYDMG
xcrun stapler staple "$LIGHTMARK_DIST_DIR/Lightmark.dmg"
xcrun stapler validate "$LIGHTMARK_DIST_DIR/Lightmark.dmg"
codesign --verify --verbose=2 "$LIGHTMARK_DIST_DIR/Lightmark.dmg"
(cd "$LIGHTMARK_DIST_DIR" && shasum -a 256 Lightmark.dmg Lightmark.zip > SHA256SUMS.txt)
python3 - "$project_root/Resources/Info.plist" "$LIGHTMARK_DIST_DIR" <<'PY'
import json,sys,pathlib,hashlib,plistlib
plist_path,folder=sys.argv[1:]; info=plistlib.loads(pathlib.Path(plist_path).read_bytes()); root=pathlib.Path(folder); archive=root/'Lightmark.dmg'
(root/'release.json').write_text(json.dumps({'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'architecture':'arm64','minimumMacOS':info['LSMinimumSystemVersion'],'downloadURL':'https://trylightmark.com/downloads/Lightmark.dmg','size':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest()},indent=2)+'\n')
PY
python3 "$project_root/scripts/create-appcast.py" "$LIGHTMARK_DIST_DIR"
print "Signed, notarized and stapled release: $LIGHTMARK_DIST_DIR/Lightmark.dmg"
