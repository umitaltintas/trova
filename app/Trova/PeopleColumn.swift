import SwiftUI
import TrovaCore

// MARK: - Kişiler sütunu

struct PeopleColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            if let address = model.selectedPersonAddress {
                PersonDetailHeader(address: address)
                Divider().overlay(Theme.line)
                personMails
            } else {
                header
                // Liste görünümünde ada/adrese göre canlı süzme (kişi detayındayken gizli).
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Kişi ara (ad/adres)…", text: $model.peopleQuery)
                        .textFieldStyle(.plain).font(.system(size: 14))
                        .onSubmit { model.loadPeople() }
                    if !model.peopleQuery.isEmpty {
                        Button { model.peopleQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faint)
                        }
                        .buttonStyle(.plain).help("Aramayı temizle")
                    }
                }
                .padding(10).cardSurface().padding(.horizontal, 12).padding(.bottom, 12)
                .onChange(of: model.peopleQuery) { model.loadPeople() }

                Divider().overlay(Theme.line)
                peopleList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface)
        .task { if model.people.isEmpty { model.loadPeople() } }
    }

    private var header: some View {
        HStack {
            Text("Kişiler").font(.rounded(18, .bold)).foregroundStyle(Theme.ink)
            Spacer()
            if !model.people.isEmpty {
                Text("\(model.people.count) kişi").font(.mono(11)).foregroundStyle(Theme.muted)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var peopleList: some View {
        if model.people.isEmpty {
            EmptyStateView(content: EmptyStates.people(
                hasIndex: model.totalCount > 0,
                hasQuery: !model.peopleQuery.trimmingCharacters(in: .whitespaces).isEmpty),
                           action: { model.runIndex() })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.people) { person in
                        PersonRow(person: person) { model.selectPerson(person.address) }
                    }
                }
                .padding(12)
            }
        }
    }

    private var personMails: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(model.personMails) { hit in
                    CitedRow(hit: hit, selected: hit.id == model.selection) {
                        model.selection = hit.id; model.loadSelected()
                    }
                }
            }
            .padding(12)
        }
    }
}

private struct PersonDetailHeader: View {
    @Environment(AppModel.self) private var model
    let address: String

    private var person: SenderStat? { model.people.first { $0.address == address } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    model.selectedPersonAddress = nil
                    model.personMails = []
                    model.personDetail = nil
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent).help("Kişilere dön")
                Avatar(name: person?.name, email: address, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person?.name ?? address).font(.rounded(14, .semibold))
                        .foregroundStyle(Theme.ink).lineLimit(1)
                    if person?.name != nil {
                        Text(address).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer()
                if !model.personMails.isEmpty {
                    ListExportMenu(markdown: { model.exportPersonMails() },
                                   csv: { model.exportPersonMailsCSV() },
                                   filename: person?.name ?? address,
                                   fullDocument: { model.exportPersonConversations() },
                                   fullDocumentFilename: "Yazışma \(person?.name ?? address)")
                }
                Button { model.composeNew(to: address) } label: {
                    Label("Yeni e-posta", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered).controlSize(.small).tint(Theme.accent)
                .help("Bu kişiye yeni e-posta oluştur (Mail.app penceresi açılır; gönderme yok)")
            }

            if let detail = model.personDetail {
                // İstatistik çipleri dar kişi panosunda taşmasın diye sarmalanır.
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    Chip(text: "\(detail.total) mail", systemImage: "envelope")
                    if detail.withAttachments > 0 {
                        Chip(text: "\(detail.withAttachments) ekli", systemImage: "paperclip")
                    }
                    if let first = detail.firstDate, let last = detail.lastDate {
                        let now = Date()
                        Chip(text: "\(RelativeTime.format(first, now: now)) – \(RelativeTime.format(last, now: now))",
                             systemImage: "calendar")
                            .help("\(RelativeTime.absolute(first)) – \(RelativeTime.absolute(last))")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
    }
}

private struct PersonRow: View {
    @Environment(AppModel.self) private var model
    let person: SenderStat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Avatar(name: person.name, email: person.address, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.name ?? person.address).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink).lineLimit(1)
                    if person.name != nil {
                        Text(person.address).font(.system(size: 10))
                            .foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer()
                Text("\(person.count)").font(.mono(11)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.accentSoft, in: Capsule())
            }
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { model.composeNew(to: person.address) } label: {
                Label("Yeni e-posta", systemImage: "square.and.pencil")
            }
        }
    }
}
