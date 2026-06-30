import SwiftUI
import TrovaCore

/// ⌘K komut paletindeki tek bir komut.
struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let run: (AppModel) -> Void
}

enum PaletteCommands {
    @MainActor static let all: [PaletteCommand] = [
        .init(id: "ask", title: "Sor", subtitle: "AI ile bul + özetle", icon: "sparkles") {
            $0.section = .ask
        },
        .init(id: "search", title: "Ara", subtitle: "Kelime / anlamsal arama", icon: "magnifyingglass") {
            $0.section = .search
        },
        .init(id: "digest", title: "Bugün", subtitle: "Brifing + yanıt bekleyenler", icon: "sun.max") {
            $0.section = .digest
        },
        .init(id: "people", title: "Kişiler", subtitle: "En çok yazışılanlar", icon: "person.2") {
            $0.section = .people; $0.selectedPersonAddress = nil
        },
        .init(id: "insights", title: "Genel Bakış", subtitle: "İstatistik + aylık hacim", icon: "chart.bar") {
            $0.section = .insights
        },
        .init(id: "new", title: "Yeni sohbet", subtitle: "Sor geçmişini temizle", icon: "square.and.pencil") {
            $0.section = .ask; $0.newConversation()
        },
        .init(id: "index", title: "İndeksle", subtitle: "Yeni mailleri tara", icon: "tray.and.arrow.down") {
            $0.runIndex()
        },
        .init(id: "embed", title: "Gömme", subtitle: "Anlamsal vektörleri üret", icon: "wand.and.stars") {
            $0.runEmbed()
        },
        .init(id: "digestRun", title: "Günlük brifing oluştur", subtitle: "Son maillerden özet", icon: "text.alignleft") {
            $0.section = .digest; $0.runDigest()
        },
        .init(id: "refresh", title: "Yenile", subtitle: "Durumu güncelle", icon: "arrow.clockwise") {
            $0.refreshStatus()
        },
    ]
}

/// ⌘K ile açılan, bulanık aramayla komutları filtreleyip çalıştıran palet.
struct CommandPaletteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var results: [PaletteCommand] {
        FuzzyMatcher.rank(query, PaletteCommands.all, key: { "\($0.title) \($0.subtitle)" })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command").foregroundStyle(Theme.muted)
                TextField("Komut ara…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 15)).focused($focused)
                    .onSubmit { runSelected() }
            }
            .padding(14)

            Divider().overlay(Theme.line)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, cmd in
                            CommandRow(cmd: cmd, selected: index == selected)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture { selected = index; runSelected() }
                        }
                        if results.isEmpty {
                            Text("Eşleşen komut yok")
                                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity).padding(.vertical, 18)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 300)
                .onChange(of: selected) { _, value in withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(value) } }
            }
        }
        .frame(width: 460)
        .background(Theme.surface)
        .onAppear { focused = true; selected = 0 }
        .onChange(of: query) { selected = 0 }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = (selected + delta + results.count) % results.count
    }

    private func runSelected() {
        guard results.indices.contains(selected) else { return }
        results[selected].run(model)
        dismiss()
    }
}

private struct CommandRow: View {
    let cmd: PaletteCommand
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: cmd.icon).font(.system(size: 13))
                .foregroundStyle(selected ? .white : Theme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(cmd.title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? .white : Theme.ink)
                Text(cmd.subtitle).font(.system(size: 10))
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Theme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(selected ? Theme.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}
