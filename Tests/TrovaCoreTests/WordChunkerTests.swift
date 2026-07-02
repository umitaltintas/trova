import XCTest
@testable import TrovaCore

/// `WordChunker`'ın saf sözleşmesini doğrular — model GEREKTİRMEZ. Kelime bazlı parçalama:
/// boş metin → boş dizi, kısa metin → tek parça, uzun metin → çok parça, kelime bütünlüğü
/// korunur, azami parça sınırı uygulanır, parçaların birleşimi metni (boşluk payıyla) kapsar.
final class WordChunkerTests: XCTestCase {

    func testEmptyOrWhitespaceYieldsNoChunks() {
        XCTAssertEqual(WordChunker.chunks(""), [])
        XCTAssertEqual(WordChunker.chunks("   \n\t  "), [])
    }

    func testShortTextIsSingleTrimmedChunk() {
        // Sınırdan (varsayılan 120 kelime) kısa metin tek parça olur, boşlukları budanır.
        XCTAssertEqual(WordChunker.chunks("  Merhaba dünya, nasılsın?  "),
                       ["Merhaba dünya, nasılsın?"])
    }

    func testPunctuationOnlyIsSingleChunk() {
        // Kelime tokenı üretmeyen metin (salt noktalama) tek parça olarak korunur.
        XCTAssertEqual(WordChunker.chunks("... !!! ---"), ["... !!! ---"])
    }

    func testLongTextSplitsIntoMultipleChunks() {
        // 7 kelime, parça başına 3 → 3 parça: [3, 3, 1].
        let chunks = WordChunker.chunks("bir iki üç dört beş altı yedi", wordsPerChunk: 3)
        XCTAssertEqual(chunks, ["bir iki üç", "dört beş altı", "yedi"])
    }

    func testMaxChunksIsEnforced() {
        // 7 kelime, parça başına 3, azami 2 parça → 2 parça (kuyruk düşer).
        let chunks = WordChunker.chunks("bir iki üç dört beş altı yedi",
                                        wordsPerChunk: 3, maxChunks: 2)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks, ["bir iki üç", "dört beş altı"])
    }

    func testWordIntegrityPreserved() {
        // Hiçbir parça bir kelimeyi ortadan bölmez: her parçadaki kelimeler orijinaldeki tam
        // kelimelerdir. Türkçe eklemeli/tireli kelimelerle kontrol.
        let text = "arkadaşlarımızla İstanbul'dan İzmir'e yolculuk ettik güneşli havada"
        let originalWords = text.split(separator: " ").map(String.init)
        let chunks = WordChunker.chunks(text, wordsPerChunk: 2)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            for word in chunk.split(separator: " ") {
                XCTAssertTrue(originalWords.contains(String(word)),
                              "Parça bir kelimeyi bölmüş olmamalı: \(word)")
            }
        }
    }

    func testChunksTogetherCoverAllWords() {
        // Sınır uygulanmadığında parçaların birleşimi tüm kelimeleri (sırayla) kapsar.
        let text = "kırk gün kırk gece süren uzun bir yolculuğun sonunda eve döndüler"
        let originalWords = text.split(separator: " ").map(String.init)
        let chunks = WordChunker.chunks(text, wordsPerChunk: 4)
        let rejoined = chunks.joined(separator: " ").split(separator: " ").map(String.init)
        XCTAssertEqual(rejoined, originalWords)
    }
}
