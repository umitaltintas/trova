import XCTest
@testable import TrovaCore

/// `EmptyStates` saf fonksiyonları: her bölüm × anlamlı durum için doğru
/// başlık / CTA etiketi / ikon üretir mi. Ağ yok, yan etki yok.
final class EmptyStateContentTests: XCTestCase {

    private let cta = "İndeksle"
    private let indexIcon = "tray.and.arrow.down"

    // MARK: - Ara

    func testSearchNoIndexInvitesIndexing() {
        let c = EmptyStates.search(hasIndex: false, hasQuery: false, hasFilters: false)
        XCTAssertEqual(c.actionLabel, cta)
        XCTAssertEqual(c.systemImage, indexIcon)
        XCTAssertEqual(c.title, "Önce postanı indeksle")
    }

    func testSearchEmptyQueryShowsStartHintWithoutCTA() {
        let c = EmptyStates.search(hasIndex: true, hasQuery: false, hasFilters: false)
        XCTAssertEqual(c.title, "Aramaya başla")
        XCTAssertNil(c.actionLabel)
        XCTAssertEqual(c.systemImage, "magnifyingglass")
    }

    func testSearchWithQueryShowsNoResults() {
        let c = EmptyStates.search(hasIndex: true, hasQuery: true, hasFilters: false)
        XCTAssertEqual(c.title, "Sonuç bulunamadı")
        XCTAssertNil(c.actionLabel)
    }

    func testSearchOnlyFiltersShowsNoMatch() {
        let c = EmptyStates.search(hasIndex: true, hasQuery: false, hasFilters: true)
        XCTAssertEqual(c.title, "Eşleşen mail yok")
        XCTAssertNil(c.actionLabel)
        XCTAssertEqual(c.systemImage, "line.3.horizontal.decrease.circle")
    }

    // MARK: - Sor

    func testAskNoIndexInvitesIndexing() {
        let c = EmptyStates.ask(hasIndex: false)
        XCTAssertEqual(c.actionLabel, cta)
        XCTAssertEqual(c.systemImage, indexIcon)
    }

    func testAskWithIndexShowsPromptWithoutCTA() {
        let c = EmptyStates.ask(hasIndex: true)
        XCTAssertEqual(c.title, "Postana soru sor")
        XCTAssertEqual(c.systemImage, "sparkles")
        XCTAssertNil(c.actionLabel)
    }

    // MARK: - Bugün

    func testDigestAllClearIsPositiveWithoutCTA() {
        let c = EmptyStates.digest(hasNeedsReply: false, hasWaiting: false)
        XCTAssertEqual(c.title, "Bugün için temiz")
        XCTAssertEqual(c.systemImage, "checkmark.circle")
        XCTAssertNil(c.actionLabel)
    }

    func testDigestWithPendingIsNeutral() {
        let c = EmptyStates.digest(hasNeedsReply: true, hasWaiting: false)
        XCTAssertNotEqual(c.title, "Bugün için temiz")
        XCTAssertNil(c.actionLabel)
    }

    // MARK: - Kişiler

    func testPeopleNoIndexInvitesIndexing() {
        let c = EmptyStates.people(hasIndex: false)
        XCTAssertEqual(c.actionLabel, cta)
        XCTAssertEqual(c.systemImage, indexIcon)
    }

    func testPeopleWithIndexShowsNoDataWithoutCTA() {
        let c = EmptyStates.people(hasIndex: true)
        XCTAssertEqual(c.title, "Henüz kişi yok")
        XCTAssertEqual(c.systemImage, "person.2")
        XCTAssertNil(c.actionLabel)
    }

    // MARK: - Genel Bakış

    func testInsightsNoIndexInvitesIndexing() {
        let c = EmptyStates.insights(hasIndex: false)
        XCTAssertEqual(c.actionLabel, cta)
        XCTAssertEqual(c.systemImage, indexIcon)
    }

    func testInsightsWithIndexShowsNoDataWithoutCTA() {
        let c = EmptyStates.insights(hasIndex: true)
        XCTAssertEqual(c.systemImage, "chart.bar")
        XCTAssertNil(c.actionLabel)
    }

    // MARK: - Ekler

    func testAttachmentsEmptyDepotInvitesIndexing() {
        let c = EmptyStates.attachments(hasAny: false, hasQueryOrFilter: false)
        XCTAssertEqual(c.actionLabel, cta)
        XCTAssertEqual(c.systemImage, indexIcon)
    }

    func testAttachmentsNoMatchForQueryHasNoCTA() {
        let c = EmptyStates.attachments(hasAny: true, hasQueryOrFilter: true)
        XCTAssertEqual(c.title, "Eşleşen ek yok")
        XCTAssertNil(c.actionLabel)
        XCTAssertEqual(c.systemImage, "paperclip")
    }

    // MARK: - Benzer mailler

    func testSimilarWithoutVectorsInvitesEmbedding() {
        let c = EmptyStates.similar(hasVectors: false)
        XCTAssertEqual(c.title, "Anlamsal benzerlik için gömme gerekli")
        XCTAssertEqual(c.systemImage, "sparkles")
        XCTAssertNil(c.actionLabel)
    }

    func testSimilarWithVectorsShowsNoMatch() {
        let c = EmptyStates.similar(hasVectors: true)
        XCTAssertEqual(c.title, "Benzer mail bulunamadı")
        XCTAssertEqual(c.systemImage, "square.stack.3d.up")
        XCTAssertNil(c.actionLabel)
    }

    // MARK: - Tutarlılık

    /// Tüm indeksleme davetleri aynı CTA etiketini ve ikonunu kullanır (tutarlı dil).
    func testAllIndexInvitesShareSameCTA() {
        let invites = [
            EmptyStates.search(hasIndex: false, hasQuery: false, hasFilters: false),
            EmptyStates.ask(hasIndex: false),
            EmptyStates.people(hasIndex: false),
            EmptyStates.insights(hasIndex: false),
            EmptyStates.attachments(hasAny: false, hasQueryOrFilter: false),
        ]
        for c in invites {
            XCTAssertEqual(c.actionLabel, cta)
            XCTAssertEqual(c.systemImage, indexIcon)
            XCTAssertEqual(c.title, "Önce postanı indeksle")
        }
    }
}
