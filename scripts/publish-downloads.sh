#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
website_dir="${LIGHTMARK_WEBSITE_DIR:-$project_root/.local/lightmark-website}"
[[ -d "$website_dir/.git" ]] || { print -u2 'Set LIGHTMARK_WEBSITE_DIR to the private website checkout.'; exit 1; }
[[ "$(git -C "$website_dir" branch --show-current)" == main ]] || { print -u2 'Website checkout must be on main.'; exit 1; }
[[ -z "$(git -C "$website_dir" status --porcelain)" ]] || { print -u2 'Commit website changes before publishing downloads.'; exit 1; }
[[ "$(cd "$website_dir" && gh repo view --json isPrivate --jq .isPrivate)" == true ]] || { print -u2 'Website checkout must use a private repository.'; exit 1; }
git -C "$website_dir" fetch origin main
[[ "$(git -C "$website_dir" rev-parse HEAD)" == "$(git -C "$website_dir" rev-parse origin/main)" ]] || { print -u2 'Website main must match origin/main.'; exit 1; }
[[ "${1:-}" == --check ]] && exit 0
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_root/Resources/Info.plist")"
release_dir="$project_root/dist/release"
python3 - "$release_dir/release.json" "$version" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
if manifest.get('version') != sys.argv[2]:
    raise SystemExit('Verified artifacts do not match the current version.')
PY
mkdir -p "$website_dir/downloads"
cp "$release_dir"/{Lightmark.dmg,Lightmark.zip,release.json,SHA256SUMS.txt,appcast.xml} "$website_dir/downloads/"
cp "$release_dir"/Lightmark-*.zip "$website_dir/downloads/"
git -C "$website_dir" add downloads
if ! git -C "$website_dir" diff --cached --quiet; then
  git -C "$website_dir" commit -m "Release $version"
fi
git -C "$website_dir" push origin main
print "Published website downloads for $version. Cloudflare deploys automatically."
