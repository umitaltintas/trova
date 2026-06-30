import XCTest
@testable import TrovaCore

final class SavedSearchTests: XCTestCase {

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-saved-\(UUID().uuidString).sqlite"))
    }

    func testSaveAndList() throws {
        let store = try makeStore()
        try store.saveSearch(name: "Faturalar", query: "fatura has:attachment", mode: "hybrid")
        try store.saveSearch(name: "Ali", query: "from:ali son 7 gün", mode: "fts")
        let all = try store.allSavedSearches()
        XCTAssertEqual(all.count, 2)
        // En yeni önce → "Ali" ilk.
        XCTAssertEqual(all.first?.name, "Ali")
        XCTAssertEqual(all.first?.query, "from:ali son 7 gün")
        XCTAssertEqual(all.first?.mode, "fts")
    }

    func testSameNameUpdates() throws {
        let store = try makeStore()
        try store.saveSearch(name: "Faturalar", query: "fatura", mode: "fts")
        try store.saveSearch(name: "Faturalar", query: "fatura has:attachment", mode: "hybrid")
        let all = try store.allSavedSearches()
        XCTAssertEqual(all.count, 1, "aynı isim güncellenmeli, çoğalmamalı")
        XCTAssertEqual(all.first?.query, "fatura has:attachment")
        XCTAssertEqual(all.first?.mode, "hybrid")
    }

    func testDelete() throws {
        let store = try makeStore()
        try store.saveSearch(name: "X", query: "x", mode: "fts")
        let id = try XCTUnwrap(try store.allSavedSearches().first?.id)
        try store.deleteSavedSearch(id)
        XCTAssertTrue(try store.allSavedSearches().isEmpty)
    }

    func testEmptyNameOrQueryIgnored() throws {
        let store = try makeStore()
        try store.saveSearch(name: "   ", query: "x", mode: "fts")
        try store.saveSearch(name: "X", query: "  ", mode: "fts")
        XCTAssertTrue(try store.allSavedSearches().isEmpty)
    }
}
