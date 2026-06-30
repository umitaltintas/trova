import SwiftUI
import Charts
import TrovaCore

/// "Genel Bakış" sütunu: posta kutusunu anlamak için istatistik kartları + aylık hacim grafiği.
struct InsightsColumn: View {
    @Environment(AppModel.self) private var model

    private var noData: Bool { model.monthly.allSatisfy { $0.count == 0 } }
    private var noBalanceData: Bool {
        model.monthlyBalance.allSatisfy { $0.received == 0 && $0.sent == 0 }
    }

    var body: some View {
        Group {
            if model.totalCount == 0 {
                // İndeks yoksa istatistik yerine indeksleme daveti (tek kaynak).
                EmptyStateView(content: EmptyStates.insights(hasIndex: false),
                               action: { model.runIndex() })
            } else {
                content
            }
        }
        .background(Theme.surface)
        .task { model.loadInsights() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Genel Bakış").font(.rounded(20, .bold)).foregroundStyle(Theme.ink)

                HStack(spacing: 10) {
                    StatCard(label: "Mail", value: model.totalCount.formatted(), icon: "envelope.fill")
                    StatCard(label: "Hesap", value: "\(model.accounts.count)", icon: "person.crop.square.fill")
                    StatCard(label: "Ekli", value: model.attachmentTotal.formatted(), icon: "paperclip")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Son 12 ay").font(.rounded(13, .semibold)).foregroundStyle(Theme.ink)
                    if noData {
                        Text(EmptyStates.insights(hasIndex: true).message)
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        Chart(model.monthly) { item in
                            BarMark(
                                x: .value("Ay", item.shortLabel),
                                y: .value("Mail", item.count)
                            )
                            .foregroundStyle(Theme.accent.gradient)
                            .cornerRadius(3)
                        }
                        .frame(height: 200)
                        .chartYAxis { AxisMarks(position: .leading) }
                    }
                }
                .padding(14).cardSurface()

                // Gelen vs Gönderilen: son 12 ay, ay başına gruplu (yan yana) çubuklar.
                // Veri yoksa kartı tamamen gizle (boş gürültü olmasın).
                if !noBalanceData {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Gelen vs Gönderilen").font(.rounded(13, .semibold)).foregroundStyle(Theme.ink)
                        Chart(model.monthlyBalance) { item in
                            BarMark(
                                x: .value("Ay", item.shortLabel),
                                y: .value("Mail", item.received)
                            )
                            .position(by: .value("Tür", "Gelen"))
                            .foregroundStyle(by: .value("Tür", "Gelen"))
                            .cornerRadius(3)
                            BarMark(
                                x: .value("Ay", item.shortLabel),
                                y: .value("Mail", item.sent)
                            )
                            .position(by: .value("Tür", "Gönderilen"))
                            .foregroundStyle(by: .value("Tür", "Gönderilen"))
                            .cornerRadius(3)
                        }
                        .chartForegroundStyleScale(["Gelen": Theme.accent, "Gönderilen": Theme.amber])
                        .chartLegend(position: .bottom, spacing: 8)
                        .frame(height: 200)
                        .chartYAxis { AxisMarks(position: .leading) }
                    }
                    .padding(14).cardSurface()
                }

                if !model.people.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("En çok yazışılanlar").font(.rounded(13, .semibold)).foregroundStyle(Theme.ink)
                        ForEach(model.people.prefix(5)) { person in
                            Button {
                                model.section = .people
                                model.selectPerson(person.address)
                            } label: {
                                HStack(spacing: 10) {
                                    Avatar(name: person.name, email: person.address, size: 26)
                                    Text(person.name ?? person.address)
                                        .font(.system(size: 12)).foregroundStyle(Theme.ink).lineLimit(1)
                                    Spacer()
                                    Text("\(person.count)").font(.mono(11)).foregroundStyle(Theme.accent)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14).cardSurface()
                }
            }
            .padding(16)
        }
    }
}

private struct StatCard: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Theme.accent)
            Text(value).font(.mono(20)).foregroundStyle(Theme.ink)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).cardSurface()
    }
}

/// MonthCount "yyyy-MM" → grafik ekseni için kısa Türkçe ay etiketi ("Kas").
/// Ay→etiket dönüşümü paylaşılan TurkishMonth yardımcısından gelir (kopyalama yok).
extension MonthCount {
    var shortLabel: String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), let label = TurkishMonth.short(m) else { return month }
        return label
    }
}

/// MonthSentReceived → grafik ekseni için kısa Türkçe ay etiketi ("Kas"); aynı paylaşılan yardımcı.
extension MonthSentReceived {
    var shortLabel: String { TurkishMonth.short(month) ?? "\(month)" }
}
