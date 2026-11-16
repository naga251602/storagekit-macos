# GitHub CI/CD for StorageKit

StorageKit's Actions are source-controlled in `.github/workflows/`.

## Continuous integration (CI)

`ci.yml` runs on pushes to `main`, pull requests, and manual dispatch:

1. **Linux:** C++ scanner fixtures, SwiftUI source-level inspector regression tests, shell syntax. Scanner tests use isolated temporary directories; they never remove real files.
2. **macOS Apple Silicon (`macos-15`):** Re-run tests, parse Swift source, build using `build.sh`, check bundle metadata/arm64 architecture/ad-hoc signature and upload a ZIP as a short-lived Actions artifact.

The layout tests catch the titlebar regression where an inspector opted out of the safe area. They are *source-level checks*, not screenshot/UI automation. Verify the header positioning on a real Mac before releasing.

## Continuous delivery (CD)

`release.yml` runs only for pushed tags matching `v*` and additionally validates the full `vMAJOR.MINOR.PATCH` pattern. It tests and compiles the project on a native arm64 runner, validates the bundle, and creates a **GitHub prerelease** containing:

- `StorageKit-vX.Y.Z-macos-arm64.zip` — preserves the `.app` bundle with `ditto`
- `SHA256SUMS.txt` — checksum for the ZIP

The tag controls the app's `CFBundleShortVersionString` using `STORAGEKIT_VERSION`; the GitHub run number controls `CFBundleVersion`.

**Security/distribution:** This project currently uses ad-hoc signing and has no Apple Developer ID certificate, notarization workflow, updater or automatic installation. Its prereleases are appropriate for source/test distribution, not polished public release. Users may encounter Gatekeeper warnings. The workflow does not request signing secrets, bypass macOS protections or run file-cleanup integration tests on actual user data.

## First-time setup

1. Create a GitHub repository and push this project's files to its `main` branch. For a brand-new local repository (replace `<account>` with your GitHub username):

   ```bash
   git init -b main
   git add .
   git commit -m "Initial StorageKit release"
   git remote add origin https://github.com/<account>/storagekit-macos.git
   git push -u origin main
   ```

   If the project is already a Git repository, keep its existing history and remote instead of running `git init` again.
2. Under **Settings → Actions → General**, enable Actions if needed. For releases, ensure the workflow token has permission to create releases (`contents: write` is requested on the release job; organization policy may further restrict it).
3. Push a commit or open a PR; open the **Actions → CI** run to view scanner/unit/build checks and download the build artifact.
4. After testing locally, create a release tag and push it:

   ```bash
   git tag v5.4.1
   git push origin v5.4.1
   ```

5. Open **Actions → Release (macOS arm64)** and then **Releases** to find the automated prerelease.

When developing a newer version, choose the new tag (e.g. `v5.4.2`); the release workflow injects it into the built bundle. Local builds default to the version defined in `build.sh`.

## On-device visual and Trash testing

CI cannot certify a real window layout, permission dialog, or restore workflow. Use `docs/TESTING.md` and additionally check:

- Select Brave (or any disposable test app). The full icon/name/bundle ID/path appears *below* the native titlebar; the icon/name are never clipped.
- Narrow the window: buttons scroll horizontally without wrapping.
- Open Cleanup Review, cancel and verify **nothing** moved.
- Use a disposable fixture for Move to Trash and Recently Deleted restoration.

## Useful commands

```bash
./scripts/test.sh            # tests and Swift syntax parsing (if swiftc exists)
./build.sh                   # build on Apple Silicon
./scripts/verify_bundle.sh   # verify output on macOS after build
```
