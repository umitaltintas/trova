import XCTest
@testable import TrovaCore

final class ShortcutCatalogTests: XCTestCase {

    func testCatalogIsNotEmptyAndFieldsFilled() {
        XCTAssertFalse(ShortcutCatalog.all.isEmpty)
        for item in ShortcutCatalog.all {
            XCTAssertFalse(item.keys.trimmingCharacters(in: .whitespaces).isEmpty,
                           "keys boş: \(item.label)")
            XCTAssertFalse(item.label.trimmingCharacters(in: .whitespaces).isEmpty,
                           "label boş: \(item.keys)")
            XCTAssertFalse(item.group.trimmingCharacters(in: .whitespaces).isEmpty,
                           "group boş: \(item.keys)")
        }
    }

    func testNoDuplicateKeys() {
        let keys = ShortcutCatalog.all.map(\.keys)
        XCTAssertEqual(keys.count, Set(keys).count, "Aynı kombinasyon iki kez tanımlı")
    }

    func testExpectedGroupsPresent() {
        let groups = Set(ShortcutCatalog.all.map(\.group))
        for expected in ["Bölümler", "Genel", "Gezinme"] {
            XCTAssertTrue(groups.contains(expected), "Beklenen grup eksik: \(expected)")
        }
    }

    func testSectionAndPaletteShortcutsListed() {
        let keys = Set(ShortcutCatalog.all.map(\.keys))
        for section in ["⌘1", "⌘2", "⌘3", "⌘4", "⌘5", "⌘6"] {
            XCTAssertTrue(keys.contains(section), "Bölüm kısayolu eksik: \(section)")
        }
        XCTAssertTrue(keys.contains("⌘K"), "⌘K listede değil")
        XCTAssertTrue(keys.contains("⌘/"), "⌘/ (kılavuz) listede değil")
    }

    func testByGroupPreservesOrderAndCoversAll() {
        let grouped = ShortcutCatalog.byGroup
        // İlk grup, ham listenin ilk öğesinin grubu olmalı (sıra korunur).
        XCTAssertEqual(grouped.first?.group, ShortcutCatalog.all.first?.group)
        // Gruplanmış öğelerin toplamı, ham listeyle birebir eşleşmeli (öğe kaybı/çiftleme yok).
        let flattened = grouped.flatMap(\.items)
        XCTAssertEqual(flattened, ShortcutCatalog.all)
        // Grup adları tekrarsız (her grup bir kez).
        let groupNames = grouped.map(\.group)
        XCTAssertEqual(groupNames.count, Set(groupNames).count)
    }
}
