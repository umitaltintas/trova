import XCTest
@testable import TrovaCore

/// Blok-düzeyi Markdown ayrıştırıcısının saf testleri (ağsız, deterministik).
final class MarkdownBlocksTests: XCTestCase {

    func testHeadingLevelsAndText() {
        XCTAssertEqual(MarkdownBlocks.parse("# Başlık"), [.heading(level: 1, text: "Başlık")])
        XCTAssertEqual(MarkdownBlocks.parse("## İkinci"), [.heading(level: 2, text: "İkinci")])
        XCTAssertEqual(MarkdownBlocks.parse("### Üçüncü düzey"),
                       [.heading(level: 3, text: "Üçüncü düzey")])
    }

    func testHashWithoutSpaceIsNotHeading() {
        // "#etiket" başlık değildir → paragraf olmalı.
        XCTAssertEqual(MarkdownBlocks.parse("#etiket"), [.paragraph(text: "#etiket")])
    }

    func testBulletListGrouping() {
        let md = "- bir\n- iki\n- üç"
        XCTAssertEqual(MarkdownBlocks.parse(md), [.bulletList(["bir", "iki", "üç"])])
    }

    func testBulletAlternateMarkers() {
        // `*` ve `+` de madde işaretidir; ardışık olduklarında tek listede toplanır.
        let md = "* yıldız\n+ artı"
        XCTAssertEqual(MarkdownBlocks.parse(md), [.bulletList(["yıldız", "artı"])])
    }

    func testOrderedListGrouping() {
        let md = "1. ilk\n2. ikinci\n3. üçüncü"
        XCTAssertEqual(MarkdownBlocks.parse(md), [.orderedList(["ilk", "ikinci", "üçüncü"])])
    }

    func testParagraphJoinsConsecutivePlainLines() {
        let md = "İlk satır\nikinci satır"
        XCTAssertEqual(MarkdownBlocks.parse(md), [.paragraph(text: "İlk satır\nikinci satır")])
    }

    func testBlankLineSeparatesParagraphs() {
        let md = "Birinci paragraf\n\nİkinci paragraf"
        XCTAssertEqual(MarkdownBlocks.parse(md),
                       [.paragraph(text: "Birinci paragraf"), .paragraph(text: "İkinci paragraf")])
    }

    func testFencedCode() {
        let md = "```swift\nlet x = 1\nprint(x)\n```"
        XCTAssertEqual(MarkdownBlocks.parse(md), [.code("let x = 1\nprint(x)")])
    }

    func testUnclosedFenceDoesNotCrashAndCapturesRest() {
        // Streaming sırasında kapanmamış çit → sona kadar kod olarak alınır, çökmeden.
        let md = "```\nyarım kod\ndevam"
        XCTAssertEqual(MarkdownBlocks.parse(md), [.code("yarım kod\ndevam")])
    }

    func testQuoteJoinsConsecutiveLines() {
        let md = "> birinci alıntı\n> ikinci alıntı"
        XCTAssertEqual(MarkdownBlocks.parse(md), [.quote(text: "birinci alıntı\nikinci alıntı")])
    }

    func testMixedDocumentOrderHeadingThenBullets() {
        // Kullanıcının ekranındaki gibi: başlık + kalın etiketli maddeler.
        let md = "## Özet\n- **Önemli:** ilk madde\n- ikinci madde"
        XCTAssertEqual(MarkdownBlocks.parse(md), [
            .heading(level: 2, text: "Özet"),
            .bulletList(["**Önemli:** ilk madde", "ikinci madde"]),
        ])
    }

    func testInlineMarkdownPreservedInItems() {
        // Madde metnindeki `**x**` ve `*y*` aynen korunur; satır-içi render view katmanında.
        let md = "- **kalın** ve *italik* ve `kod`"
        XCTAssertEqual(MarkdownBlocks.parse(md),
                       [.bulletList(["**kalın** ve *italik* ve `kod`"])])
    }

    func testComplexDocumentBlockOrder() {
        let md = """
        # Başlık

        Giriş paragrafı.

        ## Maddeler
        - bir
        - iki

        1. adım bir
        2. adım iki

        > bir not
        """
        XCTAssertEqual(MarkdownBlocks.parse(md), [
            .heading(level: 1, text: "Başlık"),
            .paragraph(text: "Giriş paragrafı."),
            .heading(level: 2, text: "Maddeler"),
            .bulletList(["bir", "iki"]),
            .orderedList(["adım bir", "adım iki"]),
            .quote(text: "bir not"),
        ])
    }

    func testEmptyInputReturnsNoBlocks() {
        XCTAssertEqual(MarkdownBlocks.parse(""), [])
        XCTAssertEqual(MarkdownBlocks.parse("   \n  \n"), [])
    }
}
