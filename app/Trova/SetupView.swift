import SwiftUI
import TrovaCore

/// İlk-çalıştırma kurulum kapısı + her zaman tekrar açılabilen sağlık/teşhis paneli.
/// `HealthCheck.evaluate` çıktısını adım adım kontrol listesine dönüştürür.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var asSheet = false

    var body: some View {
        let report = model.health
        VStack(alignment: .leading, spacing: 0) {
            header(report)
            Divider().overlay(Theme.line)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(report.items) { ChecklistRow(item: $0) }
                    if model.busy { progressCard }
                }
                .padding(18)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface)
    }

    @ViewBuilder
    private func header(_ report: HealthReport) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color(report.overall).opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: report.overall == .ok ? "checkmark.seal.fill" : "wrench.and.screwdriver.fill")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(color(report.overall))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(report.isReady ? "Trova hazır" : "Kuruluma birkaç adım kaldı")
                    .font(.rounded(18, .bold)).foregroundStyle(Theme.ink)
                Text(report.isReady
                     ? "Tüm kontroller yolunda. Maillerinizi aramaya başlayabilirsiniz."
                     : "Tam kapasite için aşağıdaki adımları tamamlayın.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button { model.refreshAccess(); model.refreshStatus() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.accent).help("Yenile")
            if asSheet {
                Button("Kapat") { dismiss() }.controlSize(.small)
            }
        }
        .padding(18)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: model.jobTotal > 0 ? Double(model.jobProcessed) : nil,
                         total: Double(max(model.jobTotal, 1))).tint(Theme.accent)
            HStack {
                Text(model.progress).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer()
                Button("İptal") { model.cancelJob() }
                    .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
        }
        .padding(12).cardSurface()
    }

    private func color(_ s: HealthStatus) -> Color {
        switch s {
        case .ok: .green
        case .warn: .orange
        case .fail: .red
        }
    }
}

/// Tek bir sağlık maddesini durum simgesi + açıklama + (gerekiyorsa) eylem düğmesiyle gösterir.
private struct ChecklistRow: View {
    @Environment(AppModel.self) private var model
    let item: HealthItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.rounded(14, .semibold)).foregroundStyle(Theme.ink)
                Text(item.detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var icon: String {
        switch item.status {
        case .ok: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch item.status {
        case .ok: .green
        case .warn: .orange
        case .fail: .red
        }
    }

    /// Madde henüz tamam değilse onu çözmeye yarayan birincil eylemi gösterir.
    @ViewBuilder
    private var action: some View {
        if item.status != .ok {
            switch item.id {
            case "fda":
                Button("Ayarları Aç") { model.openFullDiskAccessSettings() }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
            case "index":
                Button("İndeksle") { model.runIndex() }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
                    .disabled(model.busy || !model.hasAccess)
            case "vectors":
                Button("Gömme") { model.runEmbed() }
                    .buttonStyle(.bordered).tint(Theme.accent).controlSize(.small)
                    .disabled(model.busy || model.totalCount == 0)
            case "llm", "embedder":
                SettingsLink { Text("Ayarlar") }
                    .buttonStyle(.bordered).controlSize(.small)
            default:
                EmptyView()
            }
        }
    }
}
