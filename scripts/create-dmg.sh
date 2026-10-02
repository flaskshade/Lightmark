#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
app_path="${1:?Usage: create-dmg.sh APP_PATH OUTPUT_DMG}"
output="${2:?Provide output DMG path}"
work=$(mktemp -d /tmp/lightmark-dmg.XXXXXX)
mounted=false
cleanup() {
  if [[ "$mounted" == true ]]; then hdiutil detach "$work/mount" -quiet || true; fi
  rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/staging/.background" "$work/mount"
ditto "$app_path" "$work/staging/Lightmark.app"
ln -s /Applications "$work/staging/Applications"
swift -module-cache-path "$project_root/.build/swift-cache" "$project_root/scripts/dmg-background.swift" "$work/staging/.background/install.png"
hdiutil create -quiet -srcfolder "$work/staging" -volname Lightmark -fs HFS+ -format UDRW "$work/writable.dmg"
hdiutil attach -quiet -nobrowse -mountpoint "$work/mount" "$work/writable.dmg"
mounted=true
osascript - "$work/mount" <<'APPLESCRIPT'
on run argv
    set volumeFolder to POSIX file (item 1 of argv) as alias
    tell application "Finder"
        open volumeFolder
        delay 1
        set openedFolder to target of front window as alias
        if openedFolder is not volumeFolder then error "Installer window did not open"
        set installerWindow to front window
        set current view of installerWindow to icon view
        set viewOptions to icon view options of installerWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 100
        set text size of viewOptions to 13
        set background picture of viewOptions to (POSIX file ((item 1 of argv) & "/.background/install.png") as alias)
        tell installerWindow
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set bounds to {200, 200, 760, 540}
            set position of item "Lightmark.app" to {145, 145}
            set position of item "Applications" to {415, 145}
            delay 2
            close
        end tell
    end tell
end run
APPLESCRIPT
hdiutil detach -quiet "$work/mount"
mounted=false
hdiutil convert -quiet "$work/writable.dmg" -format UDZO -imagekey zlib-level=9 -o "$output" -ov
