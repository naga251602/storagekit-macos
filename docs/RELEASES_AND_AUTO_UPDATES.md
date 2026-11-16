# Releases and automatic updates

## Current public release

[Download StorageKit v0.1.0 for Apple Silicon](https://github.com/naga251602/storagekit-macos/releases/download/v0.1.0/StorageKit-v0.1.0-macos-arm64.zip) · [All releases](https://github.com/naga251602/storagekit-macos/releases)

The v0.1.0 GitHub release is a **prerelease** and **ad-hoc signed**. It does not contain Sparkle, cannot silently update itself, and may trigger Gatekeeper warnings. Use it for testing only. Future releases need a one-time manual install of the first Sparkle-enabled build before they can update automatically.

## Publishing a GitHub release

1. Merge verified changes into `main` and wait until CI is green.
2. On the source tree for the release, ensure `STORAGEKIT_VERSION` and the strictly increasing `STORAGEKIT_BUILD_NUMBER` are correct. The workflow reads the tag for the version and uses its run number as build number. **A build number must increase monotonically across all published updates, including rebuilds.** If workflow run numbers reset due to workflow changes, override them with a durable monotonically increasing scheme.
3. Run:

   ```bash
   git switch main
   git pull --ff-only origin main
   git tag -a v0.2.0 -m "StorageKit v0.2.0"
   git push origin v0.2.0
   ```

4. Your `.github/workflows/release.yml` currently publishes **ad-hoc-signed prereleases**. Download the ZIP from [Releases](https://github.com/naga251602/storagekit-macos/releases). Do not label these stable/notarized releases.
5. Optionally draft a release directly through GitHub UI under **Releases → Draft a new release**, but **do not use the same tag** when the existing tag-push workflow already automatically publishes it.

## Enabling real automatic updates (Sparkle 2)

This upgrade adds a *conditional* Sparkle integration, not a live update channel. Before it can auto-install:

1. Enroll in Apple Developer Program, get a **Developer ID Application** signing certificate, and configure **notarization** for distribution. Store signing credentials in secure CI secrets/Keychain; never commit them.
2. Download and verify a pinned official Sparkle 2 distribution (https://sparkle-project.org). Keep `Sparkle.framework` intact, including symlinks. The build script accepts its local path via `STORAGEKIT_SPARKLE_FRAMEWORK`.
3. Run Sparkle's `generate_keys` on a trusted Mac. Save a secure backup of the private signing key, and put only the PUBLIC key in `STORAGEKIT_SPARKLE_PUBLIC_KEY`. Never commit/disclose the private key or sign update archives with ad-hoc app signatures.
4. Host an HTTPS Sparkle appcast (e.g. with GitHub Pages) at `https://naga251602.github.io/storagekit-macos/appcast.xml` **only after publishing and verifying the real feed**. Point `STORAGEKIT_SPARKLE_FEED_URL` at that actual address. Configure GitHub Pages in repository **Settings → Pages → GitHub Actions** if using it.
5. Build with `STORAGEKIT_SPARKLE_FRAMEWORK`, `STORAGEKIT_SPARKLE_FEED_URL`, `STORAGEKIT_SPARKLE_PUBLIC_KEY`, and `STORAGEKIT_CODESIGN_IDENTITY` set. `build.sh` embeds Sparkle and configures its feed/key; it intentionally refuses an update-enabled build without a real Apple signing identity.
6. Notarize the built app with `xcrun notarytool`, staple the accepted ticket, then create an archive using `ditto -c -k --sequesterRsrc --keepParent 'build/StorageKit.app' ...zip`.
7. Sign every update archive with Sparkle's `sign_update` or use `generate_appcast` (signs archives via the private EdDSA key). Publish the signed appcast to the HTTPS feed and the archive to GitHub Releases. Ensure `sparkle:edSignature`, `sparkle:version`, archive length and actual release URL agree. Set appcast MIME type to XML.
8. Test from an **older Sparkle-enabled installed app** under `/Applications`, using **Check for Updates…**, then automatic updates. Do not test against important user data. An app launched from a transient ZIP/unwritable location may not update.

The existing `release.yml` is intentionally **not** changed into a fake auto-update pipeline. GitHub Actions cannot generate valid Sparkle signatures or notarize without real Apple and EdDSA credentials and a published appcast. Add a properly authenticated release workflow only after those prerequisites are configured and tested.

With Sparkle configured, StorageKit sets `SUEnableAutomaticChecks=YES` and `SUAutomaticallyUpdate=YES`. Users may adjust both in Settings. Actual installation may still require authorization or a restart.

Official references: https://sparkle-project.org/documentation/ and https://sparkle-project.org/documentation/programmatic-setup/.
