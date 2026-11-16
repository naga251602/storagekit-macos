import AppKit
import Combine
import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

/// Sparkle is enabled only for builds with a configured framework, a verified
/// HTTPS appcast and a public EdDSA key. Development builds are intentionally
/// limited to opening the GitHub Releases page.
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()
    #if canImport(Sparkle)
    private let controller: SPUStandardUpdaterController?
    #endif
    let isConfigured: Bool
    @Published var automaticChecks = false
    @Published var automaticInstalls = false

    private init() {
        #if canImport(Sparkle)
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        if feed.hasPrefix("https://"), !key.isEmpty {
            let active = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            controller = active
            isConfigured = true
            automaticChecks = active.updater.automaticallyChecksForUpdates
            automaticInstalls = active.updater.automaticallyDownloadsUpdates
        } else {
            controller = nil
            isConfigured = false
        }
        #else
        isConfigured = false
        #endif
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
        if let controller {
            controller.checkForUpdates(nil)
            return
        }
        #endif
        NSWorkspace.shared.open(StorageKitLinks.releases)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        #if canImport(Sparkle)
        controller?.updater.automaticallyChecksForUpdates = enabled
        automaticChecks = controller?.updater.automaticallyChecksForUpdates ?? false
        #endif
    }

    func setAutomaticInstalls(_ enabled: Bool) {
        #if canImport(Sparkle)
        controller?.updater.automaticallyDownloadsUpdates = enabled
        automaticInstalls = controller?.updater.automaticallyDownloadsUpdates ?? false
        #endif
    }
}
