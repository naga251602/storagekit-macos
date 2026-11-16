import AppKit
import Foundation
import SwiftUI

@MainActor final class CleanerModel: ObservableObject {
    @Published var page: BrowserPage = .applications
    @Published var apps: [ScanEntry] = []
    @Published var inventory: [ScanEntry] = []
    @Published var candidates: [ScanEntry] = []
    @Published var storageCandidates: [ScanEntry] = []
    @Published var manuallyAdded: [ScanEntry] = []
    @Published var selectedAppID: String?
    @Published var selectedInventoryID: String?
    @Published var search = ""
    @Published var hideProtected = true
    @Published var markedIDs: Set<String> = []
    @Published var markedStorageIDs: Set<String> = []
    @Published var markedDeveloperIDs: Set<String> = []
    @Published var reviewSelection: Set<String> = []
    @Published var uninstallIncludesData = false
    @Published var reviewAction: CleanupAction?
    @Published var acknowledgedRisk = false
    @Published var report: TrashReport?
    @Published var sessions: [HistorySession] = []
    @Published var selectedSessionID: UUID?
    @Published var restoring = false
    @Published var confirmReplace = false
    @Published var selectedStorageID: String?
    @Published var restoreReport: RestoreResult?
    @Published var restoreSelection: Set<UUID> = []
    @Published var restoreConflict: RestoreConflict = .skip
    @Published var busy = false
    @Published var detailBusy = false
    @Published var operationBusy = false
    private let cancellation = CancellationFlag()
    @Published var error = ""

    let settings = SettingsStore.shared
    private var activeProcess: Process?
    private var generation = 0
    private var lastScannedAppID: String?
    private let executable = Bundle.main.resourceURL?.appendingPathComponent("storagekit-scanner").path ?? ""

    var selectedApp: ScanEntry? { apps.first { $0.id == selectedAppID } }
    var selectedInventory: ScanEntry? { inventory.first { $0.id == selectedInventoryID } }
    var selectedSession: HistorySession? { sessions.first { $0.id == selectedSessionID } }
    var activeCandidates: [ScanEntry] { page == .storage ? storageCandidates : candidates }
    var filteredApps: [ScanEntry] {
        apps.filter {
            (!hideProtected
                || ($0.status != "RED" && !$0.bundleID.lowercased().hasPrefix("com.apple.")
                    && $0.bundleID.lowercased() != "com.apple"))
                && (search.isEmpty
                    || "\($0.name) \($0.path) \($0.bundleID)".localizedCaseInsensitiveContains(search))
        }
    }
    var filteredInventory: [ScanEntry] {
        inventory.filter {
            search.isEmpty || "\($0.name) \($0.path) \($0.category)".localizedCaseInsensitiveContains(search)
        }
    }
    var filteredStorage: [ScanEntry] {
        storageCandidates.filter {
            search.isEmpty || "\($0.name) \($0.path) \($0.category)".localizedCaseInsensitiveContains(search)
        }
    }

    nonisolated private static func parse(_ text: String) throws -> [ScanEntry] {
        let decoder = JSONDecoder()
        return try text.split(separator: "\n").map { try decoder.decode(ScanEntry.self, from: Data($0.utf8)) }
    }

    func cancelScan() {
        generation += 1
        if let process = activeProcess, process.isRunning { process.terminate() }
        activeProcess = nil
        busy = false
        detailBusy = false
    }

    private func execute(
        _ args: [String], isDetail: Bool,
        then completion: @escaping (Result<[ScanEntry], Error>) -> Void
    ) {
        cancelScan()
        let requestID = generation
        if isDetail { detailBusy = true } else { busy = true }
        error = ""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args + ["--jsonl"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        activeProcess = process
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<[ScanEntry], Error>
            do {
                try process.run()
                let output = stdout.fileHandleForReading.readDataToEndOfFile()
                let errors = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    result = .success(try Self.parse(String(decoding: output, as: UTF8.self)))
                } else {
                    let message = String(decoding: errors, as: UTF8.self)
                    result = .failure(
                        NSError(
                            domain: "StorageKit Scanner", code: Int(process.terminationStatus),
                            userInfo: [
                                NSLocalizedDescriptionKey: message.isEmpty ? "Scanner failed" : message
                            ]))
                }
            } catch { result = .failure(error) }
            DispatchQueue.main.async {
                guard self.generation == requestID else { return }
                self.activeProcess = nil
                self.busy = false
                self.detailBusy = false
                completion(result)
            }
        }
    }

    func navigate(_ destination: BrowserPage) {
        guard !operationBusy && !restoring else { return }
        cancelScan()
        page = destination
        search = ""
        error = ""
        switch destination {
        case .applications: loadApps()
        case .storage: loadStorage()
        case .developer: loadInventory()
        case .recent: refreshHistory()
        case .settings: break
        }
    }

    func refreshCurrent() {
        guard !operationBusy else { return }
        switch page {
        case .applications: loadApps()
        case .storage: loadStorage()
        case .developer: loadInventory()
        case .recent: refreshHistory()
        case .settings: break
        }
    }

    func loadApps() {
        let prior = selectedAppID
        // System apps are an opt-in scan to avoid unnecessary enumeration.
        let arguments = hideProtected ? ["list"] : ["list", "--include-apple"]
        execute(arguments, isDetail: false) { result in
            switch result {
            case .success(let apps):
                self.apps = apps
                self.selectedAppID = apps.contains(where: { $0.id == prior }) ? prior : nil
                if self.page == .applications, self.selectedApp != nil { self.scanSelectedApp() }
            case .failure(let error): self.error = error.localizedDescription
            }
        }
    }
    func loadInventory() {
        execute(["inventory", "--sizes"], isDetail: false) { result in
            switch result {
            case .success(let data):
                self.inventory = data
                self.selectedInventoryID =
                    data.contains(where: { $0.id == self.selectedInventoryID })
                    ? self.selectedInventoryID : nil
                // Inventory scans never auto-select destructive candidates.
                self.markedDeveloperIDs = []
            case .failure(let error): self.error = error.localizedDescription
            }
        }
    }
    func loadStorage() {
        execute(["storage", "--sizes"], isDetail: false) { result in
            switch result {
            case .success(let data):
                let folderEntries = ManualSelectionService.children(of: self.settings.reviewFolders)
                var seen = Set<String>()
                self.storageCandidates = (data + self.manuallyAdded + folderEntries).filter {
                    seen.insert($0.path).inserted
                }
                self.selectedStorageID =
                    self.storageCandidates.contains(where: { $0.id == self.selectedStorageID })
                    ? self.selectedStorageID : nil
                // Fresh discovery doesn't auto-select manually reviewed paths.
                self.markedStorageIDs = Set(
                    self.storageCandidates.filter { $0.eligible && $0.status == "GREEN" }.map(\.id))
            case .failure(let error): self.error = error.localizedDescription
            }
        }
    }
    func scanSelectedApp() {
        guard let app = selectedApp else {
            candidates = []
            markedIDs = []
            lastScannedAppID = nil
            cancelScan()
            return
        }
        let sameApp = lastScannedAppID == app.id
        let previousIDs = sameApp ? Set(candidates.map(\.id)) : []
        let previousMarked = sameApp ? markedIDs : []
        candidates = []
        markedIDs = []
        lastScannedAppID = app.id
        let apple = app.bundleID.lowercased().hasPrefix("com.apple.")
        let arguments = ["scan", "--path", app.path, "--sizes"] + (apple ? ["--include-apple"] : [])
        execute(arguments, isDetail: true) { result in
            guard self.selectedAppID == app.id else { return }
            switch result {
            case .success(let rows):
                self.candidates = rows
                self.markedIDs = Set(
                    rows.filter { entry in
                        guard entry.eligible && entry.status == "GREEN" else { return false }
                        return previousIDs.contains(entry.id) ? previousMarked.contains(entry.id) : true
                    }.map(\.id))
            case .failure(let error): self.error = error.localizedDescription
            }
        }
    }

    func addManualChoices() {
        let urls = ManualSelectionService.chooseFilesAndFolders()
        guard !urls.isEmpty else { return }
        var added = 0
        for url in urls {
            if let entry = ManualSelectionService.reviewEntry(url),
                !storageCandidates.contains(where: { $0.path == entry.path })
            {
                storageCandidates.append(entry)
                manuallyAdded.append(entry)
                added += 1
            }
        }
        if added == 0 {
            error =
                "No new eligible user-owned paths were added. Protected paths, app bundles and symlinks cannot be selected here."
        } else {
            error = ""
        }
    }

    func canSelect(_ entry: ScanEntry) -> Bool {
        guard !entry.isProtected && !entry.isManagerControlled && entry.device != 0 && entry.inode != 0,
            !entry.reason.contains("symlink path blocked")
        else { return false }
        // Apple system app bundles are never removable. In Advanced Mode only
        // exact-ID, user Library app data is selectable; block name guesses,
        // shared groups and system-wide support before opening the review sheet.
        if entry.type == "candidate", let app = selectedApp,
            app.bundleID.lowercased().hasPrefix("com.apple.")
        {
            let categories = Set([
                "Caches", "Application Support", "Preferences", "Containers",
                "Logs", "Saved Application State", "HTTPStorages", "WebKit",
            ])
            return settings.mode == .advanced && entry.bundleID == app.bundleID
                && entry.cleanup != "app" && entry.status == "AMBER"
                && entry.confidence == "review" && categories.contains(entry.category)
                && entry.reason.hasPrefix("Apple app user Library data;")
        }
        if entry.type == "inventory" {
            // Only explicitly reviewable user-owned roots can be selected.
            // TrashService revalidates these against its strict location allowlist.
            return entry.cleanup == "developer" && entry.isRisky
        }
        if entry.category == "User Selected" {
            return entry.cleanup == "manual" && ManualSelectionService.approved(entry.path)
        }
        if entry.eligible && entry.status == "GREEN" { return true }
        return settings.mode == .advanced && entry.isRisky
    }

    func marked(_ item: ScanEntry) -> Bool {
        switch page {
        case .storage: return markedStorageIDs.contains(item.id)
        case .developer: return markedDeveloperIDs.contains(item.id)
        default: return markedIDs.contains(item.id)
        }
    }
    func toggle(_ entry: ScanEntry, enabled: Bool) {
        guard canSelect(entry) else { return }
        if page == .storage {
            if enabled { markedStorageIDs.insert(entry.id) } else { markedStorageIDs.remove(entry.id) }
        } else if page == .developer {
            if enabled { markedDeveloperIDs.insert(entry.id) } else { markedDeveloperIDs.remove(entry.id) }
        } else {
            if enabled { markedIDs.insert(entry.id) } else { markedIDs.remove(entry.id) }
        }
    }

    func sourceEntries(for action: CleanupAction) -> [ScanEntry] {
        switch action {
        case .storage: return storageCandidates
        case .developer: return inventory
        default: return candidates
        }
    }

    private func selectedIDs(for action: CleanupAction) -> Set<String> {
        switch action {
        case .storage: return markedStorageIDs
        case .developer: return markedDeveloperIDs
        default: return markedIDs
        }
    }

    func prepareSelectedDeveloperItem() {
        guard let item = selectedInventory, canSelect(item), !busy, !operationBusy else { return }
        markedDeveloperIDs = [item.id]
        prepare(.developer)
    }

    func canPrepare(_ action: CleanupAction) -> Bool {
        guard !busy, !detailBusy, !operationBusy, !restoring,
            [.storage, .developer].contains(action) || selectedApp != nil
        else { return false }
        if action == .uninstall {
            guard let app = selectedApp, !app.bundleID.isEmpty, app.status != "RED",
                !app.bundleID.lowercased().hasPrefix("com.apple.")
            else {
                return false
            }
            // Uninstall must remain available even if the user deselected the app
            // bundle in the main file inspector. That bundle is mandatory here.
            return candidates.contains {
                $0.cleanup == "app" && $0.path == selectedApp?.path
                    && canSelect($0) && action.permits($0)
            }
        }
        let marked = selectedIDs(for: action)
        return sourceEntries(for: action).contains {
            marked.contains($0.id) && canSelect($0) && action.permits($0)
        }
    }
    func prepare(_ action: CleanupAction) {
        guard canPrepare(action) else { return }
        let marked = selectedIDs(for: action)
        let candidates = sourceEntries(for: action)
        uninstallIncludesData = false
        if action == .uninstall {
            // The first review shows ONLY the installed app, never its data.
            reviewSelection = Set(
                candidates.filter {
                    $0.cleanup == "app" && $0.path == selectedApp?.path
                        && canSelect($0) && action.permits($0)
                }.map(\.id))
        } else {
            reviewSelection = Set(
                candidates.filter { marked.contains($0.id) && canSelect($0) && action.permits($0) }.map(\.id))
        }
        acknowledgedRisk = false
        report = nil
        error = ""
        reviewAction = action
    }
    func setUninstallIncludesData(_ included: Bool) {
        guard reviewAction == .uninstall, !operationBusy else { return }
        uninstallIncludesData = included
        // Always retain the required application bundle. Changing the checkbox
        // cannot accidentally include files that the user did not opt into.
        let bundleIDs = Set(
            candidates.filter {
                $0.cleanup == "app" && $0.path == selectedApp?.path && canSelect($0)
            }.map(\.id))
        if included {
            let eligibleDataIDs = Set(
                candidates.filter {
                    $0.cleanup != "app" && markedIDs.contains($0.id)
                        && canSelect($0) && CleanupAction.uninstall.permits($0)
                }.map(\.id))
            reviewSelection = bundleIDs.union(eligibleDataIDs)
        } else {
            reviewSelection = bundleIDs
        }
        acknowledgedRisk = false
    }

    func approved(_ action: CleanupAction) -> [ScanEntry] {
        let source = sourceEntries(for: action)
        return source.filter {
            reviewSelection.contains($0.id) && canSelect($0) && action.permits($0)
                && (action != .uninstall || uninstallIncludesData || $0.cleanup == "app")
        }.sorted { $0.path < $1.path }
    }
    var riskSelected: Bool {
        guard let action = reviewAction else { return false }
        return approved(action).contains {
            $0.isRisky || $0.category == "Ollama Models & Configuration" || action == .developer
        }
    }
    func confirmMove() {
        guard let action = reviewAction, !operationBusy, !busy, !detailBusy else { return }
        let chosen = approved(action)
        guard !chosen.isEmpty, !chosen.contains(where: \.isRisky) || acknowledgedRisk else { return }
        if action == .uninstall {
            // Defense in depth: never run "Uninstall" without the app bundle.
            guard chosen.contains(where: { $0.cleanup == "app" && $0.path == selectedApp?.path })
            else { return }
        }
        let app = [.storage, .developer].contains(action) ? nil : selectedApp
        if let app, TrashService.isRunning(app) {
            error = "\(app.name) is running. Quit it and retry."
            return
        }
        operationBusy = true
        cancellation.reset()
        error = ""
        let advanced = settings.mode == .advanced
        let includeAppData = action == .uninstall && uninstallIncludesData
        let cancellationToken = cancellation
        DispatchQueue.global(qos: .userInitiated).async {
            let report = TrashService.moveToTrash(
                items: chosen, app: app, action: action, advanced: advanced,
                includeAppData: includeAppData,
                shouldCancel: { cancellationToken.isCanceled })
            DispatchQueue.main.async {
                self.report = report
                self.operationBusy = false
                self.refreshHistory()
            }
        }
    }
    func cancelOperation() { cancellation.cancel() }

    func closeReview() {
        reviewAction = nil
        uninstallIncludesData = false
        report = nil
        refreshCurrent()
    }
    func refreshHistory() {
        sessions = HistoryStore.shared.read()
        if !sessions.contains(where: { $0.id == selectedSessionID }) {
            selectedSessionID = sessions.first?.id
        }
        if let session = selectedSession {
            restoreSelection = Set(
                session.items.filter { $0.status == "moved" && $0.restoredAt == nil }.map(\.id))
        }
    }
    func selectSession(_ id: UUID?) {
        selectedSessionID = id
        if let session = selectedSession {
            restoreSelection = Set(
                session.items.filter { $0.status == "moved" && $0.restoredAt == nil }.map(\.id))
        } else {
            restoreSelection = []
        }
    }

    func restoreSelected() {
        guard !restoring, let session = selectedSession, !restoreSelection.isEmpty else { return }
        restoring = true
        restoreReport = nil
        let ids = restoreSelection
        let conflict = restoreConflict
        DispatchQueue.global(qos: .userInitiated).async {
            let result = TrashService.restore(sessionID: session.id, selectedIDs: ids, conflict: conflict)
            DispatchQueue.main.async {
                self.restoring = false
                self.restoreReport = result
                self.refreshHistory()
            }
        }
    }
}

final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func reset() {
        lock.lock()
        value = false
        lock.unlock()
    }
    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
    var isCanceled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
