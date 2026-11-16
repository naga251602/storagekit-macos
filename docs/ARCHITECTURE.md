# Architecture

```text
SwiftUI Views
  ├── four-step welcome + separate permission actions
  ├── sidebar / default third-party app list / opt-in Apple inspection / Rescan footer
  ├── titlebar-aligned inspector header / one-row actions / uninstall data opt-in
  ├── Storage Cleanup / inventory / Recently Deleted / Settings
  └── cleanup confirmation + result
             │
       CleanerModel (@MainActor)
         ├── launches read-only C++ scanner via Process, parses JSONL
         ├── manages explicit selection and Advanced Mode
         ├── passes immutable chosen candidates to TrashService
         ├── HistoryStore stores actual resulting Trash URLs

C++20 Scanner.cpp
  ├── enumerate .app bundles and read Info.plist bundle IDs (CoreFoundation)
  ├── scan app-specific Library file candidates with classification
  ├── discover storage candidates (exact app caches + review-only artifacts)
  └── classify user-owned developer inventory for explicit Trash review,
      leaving Homebrew packages and model manifests manager-only
```

## Ownership and safety boundaries

* Scanner is a separate, non-privileged, read-only executable that emits one JSON object per line; it never performs cleanup.
* UI `ScanEntry` includes category, confidence, status, `st_dev`/`st_ino`, last-modification timestamp, estimated logical size and a descriptive reason.
* The confirmation sheet takes a snapshot of selected items. The Trash service rechecks status, permission, path structure, file identity and running app identity before each move.
* All moves use `FileManager.trashItem(at:resultingItemURL:)` and record the **returned** Trash path, not a predicted one.
* The recovery service rechecks recorded Trash identity; original file paths are not overwritten without a separate user-approved conflict policy.
* No shell interpolation accepts user data. Apple bundles are listed when the user disables the protected-app filter, including `/System/Applications`; their binaries remain read-only. Only exact, user-owned Library candidates are manually reviewable in Advanced Mode.
* Recovery records are written atomically in the user's Application Support directory with restricted permissions.

## Data flow

1. User selects a screen. `CleanerModel` launches `storagekit-scanner` with fixed command arguments.
2. The model handles a generation counter so canceled/obsolete scans cannot update the current screen.
3. App selection triggers per-app scanning; green candidates can be preselected, uncertain/shared ones must be manually selected after opting into Advanced Mode.
4. User chooses a cleanup action from the right-hand inspector. Uninstall starts with the application bundle only. The **Delete app data** checkbox reveals optional associated paths and is off by default; the model and Trash service both reject incidental app-data removal while it is off. The review lists actual selected paths and risk acknowledgement.
5. Trash service validates again, records each outcome, and stops between files if user cancels.
6. Recently Deleted reads persisted metadata and shows restore availability based on whether recorded Trash paths still exist.

## Project boundaries

- UI does not shell out to delete files.
- C++ never claims that name similarity establishes ownership.
- Whitelisted user-owned runtime version directories and entire cache/model stores may be moved to Trash after manual selection and a strict second allowlist in TrashService. Never delete arbitrary package manager internals; Homebrew formulas and individual Ollama manifests remain inventory-only.
- Developer selections are never automatic. The confirmation explicitly warns that entire model stores and runtime versions may be shared by other projects.
- No network or telemetry dependencies; outbound GitHub link actions open the browser only when the user clicks them.
