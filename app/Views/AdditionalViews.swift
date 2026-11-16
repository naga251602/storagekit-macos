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
                    Button("Request Feature") {
                        if let url = settings.link("feature") { NSWorkspace.shared.open(url) }
                    }.disabled(settings.link("feature") == nil)
                    Button("Report Bug") {
                        if let url = settings.link("bug") { NSWorkspace.shared.open(url) }
                    }.disabled(settings.link("bug") == nil)
                }
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

    private let stepNames = ["Welcome", "Choose Folders", "Full Disk Access", "Ready"]

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 32)).foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("StorageKit").font(.title.bold())
                    Text("Know what stays. Control what goes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(flow.step + 1) of \(stepNames.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index <= flow.step ? Color.accentColor : Color.secondary.opacity(0.22))
                        .frame(height: 5)
                }
            }
            Text(stepNames[flow.step]).font(.title2.bold())
            Divider()
            Group {
                switch flow.step {
                case 0: welcomeStep
                case 1: foldersStep
                case 2: fullDiskStep
                default: readyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            HStack(spacing: 10) {
                Text("Change access options later in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if flow.step > 0 {
                    Button("Back") { flow.step -= 1 }
                        .buttonStyle(.bordered)
                }
                Button(flow.step == 3 ? "Finish Setup" : "Continue") {
                    if flow.step == 3 {
                        settings.setupCompleted = true
                        onFinish()
                    } else {
                        flow.step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 660, height: 465)
        .interactiveDismissDisabled()
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to a clearer Mac.")
                .font(.title3.bold())
            Text(
                "Discover applications and related files, review developer caches and model storage, and move selected items to macOS Trash with a recovery history."
            )
            .font(.callout).fixedSize(horizontal: false, vertical: true)
            Label("Review exactly what will move before confirming", systemImage: "checkmark.shield")
            Label("Restore recoverable items from Recently Deleted", systemImage: "arrow.uturn.backward")
            Label("No automatic cleanup, telemetry or permanent deletion", systemImage: "hand.raised")
            Text("Nothing changes on your Mac during setup.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var foldersStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose folders to review (optional)")
                .font(.title3.bold())
            Text(
                "StorageKit can scan ordinary user-accessible files. Choose any additional folders whose immediate contents you want to inspect in Storage Cleanup. macOS may ask for access when those folders are opened."
            )
            .font(.callout).fixedSize(horizontal: false, vertical: true)
            Button("Choose Review Folders...") {
                settings.addReviewFolders(ManualSelectionService.chooseReviewFolders())
            }
            .buttonStyle(.bordered)
            Text("\(settings.reviewFolders.count) folders selected")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(settings.reviewFolders.prefix(3), id: \.self) { path in
                Text(path).font(.caption.monospaced()).lineLimit(1)
                    .truncationMode(.middle).textSelection(.enabled)
            }
            Text(
                "You can continue without selecting anything. Selecting a folder does not grant Full Disk Access."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var fullDiskStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Full Disk Access (optional)")
                .font(.title3.bold())
            Text(
                "Some app data is protected by macOS. To grant broader inspection access, open System Settings → Privacy & Security → Full Disk Access and manually enable StorageKit. macOS controls this permission; StorageKit cannot grant or reliably detect it on its own."
            )
            .font(.callout).fixedSize(horizontal: false, vertical: true)
            Button("Open Full Disk Access Settings") {
                settings.openFullDiskAccessSettings()
            }
            .buttonStyle(.bordered)
            Label("A restart may be needed after changing access.", systemImage: "arrow.clockwise")
                .font(.caption).foregroundStyle(.secondary)
            Text(
                "You can skip this step and grant access later in Settings. Protected system paths remain blocked either way."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You're ready to explore.")
                .font(.title3.bold())
            Label("Application cleanup: preview all selected paths", systemImage: "app")
            Label(
                "Developer cleanup: explicitly choose caches, model stores or runtime folders",
                systemImage: "chevron.left.forwardslash.chevron.right")
            Label(
                "Recently Deleted: restore files while they remain in Trash",
                systemImage: "clock.arrow.circlepath")
            Text(
                "Homebrew packages and individual Ollama model manifests require their own manager. StorageKit will not bypass macOS protection or empty Trash."
            )
            .font(.callout).foregroundStyle(.secondary)
            Text("Finish Setup starts the application scan.")
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
                        if let link = settings.link("github") { NSWorkspace.shared.open(link) }
                    }.disabled(settings.link("github") == nil)
                }
            }
    }
}
