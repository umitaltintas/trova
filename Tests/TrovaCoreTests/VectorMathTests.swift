import XCTest
@testable import TrovaCore

final class VectorMathTests: XCTestCase {

    func testIdenticalVectorsAreOne() {
        let v: [Float] = [0.2, 0.5, -0.3, 0.8]
        XCTAssertEqual(VectorMath.cosine(v, v), 1, accuracy: 1e-5)
    }

    func testOrthogonalVectorsAreZero() {
        XCTAssertEqual(VectorMath.cosine([1, 0, 0], [0, 1, 0]), 0, accuracy: 1e-6)
    }

    func testOppositeVectorsAreMinusOne() {
        XCTAssertEqual(VectorMath.cosine([1, 0, 0], [-1, 0, 0]), -1, accuracy: 1e-6)
    }

    func testZeroVectorIsZeroNotNaN() {
        let s = VectorMath.cosine([0, 0, 0], [1, 2, 3])
        XCTAssertFalse(s.isNaN)
        XCTAssertEqual(s, 0)
    }

    func testMismatchedLengthsAreSafeZero() {
        XCTAssertEqual(VectorMath.cosine([1, 0], [1, 0, 0]), 0)
    }

    func testEmptyVectorsAreZero() {
        XCTAssertEqual(VectorMath.cosine([], []), 0)
    }

    func testScaleInvariant() {
        // Aynı yön, farklı büyüklük → 1 (kosinüs büyüklükten bağımsız).
        XCTAssertEqual(VectorMath.cosine([1, 2, 3], [2, 4, 6]), 1, accuracy: 1e-5)
    }
}
