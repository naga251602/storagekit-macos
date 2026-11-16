import AppKit
import Darwin
import Foundation

/// File/folder picker selections are explicit review candidates, not automatic
/// permission grants or evidence that content is safe to remove.
private final class UserChosenPathRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var paths = Set<String>()

    func approve(_ path: String) {
        lock.lock()
        paths.insert(path)
        lock.unlock()
    }

    func contains(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return paths.contains(path)
    }
}

enum ManualSelectionService {
    private static let registry = UserChosenPathRegistry()

    static func approved(_ path: String) -> Bool { registry.contains(path) }

    static func reviewEntry(_ url: URL) -> ScanEntry? {
        let path = url.standardizedFileURL.path
        guard !PathSafety.forbidden(path), !PathSafety.hasSymlinkComponent(path),
            let st = PathSafety.fileStat(path), st.st_uid == getuid(),
            st.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
                || st.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
        else { return nil }
        // Never allow a picked .app bundle to silently bypass app uninstaller rules.
        guard !path.lowercased().hasSuffix(".app") else { return nil }
        registry.approve(path)
        let isRegular = st.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
        return ScanEntry(
            type: "storage", id: path, name: url.lastPathComponent,
            path: path, category: "User Selected", status: "GREY",
            confidence: "manual",
            reason:
                "Explicitly selected for review; ownership and contents are not verified. Moving a directory also moves everything inside it.",
            cleanup: "manual", bundleID: "", eligible: false,
            sizeBytes: isRegular ? UInt64(max(st.st_size, 0)) : nil,
            fileCount: isRegular ? 1 : nil,
            device: UInt64(st.st_dev), inode: UInt64(st.st_ino),
            mtime: Int64(st.st_mtimespec.tv_sec))
    }

    static func children(of folders: [String]) -> [ScanEntry] {
        var entries: [ScanEntry] = []
        for folder in folders {
            guard !PathSafety.forbidden(folder), !PathSafety.hasSymlinkComponent(folder) else { continue }
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            guard
                let urls = try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles])
            else { continue }
            // No recursive indexing or auto selection; only first-level children.
            for child in urls.sorted(by: { $0.path < $1.path }).prefix(200) {
                if let entry = reviewEntry(child) { entries.append(entry) }
            }
        }
        return entries
    }

    @MainActor static func chooseFilesAndFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.message = "Select files or folders for manual review. Nothing is moved yet."
        panel.prompt = "Add for Review"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        return panel.runModal() == .OK ? panel.urls : []
    }

    /// A suggested directory is not permission. The user must confirm it in
    /// the system folder picker; cancellation leaves settings unchanged.
    @MainActor static func chooseSuggestedReviewFolder(_ name: String) -> String? {
        guard ["Desktop", "Documents", "Downloads"].contains(name) else { return nil }
        let suggested = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(name, isDirectory: true).standardizedFileURL
        let panel = NSOpenPanel()
        panel.message = "Select the \(name) folder to review in StorageKit. Nothing will be deleted."
        panel.prompt = "Select for Review"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = suggested
        guard panel.runModal() == .OK, let chosen = panel.url?.standardizedFileURL,
            chosen.path == suggested.path else { return nil }
        return chosen.path
    }

    @MainActor static func chooseReviewFolders() -> [String] {
        let panel = NSOpenPanel()
        panel.message = "Choose folders whose immediate contents should be shown in Storage Cleanup."
        panel.prompt = "Add Review Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        return panel.runModal() == .OK ? panel.urls.map { $0.standardizedFileURL.path } : []
    }
}
