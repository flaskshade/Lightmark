#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
build_mode="${1:-release}"
if [[ "$build_mode" != "release" && "$build_mode" != "debug" ]]; then
  print -u2 "Usage: scripts/build-app.sh [release|debug]"
  exit 2
fi

export CLANG_MODULE_CACHE_PATH="$project_root/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/swift-cache"

minimum_macos_version="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$project_root/Resources/Info.plist")"
sdk_macos_version="$(xcrun --sdk macosx --show-sdk-version)"

swift build -c "$build_mode" --disable-sandbox \
  --scratch-path "$project_root/.build" \
  --cache-path "$project_root/.build/package-cache" \
  --config-path "$project_root/.build/package-config" \
  --security-path "$project_root/.build/package-security" \
  -Xlinker -platform_version -Xlinker macos \
  -Xlinker "$minimum_macos_version" -Xlinker "$sdk_macos_version"

app_path="${LIGHTMARK_DIST_DIR:-$project_root/dist}/Lightmark.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS"
mkdir -p "$app_path/Contents/Resources/Fonts"
cp "$project_root/.build/$build_mode/Lightmark" "$app_path/Contents/MacOS/Lightmark"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
if [[ -d "$project_root/Resources/Fonts" ]]; then
  cp "$project_root/Resources/Fonts"/* "$app_path/Contents/Resources/Fonts/"
fi
cp -R "$project_root/Resources/Reader" "$app_path/Contents/Resources/"
python3 "$project_root/scripts/build-icons.py"
xcrun actool "$project_root/.build/IconAssets.xcassets" \
  --compile "$app_path/Contents/Resources" \
  --platform macosx --minimum-deployment-target "$minimum_macos_version" \
  --target-device mac --app-icon AppIcon \
  --output-partial-info-plist "$project_root/.build/icon-info.plist" \
  --output-format human-readable-text
chmod +x "$app_path/Contents/MacOS/Lightmark"
if [[ -n "${APPLE_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --timestamp --options runtime --sign "$APPLE_SIGNING_IDENTITY" "$app_path/Contents/MacOS/Lightmark"
  codesign --force --timestamp --options runtime --sign "$APPLE_SIGNING_IDENTITY" --identifier app.lightmark.reader "$app_path"
else
  codesign --force --sign - --identifier app.lightmark.reader "$app_path"
fi
print "$app_path"
