import XCTest
@testable import TrovaCore

final class CsvExporterTests: XCTestCase {

    private let bom = "\u{FEFF}"

    // MARK: - Genel csv()

    func testBaslikSatiriBomVeSatirSonu() {
        let csv = CsvExporter.csv(headers: ["A", "B"], rows: [["1", "2"]])
        // BOM en başta olmalı.
        XCTAssertTrue(csv.hasPrefix(bom))
        // Başlık satırı ardından \r\n ile veri satırı gelmeli.
        XCTAssertEqual(csv, "\(bom)A,B\r\n1,2\r\n")
    }

    func testBosRowsYalnizBaslikVeBom() {
        let csv = CsvExporter.csv(headers: ["Tarih", "Gönderen"], rows: [])
        XCTAssertEqual(csv, "\(bom)Tarih,Gönderen\r\n")
    }

    func testSadeAlanTirnaksiz() {
        let csv = CsvExporter.csv(headers: ["x"], rows: [["merhaba"]])
        XCTAssertTrue(csv.contains("\r\nmerhaba\r\n"))
        XCTAssertFalse(csv.contains("\"merhaba\""))
    }

    func testVirgulluAlanTirnaklanir() {
        let csv = CsvExporter.csv(headers: ["x"], rows: [["a,b"]])
        XCTAssertTrue(csv.contains("\"a,b\""))
    }

    func testIcteTirnakIkilenir() {
        let csv = CsvExporter.csv(headers: ["x"], rows: [["de\"me"]])
        // İçteki " -> "" ve tüm alan tırnakla sarılır.
        XCTAssertTrue(csv.contains("\"de\"\"me\""))
    }

    func testSatirSonuIcerenAlanTirnaklanirVeKorunur() {
        let csv = CsvExporter.csv(headers: ["x"], rows: [["üst\nalt"]])
        XCTAssertTrue(csv.contains("\"üst\nalt\""))
    }

    func testTurkceKarakterlerBozulmaz() {
        let csv = CsvExporter.csv(headers: ["İsim"], rows: [["Şağ çöğüı İ"]])
        XCTAssertTrue(csv.contains("İsim"))
        XCTAssertTrue(csv.contains("Şağ çöğüı İ"))
    }

    func testAlanSayisiTutarliKirpVeDoldur() {
        // Eksik alan boşla tamamlanır, fazla alan kırpılır; her satır 2 sütun olur.
        let csv = CsvExporter.csv(headers: ["A", "B"], rows: [["yalniz"], ["bir", "iki", "fazla"]])
        XCTAssertEqual(csv, "\(bom)A,B\r\nyalniz,\r\nbir,iki\r\n")
    }

    // MARK: - emailList()

    func testEmailListDortSutunVeBaslik() {
        let items = [
            ExportedListItem(from: "Ali", subject: "Fatura", dateLabel: "2 gün önce", mailbox: "INBOX"),
        ]
        let csv = CsvExporter.emailList(items)
        XCTAssertTrue(csv.hasPrefix("\(bom)Tarih,Gönderen,Konu,Kutu\r\n"))
        XCTAssertTrue(csv.contains("2 gün önce,Ali,Fatura,INBOX\r\n"))
    }

    func testEmailListMailboxNilBosKutu() {
        let items = [
            ExportedListItem(from: "Ev", subject: "Kira", dateLabel: "dün", mailbox: nil),
        ]
        let csv = CsvExporter.emailList(items)
        // Kutu sütunu boş kalır (satır sonunda virgülden sonra boş).
        XCTAssertTrue(csv.contains("dün,Ev,Kira,\r\n"))
    }

    func testEmailListBosListeYalnizBaslik() {
        let csv = CsvExporter.emailList([])
        XCTAssertEqual(csv, "\(bom)Tarih,Gönderen,Konu,Kutu\r\n")
    }

    func testEmailListVirgulluKonuTirnaklanir() {
        let items = [
            ExportedListItem(from: "Ali", subject: "Rapor, ek dosya", dateLabel: "bugün", mailbox: "İş"),
        ]
        let csv = CsvExporter.emailList(items)
        XCTAssertTrue(csv.contains("bugün,Ali,\"Rapor, ek dosya\",İş"))
    }
}
