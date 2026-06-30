import Foundation
import CryptoKit

public struct IndexResult: Sendable {
    public var processed = 0
    public var indexed = 0
    public var skipped = 0
    public var failed = 0
    /// Bu çalışmada DB'ye ilk kez eklenen (daha önce var olmayan) mesaj satırı sayısı.
    /// "N yeni mail" göstergesi bundan beslenir; güncellenen satırlar bu sayıya dahil değildir.
    public var inserted = 0
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
        cancel: CancellationFlag? = nil,
        progress: ((_ processed: Int, _ total: Int) -> Void)? = nil
    ) throws -> IndexResult {
        let messages = MailStore.discoverMessages(root: root, limit: limit)
        let total = messages.count
        let known = try store.indexedStates()   // id → (mtime, parserVersion)
        let now = Date()

        var result = IndexResult()
        var batch: [MessageRecord] = []
        batch.reserveCapacity(batchSize)
        // Aynı partideki mesajların ek adları (byte çıkarmadan, yalnız parse sonucu adlar).
        var attachmentBatch: [(messageID: String, names: [String])] = []

        for message in messages {
            if cancel?.isCancelled == true { break }
            result.processed += 1

            let id = stableID(for: message.fileURL)
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
                let parsed = EMLXParser.parse(data: try Data(contentsOf: message.fileURL))
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
                result.indexed += 1
            } catch {
                result.failed += 1
            }

            if batch.count >= batchSize {
                result.inserted += try store.upsert(batch)           // önce mesaj satırları (FK)
                try store.replaceAttachments(attachmentBatch)        // sonra ek adları (idempotent)
                batch.removeAll(keepingCapacity: true)
                attachmentBatch.removeAll(keepingCapacity: true)
                progress?(result.processed, total)
            }
        }
        if !batch.isEmpty {
            result.inserted += try store.upsert(batch)
            try store.replaceAttachments(attachmentBatch)
        }
        progress?(result.processed, total)
        return result
    }

    /// Dosya yolundan kararlı bir kimlik üretir (yeniden indekslemede aynı satır güncellenir).
    static func stableID(for url: URL) -> String {
        SHA256.hash(data: Data(url.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
