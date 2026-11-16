# StorageKit v5.3 — GUI behavior

## First launch

A four-stage Welcome sheet is presented when the v5.3 setup marker is absent:

1. **Welcome:** explains app scanning, review-before-Trash and restore.
2. **Choose Folders:** offers the optional native review-folder picker. macOS may separately ask for access.
3. **Full Disk Access:** links to System Settings; StorageKit does not assert/grant access.
4. **Ready:** summarizes safe cleanup and how to revisit Settings.

Each stage has a **Continue** button and previous stages have **Back**. **Finish Setup** starts the application list scan. Settings can reopen the wizard.

## Applications

The top of the right inspector is now a fixed identity header with app icon, name, bundle ID and path. A fixed row directly beneath it contains **Reveal in Finder / Copy Path / Clear Cache / Reset Data / Uninstall**. Only the file groups scroll beneath that row. Rescan remains in the application-list footer.

Uninstall still starts with **Delete app data** unchecked and just the app bundle selected. No file move happens before explicit final confirmation.

## Developer Tools & Models

Each entry displays its category, confidence dot, and size or **Managed** status. Known user-owned runtime, developer cache and model-store rows show enabled checkboxes, none preselected. The fixed footer offers **Move Selected to Trash** for multi-item cleanup. The right inspector offers **Review Move to Trash** for the current item, shows the exact path and can expand a directory preview.

The confirmation dialog displays every selected path and requires acknowledgment of project/model-sharing risks. All successful moves are recoverable through Recently Deleted until macOS Trash is emptied. Protected, missing, symlinked, unowned, changed or out-of-scope paths are skipped, never silently deleted.

**Manager-only:** Homebrew packages, individual Ollama manifests. Use `brew uninstall` / `ollama rm` for those individual entries; StorageKit deliberately does not run commands that bypass its Trash-only guarantee. Individual Hugging Face `models--...` cache directories can be selected independently; the full Ollama models store can be selected as one folder.
