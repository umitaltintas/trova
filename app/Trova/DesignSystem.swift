import SwiftUI

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
            Text(text).font(.system(size: 11))
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Theme.line, in: Capsule())
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
            Text(title).font(.rounded(16, .semibold)).foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
