#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
cd "$project_root"
[[ "$(git branch --show-current)" == main ]] || { print -u2 'Switch to main before releasing.'; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { print -u2 'Commit or save all working changes before releasing.'; exit 1; }
gh auth status > /dev/null
release_repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
tag="v$version"
git fetch origin main --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { print -u2 'Local main must match origin/main.'; exit 1; }
if git rev-parse --verify "refs/tags/$tag" > /dev/null 2>&1; then
  print -u2 "Tag $tag already exists. Use a new version, or follow the recovery instructions."; exit 1
fi
: "${NOTARY_KEYCHAIN_PROFILE:?Set the local notarytool Keychain profile}"
release_notes="$(mktemp)"
trap 'rm -f "$release_notes"' EXIT
if [[ -n "${RELEASE_NOTES_FILE:-}" ]]; then
  [[ -f "$RELEASE_NOTES_FILE" ]] || { print -u2 'Release notes file does not exist.'; exit 1; }
  cp "$RELEASE_NOTES_FILE" "$release_notes"
else
  print '[Changelog](https://trylightmark.com/changelog/)' > "$release_notes"
fi
export RELEASE_TAG="$tag"
scripts/package-release.sh
cp dist/release/{Lightmark.dmg,Lightmark.zip,release.json,SHA256SUMS.txt} website/downloads/
cp dist/release/appcast.xml dist/release/Lightmark-*.zip website/downloads/
git add website/downloads/appcast.xml website/downloads/Lightmark-*.zip
git add website/downloads/Lightmark.dmg website/downloads/Lightmark.zip website/downloads/release.json website/downloads/SHA256SUMS.txt
if ! git diff --cached --quiet; then
  git commit -m "Release $version"
fi
git tag -a "$tag" -m "Lightmark $version"
# Publish branch and immutable tag together; concurrent main updates reject both.
git push --atomic origin main "$tag"
gh release create "$tag" dist/release/Lightmark.dmg dist/release/Lightmark.zip dist/release/SHA256SUMS.txt dist/release/release.json --repo "$release_repo" --verify-tag --title "Lightmark $version" --notes-file "$release_notes"
print "Published $tag. Cloudflare will deploy the website download automatically."
