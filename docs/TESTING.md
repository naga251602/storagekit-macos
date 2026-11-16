# Test & release checklist

## Automated checks

On Linux (scanner fixtures) or macOS:

```bash
./scripts/test.sh
```

Runs C++ scanner fixture tests and Swift parser checks when `swiftc` exists. On macOS, additionally build the native bundle:

```bash
./build.sh
open -n "build/StorageKit.app"
```

GitHub Actions `macos-15` CI contains native build and scanner fixture tests. A CI workflow file is provided but has **not run until you push it to GitHub**.

## Required on-device smoke tests — macOS 13+ and M-series

- [ ] Build on a clean extracted project folder, without old artifacts.
- [ ] App icon, display name, executable and bundle metadata all show StorageKit.
- [ ] Navigate the five screens: Applications, Storage Cleanup, Developer Tools & Models, Recently Deleted, Settings. Neither Overview nor Memory Monitor appears.
- [ ] Resize the window: Clear Cache, Reset Data and Uninstall stay on the same single-row toolbar beside Copy Path (scroll horizontally on narrow windows). Rescan remains in the application list footer.
- [ ] Hide Apple & protected apps is checked on launch; turning it off reveals Apple app bundles for user-data inspection only.
- [ ] App scan selects a known third-party `.app`, shows cache/settings/containers with sizes and risk.
- [ ] Switching apps and rescanning does not use stale scan output.
- [ ] Uninstall dialog defaults to **Delete app data = off** and shows one `.app` bundle path only (not caches/preferences).
- [ ] Checking Delete app data reveals associated paths; unchecking hides them and removes them from the approved deletion set.
- [ ] Uninstall remains available if the app bundle checkbox was unchecked in the inspector: the app bundle is required in the confirmation dialog.
- [ ] Clear Cache and Reset Data still list only their permitted file categories. Cancel never moves anything.
- [ ] Advanced Mode exposes uncertain/shared items for manual selection, never preselects them; risky items require acknowledgement.
- [ ] Apple system app **bundles** and system paths, symlinks, Homebrew package directories and individual Ollama manifests cannot be moved to Trash. Apple exact-ID user Library paths need Advanced Mode and manual confirmation.
- [ ] Close a running app and rescan; check allowed actions. Verify running-app guard blocks moves.
- [ ] Create a **disposable fixture application and cache**, approve a small test cleanup, verify item moves to actual macOS Trash and HistoryStore metadata is saved.
- [ ] Reopen app and confirm Recently Deleted persists; restore and compare bytes with original fixture.
- [ ] Trigger Skip / Rename / Replace destination conflicts with disposable fixtures; verify Replace creates a backup session.
- [ ] Empty the fixture Trash item manually in Finder and confirm No longer recoverable is displayed.
- [ ] Enter actual GitHub repo URL under Settings, test Help links, issue forms and README.
- [ ] Disable network and verify all scanner and cleanup features remain functional.
- [ ] Test permission-denied and partial Trash move failures; verify honest per-file reporting.
- [ ] Confirm no app emits telemetry and no private path is uploaded.

## Not yet verified

The authoring environment is Linux and cannot type-check native SwiftUI/AppKit or execute `FileManager.trashItem` against macOS volumes. Swift parser checks **are not** macOS native compilation. Treat this as an implementation that requires the above native validation before real data cleanup.

## v5.2 regression checks (required on a real Mac)

- [ ] With no saved setup choice, StorageKit opens the permissions sheet **before scanning**; Continue is required and reopening the guide in Settings works.
- [ ] Full Disk Access control opens System Settings, but never claims to grant or verify permissions automatically; test both allowed and denied TCC access.
- [ ] Add a review folder in setup; Storage Cleanup lists its immediate children (unchecked). Remove it in Settings and rescan to verify they disappear unless manually added separately.
- [ ] Use **Add Files or Folders...** to choose a disposable file; verify grey/unselected initially, manual selection, risk acknowledgement, exact path review, and successful Trash operation.
- [ ] Attempt a symlink, `/System` path, entire Downloads directory, app bundle, and root-owned file through the picker; they must remain unavailable.
- [ ] Install a disposable Ollama fixture or test app with `com.electron.ollama` ID; confirm `.ollama` model directory, logs, and documented Library data appear. Uninstall starts with **app only**; opt-in data shows model store and warns about credentials/history.
- [ ] Inspect `~/.ollama` in Storage Cleanup after removing Ollama.app; it should be **unselected** and require Advanced review (or explicit file picker selection).
- [ ] Check the Ollama app/server is not running before moving model stores; verify running-process and permission failure handling.
- [ ] Move a disposable app plus two data paths to Trash; restore one item -> session remains; restore all -> session disappears from Recently Deleted, and the disappearance persists after relaunch.
- [ ] Confirm partial or failed restoration leaves outstanding items visible, and that files are actually restored to original paths.
- [ ] Verify no extra files are moved when the user cancels, unchecks "Delete app data", or does not acknowledge risk.

## v5.3 additional on-device checks

- [ ] Verify **Welcome → Choose Folders → Full Disk Access → Ready**, individual Continue and Back actions, folder selection and an optional Full Disk Access link. Finish Setup should trigger the app scan once.
- [ ] Check the wizard is still available from Settings and does not falsely claim access has been granted.
- [ ] The selected app's icon, name, bundle ID and path are fixed in the top right header. Buttons remain below the header when scrolling and resizing.
- [ ] In Developer Tools & Models, verify *no entry is preselected*, and that known user-owned environments/caches/model stores have selectable checkboxes.
- [ ] Verify an individual Review Move to Trash action selects only the currently inspected item, while the list footer supports multiple selected items.
- [ ] Check Homebrew packages and individual Ollama manifests remain read-only; symlinks and privileged paths never become eligible. Hugging Face cached `models--...` repository folders should be selectable individually.
- [ ] With a disposable fake `~/.pyenv/versions/<test-version>` or cache directory, test review, exact-path acknowledgement, Trash move, Recently Deleted restoration and final disappearance from recovery history. Never use a real active environment as the first test.
- [ ] Try a changed/in-use path; validate skip with clear per-item reason, not a false success.
- [ ] macOS 13 and newer native build must be performed; Linux Swift syntax parsing is insufficient to confirm UI compilation.

## v5.4.1 layout + CI regression

- Check that selected app icon, name, ID and path are wholly visible below titlebar (no clipping).
- Verify controls remain in one horizontal scrolling row when narrowing window.
- Run `./scripts/verify_bundle.sh` after `./build.sh` on macOS.
- Push a PR and confirm both CI jobs; push `v5.4.1` to verify a prerelease ZIP and checksum appear.

