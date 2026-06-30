import XCTest
@testable import TrovaCore

final class AttachmentKindTests: XCTestCase {

    // MARK: - ext()

    func testExtNoExtension() {
        XCTAssertEqual(AttachmentName.ext(of: "dosya"), "")
    }

    func testExtMultipleDotsUsesLastSegment() {
        XCTAssertEqual(AttachmentName.ext(of: "rapor.final.pdf"), "pdf")
    }

    func testExtUppercaseLowercased() {
        XCTAssertEqual(AttachmentName.ext(of: "RAPOR.PDF"), "pdf")
        XCTAssertEqual(AttachmentName.ext(of: "Resim.JPEG"), "jpeg")
    }

    func testExtLeadingDotDotfileIsSafe() {
        // Baştaki nokta uzantı ayırıcısı sayılmaz (dotfile).
        XCTAssertEqual(AttachmentName.ext(of: ".gitignore"), "")
    }

    func testExtTrailingDotIsSafe() {
        XCTAssertEqual(AttachmentName.ext(of: "rapor."), "")
    }

    func testExtEmptyString() {
        XCTAssertEqual(AttachmentName.ext(of: ""), "")
    }

    // MARK: - kind()

    func testKindKnownExtensions() {
        XCTAssertEqual(AttachmentName.kind(of: "a.pdf"), .pdf)
        XCTAssertEqual(AttachmentName.kind(of: "b.PNG"), .image)       // büyük harf de eşleşir
        XCTAssertEqual(AttachmentName.kind(of: "c.heic"), .image)
        XCTAssertEqual(AttachmentName.kind(of: "d.xlsx"), .sheet)
        XCTAssertEqual(AttachmentName.kind(of: "e.csv"), .sheet)
        XCTAssertEqual(AttachmentName.kind(of: "f.docx"), .doc)
        XCTAssertEqual(AttachmentName.kind(of: "g.pptx"), .presentation)
        XCTAssertEqual(AttachmentName.kind(of: "h.zip"), .archive)
        XCTAssertEqual(AttachmentName.kind(of: "i.mp3"), .audio)
        XCTAssertEqual(AttachmentName.kind(of: "j.mov"), .video)
        XCTAssertEqual(AttachmentName.kind(of: "k.swift"), .code)
    }

    func testKindUnknownAndExtensionlessAreOther() {
        XCTAssertEqual(AttachmentName.kind(of: "veri.bin"), .other)
        XCTAssertEqual(AttachmentName.kind(of: "LICENSE"), .other)
        XCTAssertEqual(AttachmentName.kind(of: ".gitignore"), .other)
    }

    func testLabelsAreTurkish() {
        XCTAssertEqual(AttachmentKind.image.label, "Görsel")
        XCTAssertEqual(AttachmentKind.sheet.label, "Tablo")
        XCTAssertEqual(AttachmentKind.other.label, "Diğer")
    }

    // MARK: - extensions

    func testExtensionsForKnownKinds() {
        XCTAssertEqual(AttachmentKind.pdf.extensions, ["pdf"])
        // Görsel uzantıları (AttachmentName eşlemesiyle tutarlı).
        XCTAssertEqual(AttachmentKind.image.extensions, ["png", "jpg", "jpeg", "gif", "heic", "webp"])
        XCTAssertTrue(AttachmentKind.sheet.extensions.contains("xlsx"))
        XCTAssertTrue(AttachmentKind.code.extensions.contains("swift"))
    }

    func testExtensionsConsistentWithKindMapping() {
        // Her kategori uzantısı, ada göre yine aynı kategoriye çözülmelidir (tek kaynak garantisi).
        for kind in AttachmentKind.allCases where kind != .other {
            for ext in kind.extensions {
                XCTAssertEqual(AttachmentName.kind(of: "dosya.\(ext)"), kind,
                               "\(ext) → \(kind) bekleniyordu")
            }
        }
    }

    func testOtherHasNoDirectExtensions() {
        XCTAssertTrue(AttachmentKind.other.extensions.isEmpty)
    }
}
