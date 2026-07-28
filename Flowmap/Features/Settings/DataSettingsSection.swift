import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Wraps backup JSON for `.fileExporter`. This screen only ever writes a
/// document it just built in memory, but `FileDocument` still requires a
/// reading initialiser — it is simply never exercised here.
private struct BackupJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// iCloud status, JSON backup export/import, Markdown export and demo-data
/// reset — all through the existing `BackupService` and `SeedData`, never a
/// second import/export implementation.
struct DataSettingsSection: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context

    @State private var exportDocument: BackupJSONDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingMarkdownFolderPicker = false
    @State private var showingResetConfirm = false
    @State private var statusMessage: String?
    @State private var isError = false

    var body: some View {
        FlowCard {
            VStack(alignment: .leading, spacing: FlowSpacing.l) {
                FlowEyebrow("Data")

                syncStatusRow

                if let statusMessage {
                    Text(statusMessage)
                        .font(FlowFont.caption)
                        .foregroundStyle(isError ? .red : FlowTheme.secondaryText(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: FlowSpacing.s) {
                    SecondaryActionButton("Export JSON Backup", systemImage: "square.and.arrow.up", action: prepareExport)
                    SecondaryActionButton("Import JSON Backup", systemImage: "square.and.arrow.down") {
                        showingImporter = true
                    }
                    SecondaryActionButton("Export Notes as Markdown", systemImage: "doc.text") {
                        showingMarkdownFolderPicker = true
                    }
                    SecondaryActionButton("Reset Demo Data", systemImage: "arrow.counterclockwise") {
                        showingResetConfirm = true
                    }
                }
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Flowmap Backup"
        ) { result in
            handleExportResult(result)
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            handleImportResult(result)
        }
        .fileImporter(isPresented: $showingMarkdownFolderPicker, allowedContentTypes: [.folder]) { result in
            handleMarkdownExport(result)
        }
        .confirmationDialog(
            "Reset demo data?",
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive, action: resetDemoData)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the seeded Personal workspace so you can start clean. Your own data is not affected.")
        }
    }

    private var syncStatusRow: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
            HStack(spacing: FlowSpacing.s) {
                Image(systemName: CloudSyncStatus.shared.symbolName)
                    .foregroundStyle(
                        CloudSyncStatus.shared.state.isProblem
                            ? FlowTheme.secondaryText(scheme)
                            : FlowTheme.accent
                    )
                Text(CloudSyncStatus.shared.shortDescription)
                    .font(FlowFont.secondary)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                Spacer(minLength: FlowSpacing.s)
            }
            if let lastSync = CloudSyncStatus.shared.lastSuccessfulSync {
                Text("Last successful sync: \(DurationFormatter.time(lastSync))")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }
        }
    }

    // MARK: - JSON backup

    private func prepareExport() {
        do {
            let data = try BackupService.export(from: context)
            exportDocument = BackupJSONDocument(data: data)
            showingExporter = true
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
            isError = true
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            statusMessage = "Backup exported."
            isError = false
        case .failure(let error):
            statusMessage = "Export failed: \(error.localizedDescription)"
            isError = true
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            importBackup(from: url)
        case .failure(let error):
            statusMessage = "Import failed: \(error.localizedDescription)"
            isError = true
        }
    }

    private func importBackup(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let archive = try BackupService.validate(data)
            let summary = try BackupService.importArchive(archive, into: context)
            // Report only what the summary actually supports — never a
            // success claim it doesn't back up.
            statusMessage = summary.description
            isError = false
        } catch {
            statusMessage = "That backup could not be imported: \(error.localizedDescription)"
            isError = true
        }
    }

    // MARK: - Markdown export

    private func handleMarkdownExport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let folder):
            writeMarkdown(into: folder)
        case .failure(let error):
            statusMessage = "Export failed: \(error.localizedDescription)"
            isError = true
        }
    }

    private func writeMarkdown(into folder: URL) {
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }
        let files = BackupService.exportNotesAsMarkdown(from: context)
        var written = 0
        for (filename, contents) in files {
            let destination = folder.appendingPathComponent(filename)
            if (try? contents.write(to: destination, atomically: true, encoding: .utf8)) != nil {
                written += 1
            }
        }
        statusMessage = written == files.count
            ? "\(written) note\(written == 1 ? "" : "s") exported."
            : "\(written) of \(files.count) notes exported."
        isError = written != files.count
    }

    // MARK: - Demo data

    private func resetDemoData() {
        guard let flow else { return }
        SeedData.reset(in: context, settings: flow.settings)
        statusMessage = "Demo data reset."
        isError = false
    }
}
