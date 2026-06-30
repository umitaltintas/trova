import Foundation
import PDFKit
import AppKit

/// Eklerden OCR'SIZ, ucuz metin çıkarımı — yalnızca hazır metin katmanları okunur:
/// PDF metin katmanı (PDFKit), düz metin (txt/md/log/csv/tsv) ve RTF (öznitelikli metnin düz hâli).
/// Görsel/taranmış içerikler için Vision OCR **çağrılmaz**; bu tür ekler `nil` döner.
/// Toplu (bulk) indekslemede maliyeti düşük tutmak için tasarlanmıştır (pahalı OCR yok).
public enum AttachmentTextFast {
    /// Düz metin olarak çözülecek uzantılar (UTF-8, yoksa Latin1 ile okunur).
    private static let plainTextExtensions: Set<String> =
        ["txt", "text", "md", "markdown", "log", "csv", "tsv"]

    /// Bir ekin ham byte'larından (OCR olmadan) metni çıkarır; çıkarılamıyorsa `nil`.
    /// - pdf: PDFKit metin katmanı (taranmış/görsel PDF'te metin yoktur → nil)
    /// - txt/md/log/csv/tsv: UTF-8 (yoksa Latin1) düz metin
    /// - rtf: öznitelikli metnin düz hâli
    /// - diğer/görsel: nil
    /// Çıktı `maxChars` ile sınırlanır (varsayılan ~100k karakter).
    public static func fastText(data: Data, fileName: String, maxChars: Int = 100_000) -> String? {
        guard !data.isEmpty, maxChars > 0 else { return nil }
        let ext = fileExtension(of: fileName)

        let extracted: String?
        switch ext {
        case "pdf":
            extracted = pdfText(data)
        case "rtf":
            extracted = rtfText(data)
        case let e where plainTextExtensions.contains(e):
            extracted = plainText(data)
        default:
            extracted = nil   // görsel/taranmış/bilinmeyen → OCR'a düşmeden boş bırakılır
        }

        guard let text = extracted else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxChars))
    }

    // MARK: - Tür bazlı çıkarıcılar

    /// PDF metin katmanını okur (PDFKit). Taranmış/görsel PDF'lerde metin katmanı yoktur → nil.
    /// OCR (Vision) **çağrılmaz**; pahalı görsel tanıma toplu indekslemeye sokulmaz.
    private static func pdfText(_ data: Data) -> String? {
        PDFDocument(data: data)?.string
    }

    /// Düz metni UTF-8 ile, olmazsa Latin1 ile çözer (Latin1 her byte dizisini karşılar).
    private static func plainText(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    /// RTF byte'larını öznitelikli metne çevirip düz metnini döndürür (HTML değil → ana iş
    /// parçacığı gerektirmez, arka planda güvenli). Çözülemezse nil.
    private static func rtfText(_ data: Data) -> String? {
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil) else { return nil }
        return attributed.string
    }

    /// Dosya adından küçük harf uzantı (noktasız). Uzantı yoksa boş string döner.
    static func fileExtension(of fileName: String) -> String {
        (fileName as NSString).pathExtension.lowercased()
    }
}
