## Unreleased — release and onboarding UX

- First-launch choice: Accept Default Settings or Customize, with independent folder pickers.
- Permanent source-code link in sidebar and Help menu, plus release link and update controls.
- Conditional Sparkle 2 integration for appropriately signed and hosted update releases.
- Current published GitHub prerelease linked from README with a download button.
- Setup/release documentation and regression checks. Existing cleanup safety is unchanged.

## 5.4.1 — Inspector titlebar fix and CI/CD

- Fixed clipped application icon/name in the detail inspector by respecting the macOS titlebar safe area.
- Removed the oversized top padding and preserved the one-row, horizontally scrollable action toolbar.
- Added source-level UI regression tests, native bundle verification, Linux/macOS CI and tag-based prerelease publishing.
- Documented GitHub Actions setup, release packaging, checksums and notarization limitations.

# Changelog

## v5.4 — Inspector layout, Apple app user data and documentation

- Reduced unused space above the selected-app inspector; fixed titlebar-aware top positioning.
- Kept all app action buttons on a single horizontally scrollable toolbar instead of wrapping.
- Added opt-in visibility for Apple apps via **Hide Apple & protected apps**, on by default; avoids expensive `/System/Applications` scans until opted in.
- Added manual Advanced Mode cache/data selection for exact Apple bundle-ID matches within user-owned Library directories. Apple system bundles, shared groups, symlinks and protected paths remain blocked.
- Added a second, independent Apple-data allowlist in Trash validation, plus app bundle identity verification and existing user ownership/inode checks.
- Rewrote README with onboarding, build and launch, use cases, Apple-app risk guidance, Developer Tools & Models, Recently Deleted, testing and limitations.
- Expanded scanner fixture tests (20 non-destructive cases). Native macOS build and Trash behavior still require on-device verification.

## v5.3 — Welcome and Developer Tools & Models cleanup

- Four-step welcome/setup flow.
- Application identity inspector header.
- Explicitly selectable known user-owned developer environments and model caches.
- Trash review, recovery history and restoration retained.

## v5.2 — File selection, Ollama and permissions

- Ollama model/log discovery; manual Storage Cleanup picker.
- First-launch permission guide and local review-folder settings.
- Fully restored sessions no longer appear in Recently Deleted.

## v5.1 — Application cleanup controls

- Inspector cleanup buttons and protected-app filter.
- Uninstall requires explicit Delete app data opt-in.

## v5 — StorageKit foundation

- Native C++20 scanner, SwiftUI interface, safe Trash workflow and recovery manifest.
