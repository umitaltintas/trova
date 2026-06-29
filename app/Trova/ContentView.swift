import SwiftUI
import TrovaCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("autoSync") private var autoSync = false

    var body: some View {
        NavigationSplitView {
            Sidebar(autoSync: $autoSync)
                .navigationSplitViewColumnWidth(min: 204, ideal: 224, max: 280)
        } content: {
            Group {
                if model.shouldShowSetup { SetupView() }
                else if model.section == .ask { AskColumn() }
                else if model.section == .digest { DigestColumn() }
                else { SearchColumn() }
            }
            .navigationSplitViewColumnWidth(min: 340, ideal: 440)
        } detail: {
            ReadingPane()
                .navigationSplitViewColumnWidth(min: 360, ideal: 480)
        }
        .task { model.onAppear(); if autoSync { model.setAutoSync(true) } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshAccess(); model.refreshStatus() }
        }
        .overlay(alignment: .bottom) { ErrorBanner() }
    }
}

/// Hata mesajını alttan gösteren, kapatılabilir şerit.
private struct ErrorBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let message = model.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.system(size: 12)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line))
            .frame(maxWidth: 560)
            .padding(14)
        }
    }
}

// MARK: - Kenar çubuğu

private struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var autoSync: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.accent)
                Text("Trova").font(.rounded(19, .bold)).foregroundStyle(Theme.ink)
            }
            .padding(.top, 4)

            VStack(spacing: 5) {
                ModeButton(title: "Sor", subtitle: "AI ile bul + özetle",
                           icon: "sparkles", active: model.section == .ask) { model.section = .ask }
                ModeButton(title: "Ara", subtitle: "Kelime / anlamsal",
                           icon: "magnifyingglass", active: model.section == .search) { model.section = .search }
                ModeButton(title: "Bugün", subtitle: "Brifing + yanıt bekleyenler",
                           icon: "sun.max", active: model.section == .digest) { model.section = .digest }
            }

            StatusBlock()
            FilterBlock()
            Spacer()

            HealthPill()

            Toggle(isOn: $autoSync) {
                Label("Otomatik senkron", systemImage: "bolt.fill").font(.system(size: 12))
            }
            .toggleStyle(.switch).controlSize(.mini).tint(Theme.accent)
            .disabled(!model.hasAccess)
            .onChange(of: autoSync) { _, on in model.setAutoSync(on) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Kenar çubuğunda genel sağlık durumunu renkli noktayla gösterir; tıklayınca teşhis panelini açar.
private struct HealthPill: View {
    @Environment(AppModel.self) private var model
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            HStack(spacing: 7) {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                Text("Sağlık").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "stethoscope").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .cardSurface()
        }
        .buttonStyle(.plain)
        .help("Kurulum ve sağlık teşhisi")
        .sheet(isPresented: $show) {
            SetupView(asSheet: true)
                .environment(model)
                .frame(width: 540, height: 560)
        }
    }

    private var dotColor: Color {
        switch model.health.overall {
        case .ok: .green
        case .warn: .orange
        case .fail: .red
        }
    }
}

private struct ModeButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(active ? .white : Theme.accent).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.rounded(14, .semibold))
                        .foregroundStyle(active ? .white : Theme.ink)
                    Text(subtitle).font(.system(size: 10))
                        .foregroundStyle(active ? Color.white.opacity(0.85) : Theme.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(active ? Theme.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        }
        .buttonStyle(.plain)
    }
}

private struct StatusBlock: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.hasAccess {
                StatRow(icon: "envelope.fill", label: "Mail", value: model.totalCount.formatted())
                StatRow(icon: "circle.hexagongrid.fill", label: "Vektör", value: model.vectorCount.formatted())
                if model.totalCount > 0 {
                    let coverage = Double(model.vectorCount) / Double(model.totalCount)
                    HStack(spacing: 8) {
                        Text("Kapsam").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        Spacer()
                        SignalBar(value: coverage, segments: 8, height: 8)
                        Text("\(Int(coverage * 100))%").font(.mono(10)).foregroundStyle(Theme.accent)
                    }
                }
            } else {
                Label("Erişim gerekli", systemImage: "lock.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            HStack(spacing: 6) {
                ActionButton(title: "İndeksle", icon: "tray.and.arrow.down",
                             disabled: model.busy || !model.hasAccess) { model.runIndex() }
                ActionButton(title: "Gömme", icon: "wand.and.stars",
                             disabled: model.busy) { model.runEmbed() }
            }
            if model.busy {
                ProgressView(value: model.jobTotal > 0 ? Double(model.jobProcessed) : nil,
                             total: Double(max(model.jobTotal, 1)))
                    .tint(Theme.accent)
                HStack {
                    Text(model.progress).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer()
                    Button("İptal") { model.cancelJob() }
                        .font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
            } else if !model.progress.isEmpty {
                Text(model.progress).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(2)
            }
        }
        .padding(10)
        .cardSurface()
    }
}

private struct StatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Theme.accent).frame(width: 16)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(.mono(12, .medium)).foregroundStyle(Theme.ink)
        }
    }
}

private struct ActionButton: View {
    let title: String
    let icon: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
        }
        .controlSize(.small).buttonStyle(.bordered).tint(Theme.accent).disabled(disabled)
    }
}

private struct FilterBlock: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 6) {
            Text("FİLTRE").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.faint).tracking(0.6)
            Picker("Hesap", selection: $model.filterAccount) {
                Text("Tüm hesaplar").tag("")
                ForEach(model.accounts) { account in
                    Text("\(account.account.prefix(6))… · \(account.count)").tag(account.account)
                }
            }
            .labelsHidden().controlSize(.small)
            Picker("Tarih", selection: $model.dateRange) {
                ForEach(DateRange.allCases) { range in Text(range.label).tag(range) }
            }
            .labelsHidden().controlSize(.small)
        }
        .onChange(of: model.filterAccount) { if !model.query.isEmpty { model.runSearch() } }
        .onChange(of: model.dateRange) { if !model.query.isEmpty { model.runSearch() } }
    }
}

// MARK: - Ara sütunu

private struct SearchColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Mailde ara…", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 14)).onSubmit { model.runSearch() }
                Picker("", selection: $model.mode) {
                    Text("Hibrit").tag(SearchMode.hybrid)
                    Text("Anlamsal").tag(SearchMode.semantic)
                    Text("Kelime").tag(SearchMode.fts)
                }
                .labelsHidden().frame(width: 116).controlSize(.small)
            }
            .padding(10).cardSurface().padding(12)

            Divider().overlay(Theme.line)

            if model.isSearching {
                VStack { Spacer(); ProgressView().tint(Theme.accent); Spacer() }
            } else if model.results.isEmpty {
                EmptyState(icon: "magnifyingglass", title: "Mailde ara",
                           subtitle: "Anahtar kelime ya da anlamsal bir sorgu yaz; ek dosya adları da aranır.")
            } else {
                List(selection: $model.selection) {
                    ForEach(model.results) { hit in
                        ResultRow(hit: hit)
                            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .onChange(of: model.selection) { model.loadSelected() }
            }
        }
        .background(Theme.surface)
    }
}

private struct ResultRow: View {
    let hit: SearchHit

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(name: hit.fromName, email: hit.fromAddress, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if !hit.attachments.isEmpty {
                        Image(systemName: "paperclip").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                    Text(hit.subject ?? "(konu yok)")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer()
                    if let date = hit.date {
                        Text(date.formatted(date: .numeric, time: .omitted))
                            .font(.mono(10)).foregroundStyle(Theme.faint)
                    }
                }
                Text(hit.fromName ?? hit.fromAddress ?? "—")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                if !hit.snippet.isEmpty {
                    Text(hit.snippet).font(.system(size: 11)).foregroundStyle(Theme.faint).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sor (AI) sütunu

private struct AskColumn: View {
    @Environment(AppModel.self) private var model
    @State private var showHistory = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if model.conversation.isEmpty {
                EmptyState(icon: "sparkles", title: "Bir soru sor",
                           subtitle: "Ajan arar, ilgili maili okur, bulduğuna göre yeniden arar; sonra "
                                   + "kaynaklı yanıtlar. Yanıtın üstüne takip soruları sorabilirsin.")
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

            Divider().overlay(Theme.line)

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
        .background(Theme.surface)
        .onAppear { model.loadConversations() }
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

private struct AnswerCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Yanıt", systemImage: "text.alignleft")
                .font(.rounded(12, .semibold)).foregroundStyle(Theme.accent)
            Text(markdown).font(.system(size: 13)).foregroundStyle(Theme.ink)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    private var markdown: AttributedString {
        (try? AttributedString(markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
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

private struct CitedRow: View {
    let hit: SearchHit
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Avatar(name: hit.fromName, email: hit.fromAddress, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.subject ?? "(konu yok)").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink).lineLimit(1)
                    Text(hit.fromName ?? hit.fromAddress ?? "—").font(.system(size: 10))
                        .foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                if !hit.attachments.isEmpty {
                    Image(systemName: "paperclip").font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
            }
            .padding(10)
            .background(selected ? Theme.accentSoft : Theme.card,
                        in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .stroke(selected ? Theme.accent.opacity(0.5) : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bugün (proaktif asistan) sütunu

private struct DigestColumn: View {
    @Environment(AppModel.self) private var model

    private var isEmpty: Bool {
        model.needsReply.isEmpty && model.waitingOn.isEmpty && model.digestText.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DigestCard()
                if !model.needsReply.isEmpty {
                    TriageSection(title: "Yanıt gerekiyor",
                                  subtitle: "Karşı taraf en son yazdı",
                                  icon: "arrowshape.turn.up.left.fill",
                                  hits: model.needsReply)
                }
                if !model.waitingOn.isEmpty {
                    TriageSection(title: "Yanıt bekliyor",
                                  subtitle: "Sen yazdın, henüz yanıt yok",
                                  icon: "hourglass",
                                  hits: model.waitingOn)
                }
                if isEmpty && !model.isDigesting {
                    EmptyState(icon: "sun.max", title: "Bugün için temiz",
                               subtitle: "Yanıt bekleyen bir konu yok. Üstteki düğmeyle günlük "
                                       + "brifing oluşturabilirsin.")
                        .frame(minHeight: 240)
                }
            }
            .padding(12)
        }
        .background(Theme.surface)
        .task { model.loadTriage() }
    }
}

/// Günlük brifing kartı: oluştur/yenile düğmesi + (varsa) markdown brifing.
private struct DigestCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill").font(.system(size: 14)).foregroundStyle(Theme.accent)
                Text("Günlük brifing").font(.rounded(15, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                if model.isDigesting {
                    ProgressView().controlSize(.small)
                } else {
                    Button { model.runDigest() } label: {
                        Label(model.digestText.isEmpty ? "Brifing oluştur" : "Yenile",
                              systemImage: "sparkles").font(.rounded(12, .semibold))
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
                }
            }
            if model.digestText.isEmpty && !model.isDigesting {
                Text("Son 2 günde gelen mailleri tek bakışta, temaya göre gruplayıp özetler; "
                   + "yanıt bekleyenleri çıkarır.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.digestText.isEmpty {
                AnswerCard(text: model.digestText)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }
}

/// Başlık + triyaj satırları (yanıt gerekiyor / yanıt bekliyor).
private struct TriageSection: View {
    @Environment(AppModel.self) private var model
    let title: String
    let subtitle: String
    let icon: String
    let hits: [SearchHit]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.accent)
                Text(title).font(.rounded(14, .semibold)).foregroundStyle(Theme.ink)
                Text("\(hits.count)").font(.mono(11)).foregroundStyle(Theme.faint)
                Spacer()
            }
            Text(subtitle.uppercased()).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.faint).tracking(0.5)
            VStack(spacing: 6) {
                ForEach(hits) { hit in
                    TriageRow(hit: hit, selected: hit.id == model.selection) {
                        model.selection = hit.id; model.loadSelected()
                    }
                }
            }
        }
    }
}

private struct TriageRow: View {
    let hit: SearchHit
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Avatar(name: hit.fromName, email: hit.fromAddress, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.subject ?? "(konu yok)").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink).lineLimit(1)
                    Text(hit.fromName ?? hit.fromAddress ?? "—").font(.system(size: 10))
                        .foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                if !hit.attachments.isEmpty {
                    Image(systemName: "paperclip").font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                AgeChip(date: hit.date)
            }
            .padding(10)
            .background(selected ? Theme.accentSoft : Theme.card,
                        in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .stroke(selected ? Theme.accent.opacity(0.5) : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Mailin yaşını "3g" / "bugün" gibi kısa bir çiple gösterir.
private struct AgeChip: View {
    let date: Date?

    var body: some View {
        let days = AppModel.ageDays(date)
        Text(days <= 0 ? "bugün" : "\(days)g")
            .font(.mono(10, .medium)).foregroundStyle(Theme.accent)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.accentSoft, in: Capsule())
    }
}

// MARK: - Okuma paneli

private struct ReadingPane: View {
    @Environment(AppModel.self) private var model
    @State private var formatted = true

    var body: some View {
        if let hit = model.selectedHit {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(hit.subject ?? "(konu yok)")
                        .font(.rounded(18, .bold)).foregroundStyle(Theme.ink)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Avatar(name: hit.fromName, email: hit.fromAddress, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(hit.fromName ?? hit.fromAddress ?? "—")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                            if let address = hit.fromAddress, hit.fromName != nil {
                                Text(address).font(.system(size: 11)).foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer()
                        if let date = hit.date {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.mono(11)).foregroundStyle(Theme.muted)
                        }
                    }
                    HStack(spacing: 6) {
                        Chip(text: hit.mailbox, systemImage: "tray")
                        ForEach(hit.attachments, id: \.self) { Chip(text: $0, systemImage: "paperclip") }
                        Spacer()
                        Button { model.openInMail() } label: {
                            Label("Mail'de Aç", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.bordered).controlSize(.small).tint(Theme.accent)
                        .disabled(MailLink.appleMailURL(messageID: model.selectedMessageID) == nil)
                        .help("Bu maili Apple Mail.app'te aç (yanıtlamak/işlem yapmak için)")
                        if model.selectedHTML?.isEmpty == false {
                            Picker("", selection: $formatted) {
                                Text("Biçimli").tag(true)
                                Text("Düz").tag(false)
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 140).controlSize(.small)
                        }
                    }
                }
                .padding(16)

                Divider().overlay(Theme.line)

                if formatted, let html = model.selectedHTML, !html.isEmpty {
                    HTMLView(html: html)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line))
                        .padding(12)
                } else {
                    ScrollView {
                        Text(model.selectedBody?.isEmpty == false ? model.selectedBody! : hit.snippet)
                            .font(.system(size: 13)).foregroundStyle(Theme.ink).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    }
                }

                if model.selectedThread.count > 1 {
                    Divider().overlay(Theme.line)
                    ThreadStrip()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface)
        } else {
            EmptyState(icon: "envelope.open",
                       title: "Mail seçin",
                       subtitle: "Soldaki listeden bir mail seçince içeriği burada okunur.")
                .background(Theme.surface)
        }
    }
}

private struct ThreadStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BU KONUDA \(model.selectedThread.count) MAIL")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.faint).tracking(0.6)
                .padding(.horizontal, 16).padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.selectedThread) { message in
                        Button {
                            model.selection = message.id
                            model.loadSelected()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(message.fromName ?? message.fromAddress ?? "—")
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                                if let date = message.date {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.mono(9)).foregroundStyle(Theme.muted)
                                }
                            }
                            .padding(8).frame(width: 132, alignment: .leading)
                            .background(message.id == model.selection ? Theme.accentSoft : Theme.card,
                                        in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 10)
            }
        }
    }
}

// MARK: - Erişim kapısı

