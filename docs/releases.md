# Releases

`Resources/Info.plist` owns the version and build number. Versions use `MAJOR.MINOR.PATCH`; build numbers increase with every release.

## Development

Run `scripts/build-app.sh debug` for an ad-hoc local bundle. Production signing is optional for development. Release executables have local debug/object paths stripped before signing. The debug updater does not install production releases.

## Publish

Release from clean `main` matching `origin/main`:

1. Run `python3 scripts/set-version.py VERSION BUILD`.
2. Update the changelog in the private website checkout and push it. Commit and push app changes separately.
3. Set `LIGHTMARK_WEBSITE_DIR` to the private website checkout (default `.local/lightmark-website`). Set `APPLE_SIGNING_IDENTITY` to your Developer ID Application identity and `NOTARY_KEYCHAIN_PROFILE` to your local notarytool profile.
4. Optionally set `RELEASE_NOTES_FILE` to a reviewed Markdown file containing public release notes, then run `scripts/publish-release.sh`. Without one, the release contains only a link to the public changelog. Commit messages are never used to generate release notes.

The command builds, signs, notarizes, staples and verifies the app and DMG. It generates a signed Sparkle update archive, pushes the app branch and immutable version tag atomically, creates a GitHub release, then commits verified downloads and the feed to the private website repository. Cloudflare deploys the website automatically. Nothing runs persistently on the development machine.

Signing and notarization credentials stay in Keychain. Missing credentials stop publication; there is no ad-hoc production fallback. Never overwrite published tags or downloads from development builds.

## Native updates

`AppUpdates.swift` owns Sparkle presentation; Sparkle owns archive verification and installation. The appcast is hosted at `https://trylightmark.com/downloads/appcast.xml`. The public update key is in Info.plist; the private key remains in Keychain under account `lightmark-updates`.

Header-initiated updates show download progress and offer Restart to update. Explicit menu checks use native dialogs. AppKit reviews unsaved documents before termination. The target-build marker drives the brief completion message after relaunch. Debug builds disable the updater.

Keep old versioned update ZIPs available so clients with an earlier feed can finish downloading. Sign the final, stapled archive. Losing the update-signing key requires a deliberate rotation plan.

## Recovery

If a concurrent push rejects publication, reconcile main and the local release commit before retrying the atomic branch/tag push. Do not blindly rerun after creating the tag. If GitHub release creation fails after a successful push, finish only that step with the already verified artifacts.

If website publication fails after the app release succeeds, correct the website checkout and rerun only `scripts/publish-downloads.sh` with the verified artifacts still in `dist/release`. Never recreate the version tag.

Confirm the live release manifest and appcast after Cloudflare deployment. A successful build or GitHub release does not prove runtime update behavior. Signed-release functionality and unsaved-document relaunch require separate verification.
