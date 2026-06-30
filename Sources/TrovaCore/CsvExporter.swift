import Foundation

/// Mail listelerini (arama sonuçları / kişi mailleri / benzer mailler) elektronik tabloya uygun
/// CSV metnine dönüştürür. Saf metin üretimi — yan etkisiz, test edilebilir.
///
/// RFC 4180'e uyar: virgül, çift tırnak ya da satır sonu içeren alanlar çift tırnakla sarılır;
/// alan içindeki `"` karakteri `""` olarak ikilenir. Satır sonu `\r\n`. İlk satır başlıktır.
/// Excel gibi araçlarda Türkçe karakterler doğru görünsün diye metnin başına UTF-8 BOM eklenir.
public enum CsvExporter {

    /// Genel CSV üretici. İlk satır `headers`, ardından her `row` bir satır olur.
    /// `rows` boşsa yalnızca başlık satırı (ve BOM) üretilir. Sağlamlık için her satır
    /// başlık sütun sayısına göre kırpılır/boş alanla tamamlanır (alan sayısı tutarlı kalsın).
    public static func csv(headers: [String], rows: [[String]]) -> String {
        let columnCount = headers.count
        var lines = [encodeRow(headers, columns: columnCount)]
        for row in rows {
            lines.append(encodeRow(row, columns: columnCount))
        }
        // BOM + \r\n ile birleştir; sona da satır sonu koy (araçlarla uyum için).
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// `ExportedListItem` listesinden mail CSV'si üretir.
    /// Sütunlar: Tarih, Gönderen, Konu, Kutu. Tarih için maddenin `dateLabel`'ı kullanılır
    /// (app bunu zaten dolduruyor); `mailbox` nil ise Kutu sütunu boş bırakılır.
    public static func emailList(_ items: [ExportedListItem]) -> String {
        let headers = ["Tarih", "Gönderen", "Konu", "Kutu"]
        let rows = items.map { item in
            [item.dateLabel, item.from, item.subject, item.mailbox ?? ""]
        }
        return csv(headers: headers, rows: rows)
    }

    // MARK: - Yardımcılar

    /// Bir satırı tam olarak `columns` alana sabitleyip (eksikse boş, fazlaysa kırp) CSV satırına çevirir.
    private static func encodeRow(_ fields: [String], columns: Int) -> String {
        var normalized = fields
        if normalized.count < columns {
            normalized.append(contentsOf: Array(repeating: "", count: columns - normalized.count))
        } else if normalized.count > columns {
            normalized = Array(normalized.prefix(columns))
        }
        return normalized.map(escapeField).joined(separator: ",")
    }

    /// Tek bir alanı RFC 4180'e göre kaçışlar: virgül/çift tırnak/CR/LF içeriyorsa çift tırnakla
    /// sarar ve içteki `"` karakterlerini `""` yapar; aksi halde alanı olduğu gibi bırakır.
    private static func escapeField(_ field: String) -> String {
        let needsQuoting = field.contains(",") || field.contains("\"")
            || field.contains("\n") || field.contains("\r")
        guard needsQuoting else { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
