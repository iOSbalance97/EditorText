import Foundation
import SwiftUI

/// Modelo de un archivo abierto: texto o binario (hexadecimal), con guardado en el sitio.
final class FileDoc: ObservableObject {
    let url: URL
    let pageSize = 2048   // bytes por página en el editor hexadecimal (128 líneas de 16)

    @Published var loading = true
    @Published var errorMessage: String?
    @Published var toast: String?
    @Published var mode: ViewMode = .text
    @Published var isDirty = false
    @Published var encoding: TextEnc = .utf8
    @Published var hexPage = 0

    @Published var lineEnding: LineEnding = .lf {
        didSet {
            if !suppress && lineEnding != oldValue { markTextChanged() }
        }
    }

    @Published var text: String = "" {
        didSet {
            if !suppress { markTextChanged() }
        }
    }

    @Published var hexText: String = "" {
        didSet {
            if !suppress {
                hexEdited = true
                if !isDirty { isDirty = true }
            }
        }
    }

    private(set) var bytes = Data()
    private var bom = Data()
    private var hexEdited = false
    private var bytesStale = false      // el texto cambió y `bytes` ya no lo refleja
    private var textStale = false       // `bytes` cambió (hex) y `text` ya no lo refleja
    private var textEverLoaded = false
    private var suppress = false
    private var findCursor = -1
    private var toastToken = 0
    private(set) var didLoad = false

    init(url: URL) {
        self.url = url
    }

    var pageCount: Int {
        max(1, (bytes.count + pageSize - 1) / pageSize)
    }

    var hexRangeLabel: String {
        let start = hexPage * pageSize
        let end = max(start, min(bytes.count, start + pageSize) - 1)
        return "0x" + FileDoc.hex(start, width: 6) + " – 0x" + FileDoc.hex(end, width: 6)
    }

    private func markTextChanged() {
        bytesStale = true
        if !isDirty { isDirty = true }
    }

    // MARK: Carga

    func load() {
        guard !didLoad else { return }
        didLoad = true
        loading = true
        let url = self.url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<Data, Error> = Result { try FileDoc.readCoordinated(url) }
            DispatchQueue.main.async {
                self?.finishLoad(result)
            }
        }
    }

    private func finishLoad(_ result: Result<Data, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let data):
            bytes = data
            if data.count > 12_000_000 || FileDoc.looksBinary(data) {
                textStale = true
                mode = .hex
                loadHexPage(0)
            } else {
                let detected = FileDoc.detect(data)
                if !decode(data, as: detected.0, bomLength: detected.1) {
                    _ = decode(data, as: .latin1, bomLength: 0)
                }
                mode = .text
            }
        }
        loading = false
    }

    @discardableResult
    private func decode(_ data: Data, as enc: TextEnc, bomLength: Int) -> Bool {
        let body = bomLength > 0 ? Data(data.dropFirst(bomLength)) : data
        guard var s = String(data: body, encoding: enc.ns) else { return false }

        var ending = LineEnding.lf
        if s.range(of: "\r\n") != nil {
            ending = .crlf
        } else if s.range(of: "\n") != nil {
            ending = .lf
        } else if s.range(of: "\r") != nil {
            ending = .cr
        }
        if ending == .crlf {
            s = s.replacingOccurrences(of: "\r\n", with: "\n")
        } else if ending == .cr {
            s = s.replacingOccurrences(of: "\r", with: "\n")
        }

        let wasDirty = isDirty
        suppress = true
        bom = bomLength > 0 ? Data(data.prefix(bomLength)) : Data()
        encoding = enc
        lineEnding = ending
        text = s
        suppress = false
        bytesStale = false
        textStale = false
        textEverLoaded = true
        isDirty = wasDirty
        return true
    }

    // MARK: Detección

    static func looksBinary(_ data: Data) -> Bool {
        if data.isEmpty { return false }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return false }
        var control = 0
        let sample = data.prefix(8192)
        for b in sample {
            if b == 0 { return true }
            if b < 9 || (b > 13 && b < 32 && b != 27) { control += 1 }
        }
        return Double(control) / Double(sample.count) > 0.10
    }

    static func detect(_ data: Data) -> (TextEnc, Int) {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return (.utf8, 3) }
        if data.starts(with: [0xFF, 0xFE]) { return (.utf16le, 2) }
        if data.starts(with: [0xFE, 0xFF]) { return (.utf16be, 2) }
        if String(data: data, encoding: .utf8) != nil { return (.utf8, 0) }
        return (.win1252, 0)
    }

    static func bomLength(_ data: Data, for enc: TextEnc) -> Int {
        switch enc {
        case .utf8: return data.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        case .utf16le: return data.starts(with: [0xFF, 0xFE]) ? 2 : 0
        case .utf16be: return data.starts(with: [0xFE, 0xFF]) ? 2 : 0
        default: return 0
        }
    }

    // MARK: Cambio de modo texto / hex

    func switchMode(_ newMode: ViewMode) {
        guard newMode != mode, !loading else { return }
        if newMode == .hex {
            if bytesStale {
                guard let data = encodeText() else { return }
                bytes = data
                bytesStale = false
            }
            mode = .hex
            loadHexPage(hexPage)
        } else {
            guard commitHexPage() else { return }
            if textStale || !textEverLoaded {
                var enc = encoding
                var bl = 0
                if textEverLoaded {
                    bl = FileDoc.bomLength(bytes, for: enc)
                } else {
                    let detected = FileDoc.detect(bytes)
                    enc = detected.0
                    bl = detected.1
                }
                if !decode(bytes, as: enc, bomLength: bl) {
                    _ = decode(bytes, as: .latin1, bomLength: 0)
                    showToast("Reinterpretado como ISO-8859-1")
                }
            }
            mode = .text
        }
    }

    func reinterpret(_ enc: TextEnc) {
        guard mode == .text else { return }
        guard !isDirty else {
            showToast("Guarda o descarta los cambios antes de reabrir con otra codificación")
            return
        }
        if !decode(bytes, as: enc, bomLength: FileDoc.bomLength(bytes, for: enc)) {
            showToast("No se puede leer con \(enc.rawValue)")
        }
    }

    func setSaveEncoding(_ enc: TextEnc) {
        guard mode == .text, enc != encoding else { return }
        encoding = enc
        switch enc {
        case .utf16le: bom = Data([0xFF, 0xFE])
        case .utf16be: bom = Data([0xFE, 0xFF])
        case .utf8:
            if bom != Data([0xEF, 0xBB, 0xBF]) { bom = Data() }
        default: bom = Data()
        }
        markTextChanged()
        showToast("Se guardará como \(enc.rawValue)")
    }

    // MARK: Hexadecimal

    private static let digits = Array("0123456789ABCDEF")

    static func hex(_ value: Int, width: Int) -> String {
        var s = String(value, radix: 16, uppercase: true)
        if s.count < width { s = String(repeating: "0", count: width - s.count) + s }
        return s
    }

    static func hexDump(_ d: Data, start: Int, end: Int) -> String {
        var out = ""
        out.reserveCapacity(max(0, end - start) * 4 + 64)
        var i = start
        while i < end {
            let lineEnd = min(i + 16, end)
            out += hex(i, width: 8) + ":"
            var ascii = ""
            var j = i
            while j < lineEnd {
                let b = d[j]
                out += " " + hex(Int(b), width: 2)
                if b >= 32 && b < 127 {
                    ascii.append(Character(UnicodeScalar(b)))
                } else {
                    ascii.append(".")
                }
                j += 1
            }
            if lineEnd - i < 16 {
                out += String(repeating: "   ", count: 16 - (lineEnd - i))
            }
            out += " |" + ascii + "|\n"
            i = lineEnd
        }
        return out
    }

    /// Lee bytes en hexadecimal de un texto. Ignora el desplazamiento ("0000A0:") y la columna ASCII ("|...|").
    static func parseHexPage(_ s: String) -> Data? {
        var out = Data()
        for rawLine in s.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            var line = Substring(rawLine)
            if let colon = line.firstIndex(of: ":") {
                line = line[line.index(after: colon)...]
            }
            if let bar = line.firstIndex(of: "|") {
                line = line[..<bar]
            }
            for token in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                let t = String(token)
                if t.isEmpty || t.count % 2 != 0 { return nil }
                var idx = t.startIndex
                while idx < t.endIndex {
                    let next = t.index(idx, offsetBy: 2)
                    guard let b = UInt8(t[idx..<next], radix: 16) else { return nil }
                    out.append(b)
                    idx = next
                }
            }
        }
        return out
    }

    func loadHexPage(_ page: Int) {
        let p = min(max(0, page), pageCount - 1)
        let start = p * pageSize
        let end = min(bytes.count, start + pageSize)
        suppress = true
        hexPage = p
        hexText = FileDoc.hexDump(bytes, start: start, end: end)
        suppress = false
        hexEdited = false
    }

    /// Aplica a `bytes` lo editado en la página actual.
    @discardableResult
    func commitHexPage() -> Bool {
        guard hexEdited else { return true }
        guard let edited = FileDoc.parseHexPage(hexText) else {
            showToast("Hexadecimal no válido: revisa los bytes")
            return false
        }
        let start = min(bytes.count, hexPage * pageSize)
        let end = min(bytes.count, start + pageSize)
        bytes.replaceSubrange(start..<end, with: edited)
        hexEdited = false
        textStale = true
        objectWillChange.send()
        return true
    }

    func goPage(_ page: Int) {
        guard page >= 0, page < pageCount else { return }
        guard commitHexPage() else { return }
        loadHexPage(page)
        findCursor = hexPage * pageSize - 1
    }

    /// Salta al desplazamiento indicado. Devuelve la línea (0-based) dentro de la página.
    func goToOffset(_ offset: Int) -> Int? {
        guard commitHexPage() else { return nil }
        let clamped = min(max(0, offset), max(0, bytes.count - 1))
        loadHexPage(clamped / pageSize)
        findCursor = clamped - 1
        return (clamped % pageSize) / 16
    }

    /// Busca la siguiente coincidencia del patrón y salta a ella.
    func findNext(_ pattern: Data) -> Int? {
        guard !pattern.isEmpty, commitHexPage() else { return nil }
        let start = min(bytes.count, max(0, findCursor + 1))
        var found: Int?
        if let r = bytes.range(of: pattern, options: [], in: start..<bytes.count) {
            found = r.lowerBound
        } else if start > 0, let r = bytes.range(of: pattern, options: [], in: 0..<bytes.count) {
            found = r.lowerBound
        }
        guard let offset = found else { return nil }
        let line = goToOffset(offset)
        findCursor = offset
        return line
    }

    // MARK: Guardado

    func encodeText() -> Data? {
        var s = text
        if lineEnding != .lf {
            s = s.replacingOccurrences(of: "\n", with: lineEnding.string)
        }
        guard let body = s.data(using: encoding.ns, allowLossyConversion: false) else {
            showToast("\(encoding.rawValue) no puede representar algunos caracteres")
            return nil
        }
        var data = bom
        data.append(body)
        return data
    }

    func save() {
        let data: Data
        if mode == .hex {
            guard commitHexPage() else { return }
            data = bytes
        } else {
            guard let encoded = encodeText() else { return }
            data = encoded
        }
        do {
            try FileDoc.writeCoordinated(data, to: url)
            bytes = data
            if mode == .text {
                bytesStale = false
                textStale = false
            }
            isDirty = false
            objectWillChange.send()
            showToast("Guardado")
        } catch {
            errorMessage = "No se pudo guardar: " + error.localizedDescription
        }
    }

    func showToast(_ message: String) {
        toast = message
        toastToken += 1
        let token = toastToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toastToken == token { self?.toast = nil }
        }
    }

    // MARK: Lectura y escritura coordinadas

    static func readCoordinated(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let e = coordinationError { throw e }
        guard let r = result else { throw CocoaError(.fileReadUnknown) }
        return try r.get()
    }

    static func writeCoordinated(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
            do {
                try data.write(to: writeURL)
            } catch {
                writeError = error
            }
        }
        if let e = coordinationError { throw e }
        if let e = writeError { throw e }
    }
}
