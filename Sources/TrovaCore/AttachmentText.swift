import Foundation
import PDFKit
import Vision
import ImageIO

/// Ek dosyalardan metin çıkarır: PDF (PDFKit), görsel (Vision OCR), düz metin.
/// Tamamen yerel/cihaz-içi — hiçbir şey dışarı gitmez.
public enum AttachmentText {
    public static func extract(_ attachment: EmailAttachment, maxChars: Int = 4000) -> String {
        let name = attachment.filename.lowercased()
        let type = attachment.mimeType.lowercased()

        if type.contains("pdf") || name.hasSuffix(".pdf") {
            if let document = PDFDocument(data: attachment.data),
               let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return String(text.prefix(maxChars))
            }
            return "(PDF metni çıkarılamadı — taranmış/görsel PDF olabilir.)"
        }

        if type.hasPrefix("image")
            || ["png", "jpg", "jpeg", "tiff", "tif", "heic", "gif", "bmp"].contains(where: { name.hasSuffix(".\($0)") }) {
            return ocr(attachment.data, maxChars: maxChars)
        }

        if type.hasPrefix("text") || ["txt", "csv", "md", "log", "json"].contains(where: { name.hasSuffix(".\($0)") }) {
            return String((String(data: attachment.data, encoding: .utf8) ?? "").prefix(maxChars))
        }

        return "(Bu ek türünden metin çıkarılamıyor: \(attachment.mimeType))"
    }

    /// Görselden Vision ile metin tanır (senkron).
    static func ocr(_ data: Data, maxChars: Int) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return "(Görsel okunamadı.)"
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["tr-TR", "en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return "(OCR başarısız: \(error.localizedDescription))"
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? "(Görselde metin bulunamadı.)" : String(text.prefix(maxChars))
    }
}
