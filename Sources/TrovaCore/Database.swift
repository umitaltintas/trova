import Foundation
import GRDB
import Accelerate

/// İndekslenmiş tek bir mailin veritabanı kaydı.
public struct MessageRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "message"

    public var id: String              // kararlı kimlik (dosya yolunun SHA256'sı)
    public var messageID: String?      // RFC822 Message-ID
    public var accountID: String
    public var mailbox: String
    public var filePath: String
    public var fromName: String?
    public var fromAddress: String?
    public var toField: String?
    public var ccField: String?
    public var subject: String?
    public var date: Date?
    public var snippet: String?
    public var body: String?
    public var indexedAt: Date
    public var fileModified: Date?     // artımlı indeksleme için dosya mtime'ı
    public var inReplyTo: String?
    public var threadKey: String?      // konu gruplama anahtarı
    public var attachments: String?    // ek dosya adları, satırsonu ile birleşik (FTS için)
    public var parserVersion: Int      // parser çıktısı değişince yeniden indeksleme tetikler
    public var isRead: Bool?           // .emlx flag'inden: okundu mu (bilinmiyorsa nil)
    public var isFlagged: Bool?        // .emlx flag'inden: bayraklı mı (bilinmiyorsa nil)

    public init(id: String, messageID: String?, accountID: String, mailbox: String,
                filePath: String, fromName: String?, fromAddress: String?, toField: String?,
                ccField: String?, subject: String?, date: Date?, snippet: String?,
                body: String?, indexedAt: Date, fileModified: Date? = nil,
                inReplyTo: String? = nil, threadKey: String? = nil,
                attachments: String? = nil, parserVersion: Int = 0,
                isRead: Bool? = nil, isFlagged: Bool? = nil) {
        self.id = id
        self.messageID = messageID
        self.accountID = accountID
        self.mailbox = mailbox
        self.filePath = filePath
        self.fromName = fromName
        self.fromAddress = fromAddress
        self.toField = toField
        self.ccField = ccField
        self.subject = subject
        self.date = date
        self.snippet = snippet
        self.body = body
        self.indexedAt = indexedAt
        self.fileModified = fileModified
        self.inReplyTo = inReplyTo
        self.threadKey = threadKey
        self.attachments = attachments
        self.parserVersion = parserVersion
        self.isRead = isRead
        self.isFlagged = isFlagged
    }
}

/// Tek bir arama sonucu (FTS5 + bm25 sıralaması).
public struct SearchHit: Sendable, Identifiable {
    public let id: String
    public var messageID: String? = nil  // RFC822 Message-ID (yalnız taşıyan sorgular doldurur; "Mail'de Aç" için)
    public let subject: String?
    public let fromName: String?
    public let fromAddress: String?
    public let mailbox: String
    public let date: Date?
    public let snippet: String
    public let score: Double
    public var threadKey: String? = nil
    public var attachments: [String] = []
    public var isRead: Bool? = nil       // okundu mu (bilinmiyorsa nil → rozet gösterilmez)
    public var isFlagged: Bool? = nil    // bayraklı mı (bilinmiyorsa nil → rozet gösterilmez)
    public var matchedInAttachment: Bool = false   // sonuç ek içeriği aramasından mı geldi (rozet için)
    public var isPinned: Bool? = nil     // Trova-yerel yıldızlı mı (bilinmiyorsa nil → app pinnedIDs ile işaretler)
}

/// En çok yazışılan bir kişinin özeti ("Kişiler" görünümü için).
public struct SenderStat: Sendable, Equatable, Identifiable {
    public let name: String?
    public let address: String
    public let count: Int
    public var id: String { address }
    public init(name: String?, address: String, count: Int) {
        self.name = name; self.address = address; self.count = count
    }
}

/// Bir ayın mail sayısı ("Genel Bakış" aylık hacim grafiği için). month: "yyyy-MM".
public struct MonthCount: Sendable, Equatable, Identifiable {
    public let month: String
    public let count: Int
    public var id: String { month }
    public init(month: String, count: Int) { self.month = month; self.count = count }
}

/// Bir ayın gelen/gönderilen mail sayıları ("Genel Bakış" gelen vs gönderilen grafiği için).
/// Ay anahtarlama MonthCount ile aynıdır (yıl + ay); `received` + `sent`, o ayın toplam mail
/// sayısına (monthlyCounts) eşittir — kutu filtresi yoktur.
public struct MonthSentReceived: Sendable, Equatable, Identifiable {
    public let year: Int
    public let month: Int          // 1...12
    public let received: Int       // gelen (gönderilmiş olmayan tüm kutular)
    public let sent: Int           // gönderilen (isSentMailbox)
    public var id: String { String(format: "%04d-%02d", year, month) }
    public init(year: Int, month: Int, received: Int, sent: Int) {
        self.year = year; self.month = month; self.received = received; self.sent = sent
    }
}

/// Ay numarasını (1...12) kısa Türkçe ay adına çeviren saf, paylaşılan yardımcı ("Kas").
/// Hem MonthCount hem MonthSentReceived grafik ekseni etiketleri bunu kullanır (kopyalama yok).
/// Aralık dışındaysa nil döner; çağıran uygun bir geri-dönüş seçer.
public enum TurkishMonth {
    public static let shortNames = ["Oca", "Şub", "Mar", "Nis", "May", "Haz",
                                    "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]
    public static func short(_ month: Int) -> String? {
        guard (1...12).contains(month) else { return nil }
        return shortNames[month - 1]
    }
}

/// Haftanın bir gününe düşen mail sayısı ("Genel Bakış" haftanın günü grafiği için).
/// `weekday`: SABİT 1=Pazartesi ... 7=Pazar (locale firstWeekday'den bağımsız, deterministik).
public struct WeekdayCount: Sendable, Equatable, Identifiable {
    public let weekday: Int        // 1=Pazartesi .. 7=Pazar
    public let count: Int
    public var id: Int { weekday }
    public init(weekday: Int, count: Int) { self.weekday = weekday; self.count = count }
}

/// Haftanın gün numarasını (1=Pazartesi ... 7=Pazar) kısa Türkçe ada çeviren saf, paylaşılan
/// yardımcı ("Pzt"). Grafik ekseni etiketleri bunu kullanır (TurkishMonth deseni gibi).
/// Aralık dışındaysa nil döner; çağıran uygun bir geri-dönüş seçer.
public enum TurkishWeekday {
    public static let shortNames = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]
    public static func short(_ weekday: Int) -> String? {
        guard (1...7).contains(weekday) else { return nil }
        return shortNames[weekday - 1]
    }
}

/// Bir kişinin mini analitiği ("Kişiler" detayında gösterilir).
public struct SenderDetail: Sendable, Equatable {
    public let total: Int
    public let withAttachments: Int
    public let firstDate: Date?
    public let lastDate: Date?
    public init(total: Int, withAttachments: Int, firstDate: Date?, lastDate: Date?) {
        self.total = total; self.withAttachments = withAttachments
        self.firstDate = firstDate; self.lastDate = lastDate
    }
}

/// Arama filtresi: hesap ve tarih aralığı.
public struct SearchFilter: Sendable, Equatable {
    public var accountID: String?
    public var since: Date?
    public var until: Date?
    public var fromContains: String?      // gönderen adı/e-postasında geçen metin (kimden:/from: operatörü)
    public var mailboxContains: String?   // posta kutusu adında geçen metin (kutu:/mailbox: operatörü; parça, büyük/küçük harf duyarsız)
    public var hasAttachment: Bool        // yalnızca ekli mailler (has:attachment operatörü)
    public var attachmentKind: AttachmentKind?  // yalnızca belirli türde eki olan mailler (has:pdf gibi; nil → etkisiz)
    public var unreadOnly: Bool           // yalnızca okunmamış mailler (isRead = 0)
    public var flaggedOnly: Bool          // yalnızca bayraklı mailler (isFlagged = 1)
    public var pinnedOnly: Bool           // yalnızca Trova-yerel yıldızlı (pinned) mailler
    public init(accountID: String? = nil, since: Date? = nil, until: Date? = nil,
                fromContains: String? = nil, mailboxContains: String? = nil,
                hasAttachment: Bool = false,
                attachmentKind: AttachmentKind? = nil,
                unreadOnly: Bool = false, flaggedOnly: Bool = false,
                pinnedOnly: Bool = false) {
        self.accountID = accountID; self.since = since; self.until = until
        self.fromContains = fromContains; self.mailboxContains = mailboxContains
        self.hasAttachment = hasAttachment
        self.attachmentKind = attachmentKind
        self.unreadOnly = unreadOnly; self.flaggedOnly = flaggedOnly
        self.pinnedOnly = pinnedOnly
    }
    public var isEmpty: Bool {
        accountID == nil && since == nil && until == nil && fromContains == nil
            && mailboxContains == nil
            && !hasAttachment && attachmentKind == nil && !unreadOnly && !flaggedOnly && !pinnedOnly
    }
}

/// Artımlı indeksleme için kaydın mevcut durumu.
public struct IndexedState: Sendable {
    public let mtime: Date?
    public let parserVersion: Int
}

/// `IndexStore.upsert` sonucu. `inserted`: DB'ye ilk kez giren TEKİL satır sayısı ("N yeni mail").
/// `duplicates`: aynı Message-ID zaten BAŞKA bir id'de var olduğu için EKLENMEYEN kopya `.emlx`
/// sayısı (inserted'a dahil DEĞİL). `duplicateIDs`: o kopyaların id'leri — çağıran bunların
/// eklerini/içeriğini yazmayı atlasın (yoksa olmayan mesaj satırına FK ihlali olur).
public struct UpsertResult: Sendable, Equatable {
    public var inserted: Int
    public var duplicates: Int
    public var duplicateIDs: Set<String>
    public init(inserted: Int = 0, duplicates: Int = 0, duplicateIDs: Set<String> = []) {
        self.inserted = inserted; self.duplicates = duplicates; self.duplicateIDs = duplicateIDs
    }
}

/// Ajanın oturumlar arası hatırladığı kalıcı bir bilgi (tercih, kişi/proje, talimat).
public struct Memory: Sendable, Identifiable {
    public let id: String
    public let text: String
    public let createdAt: Date
    public init(id: String, text: String, createdAt: Date) {
        self.id = id; self.text = text; self.createdAt = createdAt
    }
}

/// Kalıcı bir sohbetin geçmiş listesi için özeti (başlık + son güncelleme + tur sayısı).
public struct ConversationSummary: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let updatedAt: Date
    public let turnCount: Int
    public init(id: String, title: String, updatedAt: Date, turnCount: Int) {
        self.id = id; self.title = title; self.updatedAt = updatedAt; self.turnCount = turnCount
    }
}

/// Aranabilir tek bir e-posta eki satırı ("Ekler" görünümü için) — sahip mesajla birleştirilmiş.
public struct AttachmentRow: Sendable, Identifiable, Equatable {
    public let id: Int64           // `attachment` tablosunun satır kimliği (liste için kararlı kimlik)
    public let fileName: String    // ek dosya adı
    public let ext: String         // küçük harf uzantı (filtre/ikon)
    public let messageID: String   // sahip mesajın kararlı id'si (message.id) — RFC822 Message-ID DEĞİL
    public let subject: String?    // sahip mesajın konusu
    public let fromName: String?   // sahip mesajın gönderen adı
    public let fromAddress: String?// sahip mesajın gönderen e-postası
    public let date: Date?         // sahip mesajın tarihi (göreli zaman gösterimi için)
    public let filePath: String    // sahip `.emlx` yolu (eki çıkarıp açmak için)

    /// Ad/uzantıdan türetilen kategori (çip ikonu).
    public var kind: AttachmentKind { AttachmentName.kind(ofExt: ext) }

    public init(id: Int64, fileName: String, ext: String, messageID: String,
                subject: String?, fromName: String?, fromAddress: String?,
                date: Date?, filePath: String) {
        self.id = id; self.fileName = fileName; self.ext = ext; self.messageID = messageID
        self.subject = subject; self.fromName = fromName; self.fromAddress = fromAddress
        self.date = date; self.filePath = filePath
    }
}

/// İsimle kaydedilmiş bir arama (sorgu + mod). Sorgu operatör/tarih ifadelerini de içerebilir.
public struct SavedSearch: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let query: String
    public let mode: String
    public init(id: String, name: String, query: String, mode: String) {
        self.id = id; self.name = name; self.query = query; self.mode = mode
    }
}

/// SQLite tabanlı indeks deposu. `message` tablosu + `message_fts` (FTS5) sanal tablosu.
public final class IndexStore: Sendable {
    let dbQueue: DatabaseQueue

    public init(path: URL) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: path.path)
        try Self.migrator.migrate(dbQueue)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "message") { t in
                t.primaryKey("id", .text)
                t.column("messageID", .text)
                t.column("accountID", .text).notNull()
                t.column("mailbox", .text).notNull()
                t.column("filePath", .text).notNull()
                t.column("fromName", .text)
                t.column("fromAddress", .text)
                t.column("toField", .text)
                t.column("ccField", .text)
                t.column("subject", .text)
                t.column("date", .datetime)
                t.column("snippet", .text)
                t.column("body", .text)
                t.column("indexedAt", .datetime).notNull()
            }
            try db.create(index: "idx_message_account", on: "message", columns: ["accountID"])

            // FTS5: tetikleyicilerle `message` tablosuna otomatik senkron edilir.
            // Sütun adları içerik tablosundakilerle eşleşmeli.
            try db.create(virtualTable: "message_fts", using: FTS5()) { t in
                t.synchronize(withTable: "message")
                t.column("subject")
                t.column("fromName")
                t.column("fromAddress")
                t.column("toField")
                t.column("body")
                t.tokenizer = .unicode61()
            }
        }

        // Faz 1: anlamsal arama için vektör deposu (mail başına bir gömme).
        migrator.registerMigration("v2_vectors") { db in
            try db.execute(sql: """
                CREATE TABLE message_vector (
                    id TEXT PRIMARY KEY REFERENCES message(id) ON DELETE CASCADE,
                    dim INTEGER NOT NULL,
                    vector BLOB NOT NULL
                )
                """)
        }

        // Faz 3: artımlı indeksleme için dosya değişiklik zamanı.
        migrator.registerMigration("v3_fileModified") { db in
            try db.execute(sql: "ALTER TABLE message ADD COLUMN fileModified DATETIME")
        }

        // Faz 3+: thread gruplama, ek araması, parser sürümü.
        migrator.registerMigration("v4_threading") { db in
            try db.execute(sql: "ALTER TABLE message ADD COLUMN inReplyTo TEXT")
            try db.execute(sql: "ALTER TABLE message ADD COLUMN threadKey TEXT")
            try db.execute(sql: "ALTER TABLE message ADD COLUMN attachments TEXT")
            try db.execute(sql: "ALTER TABLE message ADD COLUMN parserVersion INTEGER NOT NULL DEFAULT 0")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_message_thread ON message(threadKey)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_message_date ON message(date)")
        }

        // FTS'i ek dosya adlarını da kapsayacak şekilde yeniden kur.
        migrator.registerMigration("v5_fts_attachments") { db in
            // Eski synchronize tetikleyicilerini temizle (yoksa yeniden kurarken çakışır).
            for name in try String.fetchAll(db, sql:
                "SELECT name FROM sqlite_master WHERE type='trigger' AND sql LIKE '%message_fts%'") {
                try db.execute(sql: "DROP TRIGGER IF EXISTS \"\(name)\"")
            }
            try db.execute(sql: "DROP TABLE IF EXISTS message_fts")
            try db.create(virtualTable: "message_fts", using: FTS5()) { t in
                t.synchronize(withTable: "message")
                t.column("subject")
                t.column("fromName")
                t.column("fromAddress")
                t.column("toField")
                t.column("body")
                t.column("attachments")
                t.tokenizer = .unicode61()
            }
        }

        // Faz 6: ajanın oturumlar arası kalıcı hafızası.
        migrator.registerMigration("v6_memory") { db in
            try db.execute(sql: """
                CREATE TABLE agent_memory (
                    id TEXT PRIMARY KEY,
                    text TEXT NOT NULL,
                    createdAt DATETIME NOT NULL
                )
                """)
        }

        // Faz 7: kalıcı sohbet geçmişi (geçmiş sohbetleri yeniden açabilmek için).
        migrator.registerMigration("v7_conversations") { db in
            try db.execute(sql: """
                CREATE TABLE conversation (
                    id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE conversation_turn (
                    id TEXT PRIMARY KEY,
                    conversationId TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
                    idx INTEGER NOT NULL,
                    question TEXT NOT NULL,
                    answer TEXT NOT NULL
                )
                """)
            try db.execute(sql:
                "CREATE INDEX idx_turn_conversation ON conversation_turn(conversationId)")
        }
        migrator.registerMigration("v8_saved_searches") { db in
            try db.execute(sql: """
                CREATE TABLE saved_search (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    query TEXT NOT NULL,
                    mode TEXT NOT NULL,
                    createdAt DATETIME NOT NULL
                )
                """)
        }

        // Faz 9: okunmadı/bayraklı yüzeyi — .emlx flag bitfield'ından çözülen durum.
        // Additive: nullable kolonlar (nil = bilinmiyor); mevcut veri korunur, parser sürümü
        // artışıyla bir kez yeniden indekslenip doldurulur.
        migrator.registerMigration("v9_flags") { db in
            try db.execute(sql: "ALTER TABLE message ADD COLUMN isRead INTEGER")
            try db.execute(sql: "ALTER TABLE message ADD COLUMN isFlagged INTEGER")
        }

        // Faz 10: "Ekler" görünümü — ek adlarını ada/türe göre aranabilir kılan normalize tablo.
        // Additive: yalnız yeni tablo eklenir; mevcut `message` verisi korunur, parser sürümü
        // artışıyla (→3) bir kez yeniden indekslenip doldurulur. `messageID` sütunu sahip mesajın
        // kararlı id'sini (message.id) tutar; mesaj silinince ekleri de gider (ON DELETE CASCADE).
        migrator.registerMigration("v10_attachments") { db in
            try db.create(table: "attachment") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("messageID", .text).notNull()
                    .references("message", onDelete: .cascade)
                t.column("fileName", .text).notNull()
                t.column("ext", .text).notNull()
            }
            try db.create(index: "idx_attachment_message", on: "attachment", columns: ["messageID"])
            try db.create(index: "idx_attachment_ext", on: "attachment", columns: ["ext"])
        }

        // Faz 11: ek içeriği araması (opt-in, varsayılan KAPALI) — eklerin İÇİNDEKİ metni
        // aranabilir kılan AYRI FTS5 tablosu. Additive: mevcut `message_fts` ve tetikleyicileri
        // YENİDEN KURULMAZ, mevcut tablolar/veri korunur; yalnız yeni sanal tablo eklenir.
        // Satırlar tetikleyiciyle değil, `replaceAttachmentContent`/backfill geçişiyle ELLE yazılır.
        // Tokenizer message_fts ile aynı (unicode61) → Türkçe ön ek/eşleşme davranışı tutarlı.
        // `messageID` UNINDEXED: yalnız saklanır (sahip mesajın kararlı id'si), aranmaz.
        migrator.registerMigration("v11_attachment_content") { db in
            try db.create(virtualTable: "attachment_content", using: FTS5()) { t in
                t.column("content")
                t.column("messageID").notIndexed()
                t.tokenizer = .unicode61()
            }
        }

        // Faz 12: Message-ID ile mail tekilleştirme. Apple Mail (Gmail/IMAP) AYNI mantıksal maili
        // birden çok yere yazar (Tüm Postalar + Gelen Kutusu + her etiket) → aynı mail için çok
        // sayıda `.emlx`. Her dosya yolu ayrı `id` ürettiğinden satırlar kopyalarla şişer ve senkron
        // sırasında sürekli "yeni mail" sayılır. `messageID` üzerine index → "bu Message-ID başka bir
        // id'de var mı?" (ileriye dönük dedup) sorgusu ucuzlar. Additive: yalnız index; veri/şema
        // değişmez, mevcut DB bozulmaz.
        migrator.registerMigration("v12_messageID_index") { db in
            try db.execute(sql:
                "CREATE INDEX IF NOT EXISTS idx_message_messageID ON message(messageID)")
        }

        // Faz 13: digest (Bugün) öğelerini "Görmezden gel". Kullanıcının hallettiği "yanıt
        // gerekiyor/bekliyor" öğeleri brifingden düşürülür; KONUYA YENİ yanıt gelirse (öğenin
        // tarihi `dismissedAt`'tan sonraysa) tekrar görünür. Anahtar thread'tir (`threadKey`;
        // yoksa mailin kendi id'si). `dismissedAt` ISO-8601 metin olarak saklanır. Additive:
        // yalnız yeni tablo eklenir; mevcut `message` verisi/şeması korunur.
        migrator.registerMigration("v13_dismissed_digest") { db in
            try db.create(table: "dismissed_digest") { t in
                t.primaryKey("threadKey", .text)
                t.column("dismissedAt", .text).notNull()
            }
        }

        // Faz 14: Trova-yerel "Yıldızlı" (pin) koleksiyonu. iter 21 Apple Mail bayrakları
        // (isRead/isFlagged) SALT-OKUNUR ve .emlx'ten çözülür; bu FARKLIDIR — kullanıcı Trova
        // İÇİNDE herhangi bir maili yıldızlar (Apple Mail'e YAZMADAN). Anahtar mesajın kararlı
        // id'sidir (message.id = dosya yolunun SHA256'sı). Sütun adı mevcut adlandırmayla
        // (dismissed_digest/attachment.messageID) tutarlı olsun diye "messageID" ama DEĞERİ
        // message.id'dir — RFC822 Message-ID DEĞİL. `pinnedAt` ISO-8601 metin saklanır.
        // Additive: yalnız yeni tablo eklenir; mevcut `message` verisi/şeması korunur.
        migrator.registerMigration("v14_pinned") { db in
            try db.create(table: "pinned") { t in
                t.primaryKey("messageID", .text)   // DEĞER = message.id (path-hash), RFC822 Message-ID DEĞİL
                t.column("pinnedAt", .text).notNull()
            }
        }
        return migrator
    }

    /// Kayıtları ekler/günceller (PK çakışmasında satırı değiştirir → FTS tetikleyicileri çalışır).
    /// İleriye dönük tekilleştirme: `messageID` non-nil ve aynı Message-ID BAŞKA bir `id`'ye (dosya
    /// yolu) ait bir satırda zaten varsa, bu kayıt kopya bir `.emlx`'tir → EKLENMEZ (`duplicates`
    /// sayılır). Kendi `id`'sinin satırı (re-upsert → güncelleme) ve NULL/boş `messageID` dedup
    /// EDİLMEZ. Dönüş: ilk kez eklenen tekil satır + atlanan kopya sayısı + kopya id'leri.
    @discardableResult
    public func upsert(_ records: [MessageRecord]) throws -> UpsertResult {
        try dbQueue.write { db in
            var result = UpsertResult()
            for record in records {
                // Bu id (dosya yolu) zaten var mı? Varsa güncelleme; yoksa olası yeni satır.
                let existsForID = try Bool.fetchOne(
                    db, sql: "SELECT EXISTS(SELECT 1 FROM message WHERE id = ?)",
                    arguments: [record.id]) ?? false
                // Kopya `.emlx` kapısı: yalnız YENİ bir id için ve messageID doluysa denetlenir.
                // (Aynı parti içindeki kopyalar da yakalanır: ilk kopya eklenir, sonrakiler bu
                // satırı BAŞKA id'de görüp atlanır.)
                if !existsForID, let mid = record.messageID, !mid.isEmpty {
                    let dupElsewhere = try Bool.fetchOne(
                        db, sql: "SELECT EXISTS(SELECT 1 FROM message WHERE messageID = ? AND id <> ?)",
                        arguments: [mid, record.id]) ?? false
                    if dupElsewhere {
                        result.duplicates += 1
                        result.duplicateIDs.insert(record.id)
                        continue   // kopyayı ekleme → sayı şişmesin, "yeni mail" churn'ü olmasın
                    }
                }
                if !existsForID { result.inserted += 1 }
                try record.insert(db, onConflict: .replace)
            }
            return result
        }
    }

    public func count() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM message") ?? 0
        }
    }

    // MARK: - Tekilleştirme (Faz 12)

    /// NULL olmayan Message-ID'ler arasındaki YİNELENEN (fazladan) satır sayısı:
    /// toplam − farklı Message-ID. `dedupeExisting`'in sileceği satır sayısına eşittir; UI'da
    /// "Yinelenenleri temizle" düğmesi yanında gösterilir. NULL/boş messageID'ler hariç tutulur.
    public func duplicateCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(messageID) - COUNT(DISTINCT messageID) FROM message
                WHERE messageID IS NOT NULL AND messageID <> ''
                """) ?? 0
        }
    }

    /// Mevcut yinelenen mailleri tek seferde temizler (kullanıcı tetikler — otomatik DEĞİL):
    /// aynı non-null `messageID` için bir KANONİK satır tutar, gerisini ve YETİM
    /// `message_vector`/`attachment`/`attachment_content` kayıtlarını siler. Hepsi tek
    /// transaction → FK/veri tutarlı kalır. `.emlx` kaynak olduğundan satır silmek geri-üretilebilir.
    ///
    /// Kanonik seçim (deterministik, veri koruyucu): (a) vektörü (embedding) olan satır — gömme
    /// kaybolmasın; yoksa (b) gelen/gönderilen kutusundaki satır — arşiv/etiket yerine; yoksa
    /// (c) en küçük rowid. Dönüş: silinen (kopya) satır sayısı.
    @discardableResult
    public func dedupeExisting(progress: ((_ processed: Int, _ total: Int) -> Void)? = nil) throws -> Int {
        try dbQueue.write { db in
            let dupMessageIDs = try String.fetchAll(db, sql: """
                SELECT messageID FROM message
                WHERE messageID IS NOT NULL AND messageID <> ''
                GROUP BY messageID HAVING COUNT(*) > 1
                """)
            let total = dupMessageIDs.count
            var deleted = 0
            for (i, mid) in dupMessageIDs.enumerated() {
                let rows = try Row.fetchAll(db, sql: """
                    SELECT m.rowid AS rid, m.id AS id, m.mailbox AS mailbox,
                           (v.id IS NOT NULL) AS hasVector
                    FROM message m LEFT JOIN message_vector v ON v.id = m.id
                    WHERE m.messageID = ?
                    """, arguments: [mid])
                guard rows.count > 1 else { continue }
                let keepID = Self.canonicalID(from: rows)
                for row in rows where (row["id"] as String) != keepID {
                    let id: String = row["id"]
                    // FTS (message_fts) tetikleyiciyle senkron; message_vector/attachment FK CASCADE
                    // ile gider — ama attachment_content (FK'siz FTS5) ELLE silinmeli. Tümünü açıkça
                    // silerek FK pragma durumundan bağımsız yetimsizliği garanti ederiz.
                    try db.execute(sql: "DELETE FROM attachment_content WHERE messageID = ?", arguments: [id])
                    try db.execute(sql: "DELETE FROM attachment WHERE messageID = ?", arguments: [id])
                    try db.execute(sql: "DELETE FROM message_vector WHERE id = ?", arguments: [id])
                    try db.execute(sql: "DELETE FROM message WHERE id = ?", arguments: [id])
                    deleted += 1
                }
                progress?(i + 1, total)
            }
            return deleted
        }
    }

    /// Aynı Message-ID'li satırlar arasından tutulacak KANONİK satırın id'sini seçer (yukarıdaki
    /// (a)→(b)→(c) önceliğiyle; rowid benzersiz olduğundan sıralama kesin/total). Saf yardımcı.
    static func canonicalID(from rows: [Row]) -> String {
        func rank(_ row: Row) -> (Int, Int, Int64) {
            let hasVector = ((row["hasVector"] as Int?) ?? 0) != 0
            let mailbox = (row["mailbox"] as String?) ?? ""
            let preferredBox = isActionableMailbox(mailbox) || isSentMailbox(mailbox)
            let rid: Int64 = row["rid"]
            return (hasVector ? 0 : 1, preferredBox ? 0 : 1, rid)   // küçük anahtar kazanır
        }
        let best = rows.min { rank($0) < rank($1) }!
        return best["id"]
    }

    // MARK: - Silinen mailleri temizle (prune)

    /// Tam, iptal edilmemiş bir taramada GÖRÜLEN tüm `.emlx` id'leri (`keepIDs`) DIŞINDA kalan
    /// `message` satırlarını — yani kaynak dosyası artık diskte olmayan (kullanıcı Mail'den silmiş)
    /// mailleri — ve yetim `message_vector`/`attachment`/`attachment_content` kayıtlarını tek
    /// transaction'da siler. `.emlx` kaynak olduğundan satır silmek geri-üretilebilir.
    ///
    /// `keepIDs` on binlerce id içerebileceğinden SQLite'ın bağlı-değişken (`?`) limitine takılmamak
    /// için tek dev bir `IN (...)` yerine geçici tabloya yazılır ve `NOT IN (SELECT ...)` ile küme
    /// bazlı (satır döngüsüz) silinir. Dönüş: silinen `message` satırı sayısı.
    ///
    /// UYARI: `keepIDs` BOŞSA tüm satırlar silinir (uç durum) — çağıran (Indexer) yalnız tam ve
    /// iptal edilmemiş, en az bir dosya görülmüş taramada çağırarak bunu güvenceye alır.
    @discardableResult
    public func pruneMissing(keepIDs: Set<String>) throws -> Int {
        try dbQueue.write { db in
            try db.execute(sql: "DROP TABLE IF EXISTS temp_keep_ids")
            try db.execute(sql: "CREATE TEMP TABLE temp_keep_ids (id TEXT PRIMARY KEY)")
            for id in keepIDs {
                try db.execute(sql: "INSERT OR IGNORE INTO temp_keep_ids (id) VALUES (?)",
                               arguments: [id])
            }
            let removed = try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM message WHERE id NOT IN (SELECT id FROM temp_keep_ids)") ?? 0
            if removed > 0 {
                // FTS (message_fts) tetikleyiciyle senkron; message_vector/attachment FK CASCADE ile
                // gider — ama attachment_content (FK'siz FTS5) ELLE silinmeli. Tümünü açıkça silerek
                // FK pragma durumundan bağımsız yetimsizliği garanti ederiz (dedupeExisting deseni).
                try db.execute(sql:
                    "DELETE FROM attachment_content WHERE messageID NOT IN (SELECT id FROM temp_keep_ids)")
                try db.execute(sql:
                    "DELETE FROM attachment WHERE messageID NOT IN (SELECT id FROM temp_keep_ids)")
                try db.execute(sql:
                    "DELETE FROM message_vector WHERE id NOT IN (SELECT id FROM temp_keep_ids)")
                try db.execute(sql:
                    "DELETE FROM message WHERE id NOT IN (SELECT id FROM temp_keep_ids)")
            }
            try db.execute(sql: "DROP TABLE IF EXISTS temp_keep_ids")
            return removed
        }
    }

    /// Artımlı indeksleme durumu: id → (dosya mtime, parser sürümü).
    public func indexedStates() throws -> [String: IndexedState] {
        try dbQueue.read { db in
            var map: [String: IndexedState] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT id, fileModified, parserVersion FROM message") {
                map[row["id"]] = IndexedState(mtime: row["fileModified"], parserVersion: row["parserVersion"] ?? 0)
            }
            return map
        }
    }

    public func accountIDs() throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT accountID FROM message ORDER BY accountID")
        }
    }

    public func accountCounts() throws -> [(account: String, count: Int)] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT accountID, COUNT(*) AS c FROM message
                GROUP BY accountID ORDER BY c DESC
                """).map { row -> (String, Int) in (row["accountID"], row["c"]) }
        }
    }

    /// FTS5 tam metin araması; bm25 ile sıralanır, gövdeden parça (snippet) döner.
    /// İsteğe bağlı hesap/tarih filtresi uygulanır.
    public func search(query: String, filter: SearchFilter = .init(), limit: Int) throws -> [SearchHit] {
        // Gelişmiş sözdizimi ("tam ifade", -hariç) destekli FTS5 ifadesi; gelişmiş söz dizimi
        // yoksa içeride `ftsPattern`'e düşer → normal/tek-terim arama çıktısı ESKİYLE aynı.
        let pattern = FtsQueryBuilder.build(query)
        guard !pattern.isEmpty else { return [] }
        let (clause, filterArgs) = Self.filterSQL(filter)
        return try dbQueue.read { db in
            var args: [(any DatabaseValueConvertible)?] = [pattern]
            args += filterArgs
            args.append(limit)
            return try Row.fetchAll(db, sql: """
                SELECT m.id AS id, m.subject AS subject, m.fromName AS fromName,
                       m.fromAddress AS fromAddress, m.mailbox AS mailbox, m.date AS date,
                       m.threadKey AS threadKey, m.attachments AS attachments,
                       m.isRead AS isRead, m.isFlagged AS isFlagged,
                       snippet(message_fts, 4, '«', '»', '…', 12) AS snip,
                       bm25(message_fts) AS score
                FROM message_fts
                JOIN message m ON m.rowid = message_fts.rowid
                WHERE message_fts MATCH ?\(clause)
                ORDER BY bm25(message_fts)
                LIMIT ?
                """, arguments: StatementArguments(args)).map(Self.hit(from:))
        }
    }

    /// Ölçütlere uyan mail SAYISINI (içerik değil) döndürür — ajanın nicel/sayma soruları için.
    /// `query` doluysa `search` ile AYNI FTS5 deseni (`FtsQueryBuilder.build` → gelişmiş söz dizimi
    /// + ftsPattern geri-düşüşü) ve aynı
    /// `message_fts JOIN message` yapısı üzerinden eşleşme + filtre sayılır; `query` boş/yalnız
    /// boşluksa FTS atlanır, yalnız `filterSQL` ile `COUNT(*)` yapılır. Mevcut `search`/`browse`
    /// davranışını bozmaz; aynı yardımcıları (ftsPattern/filterSQL) paylaşır.
    public func countMatching(query: String?, filter: SearchFilter = .init()) throws -> Int {
        let (clause, filterArgs) = Self.filterSQL(filter)
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            // Sorgu yok → yalnız filtre ile say (FTS'e gerek yok).
            return try dbQueue.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM message m WHERE 1=1\(clause)",
                                 arguments: StatementArguments(filterArgs)) ?? 0
            }
        }
        let pattern = FtsQueryBuilder.build(trimmed)   // `search` ile AYNI gelişmiş+ftsPattern davranışı
        guard !pattern.isEmpty else { return 0 }   // `search` ile tutarlı: desen boşsa eşleşme yok
        return try dbQueue.read { db in
            var args: [(any DatabaseValueConvertible)?] = [pattern]
            args += filterArgs
            return try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM message_fts
                JOIN message m ON m.rowid = message_fts.rowid
                WHERE message_fts MATCH ?\(clause)
                """, arguments: StatementArguments(args)) ?? 0
        }
    }

    /// Ham bir (kayıtlı) arama sorgusunun şu an kaç maile uyduğunu sayar. `SearchPlanner` ile
    /// operatör/Türkçe tarih ifadesini çözüp FTS metni + filtreye indirir, sonra `countMatching`
    /// çağırır. "Akıllı klasör" canlı eşleşme sayacı için kullanılır (saf sayım — PRF/embedding yok).
    public func countSavedSearch(_ rawQuery: String, now: Date, calendar: Calendar = .current) throws -> Int {
        let plan = SearchPlanner.plan(rawQuery, now: now, calendar: calendar)
        return try countMatching(query: plan.ftsQuery, filter: plan.filter)
    }

    /// Filtreye uyan id kümesi (vektör aramasını kısıtlamak için).
    public func idsMatching(_ filter: SearchFilter) throws -> Set<String> {
        let (clause, filterArgs) = Self.filterSQL(filter)
        return try dbQueue.read { db in
            let sql = "SELECT id FROM message m WHERE 1=1\(clause)"
            let rows = try String.fetchAll(db, sql: sql, arguments: StatementArguments(filterArgs))
            return Set(rows)
        }
    }

    /// Bir thread'deki (aynı konu anahtarı) tüm mailleri tarihe göre döndürür.
    public func thread(forKey key: String) throws -> [SearchHit] {
        try dbQueue.read { db in
            // messageID de seçilir: konuşma zaman çizelgesi (ConversationTimeline) aynı mantıksal
            // mailin farklı kutulardaki kopyalarını RFC822 messageID'ye göre tekilleştirir.
            try Row.fetchAll(db, sql: """
                SELECT id, messageID, subject, fromName, fromAddress, mailbox, date, threadKey,
                       attachments, isRead, isFlagged, snippet AS snip, 0.0 AS score
                FROM message WHERE threadKey = ? ORDER BY date
                """, arguments: [key]).map(Self.hit(from:))
        }
    }

    /// Belirli bir göndericiden (ad/e-posta) gelen son mailler.
    public func fromSender(_ query: String, limit: Int) throws -> [SearchHit] {
        let like = "%\(query)%"
        return try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, subject, fromName, fromAddress, mailbox, date, threadKey, attachments,
                       isRead, isFlagged, snippet AS snip, 0.0 AS score
                FROM message WHERE fromName LIKE ? OR fromAddress LIKE ?
                ORDER BY date DESC LIMIT ?
                """, arguments: [like, like, limit]).map(Self.hit(from:))
        }
    }

    public func senderCount(_ query: String) throws -> Int {
        let like = "%\(query)%"
        return try dbQueue.read { db in
            try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM message WHERE fromName LIKE ? OR fromAddress LIKE ?",
                arguments: [like, like]) ?? 0
        }
    }

    /// Ekli (boş olmayan attachments) mail sayısı.
    public func attachmentCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM message WHERE attachments IS NOT NULL AND attachments <> ''") ?? 0
        }
    }

    // MARK: - Ekler görünümü (Faz 10)

    /// Bir mesajın ek satırlarını idempotent biçimde yeniden yazar (önce siler, sonra ekler).
    /// Reindex'te çift kayıt oluşmaz; boş/yalnız boşluk adlar atlanır. `ext` ad üzerinden türetilir.
    /// Sahip `message` satırı (FK) önceden var olmalıdır.
    public func replaceAttachments(_ items: [(messageID: String, names: [String])]) throws {
        guard !items.isEmpty else { return }
        try dbQueue.write { db in
            for (messageID, names) in items {
                try db.execute(sql: "DELETE FROM attachment WHERE messageID = ?", arguments: [messageID])
                for name in names {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    try db.execute(sql:
                        "INSERT INTO attachment (messageID, fileName, ext) VALUES (?, ?, ?)",
                        arguments: [messageID, trimmed, AttachmentName.ext(of: trimmed)])
                }
            }
        }
    }

    /// Tek bir mesajın ek adlarını yeniden yazar (idempotent) — `replaceAttachments(_:)` sarmalayıcısı.
    public func replaceAttachments(forMessage messageID: String, names: [String]) throws {
        try replaceAttachments([(messageID, names)])
    }

    /// Ekleri ada (LIKE) ve/veya türe göre süzüp, sahip mesajla birleştirerek (en yeni önce) döndürür.
    /// `kind` filtresi uzantı kümesiyle uygulanır: `.other` = bilinen uzantıların hiçbiri değil.
    public func allAttachments(query: String? = nil, kind: AttachmentKind? = nil,
                               limit: Int) throws -> [AttachmentRow] {
        var parts: [String] = []
        var args: [any DatabaseValueConvertible] = []

        if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            parts.append("a.fileName LIKE ?")          // SQLite LIKE ASCII için zaten harf duyarsız
            args.append("%\(query)%")
        }
        if let kind {
            if kind == .other {
                // Bilinen uzantıların hiçbiri değil (uzantısız "" de bilinen değildir → buraya düşer).
                let known = AttachmentName.knownExtensions
                parts.append("a.ext NOT IN (\(databaseQuestionMarks(count: known.count)))")
                args.append(contentsOf: known)
            } else {
                let exts = AttachmentName.extensions(for: kind)
                guard !exts.isEmpty else { return [] }
                parts.append("a.ext IN (\(databaseQuestionMarks(count: exts.count)))")
                args.append(contentsOf: exts)
            }
        }
        let whereClause = parts.isEmpty ? "" : "WHERE " + parts.joined(separator: " AND ")
        args.append(limit)

        return try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT a.id AS id, a.fileName AS fileName, a.ext AS ext, a.messageID AS messageID,
                       m.subject AS subject, m.fromName AS fromName, m.fromAddress AS fromAddress,
                       m.date AS date, m.filePath AS filePath
                FROM attachment a
                JOIN message m ON m.id = a.messageID
                \(whereClause)
                ORDER BY m.date DESC
                LIMIT ?
                """, arguments: StatementArguments(args)).map { row in
                AttachmentRow(
                    id: row["id"], fileName: row["fileName"], ext: row["ext"],
                    messageID: row["messageID"], subject: row["subject"],
                    fromName: row["fromName"], fromAddress: row["fromAddress"],
                    date: row["date"], filePath: row["filePath"])
            }
        }
    }

    /// Kategori başına ek sayısı (çiplerdeki sayılar için). `ext` Swift'te kategoriye eşlenir.
    public func attachmentKindCounts() throws -> [AttachmentKind: Int] {
        let exts = try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT ext FROM attachment")
        }
        var counts: [AttachmentKind: Int] = [:]
        for ext in exts { counts[AttachmentName.kind(ofExt: ext), default: 0] += 1 }
        return counts
    }

    /// Son `months` ayın aylık mail sayıları (en eskiden yeniye, eksik aylar 0 ile doldurulur).
    /// Bucket'lama Swift'te yapılır (saklama formatı/zaman dilimi tutarlılığı için); `now`/`calendar`
    /// enjekte edilebildiğinden deterministik test edilir.
    public func monthlyCounts(months: Int, now: Date, calendar: Calendar = .current) throws -> [MonthCount] {
        guard months > 0 else { return [] }
        let thisMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let cutoff = calendar.date(byAdding: .month, value: -(months - 1), to: thisMonthStart) ?? thisMonthStart

        let dates: [Date] = try dbQueue.read { db in
            try Date.fetchAll(db, sql: "SELECT date FROM message WHERE date >= ?", arguments: [cutoff])
        }

        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = calendar.timeZone
        fmt.dateFormat = "yyyy-MM"

        var order: [String] = []
        var counts: [String: Int] = [:]
        for i in stride(from: months - 1, through: 0, by: -1) {
            let monthDate = calendar.date(byAdding: .month, value: -i, to: thisMonthStart) ?? thisMonthStart
            let label = fmt.string(from: monthDate)
            order.append(label); counts[label] = 0
        }
        for date in dates {
            let label = fmt.string(from: date)
            if counts[label] != nil { counts[label]! += 1 }
        }
        return order.map { MonthCount(month: $0, count: counts[$0] ?? 0) }
    }

    /// Son `months` ayın aylık GELEN/GÖNDERİLEN dağılımı (en eskiden yeniye, eksik aylar (0,0)).
    /// `monthlyCounts` ile AYNI pencere + bucket mantığı (aynı `fmt` anahtarlama, zaman dilimi
    /// tutarlı, `now`/`calendar` enjekte → deterministik test). Tarihi olan TÜM mailler sayılır;
    /// kutu filtresi YOKTUR → her ayda `received` + `sent`, `monthlyCounts(...).count` ile birebir
    /// eşittir. Sınıflandırma: `isSentMailbox(mailbox)` ise `sent`, aksi halde `received` (çöp/spam/
    /// arşiv/taslak da gelen sayılır — monthlyCounts hiçbirini dışlamadığından davranış tutarlı).
    public func monthlySentReceived(months: Int, now: Date,
                                    calendar: Calendar = .current) throws -> [MonthSentReceived] {
        guard months > 0 else { return [] }
        let thisMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let cutoff = calendar.date(byAdding: .month, value: -(months - 1), to: thisMonthStart) ?? thisMonthStart

        let rows: [(date: Date, mailbox: String)] = try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT date, mailbox FROM message WHERE date >= ?",
                             arguments: [cutoff]).map { (date: $0["date"], mailbox: $0["mailbox"] ?? "") }
        }

        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = calendar.timeZone
        fmt.dateFormat = "yyyy-MM"

        // Pencere kovaları (etiket + yıl/ay); yıl/ay aynı takvim/zaman diliminden türetilir → etiketle uyumlu.
        var buckets: [(label: String, year: Int, month: Int)] = []
        var received: [String: Int] = [:]
        var sent: [String: Int] = [:]
        for i in stride(from: months - 1, through: 0, by: -1) {
            let monthDate = calendar.date(byAdding: .month, value: -i, to: thisMonthStart) ?? thisMonthStart
            let label = fmt.string(from: monthDate)
            let comps = calendar.dateComponents([.year, .month], from: monthDate)
            buckets.append((label, comps.year ?? 0, comps.month ?? 0))
            received[label] = 0; sent[label] = 0
        }
        for row in rows {
            let label = fmt.string(from: row.date)
            guard received[label] != nil else { continue }
            if isSentMailbox(row.mailbox) { sent[label]! += 1 } else { received[label]! += 1 }
        }
        return buckets.map {
            MonthSentReceived(year: $0.year, month: $0.month,
                              received: received[$0.label] ?? 0, sent: sent[$0.label] ?? 0)
        }
    }

    /// Tarihi olan TÜM maillerin haftanın gününe göre dağılımı ("Genel Bakış" haftanın günü grafiği).
    /// Bucket'lama Swift'te yapılır (`monthlyCounts` deseni; `calendar` enjekte → deterministik test).
    /// Her zaman 7 eleman döner: Pazartesi→Pazar sırasında (eksik gün count=0). `weekday` SABİT
    /// 1=Pazartesi ... 7=Pazar (locale firstWeekday'den bağımsız); `calendar.component(.weekday)`
    /// Pazar=1..Cmt=7 verir, bunu SABİT eşlemeye dönüştürür. `now`, monthlyCounts ile imza tutarlılığı
    /// için alınır (bucket'lamada kullanılmaz — pencere yok, tüm tarihler sayılır).
    public func weekdayCounts(now: Date, calendar: Calendar = .current) throws -> [WeekdayCount] {
        let dates: [Date] = try dbQueue.read { db in
            try Date.fetchAll(db, sql: "SELECT date FROM message")
        }
        var counts: [Int: Int] = [:]
        for d in 1...7 { counts[d] = 0 }
        for date in dates {
            // Gregoryen Pazar=1..Cmt=7 → SABİT Pzt=1..Paz=7 (locale'den bağımsız, deterministik).
            let weekday = (calendar.component(.weekday, from: date) + 5) % 7 + 1
            counts[weekday]! += 1
        }
        return (1...7).map { WeekdayCount(weekday: $0, count: counts[$0] ?? 0) }
    }

    /// Bir kişinin (gönderen adresi) mini analitiği: toplam, ekli sayısı, ilk/son tarih.
    public func senderStats(address: String) throws -> SenderDetail {
        let key = address.lowercased()
        return try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) AS total,
                       SUM(CASE WHEN attachments IS NOT NULL AND attachments <> '' THEN 1 ELSE 0 END) AS att,
                       MIN(date) AS first, MAX(date) AS last
                FROM message WHERE lower(fromAddress) = ?
                """, arguments: [key]) else {
                return SenderDetail(total: 0, withAttachments: 0, firstDate: nil, lastDate: nil)
            }
            return SenderDetail(
                total: row["total"] ?? 0,
                withAttachments: row["att"] ?? 0,
                firstDate: row["first"], lastDate: row["last"])
        }
    }

    /// En çok mail ALDIĞIN kişiler (gönderen adresine göre). Gönderilenler/çöp gibi kutular
    /// (isActionableMailbox=false) hariç tutulur ki kendi adresin listeyi kirletmesin.
    /// Adres küçük harfle gruplanır; temsilci görünen ad ilk dolu addan alınır.
    ///
    /// `matching` doluysa, gruplamadan ÖNCE ad ya da adres parçasına göre süzülür
    /// (`fromName`/`fromAddress` üzerinde `%q%` LIKE, harf duyarsız; LIKE özel karakterleri
    /// `% _ \` literal aranır). `matching` nil/boş → süzme yok, mevcut davranış birebir korunur.
    /// isActionableMailbox dışlaması her iki durumda da geçerlidir.
    public func topSenders(matching: String? = nil, limit: Int) throws -> [SenderStat] {
        var sql = """
            SELECT fromName AS n, fromAddress AS a, mailbox AS m
            FROM message WHERE fromAddress IS NOT NULL AND fromAddress <> ''
            """
        var args: [any DatabaseValueConvertible] = []
        if let q = matching?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            sql += " AND (fromName LIKE ? ESCAPE '\\' OR fromAddress LIKE ? ESCAPE '\\')"
            let like = "%\(Self.escapeLikePattern(q))%"
            args.append(like); args.append(like)
        }
        let rows = try dbQueue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
        var counts: [String: (name: String?, address: String, count: Int)] = [:]
        for row in rows {
            let mailbox: String = row["m"] ?? ""
            guard isActionableMailbox(mailbox) else { continue }
            let address: String = row["a"] ?? ""
            guard !address.isEmpty else { continue }
            let name: String? = row["n"]
            let key = address.lowercased()
            if var existing = counts[key] {
                existing.count += 1
                if (existing.name?.isEmpty ?? true), let name, !name.isEmpty { existing.name = name }
                counts[key] = existing
            } else {
                counts[key] = (name: (name?.isEmpty == false ? name : nil), address: address, count: 1)
            }
        }
        return counts.values
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { SenderStat(name: $0.name, address: $0.address, count: $0.count) }
    }

    /// LIKE özel karakterlerini (`\` `%` `_`) kaçışlar; `ESCAPE '\'` ile birlikte kullanılınca
    /// kullanıcı girdisi literal aranır (joker olarak yorumlanmaz). Önce `\` kaçışlanmalı.
    static func escapeLikePattern(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "%", with: "\\%")
         .replacingOccurrences(of: "_", with: "\\_")
    }

    // MARK: - Proaktif asistan / triyaj (Faz 7)

    /// Her thread'in (aynı `threadKey`; `threadKey` yoksa `id` kendi thread'i sayılır)
    /// en son tarihli mailini tarihe göre azalan sırada döndürür. Tarihi NULL olanlar elenir.
    /// Tarih eşitliğinde küçük yineleme riski kabul edilir.
    func latestPerThread() throws -> [SearchHit] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT m.id AS id, m.messageID AS messageID, m.subject AS subject, m.fromName AS fromName,
                       m.fromAddress AS fromAddress, m.mailbox AS mailbox, m.date AS date,
                       m.threadKey AS threadKey, m.attachments AS attachments,
                       m.isRead AS isRead, m.isFlagged AS isFlagged,
                       m.snippet AS snip, 0.0 AS score
                FROM message m
                JOIN (SELECT COALESCE(threadKey, id) AS tk, MAX(date) AS md
                      FROM message WHERE date IS NOT NULL GROUP BY tk) t
                  ON COALESCE(m.threadKey, m.id) = t.tk AND m.date = t.md
                WHERE m.date IS NOT NULL
                ORDER BY m.date DESC
                """).map(Self.hit(from:))
        }
    }

    /// Yanıt gerekiyor: thread'in en son maili gelen (işlem gerektiren) bir kutuda —
    /// yani karşı taraf en son yazmış ve henüz yanıtlanmamış. Son 90 günle sınırlı.
    /// Kutu sınıflandırması (sent/çöp/spam… çeşitleri) Swift'te yapılır; SQL'de değil.
    public func needsReply(limit: Int) throws -> [SearchHit] {
        let cutoff = Date().addingTimeInterval(-90 * 86_400)
        return Array(try latestPerThread()
            .filter { isActionableMailbox($0.mailbox) && ($0.date.map { $0 >= cutoff } ?? false) }
            .prefix(limit))
    }

    /// Yanıt bekliyor: thread'in en son mailini SEN göndermişsin (gönderilmiş kutusunda)
    /// ve en az `minDays` gündür yanıt yok (en son mail gönderilmişse yanıt gelmemiş demektir).
    public func waitingOnReply(minDays: Int, limit: Int) throws -> [SearchHit] {
        let now = Date()
        return Array(try latestPerThread()
            .filter { isSentMailbox($0.mailbox) && TriageItem.ageDays(of: $0.date, now: now) >= minDays }
            .prefix(limit))
    }

    /// Son `sinceDays` günde gelen (işlem gerektiren kutulardaki) mailler — günlük brifing için.
    public func recentReceived(sinceDays: Int, limit: Int) throws -> [SearchHit] {
        let cutoff = Date().addingTimeInterval(-Double(sinceDays) * 86_400)
        let rows = try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, subject, fromName, fromAddress, mailbox, date, threadKey, attachments,
                       isRead, isFlagged, snippet AS snip, 0.0 AS score
                FROM message WHERE date >= ? ORDER BY date DESC
                """, arguments: [cutoff]).map(Self.hit(from:))
        }
        return Array(rows.filter { isActionableMailbox($0.mailbox) }.prefix(limit))
    }

    /// Bir tarih aralığındaki maileri (en yeni önce) döndürür — yalnızca tarih ifadesi yazıldığında
    /// ("son 7 gün") arama terimi olmadan listeleme için.
    public func recentInRange(since: Date?, until: Date?, limit: Int) throws -> [SearchHit] {
        var parts: [String] = []
        var args: [any DatabaseValueConvertible] = []
        if let since { parts.append("date >= ?"); args.append(since) }
        if let until { parts.append("date <= ?"); args.append(until) }
        let whereClause = parts.isEmpty ? "" : "WHERE " + parts.joined(separator: " AND ")
        args.append(limit)
        return try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, subject, fromName, fromAddress, mailbox, date, threadKey, attachments,
                       isRead, isFlagged, snippet AS snip, 0.0 AS score
                FROM message \(whereClause) ORDER BY date DESC LIMIT ?
                """, arguments: StatementArguments(args)).map(Self.hit(from:))
        }
    }

    /// Filtreye uyan maileri (en yeni önce) listeler — arama metni olmadan yalnızca operatör/tarih
    /// filtresi verildiğinde (örn. "from:ali", "has:attachment", "son 7 gün") gezinme için.
    public func browse(_ filter: SearchFilter, limit: Int) throws -> [SearchHit] {
        let (clause, filterArgs) = Self.filterSQL(filter)
        var args = filterArgs
        args.append(limit)
        return try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT m.id, m.subject, m.fromName, m.fromAddress, m.mailbox, m.date, m.threadKey,
                       m.attachments, m.isRead, m.isFlagged, m.snippet AS snip, 0.0 AS score
                FROM message m WHERE 1=1\(clause) ORDER BY m.date DESC LIMIT ?
                """, arguments: StatementArguments(args)).map(Self.hit(from:))
        }
    }

    // MARK: - Ajan kalıcı hafızası (Faz 6)

    /// Ajanın oturumlar arası hatırlayacağı kalıcı bir bilgiyi kaydeder.
    /// Boş/yalnızca boşluk metinleri atlanır; aynı (kırpılmış) metin zaten varsa tekrar eklenmez.
    public func saveMemory(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try dbQueue.write { db in
            let existing = try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM agent_memory WHERE text = ?", arguments: [trimmed]) ?? 0
            guard existing == 0 else { return }
            try db.execute(sql:
                "INSERT INTO agent_memory (id, text, createdAt) VALUES (?, ?, ?)",
                arguments: [UUID().uuidString, trimmed, Date()])
        }
    }

    /// Tüm hatırlanan bilgileri eklenme sırasına göre döndürür.
    public func allMemories() throws -> [Memory] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql:
                "SELECT id, text, createdAt FROM agent_memory ORDER BY createdAt").map {
                Memory(id: $0["id"], text: $0["text"], createdAt: $0["createdAt"])
            }
        }
    }

    public func memoryCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM agent_memory") ?? 0
        }
    }

    /// Tüm hatırlanan bilgileri siler.
    public func clearMemories() throws {
        try dbQueue.write { db in try db.execute(sql: "DELETE FROM agent_memory") }
    }

    /// Tek bir hatırlanan bilgiyi siler (kullanıcı hafıza listesinden kaldırınca).
    public func deleteMemory(_ id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM agent_memory WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Kalıcı sohbet geçmişi (Faz 7)

    /// Bir sohbeti kaydeder/günceller: konuşma satırını UPSERT eder (varsa `createdAt`
    /// korunur, `updatedAt` şimdiye çekilir), eski turlarını siler ve turları sırasıyla
    /// (idx 0..n) yeniden yazar. Hepsi tek bir yazma işleminde (transaction) yapılır.
    /// Tur listesi boşsa hiçbir şey yapılmaz.
    public func saveConversation(id: String, title: String, turns: [ChatTurn]) throws {
        guard !turns.isEmpty else { return }
        try dbQueue.write { db in
            let now = Date()
            let createdAt = try Date.fetchOne(db, sql:
                "SELECT createdAt FROM conversation WHERE id = ?", arguments: [id]) ?? now
            try db.execute(sql: """
                INSERT INTO conversation (id, title, createdAt, updatedAt) VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET title = excluded.title, updatedAt = excluded.updatedAt
                """, arguments: [id, title, createdAt, now])
            try db.execute(sql:
                "DELETE FROM conversation_turn WHERE conversationId = ?", arguments: [id])
            for (idx, turn) in turns.enumerated() {
                try db.execute(sql: """
                    INSERT INTO conversation_turn (id, conversationId, idx, question, answer)
                    VALUES (?, ?, ?, ?, ?)
                    """, arguments: [UUID().uuidString, id, idx, turn.question, turn.answer])
            }
        }
    }

    /// Tüm kayıtlı sohbetleri en son güncellenenden eskiye doğru özet olarak döndürür.
    public func allConversations() throws -> [ConversationSummary] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.id AS id, c.title AS title, c.updatedAt AS updatedAt,
                       COUNT(t.id) AS turnCount
                FROM conversation c
                LEFT JOIN conversation_turn t ON t.conversationId = c.id
                GROUP BY c.id
                ORDER BY c.updatedAt DESC
                """).map {
                ConversationSummary(id: $0["id"], title: $0["title"],
                                    updatedAt: $0["updatedAt"], turnCount: $0["turnCount"] ?? 0)
            }
        }
    }

    /// Bir sohbetin turlarını sıraya (idx) göre döndürür.
    public func conversationTurns(_ id: String) throws -> [ChatTurn] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT question, answer FROM conversation_turn
                WHERE conversationId = ? ORDER BY idx
                """, arguments: [id]).map {
                ChatTurn(question: $0["question"], answer: $0["answer"])
            }
        }
    }

    // MARK: - Kayıtlı aramalar (Faz 8)

    /// Bir aramayı isimle kaydeder (sorgu metni operatör/tarih ifadelerini de taşıyabilir).
    /// Aynı isim varsa sorgu/mod güncellenir.
    public func saveSearch(name: String, query: String, mode: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedQuery.isEmpty else { return }
        try dbQueue.write { db in
            if let existing = try String.fetchOne(db, sql:
                "SELECT id FROM saved_search WHERE name = ?", arguments: [trimmedName]) {
                try db.execute(sql: "UPDATE saved_search SET query = ?, mode = ? WHERE id = ?",
                               arguments: [trimmedQuery, mode, existing])
            } else {
                try db.execute(sql: """
                    INSERT INTO saved_search (id, name, query, mode, createdAt) VALUES (?, ?, ?, ?, ?)
                    """, arguments: [UUID().uuidString, trimmedName, trimmedQuery, mode, Date()])
            }
        }
    }

    /// Tüm kayıtlı aramaları en yeniden eskiye döndürür.
    public func allSavedSearches() throws -> [SavedSearch] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, name, query, mode FROM saved_search ORDER BY createdAt DESC, rowid DESC
                """).map {
                SavedSearch(id: $0["id"], name: $0["name"], query: $0["query"], mode: $0["mode"])
            }
        }
    }

    /// Bir kayıtlı aramayı siler.
    public func deleteSavedSearch(_ id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM saved_search WHERE id = ?", arguments: [id])
        }
    }

    /// Bir sohbeti turlarıyla birlikte siler (turlar ON DELETE CASCADE ile gider).
    public func deleteConversation(_ id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM conversation WHERE id = ?", arguments: [id])
        }
    }

    private static func filterSQL(_ filter: SearchFilter)
        -> (clause: String, args: [(any DatabaseValueConvertible)?]) {
        var parts: [String] = []
        var args: [(any DatabaseValueConvertible)?] = []
        if let account = filter.accountID { parts.append("m.accountID = ?"); args.append(account) }
        if let since = filter.since { parts.append("m.date >= ?"); args.append(since) }
        if let until = filter.until { parts.append("m.date <= ?"); args.append(until) }
        if let from = filter.fromContains, !from.isEmpty {
            parts.append("(m.fromName LIKE ? OR m.fromAddress LIKE ?)")
            args.append("%\(from)%"); args.append("%\(from)%")
        }
        // Posta kutusu daraltması (kutu:/mailbox: operatörü): parça eşleşme, LIKE ile büyük/küçük
        // harf duyarsız (ASCII katlaması). Mailbox adı yol bileşenlerinden türer (örn. "INBOX",
        // "Arşiv", "[Gmail]/All Mail"); parça arama iç içe kutu adlarını da yakalar.
        if let mailbox = filter.mailboxContains, !mailbox.isEmpty {
            parts.append("m.mailbox LIKE ?")
            args.append("%\(mailbox)%")
        }
        if filter.hasAttachment {
            parts.append("(m.attachments IS NOT NULL AND m.attachments <> '')")
        }
        // Ek türü filtresi: `attachment` tablosunda ilgili uzantılardan en az bir ek olan mailler.
        // `.other` = bilinen uzantıların hiçbiri değil (uzantısız adlar dahil).
        if let kind = filter.attachmentKind {
            if kind == .other {
                let known = AttachmentName.knownExtensions
                parts.append("EXISTS (SELECT 1 FROM attachment a WHERE a.messageID = m.id "
                    + "AND a.ext NOT IN (\(databaseQuestionMarks(count: known.count))))")
                args.append(contentsOf: known)
            } else {
                let exts = AttachmentName.extensions(for: kind)
                if !exts.isEmpty {
                    parts.append("EXISTS (SELECT 1 FROM attachment a WHERE a.messageID = m.id "
                        + "AND a.ext IN (\(databaseQuestionMarks(count: exts.count))))")
                    args.append(contentsOf: exts)
                }
            }
        }
        if filter.unreadOnly { parts.append("m.isRead = 0") }
        if filter.flaggedOnly { parts.append("m.isFlagged = 1") }
        // Trova-yerel yıldızlı (pinned) süzgeci: `pinned` tablosunda kaydı olan mailler
        // (anahtar = message.id). unreadOnly/flaggedOnly desenini izler.
        if filter.pinnedOnly {
            parts.append("EXISTS (SELECT 1 FROM pinned p WHERE p.messageID = m.id)")
        }
        return (parts.isEmpty ? "" : " AND " + parts.joined(separator: " AND "), args)
    }

    private static func hit(from row: Row) -> SearchHit {
        let attachments = (row["attachments"] as String?)?
            .split(separator: "\n").map(String.init) ?? []
        return SearchHit(
            id: row["id"],
            // messageID yalnız onu SELECT eden sorgularda (örn. triyaj) gelir; yoksa nil.
            messageID: row.hasColumn("messageID") ? row["messageID"] : nil,
            subject: row["subject"], fromName: row["fromName"],
            fromAddress: row["fromAddress"], mailbox: row["mailbox"], date: row["date"],
            snippet: (row["snip"] as String?) ?? "", score: (row["score"] as Double?) ?? 0,
            threadKey: row["threadKey"], attachments: attachments,
            isRead: row["isRead"] as Bool?, isFlagged: row["isFlagged"] as Bool?)
    }

    /// Kullanıcı sorgusunu güvenli bir FTS5 desenine çevirir.
    /// - Her belirteç tırnaklanır (operatör enjeksiyonunu önler).
    /// - Sonuna `*` eklenerek ön ek sorgusu yapılır: Türkçenin sondan eklemeli
    ///   yapısında "fatura" → "faturanız"/"faturası" gibi sözcükleri de yakalar.
    static func ftsPattern(_ query: String) -> String {
        query.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map { $0.replacingOccurrences(of: "\"", with: "\"\"") }
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"*" }
            .joined(separator: " ")
    }
}

// MARK: - Vektör depolama ve anlamsal arama (Faz 1)

extension IndexStore {
    /// Gömme vektörlerini ekler/günceller. `[Float]` BLOB olarak saklanır.
    public func upsertVectors(_ vectors: [(id: String, vector: [Float])]) throws {
        try dbQueue.write { db in
            for (id, vector) in vectors {
                let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
                try db.execute(sql: """
                    INSERT INTO message_vector (id, dim, vector) VALUES (?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET dim = excluded.dim, vector = excluded.vector
                    """, arguments: [id, vector.count, data])
            }
        }
    }

    /// Henüz gömülmemiş mailleri (id + gömülecek metin) döndürür.
    public func messagesMissingVectors(limit: Int? = nil) throws -> [(id: String, text: String)] {
        try dbQueue.read { db in
            let limitClause = limit.map { "LIMIT \($0)" } ?? ""
            return try Row.fetchAll(db, sql: """
                SELECT m.id AS id,
                       COALESCE(m.subject, '') || char(10) || COALESCE(m.body, '') AS text
                FROM message m
                LEFT JOIN message_vector v ON v.id = m.id
                WHERE v.id IS NULL
                \(limitClause)
                """).map { (id: $0["id"], text: $0["text"]) }
        }
    }

    public func vectorCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM message_vector") ?? 0
        }
    }

    /// Tüm vektörleri siler. Embedding sağlayıcısı/boyutu değişince yeniden üretmek için.
    public func clearVectors() throws {
        try dbQueue.write { db in try db.execute(sql: "DELETE FROM message_vector") }
    }

    func loadAllVectors() throws -> [(id: String, vector: [Float])] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, dim, vector FROM message_vector").map { row in
                let data: Data = row["vector"]
                let dim: Int = row["dim"]
                var vector = [Float](repeating: 0, count: dim)
                _ = vector.withUnsafeMutableBytes { data.copyBytes(to: $0) }  // hizalamadan bağımsız kopya
                return (id: row["id"], vector: vector)
            }
        }
    }

    /// Sorgu vektörüne en yakın mailleri kosinüs benzerliğiyle (kaba kuvvet) bulur.
    /// Vektörler L2 normalize edildiği için nokta çarpımı = kosinüs.
    /// `allowedIDs` verilirse yalnızca o kümedeki mailler değerlendirilir (filtre).
    public func vectorSearch(query: [Float], limit: Int,
                             allowedIDs: Set<String>? = nil) throws -> [(id: String, score: Float)] {
        let all = try loadAllVectors()
        var scored: [(id: String, score: Float)] = []
        scored.reserveCapacity(all.count)
        for (id, vector) in all where vector.count == query.count {
            if let allowedIDs, !allowedIDs.contains(id) { continue }
            var dot: Float = 0
            vDSP_dotpr(query, 1, vector, 1, &dot, vDSP_Length(query.count))
            scored.append((id, dot))
        }
        return Array(scored.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// Tek bir mailin gömme vektörünü getirir (gömülmemişse nil). `loadAllVectors`'la
    /// aynı hizalamadan-bağımsız deserileştirmeyi kullanır.
    func vector(forID id: String) throws -> [Float]? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql:
                "SELECT dim, vector FROM message_vector WHERE id = ?", arguments: [id]) else { return nil }
            let data: Data = row["vector"]
            let dim: Int = row["dim"]
            var vector = [Float](repeating: 0, count: dim)
            _ = vector.withUnsafeMutableBytes { data.copyBytes(to: $0) }
            return vector
        }
    }

    /// "Benzer mailler" (more-like-this): hedef mailin vektörüne embedding'e göre en yakın
    /// mailleri kosinüs benzerliğiyle döndürür. `vectorSearch`'in kaba-kuvvet mantığını yeniden
    /// kullanır; hedef mailin kendisi elenir. Hedef gömülmemişse boş döner. `SearchHit.score`
    /// benzerlik skorudur (normalize vektörlerde nokta çarpımı = kosinüs).
    public func similar(toMessageID id: String, limit: Int) throws -> [SearchHit] {
        guard limit > 0, let target = try vector(forID: id) else { return [] }
        // Kendini elemek için bir fazla aday çek, sonra hedef maili çıkar.
        let ranked = Array(try vectorSearch(query: target, limit: limit + 1)
            .filter { $0.id != id }
            .prefix(limit))
        guard !ranked.isEmpty else { return [] }
        let meta = try hits(forIDs: ranked.map(\.id))
        return ranked.compactMap { r -> SearchHit? in
            guard let m = meta[r.id] else { return nil }
            return SearchHit(
                id: m.id, subject: m.subject, fromName: m.fromName, fromAddress: m.fromAddress,
                mailbox: m.mailbox, date: m.date, snippet: m.snippet, score: Double(r.score),
                threadKey: m.threadKey, attachments: m.attachments,
                isRead: m.isRead, isFlagged: m.isFlagged)
        }
    }

    /// Tek bir mailin tam gövdesini getirir (detay görünümü için).
    public func body(forID id: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT body FROM message WHERE id = ?", arguments: [id])
        }
    }

    /// Mailin kaynak `.emlx` dosya yolu (HTML'i taze okumak için).
    public func filePath(forID id: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT filePath FROM message WHERE id = ?", arguments: [id])
        }
    }

    /// Mailin RFC822 Message-ID'si ("Mail'de Aç" derin-linki için). Kayıtlı değilse nil.
    public func messageID(forID id: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT messageID FROM message WHERE id = ?", arguments: [id])
        }
    }

    /// Verilen id kümesi için görüntüleme meta verisini getirir.
    public func hits(forIDs ids: [String]) throws -> [String: SearchHit] {
        guard !ids.isEmpty else { return [:] }
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, subject, fromName, fromAddress, mailbox, date, threadKey, attachments,
                       isRead, isFlagged, snippet AS snip, 0.0 AS score
                FROM message WHERE id IN (\(databaseQuestionMarks(count: ids.count)))
                """, arguments: StatementArguments(ids))
            var map: [String: SearchHit] = [:]
            for row in rows { map[row["id"]] = Self.hit(from: row) }
            return map
        }
    }
}

// MARK: - Ek içeriği araması (Faz 11, opt-in)

extension IndexStore {
    /// Bir mesajın ek içeriğini (eklerden çıkarılan ucuz metin) idempotent yeniden yazar:
    /// önce o `messageID`'nin satırlarını siler, sonra (boş değilse) tek satır ekler.
    /// `messageID` sahip mesajın kararlı id'sidir (message.id) — RFC822 Message-ID değil.
    public func replaceAttachmentContent(messageID: String, text: String) throws {
        try replaceAttachmentContents([(messageID, text)])
    }

    /// Birden çok mesajın ek içeriğini tek yazma işleminde (transaction) idempotent yeniden yazar.
    /// Her messageID için önce eski satır(lar) silinir, sonra boş olmayan metin tek satır eklenir.
    public func replaceAttachmentContents(_ items: [(messageID: String, text: String)]) throws {
        guard !items.isEmpty else { return }
        try dbQueue.write { db in
            for (messageID, text) in items {
                try db.execute(sql:
                    "DELETE FROM attachment_content WHERE messageID = ?", arguments: [messageID])
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                try db.execute(sql:
                    "INSERT INTO attachment_content (content, messageID) VALUES (?, ?)",
                    arguments: [trimmed, messageID])
            }
        }
    }

    /// Ek içeriğinde (FTS5 MATCH) sorguyla eşleşen mesaj id'lerini bm25 sırasıyla döndürür.
    /// Mesaj FTS'iyle aynı `FtsQueryBuilder.build`'i kullanır → Türkçe davranış + gelişmiş söz dizimi tutarlı.
    public func messageIDsMatchingAttachmentContent(_ query: String) throws -> [String] {
        let pattern = FtsQueryBuilder.build(query)   // mesaj FTS'iyle aynı gelişmiş+ftsPattern davranışı
        guard !pattern.isEmpty else { return [] }
        return try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT messageID FROM attachment_content
                WHERE attachment_content MATCH ?
                ORDER BY bm25(attachment_content)
                """, arguments: [pattern])
        }
    }

    /// Ek içeriği FTS tablosunu tamamen boşaltır (toggle kapatılınca temizlemek için).
    public func clearAttachmentContent() throws {
        try dbQueue.write { db in try db.execute(sql: "DELETE FROM attachment_content") }
    }

    /// Ek içeriği indekslenmiş (içerik satırı olan) mesaj sayısı.
    public func attachmentContentCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM attachment_content") ?? 0
        }
    }

    /// Eki olan tüm mesajların (id, dosya yolu) listesi — ek içeriği backfill geçişi için.
    /// `attachments` kolonu dolu (en az bir ek adı olan) mailler döner.
    public func messagesWithAttachments() throws -> [(id: String, filePath: String)] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, filePath FROM message
                WHERE attachments IS NOT NULL AND attachments <> ''
                """).map { (id: $0["id"], filePath: $0["filePath"]) }
        }
    }
}

// MARK: - Görmezden gelinen digest öğeleri (Faz 13)

extension IndexStore {
    /// Bir digest öğesini (thread) görmezden gelinmiş olarak işaretler (upsert): aynı `threadKey`
    /// zaten varsa `dismissedAt` yeni ana güncellenir. `dismissedAt` ISO-8601 metin saklanır.
    /// Boş/yalnız boşluk anahtar atlanır. Re-surface mantığı tarih karşılaştırmasıyla yapılır.
    public func dismissDigest(threadKey: String, at date: Date) throws {
        let key = threadKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        let stamp = ISO8601DateFormatter().string(from: date)
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO dismissed_digest (threadKey, dismissedAt) VALUES (?, ?)
                ON CONFLICT(threadKey) DO UPDATE SET dismissedAt = excluded.dismissedAt
                """, arguments: [key, stamp])
        }
    }

    /// Bir thread'in görmezden gelinme kaydını kaldırır (tekrar görünür kılar).
    public func undismissDigest(threadKey: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM dismissed_digest WHERE threadKey = ?", arguments: [threadKey])
        }
    }

    /// Tüm görmezden gelinen thread'leri `threadKey → dismissedAt` haritası olarak döndürür.
    /// Çözülemeyen (bozuk) tarih kayıtları atlanır.
    public func dismissedDigest() throws -> [String: Date] {
        let iso = ISO8601DateFormatter()
        return try dbQueue.read { db in
            var map: [String: Date] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT threadKey, dismissedAt FROM dismissed_digest") {
                let key: String = row["threadKey"]
                if let stamp: String = row["dismissedAt"], let date = iso.date(from: stamp) {
                    map[key] = date
                }
            }
            return map
        }
    }

    /// Tüm görmezden gelme kayıtlarını siler ("Gizlenenleri geri al").
    public func clearDismissedDigest() throws {
        try dbQueue.write { db in try db.execute(sql: "DELETE FROM dismissed_digest") }
    }
}

// MARK: - Trova-yerel yıldızlı (pin) koleksiyonu (Faz 14)

extension IndexStore {
    /// Bir maili Trova İÇİNDE yıldızlar (pin) — Apple Mail'e YAZMAZ. Anahtar mesajın kararlı
    /// id'sidir (`message.id` = path-hash), RFC822 Message-ID DEĞİL. Aynı id zaten yıldızlıysa
    /// `pinnedAt` güncellenir (idempotent upsert). Boş/yalnız boşluk id atlanır.
    public func pin(id: String, at date: Date = Date()) throws {
        let key = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        let stamp = ISO8601DateFormatter().string(from: date)
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO pinned (messageID, pinnedAt) VALUES (?, ?)
                ON CONFLICT(messageID) DO UPDATE SET pinnedAt = excluded.pinnedAt
                """, arguments: [key, stamp])
        }
    }

    /// Bir mailin yıldızını kaldırır (yıldızlı değilse etkisiz).
    public func unpin(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM pinned WHERE messageID = ?", arguments: [id])
        }
    }

    /// Birden çok maili TEK transaction'da yıldızlar (toplu pin) — Apple Mail'e YAZMAZ.
    /// Her id `pin(id:)` ile aynı kuralları izler: kararlı `message.id` anahtarı; idempotent
    /// upsert (zaten yıldızlıysa yalnız `pinnedAt` güncellenir, satır çoğalmaz); boş/yalnız
    /// boşluk id'ler atlanır. Boş liste güvenlidir (hiç yazma yapılmaz). Tek tek `pin` döngüsü
    /// yerine tek yazma → toplu seçimde tutarlı ve ucuz.
    public func pinMany(ids: [String], at date: Date = Date()) throws {
        let keys = ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !keys.isEmpty else { return }
        let stamp = ISO8601DateFormatter().string(from: date)
        try dbQueue.write { db in
            for key in keys {
                try db.execute(sql: """
                    INSERT INTO pinned (messageID, pinnedAt) VALUES (?, ?)
                    ON CONFLICT(messageID) DO UPDATE SET pinnedAt = excluded.pinnedAt
                    """, arguments: [key, stamp])
            }
        }
    }

    /// Birden çok mailin yıldızını TEK transaction'da kaldırır (toplu unpin). Yıldızlı olmayan
    /// id'ler etkisizdir (idempotent); boş/yalnız boşluk id'ler atlanır; boş liste güvenlidir.
    public func unpinMany(ids: [String]) throws {
        let keys = ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !keys.isEmpty else { return }
        try dbQueue.write { db in
            for key in keys {
                try db.execute(sql: "DELETE FROM pinned WHERE messageID = ?", arguments: [key])
            }
        }
    }

    /// Bir mailin Trova-yerel yıldızlı olup olmadığını döndürür.
    public func isPinned(id: String) throws -> Bool {
        try dbQueue.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM pinned WHERE messageID = ?)",
                              arguments: [id]) ?? false
        }
    }

    /// Tüm yıldızlı mail id'lerini (`message.id`) küme olarak döndürür — sonuç satırlarını
    /// işaretlemek (yıldız rozeti) ve `isSelectedPinned` için.
    public func pinnedIDs() throws -> Set<String> {
        try dbQueue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT messageID FROM pinned"))
        }
    }

    /// Yıldızlı (pinned) mail sayısı.
    public func pinnedCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pinned") ?? 0
        }
    }
}
