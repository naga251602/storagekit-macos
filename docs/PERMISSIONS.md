# StorageKit — macOS permission setup

On first v5.3 launch, StorageKit presents a four-step wizard **before the initial app scan**: Welcome → Choose Folders → Full Disk Access → Ready. Each screen has its own Continue action; Back revisits the previous step. The wizard runs once after upgrading from older setup flows and can be opened again from Settings.

1. **Standard access:** StorageKit runs with your current user account's privileges. macOS may ask whether StorageKit can access Documents, Desktop, Downloads, removable volumes, or other protected locations. Approve only the locations you want scanned. There is no one-click authorization for the entire disk.
2. **Review folders (optional):** Select directories through the native macOS folder picker. Storage Cleanup shows up to 200 *immediate children* per folder as **unselected** review entries. Scanning a folder never automatically deletes it or its contents. Folder paths are stored in app preferences and can be removed in Settings.
3. **Full Disk Access (optional):** Click **Open Full Disk Access Settings**, then manually add/enable StorageKit under **System Settings → Privacy & Security → Full Disk Access**. macOS controls this permission; StorageKit **cannot grant it programmatically or reliably infer that it was granted**. After changing it, quit and reopen StorageKit.
4. **Finish Setup:** On the final screen, the user finishes and scanning begins. Setup completion is stored locally. From **Settings → Review Access Setup**, reopen the guide and change the review-folder list.

No files are moved during setup. No elevated helpers, `sudo` commands, recursive shell deletion, or automatic macOS security changes are used. **Protected system paths are still blocked** even if macOS allows the process to read them.

## Manually selecting files in Storage Cleanup

Choose **Storage Cleanup → Add Files or Folders…**. The system picker returns user-selected paths. Eligible regular files and folders appear as grey, **unchecked** candidates. A second explicit selection, exact-path review, risk acknowledgement and **Move to Trash** confirmation are necessary. File and directory identity, current ownership, missing paths, symlinks, and protected roots are revalidated immediately before the move.

This is deliberate user-managed file cleanup — not proof that a file is disposable. Deleting a selected folder can remove all nested files, including valuable personal or shared resources. StorageKit does not empty macOS Trash.

Limitations: system directories, the entire user home, top-level Documents/Downloads/Desktop folders, app bundles in manual-cleanup mode, symlinks, protected StorageKit metadata, root-owned files, and certain mounted-volume locations are not eligible. These are intentional safety boundaries, not permission failures.
