#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
app_path="${1:?Pass the host app bundle}"
build_mode="${2:-release}"
extension="$app_path/Contents/PlugIns/LightmarkQuickLook.appex"
mkdir -p "$extension/Contents/MacOS" "$extension/Contents/Resources"
cp "$project_root/Resources/QuickLook/Info.plist" "$extension/Contents/Info.plist"
python3 - "$app_path/Contents/Info.plist" "$extension/Contents/Info.plist" <<'PY'
import pathlib,plistlib,sys
host=plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
p=pathlib.Path(sys.argv[2]); info=plistlib.loads(p.read_bytes())
for key in ['CFBundleShortVersionString','CFBundleVersion','LSMinimumSystemVersion']:
    info[key]=host[key]
p.write_bytes(plistlib.dumps(info))
PY
# Assets are shared in source and copied into the sandboxed extension bundle.
ditto "$project_root/Resources/Reader" "$extension/Contents/Resources/Reader"
rm -f "$extension/Contents/Resources/Reader/stress.md"
minimum_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app_path/Contents/Info.plist")"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
arch="$(uname -m)"
flags=(-O)
if [[ "$build_mode" == debug ]]; then flags=(-Onone -g -D DEBUG); fi
xcrun swiftc -swift-version 6 -parse-as-library -application-extension \
  -module-name LightmarkQuickLook -sdk "$sdk" -target "$arch-apple-macosx$minimum_os" \
  -module-cache-path "$project_root/.build/swift-cache" "${flags[@]}" \
  -framework AppKit -framework WebKit -framework QuickLookUI \
  -Xlinker -e -Xlinker _NSExtensionMain \
  "$project_root/Sources/LightmarkQuickLook/PreviewViewController.swift" \
  "$project_root/Sources/Lightmark/ReaderResources.swift" \
  -o "$extension/Contents/MacOS/LightmarkQuickLook"
if [[ "$build_mode" == release ]]; then strip -S "$extension/Contents/MacOS/LightmarkQuickLook"; fi
identity="${APPLE_SIGNING_IDENTITY:--}"
sign_flags=(--force --sign "$identity" --entitlements "$project_root/Resources/QuickLook/QuickLook.entitlements")
if [[ "$identity" != - ]]; then sign_flags+=(--timestamp --options runtime); fi
codesign "${sign_flags[@]}" "$extension"
codesign --verify --strict "$extension"
