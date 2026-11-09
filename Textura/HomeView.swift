import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var recents: Recents
    @State private var path: [Route] = []
    @State private var showImporter = false
    @State private var importFolder = false
    @State private var showSettings = false
    @State private var showNew = false
    @State private var newName = ""
    @State private var errorText: String?

    private var docsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var importTypes: [UTType] {
        importFolder ? [UTType.folder] : [UTType.item]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    actions
                    localCard
                    recentSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(AppBackground())
            .navigationTitle("Textura")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Ajustes")
                }
            }
            .navigationDestination(for: Route.self) { route in
                destination(route)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: importTypes, allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(recents)
        }
        .alert("Nuevo archivo", isPresented: $showNew) {
            TextField("nombre.txt", text: $newName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Crear") { createNew() }
            Button("Cancelar", role: .cancel) { newName = "" }
        } message: {
            Text("Se creará en la carpeta de Textura (visible en Archivos).")
        }
        .alert("No se pudo completar", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .onOpenURL { url in
            handleOpenURL(url)
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

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        if route.isDirectory {
            FolderView(url: route.url)
        } else {
            EditorView(url: route.url)
        }
    }

    // MARK: Secciones

    private var actions: some View {
        GlassGroup(spacing: 12) {
            HStack(spacing: 12) {
                ActionTile(icon: "doc.text.magnifyingglass", title: "Abrir archivo") {
                    importFolder = false
                    showImporter = true
                }
                ActionTile(icon: "folder", title: "Abrir carpeta") {
                    importFolder = true
                    showImporter = true
                }
                ActionTile(icon: "doc.badge.plus", title: "Nuevo") {
                    newName = ""
                    showNew = true
                }
            }
        }
    }

    private var localCard: some View {
        NavigationLink(value: Route(url: docsURL, isDirectory: true)) {
            HStack(spacing: 14) {
                Image(systemName: "iphone")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("En Textura")
                        .font(.body.weight(.medium))
                    Text("Archivos guardados dentro de la app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassCard(cornerRadius: 20, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recientes")
                .font(.headline)
                .padding(.leading, 4)

            if recents.items.isEmpty {
                Text("Los archivos y carpetas que abras aparecerán aquí.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .glassCard(cornerRadius: 20)
            } else {
                ForEach(recents.items) { item in
                    recentRow(item)
                }
            }
        }
    }

    private func recentRow(_ item: RecentItem) -> some View {
        Button {
            openRecent(item)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: FileKind.icon(for: URL(fileURLWithPath: item.path), isDirectory: item.isFolder))
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 20, interactive: true)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                recents.remove(item)
            } label: {
                Label("Quitar de recientes", systemImage: "xmark.circle")
            }
        }
    }

    // MARK: Acciones

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                open(url, isFolder: importFolder)
            }
        case .failure(let error):
            errorText = error.localizedDescription
        }
    }

    private func handleOpenURL(_ url: URL) {
        guard url.isFileURL else { return }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        let isDir = values?.isDirectory ?? false
        open(url, isFolder: isDir)
    }

    private func open(_ url: URL, isFolder: Bool) {
        Access.shared.start(url)
        recents.add(url: url, isFolder: isFolder)
        path.append(Route(url: url, isDirectory: isFolder))
    }

    private func openRecent(_ item: RecentItem) {
        guard let url = recents.resolve(item) else {
            errorText = "No se puede acceder a «\(item.name)». Vuelve a abrirlo con «Abrir archivo»."
            recents.remove(item)
            return
        }
        open(url, isFolder: item.isFolder)
    }

    private func createNew() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        newName = ""
        guard !name.isEmpty, !name.contains("/") else { return }
        let target = docsURL.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: target.path) {
            guard FileManager.default.createFile(atPath: target.path, contents: Data()) else {
                errorText = "No se pudo crear el archivo."
                return
            }
        }
        path.append(Route(url: target, isDirectory: false))
    }
}

private struct ActionTile: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 24, interactive: true)
        }
        .buttonStyle(.plain)
    }
}
