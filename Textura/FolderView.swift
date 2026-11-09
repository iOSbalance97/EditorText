import SwiftUI

struct FileItem: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let sizeBytes: Int64
    let date: Date?

    var id: URL { url }
    var name: String { url.lastPathComponent }

    var subtitle: String {
        if isDirectory { return "Carpeta" }
        let size = ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        if let d = date {
            return size + " · " + d.formatted(date: .abbreviated, time: .shortened)
        }
        return size
    }
}

private enum PromptKind {
    case newFile
    case newFolder
    case rename
}

struct FolderView: View {
    let url: URL

    @State private var items: [FileItem] = []
    @State private var search = ""
    @State private var showPrompt = false
    @State private var promptKind: PromptKind = .newFile
    @State private var promptText = ""
    @State private var renameTarget: FileItem?
    @State private var showDelete = false
    @State private var deleteTarget: FileItem?
    @State private var errorText: String?

    private var title: String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if url.standardizedFileURL.path == docs.standardizedFileURL.path { return "En Textura" }
        return url.lastPathComponent
    }

    private var filtered: [FileItem] {
        let q = search.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var promptTitle: String {
        switch promptKind {
        case .newFile: return "Nuevo archivo"
        case .newFolder: return "Nueva carpeta"
        case .rename: return "Renombrar"
        }
    }

    var body: some View {
        List {
            ForEach(filtered) { item in
                NavigationLink(value: Route(url: item.url, isDirectory: item.isDirectory)) {
                    FileRow(item: item)
                }
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTarget = item
                        showDelete = true
                    } label: {
                        Label("Eliminar", systemImage: "trash")
                    }
                    Button {
                        startRename(item)
                    } label: {
                        Label("Renombrar", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
                .contextMenu {
                    Button {
                        startRename(item)
                    } label: {
                        Label("Renombrar", systemImage: "pencil")
                    }
                    Button {
                        duplicate(item)
                    } label: {
                        Label("Duplicar", systemImage: "plus.square.on.square")
                    }
                    if !item.isDirectory {
                        ShareLink(item: item.url) {
                            Label("Compartir", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button(role: .destructive) {
                        deleteTarget = item
                        showDelete = true
                    } label: {
                        Label("Eliminar", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Carpeta vacía", systemImage: "folder", description: Text("Pulsa + para crear un archivo."))
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Buscar")
        .refreshable { reload() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        promptKind = .newFile
                        promptText = ""
                        showPrompt = true
                    } label: {
                        Label("Nuevo archivo", systemImage: "doc.badge.plus")
                    }
                    Button {
                        promptKind = .newFolder
                        promptText = ""
                        showPrompt = true
                    } label: {
                        Label("Nueva carpeta", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(promptTitle, isPresented: $showPrompt) {
            TextField("Nombre", text: $promptText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Aceptar") { commitPrompt() }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("Eliminar", isPresented: $showDelete, titleVisibility: .visible, presenting: deleteTarget) { item in
            Button("Eliminar «\(item.name)»", role: .destructive) {
                delete(item)
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Esta acción no se puede deshacer.")
        }
        .alert("No se pudo completar", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .onAppear {
            Access.shared.start(url)
            reload()
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorText != nil },
            set: { shown in
                if !shown { errorText = nil }
            }
        )
    }

    // MARK: Operaciones

    private func reload() {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])
            var list: [FileItem] = []
            for u in urls {
                let values = try? u.resourceValues(forKeys: Set(keys))
                list.append(FileItem(
                    url: u,
                    isDirectory: values?.isDirectory ?? false,
                    sizeBytes: Int64(values?.fileSize ?? 0),
                    date: values?.contentModificationDate
                ))
            }
            items = list.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func startRename(_ item: FileItem) {
        renameTarget = item
        promptKind = .rename
        promptText = item.name
        showPrompt = true
    }

    private func commitPrompt() {
        let name = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        promptText = ""
        guard !name.isEmpty, !name.contains("/") else { return }
        let fm = FileManager.default
        let target = url.appendingPathComponent(name)
        do {
            switch promptKind {
            case .newFile:
                if fm.fileExists(atPath: target.path) {
                    errorText = "Ya existe «\(name)»."
                } else if !fm.createFile(atPath: target.path, contents: Data()) {
                    errorText = "No se pudo crear el archivo."
                }
            case .newFolder:
                try fm.createDirectory(at: target, withIntermediateDirectories: false)
            case .rename:
                if let item = renameTarget, item.url != target {
                    try fm.moveItem(at: item.url, to: target)
                }
            }
        } catch {
            errorText = error.localizedDescription
        }
        reload()
    }

    private func duplicate(_ item: FileItem) {
        let ext = item.url.pathExtension
        let base = item.url.deletingPathExtension().lastPathComponent
        var n = 1
        var target = item.url
        repeat {
            let suffix = n > 1 ? " \(n)" : ""
            let name = ext.isEmpty ? "\(base) copia\(suffix)" : "\(base) copia\(suffix).\(ext)"
            target = url.appendingPathComponent(name)
            n += 1
        } while FileManager.default.fileExists(atPath: target.path)
        do {
            try FileManager.default.copyItem(at: item.url, to: target)
        } catch {
            errorText = error.localizedDescription
        }
        reload()
    }

    private func delete(_ item: FileItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
        } catch {
            errorText = error.localizedDescription
        }
        reload()
    }
}

private struct FileRow: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: FileKind.icon(for: item.url, isDirectory: item.isDirectory))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(item.isDirectory ? Color.accentColor : Color.secondary)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
