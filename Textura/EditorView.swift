import SwiftUI

struct EditorView: View {
    let url: URL
    @StateObject private var doc: FileDoc
    @StateObject private var ctl = EditorController()
    @AppStorage("fontSize") private var fontSize: Double = 15
    @AppStorage("autoSave") private var autoSave: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var showLeave = false
    @State private var showGoToLine = false
    @State private var goToLineText = ""
    @State private var showGoToOffset = false
    @State private var goToOffsetText = ""
    @State private var showHexSearch = false
    @State private var hexSearchText = ""

    init(url: URL) {
        self.url = url
        _doc = StateObject(wrappedValue: FileDoc(url: url))
    }

    // MARK: Cuerpo

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .navigationTitle(doc.isDirty ? "• " + url.lastPathComponent : url.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    attemptLeave()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Volver")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    doc.save()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(!doc.isDirty || doc.loading)
                .accessibilityLabel("Guardar")

                Menu {
                    menuContent
                } label: {
                    Image(systemName: "ellipsis")
                }
                .disabled(doc.loading)
                .accessibilityLabel("Más opciones")
            }
        }
        .overlay(alignment: .top) {
            if let message = doc.toast {
                Text(message)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassCapsule()
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: doc.toast)
        .onAppear { doc.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && autoSave && doc.isDirty {
                doc.save()
            }
        }
        .confirmationDialog("Cambios sin guardar", isPresented: $showLeave, titleVisibility: .visible) {
            Button("Guardar y salir") {
                doc.save()
                if !doc.isDirty { dismiss() }
            }
            Button("Descartar cambios", role: .destructive) {
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Ir a línea", isPresented: $showGoToLine) {
            TextField("Número de línea", text: $goToLineText)
                .keyboardType(.numberPad)
            Button("Ir") {
                if let n = Int(goToLineText) { ctl.goTo(line: n) }
                goToLineText = ""
            }
            Button("Cancelar", role: .cancel) { goToLineText = "" }
        }
        .alert("Ir a offset", isPresented: $showGoToOffset) {
            TextField("Hexadecimal, p. ej. 1A40", text: $goToOffsetText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Ir") {
                jumpToOffset(goToOffsetText)
                goToOffsetText = ""
            }
            Button("Cancelar", role: .cancel) { goToOffsetText = "" }
        }
        .alert("Buscar bytes", isPresented: $showHexSearch) {
            TextField("Hex (DE AD BE EF) o \"texto\"", text: $hexSearchText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Buscar") {
                searchHex(hexSearchText)
            }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(doc.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { doc.errorMessage != nil },
            set: { shown in
                if !shown { doc.errorMessage = nil }
            }
        )
    }

    // MARK: Contenido

    @ViewBuilder
    private var content: some View {
        if doc.loading {
            ProgressView("Abriendo…")
        } else if doc.mode == .text {
            CodeTextView(text: $doc.text, fontSize: CGFloat(fontSize), hexKeyboard: false, controller: ctl)
                .safeAreaInset(edge: .bottom) { textBar }
        } else {
            CodeTextView(text: $doc.hexText, fontSize: CGFloat(max(8, fontSize - 2)), hexKeyboard: true, controller: ctl)
                .safeAreaInset(edge: .bottom) { hexBar }
        }
    }

    // Barra flotante (texto)
    private var textBar: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    BarIcon(systemName: "arrow.uturn.backward", label: "Deshacer") { ctl.undo() }
                    BarIcon(systemName: "arrow.uturn.forward", label: "Rehacer") { ctl.redo() }
                    BarIcon(systemName: "magnifyingglass", label: "Buscar y reemplazar") { ctl.showFind() }
                }
                .padding(.horizontal, 6)
                .glassCapsule()

                Spacer(minLength: 0)

                Text("Ln \(ctl.line), Col \(ctl.col) · \(doc.encoding.rawValue) · \(doc.lineEnding.rawValue)")
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .glassCapsule()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    // Barra flotante (hexadecimal)
    private var hexBar: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    BarIcon(systemName: "chevron.left", label: "Página anterior") { doc.goPage(doc.hexPage - 1) }
                    Text("\(doc.hexPage + 1)/\(doc.pageCount)")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 44)
                    BarIcon(systemName: "chevron.right", label: "Página siguiente") { doc.goPage(doc.hexPage + 1) }
                }
                .padding(.horizontal, 6)
                .glassCapsule()

                HStack(spacing: 2) {
                    BarIcon(systemName: "number", label: "Ir a offset") { showGoToOffset = true }
                    BarIcon(systemName: "magnifyingglass", label: "Buscar bytes") { showHexSearch = true }
                }
                .padding(.horizontal, 6)
                .glassCapsule()

                Spacer(minLength: 0)

                Text(doc.hexRangeLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 11)
                    .glassCapsule()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    // MARK: Menú

    @ViewBuilder
    private var menuContent: some View {
        Button {
            doc.switchMode(doc.mode == .text ? .hex : .text)
        } label: {
            Label(doc.mode == .text ? "Ver como hexadecimal" : "Ver como texto",
                  systemImage: doc.mode == .text ? "number.square" : "text.alignleft")
        }

        if doc.mode == .text {
            Button {
                showGoToLine = true
            } label: {
                Label("Ir a línea…", systemImage: "arrow.down.to.line")
            }

            Menu {
                ForEach(TextEnc.allCases) { enc in
                    Button(enc.rawValue) { doc.reinterpret(enc) }
                }
            } label: {
                Label("Reabrir con codificación", systemImage: "character.book.closed")
            }

            Menu {
                ForEach(TextEnc.allCases) { enc in
                    Button(enc.rawValue) { doc.setSaveEncoding(enc) }
                }
            } label: {
                Label("Guardar como codificación", systemImage: "square.and.arrow.down.on.square")
            }

            Picker("Fin de línea", selection: $doc.lineEnding) {
                ForEach(LineEnding.allCases) { le in
                    Text(le.rawValue).tag(le)
                }
            }
        }

        Section("Tamaño del texto") {
            Button {
                fontSize = min(30, fontSize + 1)
            } label: {
                Label("Aumentar", systemImage: "textformat.size.larger")
            }
            Button {
                fontSize = max(9, fontSize - 1)
            } label: {
                Label("Reducir", systemImage: "textformat.size.smaller")
            }
        }

        ShareLink(item: url) {
            Label("Compartir", systemImage: "square.and.arrow.up")
        }
    }

    // MARK: Acciones

    private func attemptLeave() {
        if doc.isDirty {
            if autoSave {
                doc.save()
                if !doc.isDirty { dismiss() }
            } else {
                showLeave = true
            }
        } else {
            dismiss()
        }
    }

    private func jumpToOffset(_ input: String) {
        var t = input.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasPrefix("0x") { t.removeFirst(2) }
        guard let offset = Int(t, radix: 16) else {
            doc.showToast("Offset no válido (hexadecimal)")
            return
        }
        if let line = doc.goToOffset(offset) {
            focusHexLine(line)
        }
    }

    private func searchHex(_ input: String) {
        let t = input.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        var pattern: Data?
        if t.count >= 2 && t.hasPrefix("\"") && t.hasSuffix("\"") {
            pattern = String(t.dropFirst().dropLast()).data(using: .utf8)
        } else {
            pattern = FileDoc.parseHexPage(t)
        }
        guard let p = pattern, !p.isEmpty else {
            doc.showToast("Patrón no válido")
            return
        }
        if let line = doc.findNext(p) {
            focusHexLine(line)
        } else {
            doc.showToast("No encontrado")
        }
    }

    private func focusHexLine(_ line: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ctl.goTo(line: line + 1, focus: false)
        }
    }
}
