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
scripts/publish-downloads.sh --check
export RELEASE_TAG="$tag"
scripts/package-release.sh
git tag -a "$tag" -m "Lightmark $version"
# Publish branch and immutable tag together; concurrent main updates reject both.
git push --atomic origin main "$tag"
gh release create "$tag" dist/release/Lightmark.dmg dist/release/Lightmark.zip dist/release/SHA256SUMS.txt dist/release/release.json --repo "$release_repo" --verify-tag --title "Lightmark $version" --notes-file "$release_notes"
scripts/publish-downloads.sh
print "Published $tag. Cloudflare will deploy the website download automatically."
