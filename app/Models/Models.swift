import AppKit
import Foundation
import SwiftUI

enum BrowserPage: String, CaseIterable, Identifiable {
    case applications = "Applications"
    case storage = "Storage Cleanup"
    case developer = "Developer Tools & Models"
    case recent = "Recently Deleted"
    case settings = "Settings"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .applications: return "app"
        case .storage: return "internaldrive"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .recent: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

enum SelectionMode: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case advanced = "Advanced"
    var id: String { rawValue }
}

struct ScanEntry: Identifiable, Hashable, Decodable {
    let type: String
    let id: String
    let name: String
    let path: String
    let category: String
    let status: String
    let confidence: String
    let reason: String
    let cleanup: String
    let bundleID: String
    let eligible: Bool
    let sizeBytes: UInt64?
    let fileCount: UInt64?
    let device: UInt64
    let inode: UInt64
    let mtime: Int64

    enum CodingKeys: String, CodingKey {
        case type, id, name, path, category, status, confidence, reason, cleanup, eligible
        case bundleID = "bundle_id"
        case sizeBytes = "size_bytes"
        case fileCount = "file_count"
        case device = "dev"
        case inode
        case mtime = "mtime_sec"
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var color: Color {
        switch status {
        case "GREEN": return .green
        case "AMBER": return .orange
        case "RED": return .red
        default: return .gray
        }
    }
    var sizeLabel: String {
        guard let bytes = sizeBytes else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }
    var isRisky: Bool { status == "GREY" || status == "AMBER" }
    var isProtected: Bool { status == "RED" }
    var isManagerControlled: Bool { cleanup == "none" }
    var isSelectableInAdvanced: Bool {
        !isProtected && !isManagerControlled && (eligible || isRisky)
    }
}

enum CleanupAction: String, Identifiable {
    case cache, reset, uninstall, storage, developer
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cache: return "Clear Cache"
        case .reset: return "Reset App Data"
        case .uninstall: return "Uninstall"
        case .storage: return "Storage Cleanup"
        case .developer: return "Developer Tools & Models"
        }
    }
    var warning: String {
        switch self {
        case .cache:
            return
                "Cache files may be recreated. For Apple apps, only explicitly checked user Library caches in Advanced Mode can be moved. Close the app before cleanup."
        case .reset:
            return
                "Reset may remove passwords, settings, offline or iCloud-synced data and unsynced work. Apple app resets require Advanced Mode and manual selection. The application remains installed."
        case .uninstall:
            return
                "The application bundle will be moved to macOS Trash. Additional app data is optional and must be explicitly selected."
        case .storage:
            return
                "Review each path carefully. Build artifacts, logs and downloads may still be needed. Managed caches are inventory-only."
        case .developer:
            return
                "Selected runtime versions, caches and model stores may be shared by projects. Trashing them can break tools or remove downloaded models. Homebrew packages and individual Ollama manifests remain manager-only."
        }
    }
    func permits(_ entry: ScanEntry) -> Bool {
        guard entry.cleanup != "none" else { return false }
        switch self {
        case .cache: return entry.cleanup == "cache" && entry.category == "Caches"
        case .reset: return entry.cleanup == "cache" || entry.cleanup == "data"
        case .uninstall: return ["cache", "data", "app"].contains(entry.cleanup)
        case .storage:
            return entry.type == "storage" && (entry.cleanup == "cache" || entry.cleanup == "manual")
        case .developer:
            return entry.type == "inventory" && entry.cleanup == "developer"
        }
    }
}

struct TrashOutcome: Identifiable {
    let id = UUID()
    let originalPath: String
    let resultingPath: String?
    let sizeBytes: UInt64?
    let status: String
    let message: String
}

struct TrashReport {
    let outcomes: [TrashOutcome]
    var movedCount: Int { outcomes.filter { $0.status == "moved" }.count }
    var skippedCount: Int { outcomes.filter { $0.status == "skipped" }.count }
    var failedCount: Int { outcomes.filter { $0.status == "failed" }.count }
    var estimatedMovedBytes: UInt64 {
        outcomes.filter { $0.status == "moved" }.compactMap(\.sizeBytes).reduce(0, +)
    }
}

struct HistoryItem: Codable, Identifiable {
    var id: UUID = UUID()
    var originalPath: String
    var trashPath: String?
    var bytes: UInt64?
    var device: UInt64
    var inode: UInt64
    var status: String
    var message: String
    var restoredAt: Date?
    var trashDevice: UInt64?
    var trashInode: UInt64?
    var risk: String

    var recoverable: Bool {
        guard status == "moved", restoredAt == nil, let trashPath,
            let file = PathSafety.fileStat(trashPath),
            trashDevice == UInt64(file.st_dev), trashInode == UInt64(file.st_ino),
            !PathSafety.hasSymlinkComponent(trashPath)
        else { return false }
        return true
    }
}

struct HistorySession: Codable, Identifiable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var appName: String
    var bundleID: String
    var action: String
    var productVersion: String = "5.4"
    var items: [HistoryItem]
    var fullyRestored: Bool {
        let moved = items.filter { $0.status == "moved" }
        return !moved.isEmpty && moved.allSatisfy { $0.restoredAt != nil }
    }
    var recoveryStatus: String {
        let moved = items.filter { $0.status == "moved" }
        if moved.isEmpty { return "No moved items" }
        let outstanding = moved.filter { $0.restoredAt == nil }
        if outstanding.isEmpty { return "Restored" }
        let recoverable = outstanding.filter(\.recoverable).count
        if recoverable == 0 { return "No longer recoverable" }
        if recoverable < outstanding.count { return "Partially recoverable" }
        return outstanding.count == moved.count ? "Recoverable" : "Partially restored"
    }
}

enum RestoreConflict: String, CaseIterable, Identifiable {
    case skip = "Skip existing"
    case rename = "Restore with new name"
    case replace = "Move existing to Trash, then restore"
    var id: String { rawValue }
}
