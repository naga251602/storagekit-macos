import AppKit
import Combine
import Darwin
import Foundation

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    @Published var mode: SelectionMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "selectionMode") }
    }
    @Published var githubRepository: String {
        didSet { UserDefaults.standard.set(githubRepository, forKey: "githubRepository") }
    }
    @Published var setupCompleted: Bool {
        didSet { UserDefaults.standard.set(setupCompleted, forKey: "setupCompleted.v3") }
    }
    @Published var reviewFolders: [String] {
        didSet { UserDefaults.standard.set(reviewFolders, forKey: "reviewFolders.v2") }
    }
    func addReviewFolders(_ paths: [String]) {
        for path in paths where !PathSafety.forbidden(path) && !PathSafety.hasSymlinkComponent(path) {
            guard let st = PathSafety.fileStat(path), st.st_uid == getuid(),
                st.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
            else { continue }
            if !reviewFolders.contains(path) { reviewFolders.append(path) }
        }
    }
    func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }
    init() {
        setupCompleted = UserDefaults.standard.bool(forKey: "setupCompleted.v3")
        reviewFolders = UserDefaults.standard.stringArray(forKey: "reviewFolders.v2") ?? []
        mode =
            SelectionMode(rawValue: UserDefaults.standard.string(forKey: "selectionMode") ?? "") ?? .standard
        githubRepository = UserDefaults.standard.string(forKey: "githubRepository") ?? ""
    }
    var validatedRepository: URL? {
        guard let url = URL(string: githubRepository.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme == "https", url.host?.lowercased() == "github.com",
            url.pathComponents.filter({ $0 != "/" }).count == 2,
            url.query == nil, url.fragment == nil
        else { return nil }
        return url
    }
    func link(_ kind: String) -> URL? {
        guard let repository = validatedRepository else { return nil }
        let path: String
        switch kind {
        case "bug": path = "issues/new?template=bug_report.yml"
        case "feature": path = "issues/new?template=feature_request.yml"
        case "github": return repository
        default: return nil
        }
        return URL(
            string: repository.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
                + path)
    }
}
