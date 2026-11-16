import AppKit
import Foundation
import SwiftUI

// Use an ObservableObject rather than a standalone @State property here.
// Some SwiftUI toolchains report a missing SwiftUIMacros.StateMacro plugin
// when compiling with swiftc directly (outside an Xcode project).
private final class PermissionsPresentationState: ObservableObject {
    @Published var isPresented = false
}

struct ContentView: View {
    @StateObject private var model = CleanerModel()
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var permissionsState = PermissionsPresentationState()

    private var groupedCandidates: [(String, [ScanEntry])] {
        let groups = Dictionary(grouping: model.candidates, by: \.category)
        return groups.keys.sorted().map { ($0, (groups[$0] ?? []).sorted { $0.path < $1.path }) }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "internaldrive.fill")
                        .font(.title2).foregroundStyle(.mint)
                    Text("StorageKit").font(.title2.bold())
                }
                Text("Know what stays. Control what goes.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                ForEach(BrowserPage.allCases) { page in
                    Button {
                        model.navigate(page)
                    } label: {
                        HStack {
                            Label(page.rawValue, systemImage: page.symbol)
                            Spacer(minLength: 0)
                            if page == model.page { Image(systemName: "checkmark").font(.caption2) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(
                            model.page == page ? Color.accentColor.opacity(0.16) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.operationBusy || model.restoring)
                }
                Spacer(minLength: 10)
                Divider()
                Label("Trash only · No permanent deletion", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(17)
            .frame(minWidth: 230)
        } content: {
            VStack(spacing: 0) {
                HStack {
                    Text(model.page.rawValue).font(.headline)
                    Spacer()
                    if model.busy || model.detailBusy { ProgressView().controlSize(.small) }
                }
                .padding(12)
                if [.applications, .storage, .developer].contains(model.page) {
                    TextField("Search files, apps or paths", text: $model.search)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 7)
                }
                if model.page == .applications {
                    HStack(spacing: 8) {
                        Toggle("Hide Apple & protected apps", isOn: $model.hideProtected)
                            .toggleStyle(.checkbox)
                            .help(
                                "Checked by default. Uncheck to inspect Apple apps; only user-owned data may be reviewed in Advanced Mode. System apps cannot be uninstalled."
                            )
                            .onChange(of: model.hideProtected) { _ in
                                model.loadApps()
                            }
                        Spacer()
                        Text("\(model.filteredApps.count) apps")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                Divider()
                if model.busy {
                    ProgressView("Scanning...").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    middleContent
                }
                Divider()
                footer
            }
            .frame(minWidth: 355)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 880, minHeight: 620)
        .sheet(item: $model.reviewAction) { action in
            if let report = model.report {
                CleanupReportView(report: report) { model.closeReview() }
            } else {
                CleanupReviewView(model: model, action: action)
            }
        }
        .sheet(isPresented: $permissionsState.isPresented) {
            PermissionsSetupView(settings: settings) {
                permissionsState.isPresented = false
                if model.apps.isEmpty { model.loadApps() }
            }
        }
        .onAppear {
            if !settings.setupCompleted {
                permissionsState.isPresented = true
            } else {
                model.loadApps()
            }
        }
    }

    @ViewBuilder private var middleContent: some View {
        switch model.page {
        case .applications:
            List(model.filteredApps, selection: $model.selectedAppID) { app in
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable().frame(width: 27, height: 27)
                    Circle().fill(app.color).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).lineLimit(1).fontWeight(.medium)
                        Text(app.bundleID.isEmpty ? app.path : app.bundleID)
                            .lineLimit(1).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 2)
                }.tag(app.id)
            }
            .onChange(of: model.selectedAppID) { _ in model.scanSelectedApp() }
        case .storage:
            List(model.filteredStorage, selection: $model.selectedStorageID) { item in
                HStack(spacing: 6) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.markedStorageIDs.contains(item.id) },
                            set: { model.toggle(item, enabled: $0) })
                    )
                    .toggleStyle(.checkbox).labelsHidden()
                    .disabled(!model.canSelect(item) || model.operationBusy)
                    Circle().fill(item.color).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).lineLimit(1)
                        Text(item.category).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 1)
                    Text(item.sizeLabel).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }.tag(item.id)
            }
        case .developer:
            List(model.filteredInventory, selection: $model.selectedInventoryID) { item in
                HStack(spacing: 7) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.markedDeveloperIDs.contains(item.id) },
                            set: { model.toggle(item, enabled: $0) }
                        )
                    )
                    .toggleStyle(.checkbox).labelsHidden()
                    .disabled(!model.canSelect(item) || model.operationBusy)
                    Circle().fill(item.color).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).lineLimit(1).fontWeight(.medium)
                        Text(item.category).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 2)
                    Text(item.cleanup == "developer" ? item.sizeLabel : "Managed")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                .tag(item.id)
                .help(
                    item.cleanup == "developer"
                        ? "Select for an explicit Trash review. May break projects or remove downloaded models."
                        : "Managed by its own package or model manager; direct deletion disabled.")
            }
        case .recent:
            List(
                model.sessions,
                selection: Binding(
                    get: { model.selectedSessionID },
                    set: { model.selectSession($0) })
            ) { session in
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.appName).fontWeight(.medium)
                    Text(
                        "\(session.action) · \(session.timestamp.formatted(date: .abbreviated, time: .shortened))"
                    )
                    .font(.caption2).foregroundStyle(.secondary)
                    Text("\(session.items.count) items · \(session.recoveryStatus)")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.vertical, 5).tag(session.id)
            }
        case .settings:
            VStack(alignment: .leading, spacing: 10) {
                Label("Selection and Privacy", systemImage: "gearshape")
                Text("Standard by default. Advanced enables explicit review of uncertain and shared files.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(16)
        }
    }

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.page == .applications {
                HStack(spacing: 10) {
                    Text(
                        model.selectedApp == nil
                            ? "Select an app to inspect and clean it"
                            : (model.detailBusy
                                ? "Scanning associated files..."
                                : "Selected: \(model.selectedApp?.name ?? "")")
                    )
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 6)
                    rescanButton
                }
            } else if model.page == .storage {
                HStack {
                    Button("Rescan") { model.loadStorage() }.disabled(model.busy || model.operationBusy)
                    Button("Add Files or Folders...") { model.addManualChoices() }
                        .disabled(model.busy || model.operationBusy)
                    Spacer()
                    Button("Move Selected to Trash") { model.prepare(.storage) }
                        .disabled(!model.canPrepare(.storage))
                }
            } else if model.page == .developer {
                HStack(spacing: 8) {
                    Text("\(model.markedDeveloperIDs.count) selected")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { model.loadInventory() }
                        .disabled(model.busy || model.operationBusy)
                    Button("Move Selected to Trash") { model.prepare(.developer) }
                        .disabled(!model.canPrepare(.developer))
                }
            } else if model.page == .recent {
                HStack {
                    Text(footerCount).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { model.refreshCurrent() }
                        .disabled(model.busy || model.operationBusy || model.restoring)
                }
            } else {
                Text("Settings apply to future cleanup confirmations.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.error.isEmpty { Text(model.error).font(.caption).foregroundStyle(.red) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(11)
    }
    private var footerCount: String {
        switch model.page {
        case .applications: return "\(model.apps.count) apps"
        case .developer: return "\(model.inventory.count) locations"
        case .recent: return "\(model.sessions.count) sessions"
        default: return "StorageKit"
        }
    }
    private var rescanButton: some View {
        Button {
            model.scanSelectedApp()
        } label: {
            Label("Rescan", systemImage: "arrow.clockwise")
        }
        .disabled(model.selectedApp == nil || model.detailBusy || model.operationBusy)
        .help("Scan the selected application's associated files")
    }
    private var cacheButton: some View {
        Button("Clear Cache") { model.prepare(.cache) }
            .disabled(!model.canPrepare(.cache))
            .help("Requires selected verified or Advanced Mode cache files")
    }
    private var resetButton: some View {
        Button("Reset Data") { model.prepare(.reset) }
            .disabled(!model.canPrepare(.reset))
            .help("Moves selected app data to Trash; unsynced content can be lost")
    }
    private var uninstallButton: some View {
        Button("Uninstall") { model.prepare(.uninstall) }
            .disabled(!model.canPrepare(.uninstall))
            .help("Moves selected application and associated files to Trash")
    }

    @ViewBuilder private var detailContent: some View {
        switch model.page {
        case .applications:
            if let app = model.selectedApp {
                // Respect the detail pane's titlebar safe area. Drawing the
                // inspector underneath it clips the app icon and name.
                appDetails(app)
            } else {
                EmptyPanel(
                    title: "Select an application", message: "Inspect its bundle and related Library files.",
                    symbol: "app.badge")
            }
        case .storage:
            if let item = model.storageCandidates.first(where: { $0.id == model.selectedStorageID }) {
                itemDetails(item)
            } else {
                EmptyPanel(
                    title: "Storage Cleanup",
                    message:
                        "Green: verified caches. Grey: manual review. Use Add Files or Folders to review additional user-owned paths. Protected system locations are excluded.",
                    symbol: "internaldrive")
            }
        case .developer:
            if let item = model.selectedInventory {
                itemDetails(item)
            } else {
                EmptyPanel(
                    title: "Developer Tools & Models",
                    message:
                        "Inspect runtimes, package caches and AI model storage without deleting managed packages.",
                    symbol: "chevron.left.forwardslash.chevron.right")
            }
        case .recent: RecentlyDeletedView(model: model)
        case .settings: SettingsView(settings: settings) { permissionsState.isPresented = true }
        }
    }

    private func appDetails(_ app: ScanEntry) -> some View {
        VStack(spacing: 0) {
            // Keep identity above the file list and inside the usable detail
            // area. NavigationSplitView already accounts for the titlebar.
            HStack(alignment: .center, spacing: 13) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                    .resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.title2.bold()).lineLimit(1)
                    Text(app.bundleID.isEmpty ? "Bundle ID unavailable" : app.bundleID)
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(app.path).font(.caption.monospaced())
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            // A single-line toolbar: never reflow actions into two rows.
            // Smaller windows can scroll horizontally instead of wrapping.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    InspectorButtons(path: app.path)
                    cacheButton
                    resetButton
                    if !app.bundleID.lowercased().hasPrefix("com.apple.") {
                        uninstallButton
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 20).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.detailBusy {
                        ProgressView("Scanning associated files...")
                    } else if model.candidates.isEmpty {
                        EmptyPanel(
                            title: "No candidates found", message: "Press Rescan to refresh.",
                            symbol: "folder.badge.questionmark"
                        )
                        .frame(height: 180)
                    } else {
                        let selected = model.candidates.filter { model.markedIDs.contains($0.id) }
                        let size = selected.compactMap(\.sizeBytes).reduce(UInt64(0), +)
                        Text(
                            "\(selected.count) selected · \(ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file)) estimated"
                        )
                        .font(.headline)
                        ForEach(groupedCandidates, id: \.0) { group in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(group.1) { item in
                                        CandidateRow(model: model, item: item)
                                        Divider()
                                    }
                                }.padding(.top, 7)
                            } label: {
                                HStack {
                                    Text(group.0).fontWeight(.semibold)
                                    Spacer()
                                    Text("\(group.1.count) items").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(
                                Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    Text(
                        app.bundleID.lowercased().hasPrefix("com.apple.")
                            ? "Apple app: only exact user Library matches are reviewable in Settings → Advanced. System app bundles, shared data and protected locations remain blocked. Close the app before cleanup; resetting may erase synced or personal data."
                            : "Discovered files are listed here for inspection. Uninstall moves only the app by default; app data requires a separate opt-in. Grey/amber entries require Advanced Mode."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func itemDetails(_ item: ScanEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.name).font(.title2.bold())
                HStack {
                    Circle().fill(item.color).frame(width: 10, height: 10)
                    Text("\(item.status) · \(item.category)")
                }
                Text("Estimated size: \(item.sizeLabel)")
                Text("Confidence: \(item.confidence)")
                Text(item.reason).foregroundStyle(.secondary)
                Text(item.path).font(.callout.monospaced()).textSelection(.enabled)
                InspectorButtons(path: item.path)
                if (item.fileCount ?? 0) > 1 {
                    DirectoryPreview(path: item.path)
                }
                if model.page == .developer && item.cleanup == "developer" {
                    Text(
                        "This location may be shared by developer projects. Inspect its contents before moving it to Trash."
                    )
                    .font(.caption).foregroundStyle(.orange)
                    Button("Review Move to Trash") { model.prepareSelectedDeveloperItem() }
                        .disabled(model.busy || model.operationBusy)
                        .buttonStyle(.borderedProminent)
                } else if item.cleanup == "none" {
                    Label(
                        "Managed package or model metadata. Use its native manager for removal.",
                        systemImage: "lock.shield"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
