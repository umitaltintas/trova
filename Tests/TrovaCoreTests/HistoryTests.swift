import XCTest
@testable import TrovaCore

/// Kalıcı sohbet geçmişi (conversation/conversation_turn) ve tekil hafıza silme testleri.
final class HistoryTests: XCTestCase {

    private func makeStore() throws -> IndexStore {
        try IndexStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("trova-history-\(UUID().uuidString).sqlite"))
    }

    func testSaveAndListConversations() throws {
        let store = try makeStore()
        try store.saveConversation(id: "a", title: "İlk sohbet",
            turns: [ChatTurn(question: "soru1", answer: "yanıt1")])
        Thread.sleep(forTimeInterval: 0.01)   // updatedAt'ların milisaniye düzeyinde ayrışması için
        try store.saveConversation(id: "b", title: "İkinci sohbet",
            turns: [ChatTurn(question: "soru2", answer: "yanıt2"),
                    ChatTurn(question: "soru3", answer: "yanıt3")])

        let all = try store.allConversations()
        XCTAssertEqual(all.count, 2)
        // En son kaydedilen (b) en üstte olmalı (updatedAt DESC).
        XCTAssertEqual(all.first?.id, "b")
        XCTAssertEqual(all.first?.title, "İkinci sohbet")
        XCTAssertEqual(all.first?.turnCount, 2)
        XCTAssertEqual(all.last?.turnCount, 1)
    }

    func testTurnsRoundTripPreservesOrder() throws {
        let store = try makeStore()
        let turns = [ChatTurn(question: "q0", answer: "a0"),
                     ChatTurn(question: "q1", answer: "a1"),
                     ChatTurn(question: "q2", answer: "a2")]
        try store.saveConversation(id: "c", title: "Sıralı", turns: turns)

        let loaded = try store.conversationTurns("c")
        XCTAssertEqual(loaded.map(\.question), ["q0", "q1", "q2"])
        XCTAssertEqual(loaded.map(\.answer), ["a0", "a1", "a2"])
    }

    func testReSaveReplacesTurns() throws {
        let store = try makeStore()
        try store.saveConversation(id: "c", title: "v1",
            turns: [ChatTurn(question: "q0", answer: "a0")])
        // Aynı id ile yeniden kaydet: eski turlar silinip yenileri yazılmalı (kopya olmamalı).
        try store.saveConversation(id: "c", title: "v2",
            turns: [ChatTurn(question: "q0", answer: "a0"),
                    ChatTurn(question: "q1", answer: "a1")])

        let all = try store.allConversations()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "v2")
        XCTAssertEqual(all.first?.turnCount, 2)
        XCTAssertEqual(try store.conversationTurns("c").count, 2)
    }

    func testEmptyTurnsNotSaved() throws {
        let store = try makeStore()
        try store.saveConversation(id: "c", title: "boş", turns: [])
        XCTAssertTrue(try store.allConversations().isEmpty)
    }

    func testDeleteConversationRemovesTurns() throws {
        let store = try makeStore()
        try store.saveConversation(id: "a", title: "A",
            turns: [ChatTurn(question: "q", answer: "a")])
        try store.saveConversation(id: "b", title: "B",
            turns: [ChatTurn(question: "q", answer: "a")])

        try store.deleteConversation("a")
        let all = try store.allConversations()
        XCTAssertEqual(all.map(\.id), ["b"])
        // Silinen sohbetin turları da gitmeli (ON DELETE CASCADE).
        XCTAssertTrue(try store.conversationTurns("a").isEmpty)
    }

    func testDeleteMemoryRemovesOne() throws {
        let store = try makeStore()
        try store.saveMemory("bir")
        try store.saveMemory("iki")
        try store.saveMemory("üç")
        guard let target = try store.allMemories().first(where: { $0.text == "iki" }) else {
            return XCTFail("hafıza kaydı bulunamadı")
        }

        try store.deleteMemory(target.id)
        let remaining = try store.allMemories().map(\.text)
        XCTAssertEqual(Set(remaining), ["bir", "üç"])
        XCTAssertEqual(try store.memoryCount(), 2)
    }
}
