# Lightmark agent guide

If a local `Blueprint.md` exists, read it first; it is not distributed with the repository. For website work read `website/README.md`; for releases, signing, versions, branches or publishing read `docs/releases.md` and `website/DEPLOYMENT.md`.

- Preserve the custom tabs and document/save architecture. No AppKit native tabs.
- Follow current user instructions and testing preferences. Never claim runtime verification from a build alone.
- Keep native reader code under `Renderer/` authoritative; bundled assets under `Resources/Reader/` must be regenerated after renderer changes.
- `Resources/Info.plist` owns version/build, bundle ID and minimum OS. Use `scripts/set-version.py` for version bumps.
- Feature branches use `codex/` by default. Do not force-push or rewrite published tags.
- Production releases require hardened runtime, Developer ID signing, Accepted notarization, a valid stapled ticket and Gatekeeper assessment. Never replace the public download with an ad-hoc build.
- Releases are explicitly published locally with scripts/publish-release.sh; ordinary main pushes only deploy the website. Confirm release scope/version in the user session before tagging.
- All release credentials remain in Keychain; never expose credentials in code, logs or chat.
- Website deployments use the repository's main branch and Cloudflare Pages Git integration. Public downloads are copied into website/downloads by the local release script, not served from private GitHub asset URLs.
- Keep deployment status and documentation truthful. Native updates use Sparkle; read docs/releases.md before changing update signing, feed publishing or relaunch behavior.

- Keep private working notes out of tracked files. Use concise, factual commit messages and curated user-visible release notes; avoid conversation references and internal process narration.
