import Foundation
import Accelerate

/// Vektörler üzerinde saf, test edilebilir matematik yardımcıları.
public enum VectorMath {
    /// İki vektör arasındaki kosinüs benzerliği [-1, 1].
    /// Güvenli: uzunluk farkında ya da bir taraf sıfır vektörse 0 döner (NaN üretmez).
    /// Birebir aynı yön → 1, dik → 0, ters yön → -1.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, sumA: Float = 0, sumB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &sumA, vDSP_Length(a.count))   // Σ aᵢ²
        vDSP_svesq(b, 1, &sumB, vDSP_Length(b.count))   // Σ bᵢ²
        let denom = (sumA * sumB).squareRoot()           // |a|·|b|
        return denom == 0 ? 0 : dot / denom
    }
}
