import SwiftUI
import TrovaCore

// MARK: - Sor (AI) sütunu

struct AskColumn: View {
    @Environment(AppModel.self) private var model
    @State private var showHistory = false

    private var exportedTurns: [ExportedTurn] {
        model.conversation.filter { !$0.answer.isEmpty }
            .map { ExportedTurn(question: $0.question, answer: $0.answer, citations: $0.cited) }
    }
    private var conversationTitle: String {
        model.conversation.first.map { "Trova: " + String($0.question.prefix(40)) } ?? "Trova sohbeti"
    }
    private var conversationMarkdown: String {
        MarkdownExporter.conversation(exportedTurns, title: conversationTitle)
    }

    var body: some View {
        Group {
            if model.conversation.isEmpty {
                EmptyStateView(content: EmptyStates.ask(hasIndex: model.totalCount > 0),
                               action: { model.runIndex() })
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(model.conversation) { exchange in
                                ExchangeView(exchange: exchange)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(12)
                    }
                    .onChange(of: model.conversation.count) { scrollToBottom(proxy) }
                    .onChange(of: model.conversation.last?.steps.count) { scrollToBottom(proxy) }
                    .onChange(of: model.conversation.last?.answer) { scrollToBottom(proxy) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        // Giriş çubuğunu safeAreaInset ile alta sabitleriz: boş durumda EmptyStateView tüm
        // alanı yutsa bile composer için yer rezerve edilir ve her zaman görünür kalır.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider().overlay(Theme.line)
                composer
            }
            .background(Theme.surface)   // şeffaf inset değil; içerik composer ardından sızmasın
        }
        .onAppear { model.loadConversations() }
    }

    /// Mesaj giriş çubuğu (composer): metin alanı, geçmiş popover'ı, dışa aktarma menüsü,
    /// "Yeni sohbet" ile "Sor"/"İptal" düğmeleri. Ekranın altında sabit durur.
    @ViewBuilder private var composer: some View {
        @Bindable var model = model
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(Theme.accent)
            TextField(model.conversation.isEmpty
                        ? "Sor: geçen ay kira ile ilgili mailleri özetle…"
                        : "Takip sorusu sor…",
                      text: $model.question)
                .textFieldStyle(.plain).font(.system(size: 14)).onSubmit { model.runAsk() }
            Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Geçmiş sohbetler")
                .popover(isPresented: $showHistory, arrowEdge: .bottom) {
                    ConversationHistoryList(dismiss: { showHistory = false })
                }
            if !model.conversation.isEmpty && !model.isAsking {
                if !exportedTurns.isEmpty {
                    Menu {
                        Button("Markdown kopyala") { Exporter.copy(conversationMarkdown) }
                        Button("Dışa aktar (.md)") {
                            Exporter.save(conversationMarkdown, suggestedName: conversationTitle)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .fixedSize().foregroundStyle(Theme.muted).help("Sohbeti dışa aktar")
                }
                Button { model.newConversation() } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Yeni sohbet")
            }
            if model.isAsking {
                Button { model.cancelJob() } label: { Text("İptal").font(.rounded(13, .semibold)) }
                    .buttonStyle(.bordered).tint(Theme.accent)
            } else {
                Button { model.runAsk() } label: { Text("Sor").font(.rounded(13, .semibold)) }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }
        .padding(10).cardSurface().padding(12)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

/// Geçmiş sohbetlerin listesi: bir satıra dokununca o sohbeti yeniden açar, çöp kutusu siler.
private struct ConversationHistoryList: View {
    @Environment(AppModel.self) private var model
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 12)).foregroundStyle(Theme.accent)
                Text("Geçmiş sohbetler").font(.rounded(13, .semibold)).foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

            Divider().overlay(Theme.line)

            if model.conversations.isEmpty {
                EmptyState(icon: "bubble.left.and.bubble.right",
                           title: "Henüz sohbet yok",
                           subtitle: "Sorduğun sohbetler burada birikir; eskilerini yeniden açabilirsin.")
                    .frame(height: 240)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.conversations) { summary in
                            ConversationRow(summary: summary,
                                            open: { model.loadConversation(summary.id); dismiss() },
                                            delete: { model.deleteConversation(summary.id) })
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 320, height: 380)
        .onAppear { model.loadConversations() }
    }
}

private struct ConversationRow: View {
    let summary: ConversationSummary
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(summary.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.mono(10)).foregroundStyle(Theme.faint)
                        Text("· \(summary.turnCount) tur").font(.mono(10)).foregroundStyle(Theme.faint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button(action: delete) { Image(systemName: "trash").font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Sohbeti sil")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line, lineWidth: 1))
    }
}

/// Sohbetteki tek bir tur: kullanıcı sorusu (baloncuk) + ajan izi + yanıt + kaynaklar.
private struct ExchangeView: View {
    @Environment(AppModel.self) private var model
    let exchange: AppModel.Exchange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer(minLength: 40)
                Text(exchange.question)
                    .font(.system(size: 13)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radius))
            }
            if !exchange.steps.isEmpty || exchange.running {
                AgentTrace(steps: exchange.steps, running: exchange.running)
            }
            if !exchange.answer.isEmpty { AnswerCard(text: exchange.answer) }
            if let verification = exchange.verification, verification.verdict != .unknown {
                VerificationBadge(verification: verification)
            }
            if !exchange.cited.isEmpty {
                ForEach(exchange.cited) { hit in
                    CitedRow(hit: hit, selected: hit.id == model.selection) {
                        model.selection = hit.id; model.loadSelected()
                    }
                }
            }
            if !exchange.answer.isEmpty && !exchange.running {
                ExportBar(
                    markdown: {
                        MarkdownExporter.answer(question: exchange.question,
                                                answer: exchange.answer, citations: exchange.cited)
                    },
                    filename: exchange.question)
            }
        }
    }
}

/// Ajanın adım adım ne yaptığını gösteren canlı iz.
private struct AgentTrace: View {
    let steps: [AgentStep]
    let running: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                HStack(spacing: 8) {
                    Image(systemName: icon(step.kind)).font(.system(size: 11))
                        .foregroundStyle(Theme.accent).frame(width: 16)
                    Text(label(step)).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            if running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Çalışıyor…").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    private func icon(_ kind: AgentStep.Kind) -> String {
        switch kind {
        case .search: "magnifyingglass"
        case .read: "doc.text"
        case .thread: "bubble.left.and.bubble.right"
        case .answer: "checkmark.seal.fill"
        case .note: "info.circle"
        }
    }
    private func label(_ step: AgentStep) -> String {
        switch step.kind {
        case .search: "Arandı: \(step.detail)"
        case .read: "Okundu: \(step.detail)"
        case .thread: "Konu incelendi: \(step.detail)"
        case .answer: "Yanıt hazırlandı"
        case .note: step.detail
        }
    }
}

/// AI yanıtını (blok-düzeyi markdown) gösteren kart. Sor ve Bugün (brifing) sütunlarınca
/// paylaşıldığından `internal`.
struct AnswerCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Yanıt", systemImage: "text.alignleft")
                .font(.rounded(12, .semibold)).foregroundStyle(Theme.accent)
            // Blok-düzeyi markdown (başlık/liste/kod) render edilir; satır-içi de korunur.
            MarkdownText(text, baseSize: 13)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.radius))
    }
}

/// Yanıtın kaynaklarla ne ölçüde desteklendiğini gösteren küçük rozet (self-critique).
private struct VerificationBadge: View {
    let verification: Verification

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(tint)
                Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(tint)
            }
            ForEach(Array(verification.issues.enumerated()), id: \.offset) { _, issue in
                Text("• \(issue)").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var icon: String {
        switch verification.verdict {
        case .grounded: "checkmark.seal.fill"
        case .partial: "exclamationmark.triangle.fill"
        case .unsupported: "xmark.seal.fill"
        case .unknown: "questionmark.circle"
        }
    }
    private var label: String {
        switch verification.verdict {
        case .grounded: "Kaynaklarla doğrulandı"
        case .partial: "Bazı iddialar kısmen destekli"
        case .unsupported: "İddialar kaynaklarla desteklenmiyor"
        case .unknown: ""
        }
    }
    private var tint: Color {
        switch verification.verdict {
        case .grounded: .green
        case .partial: .orange
        case .unsupported: .red
        case .unknown: Theme.muted
        }
    }
}
