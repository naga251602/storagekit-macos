import AppKit
import Darwin
import Foundation

struct RestoreResult {
    var messages: [String]
    var restored: Int
    var skipped: Int
    var failed: Int
}

enum PathSafety {
    static let fm = FileManager.default
    static let home = fm.homeDirectoryForCurrentUser.standardizedFileURL.path

    static func within(_ path: String, _ root: String) -> Bool {
        let parts = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        let prefix = URL(fileURLWithPath: root).standardizedFileURL.pathComponents
        return parts.count > prefix.count && Array(parts.prefix(prefix.count)) == prefix
    }

    static func directChild(_ path: String, _ root: String) -> Bool {
        URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL.path == root
    }

    static func fileStat(_ path: String) -> stat? {
        var result = stat()
        return path.withCString { lstat($0, &result) == 0 ? result : nil }
    }

    static func hasSymlinkComponent(_ path: String) -> Bool {
        var current = ""
        for component in URL(fileURLWithPath: path).standardizedFileURL.pathComponents {
            if component == "/" {
                current = "/"
                continue
            }
            current = (current == "/" ? "/" : current + "/") + component
            guard let st = fileStat(current) else { return true }
            if st.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK) { return true }
        }
        return false
    }

    static func forbidden(_ path: String) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        if p != path || p == "/" || p == home || p == home + "/Library" { return true }
        // User-picked folders can contain entire personal libraries or installed apps.
        // Permit selecting their children, never trashing the entire anchor itself.
        let topLevelRoots = [
            "/Applications", "/Users", home + "/Applications", home + "/Desktop",
            home + "/Documents", home + "/Downloads", home + "/Movies",
            home + "/Music", home + "/Pictures", home + "/Public",
            home + "/.ssh", home + "/.gnupg", home + "/.aws",
        ]
        let libraryCategoryRoots = [
            "Application Support", "Caches", "Preferences", "Containers",
            "Group Containers", "Logs", "HTTPStorages", "WebKit",
            "Saved Application State", "LaunchAgents",
        ].map { home + "/Library/" + $0 }
        if (topLevelRoots + libraryCategoryRoots).contains(p) { return true }
        for root in [
            "/System", "/usr", "/bin", "/sbin", "/Library", "/private", "/etc", "/dev", "/opt", "/Volumes",
            "/Network",
        ] {
            if p == root || within(p, root) { return true }
        }
        if within(p, home + "/.Trash") || p == home + "/.Trash" { return true }
        if within(p, home + "/Library/Application Support/StorageKit")
            || p == home + "/Library/Application Support/StorageKit"
        {
            return true
        }
        return false
    }
}

struct TrashService {
    private static let fm = FileManager.default

    static func isRunning(_ app: ScanEntry) -> Bool {
        if !app.bundleID.isEmpty
            && !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
        {
            return true
        }
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.standardizedFileURL.path == app.path
        }
    }

    private static func appLibraryRoot(_ category: String) -> String? {
        let prefix = PathSafety.home + "/Library/"
        switch category {
        case "Application Support": return prefix + "Application Support"
        case "Caches": return prefix + "Caches"
        case "Preferences": return prefix + "Preferences"
        case "Containers": return prefix + "Containers"
        case "Group Containers": return prefix + "Group Containers"
        case "Logs": return prefix + "Logs"
        case "Saved Application State": return prefix + "Saved Application State"
        case "HTTPStorages": return prefix + "HTTPStorages"
        case "WebKit": return prefix + "WebKit"
        case "Launch Agents": return prefix + "LaunchAgents"
        default: return nil
        }
    }

    // A second, independent allowlist for developer cleanup. A forged scanner
    // row cannot make Homebrew formulas, arbitrary paths, or manifest blobs
    // eligible for Trash. Exact user-owned roots only; runtime versions must
    // be direct children of a known environment root.
    private static func permittedDeveloperLocation(_ item: ScanEntry) -> Bool {
        let home = PathSafety.home
        let runtimeRoots = [
            ".nvm/versions/node", ".pyenv/versions", ".local/share/uv/python",
            "miniconda3/envs", "anaconda3/envs", "miniforge3/envs", ".conda/envs",
        ].map { home + "/" + $0 }
        let cacheRoots = [
            ".npm", ".cache/pip", "Library/Caches/pip", ".cache/uv",
            ".cache/huggingface/hub", ".cache/torch/hub", ".ollama/models",
            "Library/Application Support/LM Studio/models",
            "Library/Application Support/Jan/models", ".cache/lm-studio/models",
        ].map { home + "/" + $0 }
        let dataRoots = [
            ".local/share/virtualenvs", "Library/Python", ".bun/install/cache",
            ".pnpm-store", ".yarn/berry/cache", ".cargo/registry", ".rustup/toolchains",
        ].map { home + "/" + $0 }
        switch item.category {
        case "Runtime/environment":
            return runtimeRoots.contains { PathSafety.directChild(item.path, $0) }
        case "Cache/model store": return cacheRoots.contains(item.path)
        case "Hugging Face cached model":
            return PathSafety.directChild(item.path, home + "/.cache/huggingface/hub")
                && URL(fileURLWithPath: item.path).lastPathComponent.hasPrefix("models--")
        case "Developer data": return dataRoots.contains(item.path)
        default: return false
        }
    }

    private static func validate(
        _ item: ScanEntry, app: ScanEntry?, action: CleanupAction,
        advanced: Bool, includeAppData: Bool
    ) -> String? {
        // Reject associated files even if an old or malformed UI passes them in.
        if action == .uninstall && !includeAppData && item.cleanup != "app" {
            return "Delete app data was not enabled"
        }
        guard action.permits(item) && !item.isProtected && !item.isManagerControlled else {
            return "Action disallowed or protected path"
        }
        if action == .developer {
            guard item.type == "inventory", item.cleanup == "developer",
                item.confidence == "manual", permittedDeveloperLocation(item),
                !PathSafety.forbidden(item.path),
                !PathSafety.hasSymlinkComponent(item.path),
                let st = PathSafety.fileStat(item.path), st.st_uid == getuid(),
                UInt64(st.st_dev) == item.device, UInt64(st.st_ino) == item.inode,
                Int64(st.st_mtimespec.tv_sec) == item.mtime,
                st.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
            else { return "Developer path changed, is protected, or is not a permitted root; rescan" }
            if item.path == PathSafety.home + "/.ollama/models" {
                let knownIDs = ["com.electron.ollama", "com.ollama.ollama"]
                if knownIDs.contains(where: {
                    !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
                }) {
                    return "Quit Ollama before moving its model store to Trash"
                }
            }
            // A headless model server may not appear in NSRunningApplication;
            // users must stop servers and other tools before cleaning shared data.
            return nil
        }
        if item.isRisky && !advanced && item.category != "User Selected" {
            return "Requires Advanced Mode and manual selection"
        }
        guard item.type == (action == .storage ? "storage" : "candidate") else {
            return "Unexpected scan result type"
        }
        if PathSafety.forbidden(item.path) || PathSafety.hasSymlinkComponent(item.path) {
            return "Protected, changed, or symlink-containing path"
        }
        guard let st = PathSafety.fileStat(item.path),
            st.st_uid == getuid(),
            UInt64(st.st_dev) == item.device,
            UInt64(st.st_ino) == item.inode,
            Int64(st.st_mtimespec.tv_sec) == item.mtime
        else {
            return "File identity/ownership changed since scan; rescan"
        }
        let path = item.path
        if action == .storage {
            if item.category == "User Selected" {
                guard item.cleanup == "manual", item.confidence == "manual",
                    ManualSelectionService.approved(path)
                else {
                    return "Path was not explicitly chosen in this session"
                }
                // User-chosen items are never automatically selected; the review
                // sheet requires manual checkbox selection and risk confirmation.
                return nil
            }
            if item.category == "Orphaned Ollama Data" {
                guard advanced, path == PathSafety.home + "/.ollama",
                    URL(fileURLWithPath: path).lastPathComponent == ".ollama"
                else {
                    return "Ollama data needs Advanced Mode and explicit review"
                }
                return nil
            }
            if item.category == "App Cache" {
                guard !item.bundleID.isEmpty, !item.bundleID.lowercased().hasPrefix("com.apple."),
                    item.confidence == "high", item.eligible,
                    PathSafety.directChild(path, PathSafety.home + "/Library/Caches"),
                    URL(fileURLWithPath: path).lastPathComponent == item.bundleID
                else {
                    return "Cache no longer matches a verified app identity"
                }
                if !NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleID).isEmpty {
                    return "Owning application is running"
                }
                return nil
            }
            if item.category == "Xcode DerivedData"
                && !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Xcode")
                    .isEmpty
            {
                return "Close Xcode before moving its build artifacts"
            }
            let roots: [String: String] = [
                "Xcode DerivedData": PathSafety.home + "/Library/Developer/Xcode/DerivedData",
                "User Logs": PathSafety.home + "/Library/Logs",
                "Old Downloads": PathSafety.home + "/Downloads",
            ]
            guard advanced, let root = roots[item.category], PathSafety.directChild(path, root) else {
                return "This storage category is inventory-only or needs Advanced Mode"
            }
            if item.category == "Old Downloads" || item.category == "User Logs" {
                let minimumDays: TimeInterval = item.category == "Old Downloads" ? 90 : 30
                guard let attributes = try? fm.attributesOfItem(atPath: path),
                    let modified = attributes[.modificationDate] as? Date,
                    Date().timeIntervalSince(modified) >= minimumDays * 86_400
                else {
                    return "Age requirement no longer satisfied"
                }
            }
            return nil
        }

        guard let app, !app.bundleID.isEmpty else {
            return "App identity is missing"
        }
        let appleApp = app.bundleID.lowercased().hasPrefix("com.apple.")
        if appleApp {
            let appURL = URL(fileURLWithPath: app.path)
            guard !PathSafety.hasSymlinkComponent(app.path),
                PathSafety.within(app.path, "/System/Applications")
                    || PathSafety.within(app.path, "/Applications")
                    || PathSafety.within(app.path, PathSafety.home + "/Applications"),
                Bundle(url: appURL)?.bundleIdentifier?.lowercased() == app.bundleID.lowercased()
            else { return "Apple app bundle identity changed; rescan" }
            // System-app binaries remain read-only. Manual Advanced cleanup may
            // ONLY touch exact-ID user-owned Library items, never shared roots.
            guard action == .cache || action == .reset, advanced,
                item.cleanup != "app", item.isRisky, item.confidence == "review",
                item.status == "AMBER", item.bundleID == app.bundleID,
                !PathSafety.forbidden(item.path)
            else {
                return "Apple apps allow Advanced review of user data only; system apps cannot be uninstalled"
            }
            let allowedCategories = [
                "Caches", "Application Support", "Preferences", "Containers",
                "Logs", "Saved Application State", "HTTPStorages", "WebKit",
            ]
            guard allowedCategories.contains(item.category),
                let root = appLibraryRoot(item.category), PathSafety.directChild(item.path, root)
            else { return "Shared or system-wide Apple data cannot be moved" }
            let name = URL(fileURLWithPath: item.path).lastPathComponent.lowercased()
            let bundle = app.bundleID.lowercased()
            let exact =
                name == bundle || (item.category == "Preferences" && name == bundle + ".plist")
                || (item.category == "Saved Application State" && name == bundle + ".savedstate")
            guard exact else { return "Apple app file must be an exact bundle-ID match" }
            // Identity/uid/inode/mtime/symlink safety was checked above.
            return nil
        }
        guard app.status != "RED", !PathSafety.forbidden(app.path) else {
            return "App identity is protected or missing"
        }
        if item.cleanup == "app" {
            guard item.category == "Application", path == app.path,
                PathSafety.within(path, "/Applications")
                    || PathSafety.within(path, PathSafety.home + "/Applications"),
                URL(fileURLWithPath: path).pathExtension == "app",
                Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier == app.bundleID,
                (item.eligible && item.confidence == "high") || (advanced && item.status == "AMBER")
            else {
                return "Installed bundle identity failed verification"
            }
            return nil
        }
        if item.category == "Ollama Models & Configuration" {
            guard app.name.lowercased() == "ollama",
                ["com.electron.ollama", "com.ollama.ollama"].contains(app.bundleID.lowercased()),
                path == PathSafety.home + "/.ollama", item.cleanup == "data",
                item.confidence == "high", item.eligible
            else {
                return "Ollama model store identity failed verification"
            }
            return nil
        }
        guard let root = appLibraryRoot(item.category), PathSafety.directChild(path, root) else {
            return "Associated file is outside approved per-app Library directories"
        }
        let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        let bundle = app.bundleID.lowercased()
        let appName = app.name.lowercased()
        let matches =
            filename == bundle || filename == appName || filename == bundle + ".plist"
            || filename == bundle + ".savedstate" || filename.hasPrefix(bundle + ".")
        let knownOllama =
            app.name.lowercased() == "ollama"
            && ["com.electron.ollama", "com.ollama.ollama"].contains(bundle)
            && Set([
                "ollama", "com.electron.ollama", "com.electron.ollama.plist",
                "com.electron.ollama.savedstate",
            ]).contains(filename)
        guard matches || knownOllama else { return "File name no longer matches selected app" }
        if !advanced {
            guard item.eligible, item.confidence == "high", item.status == "GREEN" else {
                return "Not verified as app-owned in Standard Mode"
            }
        }
        return nil
    }

    static func moveToTrash(
        items: [ScanEntry], app: ScanEntry?, action: CleanupAction,
        advanced: Bool, includeAppData: Bool = false,
        shouldCancel: () -> Bool = { false }
    ) -> TrashReport {
        if let app, isRunning(app) {
            return TrashReport(
                outcomes: items.map {
                    TrashOutcome(
                        originalPath: $0.path, resultingPath: nil, sizeBytes: $0.sizeBytes,
                        status: "skipped", message: "Quit the selected application first")
                })
        }
        let label = app?.name ?? (action == .developer ? "Developer Tools & Models" : "Storage Cleanup")
        var session = HistorySession(
            appName: label, bundleID: app?.bundleID ?? "",
            action: action.rawValue, items: [])
        guard HistoryStore.shared.append(session) else {
            return TrashReport(
                outcomes: items.map {
                    TrashOutcome(
                        originalPath: $0.path, resultingPath: nil, sizeBytes: $0.sizeBytes,
                        status: "failed", message: "Cannot create recovery manifest; no files moved")
                })
        }
        var outcomes: [TrashOutcome] = []
        var previous: [String] = []
        for item in items.sorted(by: { $0.path.count < $1.path.count }) {
            var outcome: TrashOutcome
            if shouldCancel() {
                outcome = TrashOutcome(
                    originalPath: item.path, resultingPath: nil,
                    sizeBytes: item.sizeBytes, status: "skipped", message: "Canceled")
            } else if previous.contains(where: { item.path == $0 || PathSafety.within(item.path, $0) }) {
                outcome = TrashOutcome(
                    originalPath: item.path, resultingPath: nil,
                    sizeBytes: item.sizeBytes, status: "skipped", message: "Covered by selected parent")
            } else if let problem = validate(
                item, app: app, action: action, advanced: advanced, includeAppData: includeAppData)
            {
                outcome = TrashOutcome(
                    originalPath: item.path, resultingPath: nil,
                    sizeBytes: item.sizeBytes, status: "skipped", message: problem)
            } else {
                do {
                    var resultingURL: NSURL?
                    try fm.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: &resultingURL)
                    outcome = TrashOutcome(
                        originalPath: item.path, resultingPath: resultingURL?.path,
                        sizeBytes: item.sizeBytes, status: "moved", message: "Moved to macOS Trash")
                    previous.append(item.path)
                } catch {
                    outcome = TrashOutcome(
                        originalPath: item.path, resultingPath: nil,
                        sizeBytes: item.sizeBytes, status: "failed", message: error.localizedDescription)
                }
            }
            outcomes.append(outcome)
            let trashStat = outcome.resultingPath.flatMap { PathSafety.fileStat($0) }
            session.items.append(
                HistoryItem(
                    originalPath: item.path, trashPath: outcome.resultingPath,
                    bytes: item.sizeBytes, device: item.device, inode: item.inode,
                    status: outcome.status, message: outcome.message, restoredAt: nil,
                    trashDevice: trashStat.map { UInt64($0.st_dev) },
                    trashInode: trashStat.map { UInt64($0.st_ino) }, risk: item.status))
            // Persist each outcome before beginning the next operation.
            if !HistoryStore.shared.update(session) {
                outcomes.append(
                    TrashOutcome(
                        originalPath: item.path, resultingPath: nil,
                        sizeBytes: nil, status: "failed",
                        message: "Could not persist recovery metadata; further moves halted"))
                break
            }
        }
        return TrashReport(outcomes: outcomes)
    }

    private static func newName(_ source: String) -> String {
        let url = URL(fileURLWithPath: source)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for counter in 1...1000 {
            let suffix = " (restored \(counter))"
            let filename = base + suffix + (ext.isEmpty ? "" : "." + ext)
            let candidate = url.deletingLastPathComponent().appendingPathComponent(filename).path
            if !fm.fileExists(atPath: candidate) { return candidate }
        }
        return ""
    }

    static func restore(sessionID: UUID, selectedIDs: Set<UUID>, conflict: RestoreConflict) -> RestoreResult {
        guard var session = HistoryStore.shared.read().first(where: { $0.id == sessionID }) else {
            return RestoreResult(
                messages: ["History entry no longer exists"], restored: 0, skipped: 0, failed: 1)
        }
        var result = RestoreResult(messages: [], restored: 0, skipped: 0, failed: 0)
        for index in session.items.indices where selectedIDs.contains(session.items[index].id) {
            let item = session.items[index]
            guard item.status == "moved", item.restoredAt == nil, let trashPath = item.trashPath,
                let st = PathSafety.fileStat(trashPath),
                item.trashDevice == UInt64(st.st_dev), item.trashInode == UInt64(st.st_ino),
                !PathSafety.hasSymlinkComponent(trashPath),
                !PathSafety.forbidden(item.originalPath),
                !PathSafety.hasSymlinkComponent(
                    URL(fileURLWithPath: item.originalPath).deletingLastPathComponent().path)
            else {
                result.skipped += 1
                result.messages.append("Unavailable or unsafe: \(item.originalPath)")
                continue
            }
            let original = URL(fileURLWithPath: item.originalPath)
            var destination = original
            if fm.fileExists(atPath: original.path) {
                switch conflict {
                case .skip:
                    result.skipped += 1
                    result.messages.append("Already exists: \(original.path)")
                    continue
                case .rename:
                    let path = newName(original.path)
                    guard !path.isEmpty else {
                        result.failed += 1
                        result.messages.append("Could not find unused name: \(original.path)")
                        continue
                    }
                    destination = URL(fileURLWithPath: path)
                case .replace:
                    guard let prior = PathSafety.fileStat(original.path),
                        prior.st_uid == getuid(),
                        !PathSafety.hasSymlinkComponent(original.path)
                    else {
                        result.failed += 1
                        result.messages.append("Existing destination is not safely movable: \(original.path)")
                        continue
                    }
                    var backup = HistorySession(
                        appName: session.appName, bundleID: session.bundleID,
                        action: "restore-conflict-backup", items: [])
                    guard HistoryStore.shared.append(backup) else {
                        result.failed += 1
                        result.messages.append("Cannot record replace backup")
                        continue
                    }
                    do {
                        var backupURL: NSURL?
                        try fm.trashItem(at: original, resultingItemURL: &backupURL)
                        let backupStat = backupURL?.path.flatMap { PathSafety.fileStat($0) }
                        backup.items.append(
                            HistoryItem(
                                originalPath: original.path, trashPath: backupURL?.path,
                                bytes: nil, device: UInt64(prior.st_dev), inode: UInt64(prior.st_ino),
                                status: "moved", message: "Backed up before replacement", restoredAt: nil,
                                trashDevice: backupStat.map { UInt64($0.st_dev) },
                                trashInode: backupStat.map { UInt64($0.st_ino) }, risk: "AMBER"))
                        guard HistoryStore.shared.update(backup) else {
                            result.failed += 1
                            result.messages.append(
                                "Backup moved but its metadata could not be saved; restore halted")
                            continue
                        }
                    } catch {
                        result.failed += 1
                        result.messages.append("Cannot back up existing file: \(error.localizedDescription)")
                        continue
                    }
                }
            }
            do {
                guard !fm.fileExists(atPath: destination.path),
                    fm.fileExists(atPath: destination.deletingLastPathComponent().path)
                else {
                    throw NSError(
                        domain: "StorageKit", code: 14,
                        userInfo: [NSLocalizedDescriptionKey: "Destination missing or already occupied"])
                }
                try fm.moveItem(at: URL(fileURLWithPath: trashPath), to: destination)
                session.items[index].restoredAt = Date()
                if !HistoryStore.shared.update(session) {
                    result.messages.append(
                        "Restored, but could not persist updated recovery status: \(destination.path)")
                }
                result.restored += 1
                result.messages.append("Restored: \(destination.path)")
            } catch {
                result.failed += 1
                result.messages.append("Restore failed: \(item.originalPath): \(error.localizedDescription)")
            }
        }
        return result
    }
}
