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
(cd "$LIGHTMARK_DIST_DIR" && shasum -a 256 Lightmark.zip > SHA256SUMS.txt)
python3 - "$project_root/Resources/Info.plist" "$LIGHTMARK_DIST_DIR" <<'PY'
import json,sys,pathlib,hashlib,plistlib
plist_path,folder=sys.argv[1:]; info=plistlib.loads(pathlib.Path(plist_path).read_bytes()); root=pathlib.Path(folder); archive=root/'Lightmark.zip'
(root/'release.json').write_text(json.dumps({'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'architecture':'arm64','minimumMacOS':info['LSMinimumSystemVersion'],'downloadURL':'https://trylightmark.com/downloads/Lightmark.zip','size':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest()},indent=2)+'\n')
PY
print "Signed, notarized and stapled release: $LIGHTMARK_DIST_DIR/Lightmark.zip"
