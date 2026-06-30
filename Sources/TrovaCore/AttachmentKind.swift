import Foundation

/// Bir e-posta ekinin kaba kategorisi (ada/uzantıya göre). UI'da çip + ikon olarak gösterilir.
public enum AttachmentKind: String, CaseIterable, Sendable {
    case pdf, image, sheet, doc, presentation, archive, audio, video, code, other

    /// Türkçe görünen etiket (kategori çipi).
    public var label: String {
        switch self {
        case .pdf:          "PDF"
        case .image:        "Görsel"
        case .sheet:        "Tablo"
        case .doc:          "Belge"
        case .presentation: "Sunum"
        case .archive:      "Arşiv"
        case .audio:        "Ses"
        case .video:        "Video"
        case .code:         "Kod"
        case .other:        "Diğer"
        }
    }

    /// Bu kategoriye düşen bilinen dosya uzantıları (SQL `ext IN (...)` filtresi ve testler için).
    /// `AttachmentName` uzantı→kategori eşlemesiyle tek kaynaktan türetilir (tutarlılık garantisi).
    /// `.other` için boş küme döner (hiçbir uzantı doğrudan `.other`'a eşlenmez).
    public var extensions: Set<String> {
        Set(AttachmentName.extensions(for: self))
    }

    /// Kategoriyi temsil eden SF Symbol adı.
    public var systemImage: String {
        switch self {
        case .pdf:          "doc.richtext"
        case .image:        "photo"
        case .sheet:        "tablecells"
        case .doc:          "doc.text"
        case .presentation: "play.rectangle"
        case .archive:      "archivebox"
        case .audio:        "waveform"
        case .video:        "film"
        case .code:         "chevron.left.forwardslash.chevron.right"
        case .other:        "paperclip"
        }
    }
}

/// Ek dosya adından uzantı/kategori çıkaran saf yardımcılar (byte çözmeden, yalnız ad üzerinden).
public enum AttachmentName {

    /// Uzantı → kategori eşlemesi (tek kaynak). Burada olmayan her uzantı — ve uzantısız adlar —
    /// `.other` sayılır. Anahtarlar küçük harftir (uzantı zaten küçük harfe indirilerek aranır).
    private static let extensionKinds: [String: AttachmentKind] = [
        "pdf": .pdf,
        "png": .image, "jpg": .image, "jpeg": .image, "gif": .image, "heic": .image, "webp": .image,
        "xls": .sheet, "xlsx": .sheet, "csv": .sheet, "numbers": .sheet,
        "doc": .doc, "docx": .doc, "pages": .doc, "txt": .doc, "rtf": .doc,
        "ppt": .presentation, "pptx": .presentation, "key": .presentation,
        "zip": .archive, "rar": .archive, "7z": .archive, "gz": .archive, "tar": .archive,
        "mp3": .audio, "wav": .audio, "m4a": .audio,
        "mp4": .video, "mov": .video, "avi": .video,
        "swift": .code, "js": .code, "py": .code, "json": .code, "xml": .code, "html": .code,
    ]

    /// Dosya adının küçük harf uzantısı. Uzantısız → ""; çok noktalıda son parça
    /// ("rapor.final.pdf" → "pdf"); baş nokta (dotfile, ".gitignore") ve son nokta ("rapor.")
    /// güvenli biçimde "" döndürür.
    public static func ext(of fileName: String) -> String {
        // Olası yol bileşenlerini at, yalnız son ad parçasıyla çalış.
        let name = (fileName as NSString).lastPathComponent
        // Baştaki nokta (dotfile) bir uzantı ayırıcısı sayılmaz.
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }

    /// Dosya adından kategori (uzantı eşlemesine göre; bilinmeyen/uzantısız → `.other`).
    public static func kind(of fileName: String) -> AttachmentKind {
        kind(ofExt: ext(of: fileName))
    }

    /// Önceden çıkarılmış (küçük harf) uzantıdan kategori.
    static func kind(ofExt ext: String) -> AttachmentKind {
        extensionKinds[ext] ?? .other
    }

    /// Bir kategoriye düşen bilinen tüm uzantılar (SQL `ext IN (...)` filtresi için).
    static func extensions(for kind: AttachmentKind) -> [String] {
        extensionKinds.compactMap { $0.value == kind ? $0.key : nil }
    }

    /// Eşlemede tanımlı tüm uzantılar (`.other` için `ext NOT IN (...)` filtresine).
    static var knownExtensions: [String] {
        Array(extensionKinds.keys)
    }
}
