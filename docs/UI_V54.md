# StorageKit v5.4 — macOS UI and Apple cleanup

## Application inspector

- The right inspector uses the top titlebar safe area; the app identity starts near the top instead of below an empty header gap. The SwiftUI detail view uses `ignoresSafeArea` with a controlled 44-point top inset to avoid covering titlebar controls. Verify placement on Ventura, Sonoma and newer macOS versions.
- The toolbar under the identity is a **single horizontal line**: Reveal in Finder · Copy Path · Clear Cache · Reset Data · Uninstall (third-party only). It scrolls horizontally on smaller windows instead of reflowing to two rows.
- The footer retains **Rescan** only.

## Apple apps (explicit opt-in)

- **Hide Apple & protected apps** is **on by default**. The C++ scanner avoids enumerating `/System/Applications` unless the filter is disabled; unchecking causes a new app scan that includes Apple apps.
- Apple application bundles stay read-only regardless of their installation path. **Uninstall** is not displayed for Apple apps.
- Apple **Clear Cache / Reset Data** requires Settings → Advanced, explicit manual checking of exact bundle-ID user Library matches, and the confirmation sheet's risk acknowledgement.
- Scanner candidate matches are in the user's known Library directories. Shared Group Containers and system-wide `/Library` are blocked. No filename prefix/name-only matches are accepted for Apple app data in the Trash validator.
- The system app may be running or inaccessible; partial results and failures are reported. No bypass of macOS access restrictions.

## On-device acceptance checklist

- [ ] The right app header starts near the top of the window; icon, name, bundle ID and path do not overlap the macOS titlebar.
- [ ] Reveal / Copy / Clear Cache / Reset Data / Uninstall form one row. Resizing horizontally shows scroll behavior without a second row.
- [ ] Apple apps are hidden by default. Disabling the filter reveals them, with no Uninstall action.
- [ ] In Standard Mode, Apple cache and data rows are not selectable; Advanced Mode allows manually choosing only exact user-Library matches.
- [ ] Apple app bundle, shared group containers and any `/System` or `/Library` paths cannot be moved to Trash.
- [ ] For an Apple app fixture, Clear Cache and Reset Data show selected paths, warnings and risk acknowledgement before Trash; tests must use disposable data, not actual iCloud/Photos/Mail content.
- [ ] Apple data restoration uses Recently Deleted when its Trash contents remain recoverable.
- [ ] Third-party uninstall remains bundle-only unless Delete app data is explicitly checked.

Native macOS build, rendering and Trash flows are unverified in the Linux authoring environment. The portable fixture tests only cover scanner discovery and classification.
