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

app_path="$project_root/dist/Lightmark.app"
mkdir -p "$app_path/Contents/MacOS"
mkdir -p "$app_path/Contents/Resources/Fonts"
cp "$project_root/.build/$build_mode/Lightmark" "$app_path/Contents/MacOS/Lightmark"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
if [[ -d "$project_root/Resources/Fonts" ]]; then
  cp "$project_root/Resources/Fonts"/* "$app_path/Contents/Resources/Fonts/"
fi
chmod +x "$app_path/Contents/MacOS/Lightmark"
codesign --force --deep --sign - --identifier app.lightmark.reader "$app_path"
print "$app_path"
