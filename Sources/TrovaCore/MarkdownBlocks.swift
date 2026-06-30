import Foundation

/// AI çıktılarındaki blok-düzeyi Markdown öğeleri. Satır-içi biçimlendirme (kalın/italik/
/// bağlantı/`kod`) bu noktada ÇÖZÜLMEZ — metinde olduğu gibi korunur; görünüm katmanı her
/// blok metnini ayrıca satır-içi olarak render eder.
public enum MarkdownBlock: Equatable, Sendable {
    /// `#`..`######` başlık. `level` 1..6, `text` satır-içi markdown'ı korur.
    case heading(level: Int, text: String)
    /// Boş satırla ayrılmış paragraf; ardışık düz satırlar `\n` ile tek paragrafta birleşir.
    case paragraph(text: String)
    /// Ardışık `- `/`* `/`+ ` maddeleri. Her madde metni satır-içi markdown'ı korur.
    case bulletList([String])
    /// Ardışık `1.` `2.` … maddeleri. Numara görünümde yeniden üretilebilir.
    case orderedList([String])
    /// ``` ile çitlenmiş (fenced) kod bloğu; dil etiketi atılır, kapanmazsa sona kadar.
    case code(String)
    /// `> ` alıntı; ardışık alıntı satırları `\n` ile birleşir.
    case quote(text: String)
}

/// Saf (yan etkisiz, ağsız) blok-düzeyi Markdown ayrıştırıcı. Streaming sırasında yarım/kapanmamış
/// markdown gelebileceğinden hiçbir durumda çökmez; eksik girdide makul davranır.
public enum MarkdownBlocks {
    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []

        // Ardışık düz satırları biriktiren paragraf tamponu.
        var paragraphBuffer: [String] = []
        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            blocks.append(.paragraph(text: paragraphBuffer.joined(separator: "\n")))
            paragraphBuffer.removeAll()
        }

        var i = 0
        while i < lines.count {
            let raw = lines[i]
            // Algılama için baştaki boşlukları at; satır içi/sondaki içerik gerekirse ayrıca temizlenir.
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            // 1) Fenced kod bloğu: ``` açar, ``` kapatır (kapanmazsa metnin sonuna kadar).
            if trimmed.hasPrefix("```") {
                flushParagraph()
                i += 1   // açılış satırını (ve dil etiketini) atla
                var codeLines: [String] = []
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1   // kapanış çitini tüket
                        break
                    }
                    codeLines.append(lines[i])   // iç satırlar girinti dahil aynen korunur
                    i += 1
                }
                blocks.append(.code(codeLines.joined(separator: "\n")))
                continue
            }

            // 2) Boş satır → blokları ayırır.
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // 3) Başlık: satır başında 1-6 `#` + boşluk.
            if let heading = Self.heading(from: trimmed) {
                flushParagraph()
                blocks.append(heading)
                i += 1
                continue
            }

            // 4) Alıntı: `>` ile başlayan ardışık satırlar birleşir.
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while i < lines.count {
                    let q = lines[i].trimmingCharacters(in: .whitespaces)
                    guard q.hasPrefix(">") else { break }
                    var content = String(q.dropFirst())     // baştaki `>` atılır
                    if content.hasPrefix(" ") { content.removeFirst() }
                    quoteLines.append(content)
                    i += 1
                }
                blocks.append(.quote(text: quoteLines.joined(separator: "\n")))
                continue
            }

            // 5) Madde işaretli liste: ardışık `- `/`* `/`+ ` maddeleri gruplanır.
            if Self.bulletItem(from: trimmed) != nil {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    guard let item = Self.bulletItem(from: lines[i].trimmingCharacters(in: .whitespaces))
                    else { break }
                    items.append(item)
                    i += 1
                }
                blocks.append(.bulletList(items))
                continue
            }

            // 6) Numaralı liste: ardışık `^\d+\.\s` maddeleri gruplanır.
            if Self.orderedItem(from: trimmed) != nil {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    guard let item = Self.orderedItem(from: lines[i].trimmingCharacters(in: .whitespaces))
                    else { break }
                    items.append(item)
                    i += 1
                }
                blocks.append(.orderedList(items))
                continue
            }

            // 7) Aksi halde düz paragraf satırı.
            paragraphBuffer.append(trimmed)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    // MARK: - Satır çözümleyicileri

    /// Satır başında 1-6 `#` ve ardından boşluk varsa başlığı döndürür; aksi halde nil.
    private static func heading(from line: String) -> MarkdownBlock? {
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "#", level < 6 {
            level += 1
            idx = line.index(after: idx)
        }
        guard level >= 1, idx < line.endIndex, line[idx] == " " || line[idx] == "\t" else { return nil }
        let text = line[idx...].trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: text)
    }

    /// `- `/`* `/`+ ` ile başlıyorsa madde metnini (satır-içi korunmuş) döndürür.
    private static func bulletItem(from line: String) -> String? {
        guard let first = line.first, first == "-" || first == "*" || first == "+" else { return nil }
        let after = line.index(after: line.startIndex)
        guard after < line.endIndex, line[after] == " " || line[after] == "\t" else { return nil }
        return line[line.index(after: after)...].trimmingCharacters(in: .whitespaces)
    }

    /// `\d+.` + boşluk ile başlıyorsa madde metnini (satır-içi korunmuş) döndürür.
    private static func orderedItem(from line: String) -> String? {
        var idx = line.startIndex
        var digits = 0
        while idx < line.endIndex, line[idx].isNumber {
            digits += 1
            idx = line.index(after: idx)
        }
        guard digits > 0, idx < line.endIndex, line[idx] == "." else { return nil }
        let afterDot = line.index(after: idx)
        guard afterDot < line.endIndex, line[afterDot] == " " || line[afterDot] == "\t" else { return nil }
        return line[line.index(after: afterDot)...].trimmingCharacters(in: .whitespaces)
    }
}
