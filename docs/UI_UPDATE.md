# StorageKit — Historical v5.1 Applications UI update

> This is a historical brief. For the current one-row toolbar and Apple app cleanup rules, see [UI_V54.md](UI_V54.md).

**Source of truth:** the two user-supplied screenshots of StorageKit v5, followed by the requested changes.

This brief captures the existing desktop interface and the revised behavior implemented in the accompanying source. It does not assume a different design system or replace the native SwiftUI structure.

## 1. Existing UI extracted from screenshots

The screenshots show a dark native macOS window with three working columns:

1. **Left sidebar:** StorageKit branding/tagline, app navigation, and a permanent “Trash only · No permanent deletion” message.
2. **Middle list:** an Applications heading, search field, scrolling app icons with status dots and bundle IDs, and a footer showing the selected app and controls.
3. **Right inspector:** selected app icon/title, bundle ID, exact installed path, Reveal in Finder and Copy Path buttons, a selected-path/size summary, and accordion groups for Application, Caches, HTTPStorages, Preferences, etc.

The current confirmation window (second screenshot) is a macOS-style sheet containing a title, chosen action, selected count and size, a checkbox per path, ownership-confidence explanation, a Trash retention notice, Cancel, and Move to Trash. In the screenshot it defaults to selecting VS Code's bundle **and** some associated files. That default is what this update changes.

## 2. New Applications view

### Sidebar

- Keep: **Applications**, **Storage Cleanup**, **Developer Tools & Models**, **Recently Deleted**, **Settings**.
- Remove: **Overview**, **Memory Monitor**.
- Default launch destination: **Applications**.
- Continue to display the native “Trash only” safety footer.

### Middle application list

- Keep search, app icons, names, bundle IDs and visual status indicators.
- Add a checkbox directly under search: **Hide protected apps**. It is **checked** on each launch.
- Checking it hides Apple and protected apps; unchecking it reveals them for inspection (Apple bundles remain read-only).
- Apple `com.apple.*` bundles are hidden by default, but can be shown by disabling the filter. The scanner lists `/System/Applications` only when the user opts into showing Apple apps, protecting all system bundles.
- Keep a small count of visible apps near the checkbox.
- The footer contains **Selected: {app}** and **Rescan** only.

### Right inspector

- Keep the selected app icon, name, bundle ID and absolute bundle path.
- Put the following action sequence together near the top, on one scrollable row:
  **Reveal in Finder** | **Copy Path** | **Clear Cache** | **Reset Data** | **Uninstall**.
- On narrow windows, keep one row and scroll horizontally rather than wrapping.
- Keep the grouped, expandable related-file list with manual selection, metadata and paths.
- Clear Cache and Reset Data continue to use their action-specific categories.

## 3. Uninstall dialog — intentional opt-in

**Initial state, every time Uninstall is clicked:**

- **Delete app data (caches, preferences and support files):** unchecked.
- The file list shows **only the required `.app` bundle**.
- The `.app` checkbox is selected and non-editable inside the uninstall dialog; it is the uninstall target.
- The count and estimated bytes reflect **only the app bundle**.
- No cache, preference, HTTPStorage or Application Support item is approved for this uninstall.

**When Delete app data is checked:**

- The list expands to show all discovered, selectable related app-data candidates and their paths, sizes and classification.
- Verified, previously selected entries may be checked initially; unknown/shared entries require manual selection in Advanced Mode, as before.
- The user can uncheck any optional app-data entry in the dialog.
- Risk acknowledgement remains required for risky entries.
- Only explicitly selected paths move to Trash after **Move to Trash** is clicked.

**When Delete app data is unchecked again:**

- All related app-data IDs are removed from the review selection.
- The list returns to **only the `.app`**.
- The shown count and estimated size shrink accordingly.
- The C++ scanner remains read-only; the Swift model AND Trash service independently reject app-data movement by an uninstall operation without the opt-in.

**Uninstalling is not a “Reset Data” action:** Clear Cache or Reset Data must be requested independently. Standard file safety rules, the running-app guard, Trash retention and Recently Deleted recovery remain unchanged.

## 4. Safety, disclosure, and non-goals

- No permanent delete API; use `FileManager.trashItem`.
- Never empty macOS Trash.
- Keep user-visible exact-path review before every cleanup.
- macOS-protected locations remain blocked. Apple apps appear only when the filter is disabled; their binaries remain non-removable and cache/data selection is an explicit Advanced-only workflow.
- The source does not guarantee exhaustive discovery of every application-created file.
- **Deleted files still occupying Trash do not immediately free storage**; “Delete app data” is a choice about which files to move, not a promise of reclaimed SSD capacity.
- Do not reinterpret cache deletion as RAM cleaning.

## 5. Code changes

- `app/Views/MainViews.swift`: navigation change, protected filter, action positioning, footer, removed views.
- `app/Views/Components.swift`: optional app-data checkbox and conditional file list.
- `app/ViewModels/CleanerModel.swift`: default app-only uninstall, optional selection logic, defensive approval, protected filter.
- `app/Models/Models.swift`: removed page cases and revised uninstall warning.
- `app/Services/TrashService.swift`: requires explicit `includeAppData` authorization for app-data paths in uninstall.
- `engine/Scanner.cpp`: includes Apple bundles as protected/review-only inventory and scans `/System/Applications`.
- `build.sh`: removes the unused memory service build input.

## 6. Acceptance checklist

- [ ] Apps open by default; Overview and Memory Monitor are absent.
- [ ] `com.apple.*` apps are hidden by default but visible after unchecking the Apple/protected filter; system app binaries remain blocked.
- [ ] Clear Cache, Reset Data, Uninstall are next to Copy Path in the same row; horizontally scroll if needed.
- [ ] Rescan stays in the app-list footer.
- [ ] Uninstall initially displays exactly one application-bundle item and zero app-data items.
- [ ] App-data checkbox is OFF initially, every time the dialog opens.
- [ ] Checking it reveals selectable associated files; unchecking clears their approval.
- [ ] All moves require the final Move to Trash confirmation.
- [ ] Recently Deleted still records Trash destinations and supports recoverable restoration.
- [ ] Cancel and application switching do not move any files.

The bundled portable C++ fixture tests verify read-only scanning and manual Apple cache/data discovery. Swift syntax parsing is performed in the authoring environment; native macOS UI and Trash behavior require on-device smoke testing before production use.
