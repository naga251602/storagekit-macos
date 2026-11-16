# File safety and recovery contract

## Hard rules

1. Never call `rm`, recursively delete, empty Trash or clear kernel swap.
2. Block system roots, mounted-volume roots, user home root, StorageKit history directory, Trash root and privileged paths.
3. Block any existing symlink component, symlink targets and changed file identities; no implicit symlink traversal.
4. The entry must be a direct child of a documented category root (or a selected verified app bundle under an accepted Applications root).
5. Only files owned by the current user may be moved. No automatic authorization bypass or elevated-helper requests.
6. Never auto-select grey, amber, protected or manager-controlled data. Manually selected developer inventory is permitted only at precisely whitelisted current-user paths. Advanced Mode never bypasses red/system restrictions.
7. Ask for approval of the complete selected list and extra risk acknowledgement for uncertain/shared paths.
8. A running application blocks per-app cleanup; storage app caches of running apps are also blocked.
9. Per-item results record moved, skipped or failed; partial success must not claim everything moved.
10. Recovery depends on macOS Trash. No extra copies or promises after Empty Trash.

## Confidence is not authorization

An exact bundle-ID match (green) improves confidence but does not prove that content is disposable. Third-party file locations can contain valuable unsynced data. A grey or amber item may be user-accessible but must only be selected manually in Advanced Mode. Protected files remain inaccessible even with Advanced Mode.

## Safe vs unsupported cleanup

| Supported | Unsupported in v5 |
| --- | --- |
| Verified app caches + manually approved ordinary app data | System-wide `/private/var/folders` purges |
| Approved items under `~/Library` and selected bundle paths | System app bundles, launch daemons, privileged helpers |
| Xcode DerivedData folders after Advanced review | Active Docker internal storage raw deletion |
| Old user logs/downloads after Advanced review | Editing Homebrew Cellar, individual Ollama manifest/blob internals, Docker internals |
| Manually checked developer runtime versions and complete known cache/model directories | Automatically selecting developer resources or trashing system-owned manager roots |
| Trash via Foundation and restore via file move | Unattended background cleanup |

## Important limitations

* APFS clone/block accounting, open files, sparse files and compression make logical byte estimates different from physical reclaimable bytes.
* TOCTOU risks cannot be eliminated entirely through path-based Foundation APIs; the app revalidates immediately before moving but should never be used to remove suspicious or adversarial filesystem content.
* Restore does not recreate missing parent folders or recover items already removed from Trash.
* Destination replacement is explicit. An existing file is itself moved into Trash before restoring the older one, and that backup appears as its own Recently Deleted session.
* App names may differ from on-disk folder names. StorageKit cannot guarantee a total uninstall.

## Developer cleanup safeguards (v5.3)

- C++ inventory emits `cleanup=developer` and `confidence=manual` only for known runtime versions, cache/model stores (including individual Hugging Face `models--...` repositories) and developer data; entries remain unchecked.
- Swift's independent deletion allowlist checks the *exact* selected directory or its direct-child relation to a known runtime root, plus current user ownership, device/inode/mtime and absence of symlink components.
- UI requires an explicit checkbox, separate confirmation listing actual paths, and extra risk acknowledgement.
- Homebrew Cellar/Caskroom and individual Ollama manifests are inventory-only; moving the entire Ollama model store affects **all** downloaded Ollama models.
- Stop language servers, model servers, database processes and other developer tools before moving in-use data.

## Apple application user data (v5.4)

- Apple bundles are never eligible for uninstall, even when shown through the opt-in filter.
- Only exact bundle-ID, direct-child user Library paths in approved categories can be manually selected in Advanced Mode. Shared group containers, system-wide folders and name/prefix guesses are rejected.
- A separate TrashService validation checks the selected app's bundle ID, item identity, category, path, user ownership, symlinks and file timestamps again before any move.
- Apple app caches and settings may contain synced personal content. They are never preselected and require explicit risk acknowledgement; even Trash is not a guarantee of safe recovery.
