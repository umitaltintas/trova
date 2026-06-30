import Foundation
import CryptoKit

public struct IndexResult: Sendable {
    public var processed = 0
    public var indexed = 0
    public var skipped = 0
    public var failed = 0
    /// Bu çalışmada DB'ye ilk kez eklenen (daha önce var olmayan) TEKİL mesaj satırı sayısı.
    /// "N yeni mail" göstergesi bundan beslenir; güncellenen VE kopya satırlar bu sayıya dahil değildir.
    public var inserted = 0
    /// Bu çalışmada Message-ID'si zaten BAŞKA bir satırda var olduğu için ATLANAN kopya `.emlx`
    /// sayısı (Apple Mail aynı maili birden çok yere yazar). inserted'a dahil DEĞİLDİR.
    public var duplicates = 0
    /// Bu çalışmada kaynak `.emlx` dosyası artık var olmadığı için (kullanıcı Mail'den silmiş)
    /// DB'den TEMİZLENEN satır sayısı. Yalnız TAM, iptal edilmemiş taramada doldurulur (prune);
    /// kısmi/iptal/limit'li taramada her zaman 0 (eksik `seen` ile yanlışlıkla silme yapılmaz).
    public var removed = 0
}

/// Uzun işlemleri iş parçacıkları arası güvenli biçimde iptal etmek için bayrak.
public final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

/// Mail deposunu gezip `.emlx` dosyalarını ayrıştırarak indeks deposuna yazar.
/// Artımlı: dosya değişiklik zamanı (mtime) ve parser sürümü aynıysa yeniden ayrıştırmaz.
public enum Indexer {
    /// Parser çıktısı değişince artır → tüm kayıtlar bir kez yeniden indekslenir.
    /// v2: okundu/bayraklı flag'leri (.emlx plist trailer'ından) eklendi.
    /// v3: ek adları ayrı `attachment` tablosuna yazılmaya başlandı ("Ekler" görünümü, ada/türe arama).
    public static let currentParserVersion = 3

    public static func run(
        store: IndexStore,
        root: URL,
        limit: Int? = nil,
        batchSize: Int = 500,
        indexAttachmentContent: Bool = false,
        pruneMissing: Bool = true,
        cancel: CancellationFlag? = nil,
        progress: ((_ processed: Int, _ total: Int) -> Void)? = nil
    ) throws -> IndexResult {
        let messages = MailStore.discoverMessages(root: root, limit: limit)
        let total = messages.count
        let known = try store.indexedStates()   // id → (mtime, parserVersion)
        let now = Date()

        var result = IndexResult()
        // Bu taramada GÖRÜLEN tüm `.emlx` id'leri (dosyası diskte var demek). Tarama tam ve iptal
        // edilmeden biterse, bu kümede OLMAYAN satırlar = kaynağı silinmiş mailler → prune edilir.
        var seen = Set<String>()
        seen.reserveCapacity(total)
        var batch: [MessageRecord] = []
        batch.reserveCapacity(batchSize)
        // Aynı partideki mesajların ek adları (byte çıkarmadan, yalnız parse sonucu adlar).
        var attachmentBatch: [(messageID: String, names: [String])] = []
        // Opt-in: ek İÇERİĞİ (OCR'sız ucuz metin). KAPALIYKEN bu liste hiç doldurulmaz.
        var contentBatch: [(messageID: String, text: String)] = []

        // Biriken partiyi yazar: önce mesaj satırları (dedup'lı), sonra YALNIZ eklenen mesajların
        // ek adları/içeriği. Kopya `.emlx` olarak atlanan id'lerin (mesaj satırı yok) eklerini
        // yazmayız — yoksa FK ihlali olur; kanonik satırın ekleri zaten korunur.
        func flush() throws {
            guard !batch.isEmpty else { return }
            let up = try store.upsert(batch)
            result.inserted += up.inserted
            result.duplicates += up.duplicates
            let keptAttachments = up.duplicateIDs.isEmpty ? attachmentBatch
                : attachmentBatch.filter { !up.duplicateIDs.contains($0.messageID) }
            try store.replaceAttachments(keptAttachments)
            if !contentBatch.isEmpty {
                let keptContent = up.duplicateIDs.isEmpty ? contentBatch
                    : contentBatch.filter { !up.duplicateIDs.contains($0.messageID) }
                if !keptContent.isEmpty { try store.replaceAttachmentContents(keptContent) }
            }
            batch.removeAll(keepingCapacity: true)
            attachmentBatch.removeAll(keepingCapacity: true)
            contentBatch.removeAll(keepingCapacity: true)
        }

        for message in messages {
            if cancel?.isCancelled == true { break }
            result.processed += 1

            let id = stableID(for: message.fileURL)
            seen.insert(id)   // dosya enumerasyonda göründü → atlansa/başarısız olsa bile satırı KORU
            let mtime = try? message.fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate

            // Değişmemiş VE aynı parser sürümüyle indekslenmiş dosyayı atla.
            if let mtime, let previous = known[id], let previousMtime = previous.mtime,
               abs(previousMtime.timeIntervalSince(mtime)) < 1,
               previous.parserVersion == currentParserVersion {
                result.skipped += 1
                if result.processed % batchSize == 0 { progress?(result.processed, total) }
                continue
            }

            do {
                let data = try Data(contentsOf: message.fileURL)
                let parsed = EMLXParser.parse(data: data)
                let body = parsed.body
                let normalizedSubject = EMLXParser.normalizeSubject(parsed.subject)
                let threadKey = normalizedSubject.isEmpty ? "id:\(id)" : "s:\(normalizedSubject)"
                let attachments = parsed.attachments.isEmpty ? nil
                    : parsed.attachments.joined(separator: "\n")
                let flags = parsed.emailFlags   // flags yoksa nil → kolonlar NULL
                batch.append(MessageRecord(
                    id: id,
                    messageID: parsed.messageID,
                    accountID: message.accountID,
                    mailbox: message.mailbox,
                    filePath: message.fileURL.path,
                    fromName: parsed.fromName,
                    fromAddress: parsed.fromAddress,
                    toField: parsed.to,
                    ccField: parsed.cc,
                    subject: parsed.subject,
                    date: parsed.date,
                    snippet: String(body.prefix(280)),
                    body: body,
                    indexedAt: now,
                    fileModified: mtime,
                    inReplyTo: parsed.inReplyTo,
                    threadKey: threadKey,
                    attachments: attachments,
                    parserVersion: currentParserVersion,
                    isRead: flags?.isRead,
                    isFlagged: flags?.isFlagged))
                // Ek adlarını ayrı tabloya yazmak üzere biriktir (mesaj satırıyla aynı partide).
                attachmentBatch.append((messageID: id, names: parsed.attachments))
                // Opt-in AÇIKsa ve ek varsa: eklerin İÇERİĞİNDEN ucuz metni (OCR'sız) çıkar.
                // KAPALIYKEN bu adım tamamen atlanır → davranış birebir korunur.
                if indexAttachmentContent, !parsed.attachments.isEmpty {
                    contentBatch.append((messageID: id, text: attachmentContentText(from: data)))
                }
                result.indexed += 1
            } catch {
                result.failed += 1
            }

            if batch.count >= batchSize {
                try flush()
                progress?(result.processed, total)
            }
        }
        try flush()
        progress?(result.processed, total)

        // Prune (silinen mailleri DB'den düş): YALNIZ tam, iptal edilmemiş, limit'siz bir taramada.
        // Aşağıdaki koşullardan herhangi biri varsa `seen` EKSİK olabilir → asla silme (yanlışlıkla
        // tüm DB'yi süpürme felaketini önler):
        //  • pruneMissing kapalı (örn. FSEvents/autoSync kısmi-davranış kaygısı),
        //  • iptal edildi (kullanıcı durdurdu — kalan dosyalar görülmedi),
        //  • limit verildi (yalnız ilk N dosya gezildi),
        //  • hiç dosya görülmedi (boş/erişim sorunu — boş `seen` ile her şeyi silmeyiz).
        let completed = cancel?.isCancelled != true
        if pruneMissing, limit == nil, completed, !seen.isEmpty {
            result.removed = try store.pruneMissing(keepIDs: seen)
        }
        return result
    }

    /// Ek içeriği backfill geçişi (opt-in toggle AÇIKken kullanıcı tetikler): eki olan TÜM
    /// mailleri gezer, eklerinden OCR'SIZ ucuz metni (PDF metin katmanı + düz metin) çıkarır ve
    /// `attachment_content` FTS tablosuna yazar. Artımlı indeksleme (mtime-skip) yüzünden yeniden
    /// işlenmeyen mevcut maillerin içeriğini de kapsar — bu yüzden ayrı bir geçiş gerekir.
    /// `parserVersion`'a DOKUNMAZ (kimseyi yeniden indekslemeye zorlamaz). İptal + ilerleme destekli.
    /// Dönüş: içerik (boş olmayan metin) yazılan mail sayısı.
    @discardableResult
    public static func indexAttachmentContentPass(
        store: IndexStore,
        batchSize: Int = 100,
        cancel: CancellationFlag? = nil,
        progress: ((_ processed: Int, _ total: Int) -> Void)? = nil
    ) throws -> Int {
        let messages = try store.messagesWithAttachments()
        let total = messages.count
        var processed = 0
        var written = 0
        var batch: [(messageID: String, text: String)] = []
        batch.reserveCapacity(batchSize)

        func flush() throws {
            guard !batch.isEmpty else { return }
            try store.replaceAttachmentContents(batch)
            batch.removeAll(keepingCapacity: true)
        }

        for message in messages {
            if cancel?.isCancelled == true { break }
            processed += 1
            if let data = try? Data(contentsOf: URL(fileURLWithPath: message.filePath)) {
                // Boş metinde de satırı yeniden yazarız (idempotent; eski içerik bayatlamasın).
                let text = attachmentContentText(from: data)
                batch.append((messageID: message.id, text: text))
                if !text.isEmpty { written += 1 }
            }
            if batch.count >= batchSize {
                try flush()
                progress?(processed, total)
            }
        }
        try flush()
        progress?(processed, total)
        return written
    }

    /// Bir mailin tüm eklerinden OCR'SIZ ucuz metni toplar (PDF metin katmanı + düz metin).
    /// Görsel/taranmış ekler atlanır (nil). Toplam uzunluk `maxChars` ile sınırlanır.
    static func attachmentContentText(from data: Data, maxChars: Int = 100_000) -> String {
        let attachments = EMLXParser.extractAttachments(data: data)
        guard !attachments.isEmpty else { return "" }
        var pieces: [String] = []
        var budget = maxChars
        for attachment in attachments where budget > 0 {
            guard let text = AttachmentTextFast.fastText(
                data: attachment.data, fileName: attachment.filename, maxChars: budget),
                  !text.isEmpty else { continue }
            pieces.append(text)
            budget -= text.count
        }
        return pieces.joined(separator: "\n")
    }

    /// Dosya yolundan kararlı bir kimlik üretir (yeniden indekslemede aynı satır güncellenir).
    static func stableID(for url: URL) -> String {
        SHA256.hash(data: Data(url.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
