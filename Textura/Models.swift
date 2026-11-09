import Foundation
import SwiftUI

// MARK: - Navegación

struct Route: Hashable {
    let url: URL
    let isDirectory: Bool
}

// MARK: - Acceso a archivos externos (security-scoped)

/// Mantiene abierto el acceso a los archivos/carpetas elegidos por el usuario
/// mientras dure la sesión. Se evita cerrar el acceso al navegar entre pantallas.
final class Access {
    static let shared = Access()
    private var started = Set<String>()
    private init() {}

    func start(_ url: URL) {
        let key = url.standardizedFileURL.path
        if started.contains(key) { return }
        if url.startAccessingSecurityScopedResource() {
            started.insert(key)
        }
    }
}

// MARK: - Recientes

struct RecentItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var path: String
    var isFolder: Bool
    var bookmark: Data
    var date: Date
}

final class Recents: ObservableObject {
    @Published private(set) var items: [RecentItem] = []
    private let key = "textura.recents.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([RecentItem].self, from: data) {
            items = decoded
        }
    }

    func add(url: URL, isFolder: Bool) {
        guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return
        }
        let path = url.standardizedFileURL.path
        items.removeAll(where: { $0.path == path && $0.isFolder == isFolder })
        let item = RecentItem(name: url.lastPathComponent, path: path, isFolder: isFolder, bookmark: bookmark, date: Date())
        items.insert(item, at: 0)
        if items.count > 30 {
            items = Array(items.prefix(30))
        }
        persist()
    }

    func resolve(_ item: RecentItem) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: item.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    func remove(_ item: RecentItem) {
        items.removeAll(where: { $0.id == item.id })
        persist()
    }

    func clear() {
        items = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Codificaciones y finales de línea

enum TextEnc: String, CaseIterable, Identifiable {
    case utf8 = "UTF-8"
    case utf16le = "UTF-16 LE"
    case utf16be = "UTF-16 BE"
    case latin1 = "ISO-8859-1"
    case win1252 = "Windows-1252"
    case macRoman = "Mac Roman"
    case shiftJIS = "Shift-JIS"
    case ascii = "ASCII"

    var id: String { rawValue }

    var ns: String.Encoding {
        switch self {
        case .utf8: return .utf8
        case .utf16le: return .utf16LittleEndian
        case .utf16be: return .utf16BigEndian
        case .latin1: return .isoLatin1
        case .win1252: return .windowsCP1252
        case .macRoman: return .macOSRoman
        case .shiftJIS: return .shiftJIS
        case .ascii: return .ascii
        }
    }
}

enum LineEnding: String, CaseIterable, Identifiable {
    case lf = "LF"
    case crlf = "CRLF"
    case cr = "CR"

    var id: String { rawValue }

    var string: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        case .cr: return "\r"
        }
    }
}

enum ViewMode {
    case text
    case hex
}

// MARK: - Iconos por tipo de archivo

enum FileKind {
    static func icon(for url: URL, isDirectory: Bool) -> String {
        if isDirectory { return "folder.fill" }
        switch url.pathExtension.lowercased() {
        case "json", "xml", "plist", "yaml", "yml", "toml":
            return "curlybraces"
        case "ini", "cfg", "conf", "config", "properties":
            return "slider.horizontal.3"
        case "pnach", "cht", "pat", "cheat", "gct", "ggcode", "wlb":
            return "gamecontroller.fill"
        case "ips", "bps", "ups", "ppf", "xdelta", "vcdiff", "aps", "rup",
             "bin", "rom", "gba", "gb", "gbc", "nes", "sfc", "smc", "n64", "z64", "v64",
             "nds", "3ds", "iso", "cue", "sav", "srm", "state":
            return "cpu"
        case "swift", "c", "h", "cpp", "hpp", "m", "mm", "py", "js", "ts", "lua", "rb",
             "sh", "bat", "cmd", "asm", "s", "java", "kt", "go", "rs", "php", "html", "css":
            return "chevron.left.forwardslash.chevron.right"
        case "patch", "diff":
            return "plusminus"
        case "md", "markdown", "txt", "rtf", "log", "csv", "tsv":
            return "doc.text"
        default:
            return "doc"
        }
    }
}
