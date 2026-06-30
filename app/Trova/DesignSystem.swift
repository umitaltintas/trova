import SwiftUI
import TrovaCore

/// Indigo Console tasarım dili — token'lar ve yeniden kullanılabilir bileşenler.
enum Theme {
    static let accent = Color(red: 0.35, green: 0.30, blue: 0.92)   // indigo
    static let accentSoft = accent.opacity(0.14)
    static let ink = Color.primary
    static let muted = Color.secondary
    static let faint = Color.secondary.opacity(0.55)
    static let line = Color.primary.opacity(0.08)
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.07)   // bayrak rozeti

    static let radius: CGFloat = 12
    static let radiusSmall: CGFloat = 8
}

extension Font {
    /// Başlıklar — SF Pro Rounded (dostane, yerli, ayırt edici).
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    /// Sayılar/skorlar — SF Mono (enstrüman hissi).
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    func cardSurface(_ radius: CGFloat = Theme.radius) -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Theme.line, lineWidth: 1))
    }
}

/// İmza öğesi: alaka skorunu (0–1) bölmeli bir sinyal çubuğu olarak gösterir.
struct SignalBar: View {
    let value: Double
    var segments = 6
    var height: CGFloat = 13

    var body: some View {
        let filled = max(0, min(segments, Int((value * Double(segments)).rounded())))
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < filled ? Theme.accent : Theme.accent.opacity(0.16))
                    .frame(width: 5, height: height)
            }
        }
    }
}

/// Gönderen baş harfleri — indigo tonlu yuvarlak rozet.
struct Avatar: View {
    let name: String?
    let email: String?
    var size: CGFloat = 34

    private var initials: String {
        let base = (name?.isEmpty == false ? name : email) ?? "?"
        let letters = base.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "@" })
            .prefix(2).compactMap(\.first)
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }

    var body: some View {
        Circle()
            .fill(Theme.accentSoft)
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.rounded(size * 0.38, .bold))
                    .foregroundStyle(Theme.accent))
    }
}

/// Küçük etiket çipi (ek, kutu vb.).
struct Chip: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9)) }
            // Tek satırda kal: uzun dosya adı/etiket çipi dikey büyüyüp satırı bozmasın.
            Text(text).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Theme.line, in: Capsule())
    }
}

/// Okunmadı/bayraklı durum rozetleri: okunmamışsa belirgin bir indigo nokta, bayraklıysa
/// amber `flag.fill`. Yalnız ilgili durum kesinleşmişse (true) gösterilir; nil/false → gizli.
struct MessageBadges: View {
    let isRead: Bool?
    let isFlagged: Bool?
    var dotSize: CGFloat = 7

    var body: some View {
        if isRead == false {
            Circle().fill(Theme.accent).frame(width: dotSize, height: dotSize)
                .help("Okunmadı")
        }
        if isFlagged == true {
            Image(systemName: "flag.fill").font(.system(size: dotSize + 3))
                .foregroundStyle(Theme.amber)
                .help("Bayraklı")
        }
    }
}

/// Açık/kapalı durumu olan tıklanabilir filtre çipi (okunmadı/bayraklı gibi). Aktifken indigo dolgu.
struct FilterToggleChip: View {
    let text: String
    let systemImage: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 9))
                Text(text).font(.system(size: 11)).lineLimit(1)
            }
            .foregroundStyle(isOn ? .white : Theme.muted)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(isOn ? Theme.accent : Theme.line, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.7))
                .accessibilityHidden(true)
            Text(title).font(.rounded(16, .semibold)).foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Tek kaynaklı boş durum görünümü: `EmptyStateContent`'i (ikon + başlık + mesaj + opsiyonel
/// CTA) çizer. CTA yalnız `actionLabel` dolu ve bir `action` verildiğinde belirir; ilgili komutu
/// (örn. İndeksle) tetikler. Dekoratif ikon erişilebilirlikte gizlenir, başlık+mesaj okunur.
struct EmptyStateView: View {
    let content: EmptyStateContent
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: content.systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.7))
                .accessibilityHidden(true)
            Text(content.title).font(.rounded(16, .semibold)).foregroundStyle(Theme.ink)
            Text(content.message)
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 300)
                .fixedSize(horizontal: false, vertical: true)
            if let label = content.actionLabel, let action {
                Button(action: action) {
                    Text(label).font(.rounded(13, .semibold))
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.large)
                .padding(.top, 4)
                .accessibilityHint("Postanı indekslemeyi başlatır")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Yükleme iskeleti (skeleton)

/// Yükleme sırasında içeriğin yerine geçen, hafifçe parlayan (shimmer) gri blok.
/// `accessibilityReducedMotion` açıkken animasyon kapanır; statik bir yer tutucu kalır.
struct ShimmerView: View {
    var cornerRadius: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.line)
            .overlay {
                // Hareket azaltma kapalıyken soldan sağa kayan ışık bandı.
                if !reduceMotion {
                    GeometryReader { geo in
                        let width = geo.size.width
                        LinearGradient(
                            colors: [.clear, Theme.accent.opacity(0.10), .clear],
                            startPoint: .leading, endPoint: .trailing)
                            .frame(width: width * 0.55)
                            .offset(x: animate ? width * 1.3 : -width * 0.9)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// Bir mail/ek satırının yüklenirken yerine geçen iskelet: avatar + iki metin çizgisi.
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ShimmerView(cornerRadius: 16).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 6) {
                ShimmerView().frame(height: 11).frame(maxWidth: .infinity)
                ShimmerView().frame(width: 150, height: 9)
            }
            Spacer()
        }
        .padding(.vertical, 6).padding(.horizontal, 4)
        .accessibilityHidden(true)
    }
}

/// Liste yüklenirken birkaç `SkeletonRow` gösteren kapsayıcı. Tek bir erişilebilirlik
/// öğesi olarak "yükleniyor" duyurur; içerideki dekoratif iskeletler okunmaz.
struct SkeletonList: View {
    var rows = 6

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<rows, id: \.self) { _ in SkeletonRow() }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Yükleniyor")
    }
}
