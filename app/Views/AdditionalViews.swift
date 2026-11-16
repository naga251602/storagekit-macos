import AppKit
import Foundation
import SwiftUI

private final class HistoryViewState: ObservableObject {
    @Published var confirmClear = false
}

struct RecentlyDeletedView: View {
    @ObservedObject var model: CleanerModel
    @StateObject private var viewState = HistoryViewState()
    private var session: HistorySession? { model.selectedSession }

    var body: some View {
        VStack(spacing: 0) {
            if let session {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.appName).font(.title2.bold())
                            Text(
                                "\(session.action) · \(session.timestamp.formatted(date: .abbreviated, time: .standard))"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(session.recoveryStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(
                        "StorageKit tracks files it moved to macOS Trash. This is not a second copy of your files."
                    )
                    .font(.callout).foregroundStyle(.secondary)
                    Divider()
                    List(session.items) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { model.restoreSelection.contains(item.id) },
                                    set: { checked in
                                        if checked {
                                            model.restoreSelection.insert(item.id)
                                        } else {
                                            model.restoreSelection.remove(item.id)
                                        }
                                    }
                                )
                            )
                            .toggleStyle(.checkbox).labelsHidden()
                            .disabled(
                                item.status != "moved" || item.restoredAt != nil || item.trashPath == nil
                                    || !FileManager.default.fileExists(atPath: item.trashPath ?? ""))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.originalPath).font(.caption.monospaced()).textSelection(.enabled)
                                Text(
                                    "\(item.status) · \(item.bytes.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .file) } ?? "Unknown size") · \(item.risk)"
                                )
                                .font(.caption2).foregroundStyle(.secondary)
                                if let trash = item.trashPath {
                                    Text("Trash: \(trash)").font(.caption2.monospaced())
                                        .foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                if item.restoredAt != nil {
                                    Label("Restored", systemImage: "checkmark.circle").foregroundStyle(.green)
                                } else if item.status == "moved"
                                    && !FileManager.default.fileExists(atPath: item.trashPath ?? "")
                                {
                                    Label("No longer recoverable", systemImage: "exclamationmark.circle")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        Picker("If an original path exists", selection: $model.restoreConflict) {
                            ForEach(RestoreConflict.allCases) { option in Text(option.rawValue).tag(option) }
                        }
                        .pickerStyle(.menu)
                        Text(
                            "Replace first moves the existing destination to Trash and creates its own recovery session. No silent overwrites."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        if let report = model.restoreReport {
                            Text(
                                "\(report.restored) restored · \(report.skipped) skipped · \(report.failed) failed"
                            )
                            .font(.headline)
                            ScrollView {
                                ForEach(report.messages, id: \.self) { message in
                                    Text(message).font(.caption).textSelection(.enabled)
                                }
                            }.frame(maxHeight: 90)
                        }
                        HStack {
                            Button("Open Trash") {
                                NSWorkspace.shared.open(
                                    FileManager.default.homeDirectoryForCurrentUser
                                        .appendingPathComponent(".Trash", isDirectory: true))
                            }
                            Spacer()
                            Button("Restore Selected") {
                                if model.restoreConflict == .replace {
                                    model.confirmReplace = true
                                } else {
                                    model.restoreSelected()
                                }
                            }
                            .disabled(model.restoreSelection.isEmpty || model.restoring)
                            if model.restoring { ProgressView().controlSize(.small) }
                        }
                    }
                }
                .padding(18)
            } else {
                EmptyPanel(
                    title: "Recently Deleted",
                    message: "Cleanup history will appear here. No files are copied or permanently erased.",
                    symbol: "clock.arrow.circlepath")
            }
            Divider()
            HStack {
                Text("Emptying macOS Trash makes items unrecoverable.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear History Only") { viewState.confirmClear = true }
                    .disabled(model.sessions.isEmpty || model.restoring)
                    .alert("Clear cleanup history?", isPresented: $viewState.confirmClear) {
                        Button("Clear Metadata Only", role: .destructive) {
                            if HistoryStore.shared.clearMetadata() {
                                model.refreshHistory()
                            } else {
                                model.error = "Unable to clear history metadata"
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "This removes only StorageKit's recovery records. It does not remove files from macOS Trash, but removes StorageKit's restore shortcuts."
                        )
                    }
            }.padding(12)
        }
        .alert("Replace existing destinations?", isPresented: $model.confirmReplace) {
            Button("Move Existing to Trash and Restore", role: .destructive) { model.restoreSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Every existing destination will be moved to Trash first and recorded as a separate recovery session. If backup fails, restoration is skipped."
            )
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let onOpenPermissions: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings").font(.title2.bold())
                Text("Permissions & Review Folders").font(.headline)
                Text(
                    "macOS controls access. Full Disk Access cannot be granted automatically. Changes may require restarting StorageKit."
                )
                .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Review Access Setup") { onOpenPermissions() }
                    Button("Open Full Disk Access Settings") {
                        settings.openFullDiskAccessSettings()
                    }
                }
                ForEach(settings.reviewFolders, id: \.self) { folder in
                    HStack {
                        Text(folder).font(.caption.monospaced()).textSelection(.enabled)
                        Spacer()
                        Button("Remove") { settings.reviewFolders.removeAll { $0 == folder } }
                    }
                }
                Button("Add Review Folder...") {
                    settings.addReviewFolders(ManualSelectionService.chooseReviewFolders())
                }
                Text(
                    "Only the immediate contents of these folders appear in Storage Cleanup, unselected. A folder choice does not override system privacy protections."
                )
                .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("File Selection Mode").font(.headline)
                Picker("Mode", selection: $settings.mode) {
                    ForEach(SelectionMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }.pickerStyle(.segmented)
                Text(
                    settings.mode == .standard
                        ? "Standard: only exact, verified third-party items can be selected."
                        : "Advanced: manually select unknown or shared user-accessible files. Every risky path requires extra acknowledgement. System paths and symlinks remain blocked."
                )
                .font(.callout).foregroundStyle(.secondary)
                Divider()
                Text("GitHub Feedback").font(.headline)
                TextField("https://github.com/owner/repository", text: $settings.githubRepository)
                    .textFieldStyle(.roundedBorder)
                Text(
                    "Provide the real repository URL after publishing and adding the included GitHub issue forms. No account credentials, filesystem paths or logs are transmitted by StorageKit."
                )
                .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("View Source on GitHub") {
                        NSWorkspace.shared.open(StorageKitLinks.repository)
                    }
                    Button("Download StorageKit") {
                        NSWorkspace.shared.open(StorageKitLinks.releases)
                    }
                }
                HStack {
                    Button("Request Feature") {
                        if let url = settings.link("feature") { NSWorkspace.shared.open(url) }
                    }.disabled(settings.link("feature") == nil)
                    Button("Report Bug") {
                        if let url = settings.link("bug") { NSWorkspace.shared.open(url) }
                    }.disabled(settings.link("bug") == nil)
                }
                Divider()
                Text("Software Updates").font(.headline)
                if UpdateService.shared.isConfigured {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { UpdateService.shared.automaticChecks },
                        set: { UpdateService.shared.setAutomaticChecks($0) }))
                    Toggle("Automatically download and install updates", isOn: Binding(
                        get: { UpdateService.shared.automaticInstalls },
                        set: { UpdateService.shared.setAutomaticInstalls($0) }))
                } else {
                    Text("Automatic updates require a signed release with Sparkle. This development build opens GitHub Releases instead.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Check for Updates…") { UpdateService.shared.checkForUpdates() }
                Divider()
                Text("Privacy & Safety").font(.headline)
                Text(
                    "No telemetry, server uploads, automatic cleanup or permanent deletion. Recovery metadata is stored locally under ~/Library/Application Support/StorageKit with user-only permissions. Shared manager caches are not directly deleted."
                )
                Text(
                    "macOS may deny protected paths without extra authorization. StorageKit never attempts to bypass those protections."
                )
                .font(.caption).foregroundStyle(.secondary)
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The welcome wizard never claims to grant permissions. macOS controls
/// access and the user can revisit this guide from Settings at any time.
private final class SetupFlowState: ObservableObject {
    @Published var step = 0
}

struct PermissionsSetupView: View {
    @ObservedObject var settings: SettingsStore
    let onFinish: () -> Void
    @StateObject private var flow = SetupFlowState()
    private let stages = ["Welcome", "Choose Folders", "Full Disk Access", "Ready"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 30)).foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("StorageKit Setup").font(.title.bold())
                    Text("Know what stays. Control what goes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(flow.step + 1) / 4")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index <= flow.step ? Color.accentColor : Color.secondary.opacity(0.22))
                        .frame(height: 5)
                }
            }
            Text(stages[flow.step]).font(.title2.bold())
            Divider()
            Group {
                switch flow.step {
                case 0: welcomeStep
                case 1: folderStep
                case 2: fullDiskStep
                default: readyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            HStack(spacing: 10) {
                Text("You can change these settings later.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if flow.step > 0 {
                    Button("Back") { flow.step -= 1 }
                        .buttonStyle(.bordered)
                }
                if flow.step > 0 {
                    Button(flow.step == 3 ? "Finish Setup" : "Continue") {
                        if flow.step == 3 { finish() } else { flow.step += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 690, height: 500)
        .interactiveDismissDisabled()
    }

    private func finish() {
        settings.setupCompleted = true
        onFinish()
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome to StorageKit")
                .font(.title3.bold())
            Text("Discover installed apps and their files, inspect developer caches, and move selected items to macOS Trash with a recovery history.")
                .fixedSize(horizontal: false, vertical: true)
            Label("Files are never removed just by enabling review folders", systemImage: "checkmark.shield")
            Label("Cleanup always requires confirmation", systemImage: "hand.raised")
            Label("No sudo access or permanent deletion", systemImage: "lock.shield")
            HStack(spacing: 12) {
                Button("Accept Default Settings") {
                    settings.mode = .standard
                    settings.reviewFolders = []
                    finish()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                Button("Customize") { flow.step = 1 }
                    .buttonStyle(.bordered)
            }
            Text("Defaults: Standard Mode, no extra review folders, and no Full Disk Access requirement. Choosing defaults clears previous optional review folders.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var folderStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Customize folders to review")
                .font(.title3.bold())
            Text("Each folder must be confirmed separately in macOS's folder picker. Selected folders show only their immediate contents in Storage Cleanup, all unchecked.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            ForEach(["Desktop", "Documents", "Downloads"], id: \.self) { name in
                let path = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(name, isDirectory: true).path
                HStack(spacing: 10) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(name).frame(width: 105, alignment: .leading)
                    Spacer()
                    Text(settings.reviewFolders.contains(path) ? "Selected for review" : "Not selected")
                        .font(.caption).foregroundStyle(.secondary)
                    if settings.reviewFolders.contains(path) {
                        Button("Remove") {
                            settings.reviewFolders.removeAll { $0 == path }
                        }
                    } else {
                        Button("Choose Folder…") {
                            if let chosen = ManualSelectionService.chooseSuggestedReviewFolder(name) {
                                settings.addReviewFolders([chosen])
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Add Another Folder…") {
                settings.addReviewFolders(ManualSelectionService.chooseReviewFolders())
            }
            Text("\(settings.reviewFolders.count) folders selected. Folder selection is not a grant of Full Disk Access.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var fullDiskStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Full Disk Access is optional")
                .font(.title3.bold())
            Text("For additional protected user data, macOS requires you to enable StorageKit manually in System Settings → Privacy & Security → Full Disk Access. The app cannot grant or confirm this permission automatically.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Full Disk Access Settings") {
                settings.openFullDiskAccessSettings()
            }
            .buttonStyle(.bordered)
            Label("Restart StorageKit after changing privacy permissions.", systemImage: "arrow.clockwise")
                .font(.caption).foregroundStyle(.secondary)
            Text("Continue to skip. macOS system-protected files always remain blocked.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ready to explore")
                .font(.title3.bold())
            Label("\(settings.reviewFolders.count) optional folders selected for review", systemImage: "folder")
            Label("Standard or Advanced: \(settings.mode.rawValue)", systemImage: "slider.horizontal.3")
            Label("Every move to Trash requires an exact-path confirmation", systemImage: "checkmark.shield")
            Text("Finish Setup starts application discovery. The setup can be reopened from Settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

@main struct StorageKitApp: App {
    @StateObject private var settings = SettingsStore.shared
    var body: some Scene {
        WindowGroup { ContentView() }
            .commands {
                CommandGroup(replacing: .help) {
                    Button("Request a Feature") {
                        if let link = settings.link("feature") { NSWorkspace.shared.open(link) }
                    }.disabled(settings.link("feature") == nil)
                    Button("Report a Bug") {
                        if let link = settings.link("bug") { NSWorkspace.shared.open(link) }
                    }.disabled(settings.link("bug") == nil)
                    Divider()
                    Button("Documentation") {
                        if let resource = Bundle.main.resourceURL?.appendingPathComponent("README.md") {
                            NSWorkspace.shared.open(resource)
                        }
                    }
                    Button("View on GitHub") {
                        NSWorkspace.shared.open(StorageKitLinks.repository)
                    }
                    Button("Check for Updates…") {
                        UpdateService.shared.checkForUpdates()
                    }
                }
            }
    }
}
