import AppKit
import Foundation
import SwiftUI

struct EmptyPanel: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(25)
    }
}

struct InspectorButtons: View {
    let path: String
    var body: some View {
        HStack(spacing: 8) {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private final class DirectoryPreviewModel: ObservableObject {
    @Published var expanded = false
    @Published var names: [String] = []
    @Published var loading = false
    @Published var truncated = false
    func load(_ path: String) {
        guard !loading && names.isEmpty else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            let first = Array(items.sorted().prefix(100))
            DispatchQueue.main.async {
                self.names = first
                self.truncated = items.count > first.count
                self.loading = false
            }
        }
    }
}

struct DirectoryPreview: View {
    let path: String
    @StateObject private var preview = DirectoryPreviewModel()
    var body: some View {
        DisclosureGroup(isExpanded: $preview.expanded) {
            if preview.loading { ProgressView().controlSize(.small) }
            ForEach(preview.names, id: \.self) { name in
                Text(name).font(.caption2.monospaced()).textSelection(.enabled)
            }
            if preview.truncated {
                Text("Showing first 100 entries; open Finder to inspect everything.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } label: {
            Text("Preview directory contents").font(.caption)
        }
        .onChange(of: preview.expanded) { value in if value { preview.load(path) } }
    }
}

struct CandidateRow: View {
    @ObservedObject var model: CleanerModel
    let item: ScanEntry
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { model.marked(item) },
                    set: { model.toggle(item, enabled: $0) }
                )
            )
            .labelsHidden().toggleStyle(.checkbox)
            .disabled(!model.canSelect(item) || model.operationBusy)
            Circle().fill(item.color).frame(width: 9, height: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name).fontWeight(.medium).lineLimit(2)
                    Spacer()
                    Text(item.sizeLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(item.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("\(item.category) · \(item.status) · \(item.confidence) confidence")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(item.reason).font(.caption2).foregroundStyle(
                    item.isProtected ? Color.red : Color.secondary)
                HStack {
                    InspectorButtons(path: item.path)
                    Spacer(minLength: 0)
                }
                if (item.fileCount ?? 0) > 1 { DirectoryPreview(path: item.path) }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

struct CleanupReviewView: View {
    @ObservedObject var model: CleanerModel
    let action: CleanupAction

    private var available: [ScanEntry] {
        let source = model.sourceEntries(for: action)
        return source.filter {
            model.canSelect($0) && action.permits($0)
                && (action != .uninstall || model.uninstallIncludesData || $0.cleanup == "app")
        }.sorted {
            $0.cleanup == "app" && $1.cleanup != "app" || ($0.cleanup == $1.cleanup && $0.path < $1.path)
        }
    }
    private var approved: [ScanEntry] { model.approved(action) }
    private var estimatedBytes: UInt64 { approved.compactMap(\.sizeBytes).reduce(0, +) }
    private var name: String {
        switch action {
        case .storage: return "Storage Cleanup"
        case .developer: return "Developer Tools & Models"
        default: return model.selectedApp?.name ?? "App"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move selected files to Trash?").font(.title2.bold())
            Text("\(name) · \(action.label)").font(.headline)
            Text(action.warning).font(.callout)
            Text("Every selected path is shown below. No file is moved until you confirm.")
                .font(.caption).foregroundStyle(.secondary)
            if action == .uninstall {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle(
                        "Delete app data (including discovered models and logs)",
                        isOn: Binding(
                            get: { model.uninstallIncludesData },
                            set: { model.setUninstallIncludesData($0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .fontWeight(.semibold)
                    .disabled(model.operationBusy)
                    Text(
                        model.uninstallIncludesData
                            ? "Additional app data appears below. For Ollama, ~/.ollama includes downloaded LLMs, logs, configuration and possibly credentials. Review before moving."
                            : "Off by default: only the application bundle will move to Trash. Your app data stays on disk."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 9))
            }
            Divider()
            HStack {
                Text(
                    "\(approved.count) selected · \(ByteCountFormatter.string(fromByteCount: Int64(clamping: estimatedBytes), countStyle: .file)) estimated"
                )
                .font(.headline)
                Spacer()
                if model.operationBusy { ProgressView().controlSize(.small) }
            }
            List(available) { entry in
                Toggle(
                    isOn: Binding(
                        get: { model.reviewSelection.contains(entry.id) },
                        set: { checked in
                            if checked {
                                model.reviewSelection.insert(entry.id)
                            } else {
                                model.reviewSelection.remove(entry.id)
                            }
                            model.acknowledgedRisk = false
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle().fill(entry.color).frame(width: 8, height: 8)
                            Text(entry.path).font(.caption.monospaced()).textSelection(.enabled)
                            Spacer()
                            Text(entry.sizeLabel).font(.caption.monospacedDigit())
                        }
                        Text(
                            action == .uninstall && entry.cleanup == "app"
                                ? "Application bundle · required for uninstall"
                                : "\(entry.category): \(entry.reason)"
                        )
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(model.operationBusy || (action == .uninstall && entry.cleanup == "app"))
            }
            .frame(minHeight: 185)
            if model.riskSelected {
                Toggle(
                    "I understand these selections may remove downloaded models, credentials, personal data or files shared by other apps.",
                    isOn: $model.acknowledgedRisk
                )
                .toggleStyle(.checkbox)
                .font(.callout)
            }
            if !model.error.isEmpty {
                Text(model.error).font(.caption).foregroundStyle(.red)
            }
            Text(
                "Items stay in macOS Trash until it is emptied. Moving them does not immediately free SSD space."
            )
            .font(.caption).foregroundStyle(.secondary)
            HStack {
                if model.operationBusy {
                    Button("Stop after current item") { model.cancelOperation() }
                }
                Spacer()
                Button("Cancel") { model.reviewAction = nil }.disabled(model.operationBusy)
                Button("Move to Trash") { model.confirmMove() }
                    .disabled(
                        approved.isEmpty || model.operationBusy
                            || (model.riskSelected && !model.acknowledgedRisk)
                    )
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(minWidth: 710, minHeight: 490)
        .interactiveDismissDisabled(model.operationBusy)
    }
}

struct CleanupReportView: View {
    let report: TrashReport
    let onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup Results").font(.title2.bold())
            Text("\(report.movedCount) moved · \(report.skippedCount) skipped · \(report.failedCount) failed")
                .font(.headline)
            Text(
                "Estimated \(ByteCountFormatter.string(fromByteCount: Int64(clamping: report.estimatedMovedBytes), countStyle: .file)) moved to Trash, not yet reclaimed."
            )
            .font(.caption).foregroundStyle(.secondary)
            Divider()
            List(report.outcomes) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.originalPath).font(.caption.monospaced()).textSelection(.enabled)
                    Text("\(item.status.capitalized): \(item.message)").font(.caption).foregroundStyle(
                        .secondary)
                    if let destination = item.resultingPath {
                        Text("Trash: \(destination)").font(.caption2.monospaced()).textSelection(.enabled)
                    }
                }
            }
            HStack {
                Button("Open Trash") {
                    NSWorkspace.shared.open(
                        FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent(".Trash", isDirectory: true))
                }
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 450)
    }
}
