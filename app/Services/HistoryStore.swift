import Foundation

/// Metadata only. Contents remain in macOS Trash, never in this directory.
final class HistoryStore {
    static let shared = HistoryStore()
    private let lock = NSLock()
    private let fm = FileManager.default
    private let url: URL

    private init() {
        let directory = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/StorageKit", isDirectory: true)
        try? fm.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        url = directory.appendingPathComponent("history-v1.json")
    }

    func read() -> [HistorySession] {
        lock.lock()
        defer { lock.unlock() }
        return (readUnlocked() ?? []).filter {
            !$0.fullyRestored && $0.items.contains { $0.status == "moved" }
        }
    }

    @discardableResult func append(_ session: HistorySession) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var sessions = readUnlocked() else { return false }
        sessions.insert(session, at: 0)
        return writeUnlocked(sessions)
    }

    @discardableResult func update(_ session: HistorySession) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var sessions = readUnlocked() else { return false }
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return false }
        if session.fullyRestored {
            sessions.remove(at: index)
        } else {
            sessions[index] = session
        }
        return writeUnlocked(sessions)
    }

    @discardableResult func clearMetadata() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return writeUnlocked([])
    }

    private func readUnlocked() -> [HistorySession]? {
        guard fm.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([HistorySession].self, from: data)
    }

    private func writeUnlocked(_ sessions: [HistorySession]) -> Bool {
        guard let bytes = try? JSONEncoder().encode(sessions) else { return false }
        do {
            try bytes.write(to: url, options: [.atomic])
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch { return false }
    }
}
