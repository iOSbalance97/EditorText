import SwiftUI

struct SettingsView: View {
    @AppStorage("fontSize") private var fontSize: Double = 15
    @AppStorage("autoSave") private var autoSave: Bool = false
    @EnvironmentObject private var recents: Recents
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Editor") {
                    Stepper(value: $fontSize, in: 9...30, step: 1) {
                        Text("Tamaño del texto: \(Int(fontSize)) pt")
                    }
                    Toggle("Guardado automático", isOn: $autoSave)
                    Text("let patch = 0x1A40 // vista previa")
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Borrar recientes", role: .destructive) {
                        recents.clear()
                    }
                }

                Section("Acerca de") {
                    LabeledContent("Versión", value: "1.0.0")
                    Text("Abre y edita cualquier archivo: texto, configuraciones, trucos y parches de emuladores. Los archivos binarios se abren en un editor hexadecimal.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hecho") { dismiss() }
                }
            }
        }
    }
}
