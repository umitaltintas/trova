import SwiftUI

/// Embedding ve LLM sağlayıcı ayarları. Anahtarlar Keychain'de saklanır.
struct SettingsView: View {
    @AppStorage(SettingsKeys.embedProvider) private var embedProvider = "local"
    @AppStorage(SettingsKeys.embedModel) private var embedModel = ""
    @AppStorage(SettingsKeys.embedDim) private var embedDim = ""
    @AppStorage(SettingsKeys.llmModel) private var llmModel = "anthropic/claude-sonnet-4.6"
    @AppStorage(SettingsKeys.reranking) private var reranking = false
    @AppStorage(SettingsKeys.verify) private var verify = false
    @AppStorage(SettingsKeys.diversify) private var diversify = true
    @AppStorage(SettingsKeys.queryExpansion) private var queryExpansion = false
    @AppStorage(SettingsKeys.streamAnswers) private var streamAnswers = true
    @AppStorage(SettingsKeys.indexAttachmentContent) private var indexAttachmentContent = false

    @Environment(AppModel.self) private var model

    @State private var embedKey = Keychain.get(KeychainKeys.embedKey)
    @State private var llmKey = Keychain.get(KeychainKeys.llmKey)

    var body: some View {
        TabView {
            Form {
                Picker("Sağlayıcı", selection: $embedProvider) {
                    Text("Yerel (offline, ücretsiz)").tag("local")
                    Text("OpenRouter (LLM ile tek anahtar)").tag("openrouter")
                    Text("OpenAI").tag("openai")
                    Text("Voyage").tag("voyage")
                }
                if embedProvider == "openrouter" {
                    Text("AI sekmesindeki OpenRouter anahtarı kullanılır. "
                       + "Model örn. openai/text-embedding-3-small, qwen/qwen3-embedding-0.6b.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Model (opsiyonel)", text: $embedModel)
                    TextField("Boyut (opsiyonel)", text: $embedDim)
                } else if embedProvider != "local" {
                    SecureField("API anahtarı", text: $embedKey)
                        .onChange(of: embedKey) { _, value in Keychain.set(value, for: KeychainKeys.embedKey) }
                    TextField("Model (opsiyonel)", text: $embedModel)
                    TextField("Boyut (opsiyonel)", text: $embedDim)
                }
                if embedProvider != "local" {
                    Text("Sağlayıcı/boyut değişince mailleri yeniden gömün (Gömme düğmesi).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("Embedding", systemImage: "wand.and.stars") }
            .padding()

            Form {
                SecureField("OpenRouter API anahtarı", text: $llmKey)
                    .onChange(of: llmKey) { _, value in Keychain.set(value, for: KeychainKeys.llmKey) }
                TextField("Model", text: $llmModel)
                Text("Örn. anthropic/claude-sonnet-4.6, openai/gpt-4o-mini. "
                   + "Anahtar Keychain'de saklanır.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("AI yeniden sıralama (reranking)", isOn: $reranking)
                Text("Sonuçları LLM ile yeniden sıralar: ek bir model çağrısı maliyeti getirir "
                   + "ama sıralama kalitesini artırır.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Yanıt doğrulama (self-critique)", isOn: $verify)
                Text("Yanıt sonrası ek bir LLM çağrısı: iddiaların kaynak maillerce desteklenip "
                   + "desteklenmediğini denetler ve desteklenmeyenleri işaretler (ek maliyet).")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Sonuçları çeşitlendir", isOn: $diversify)
                Text("Aynı konuşmanın çok sayıda benzer mesajının üst sıraları tıkamasını önler; "
                   + "thread başına en çok \(Retrieval.perThread) sonuç gösterip farklı konuşmaları öne çıkarır.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Sorgu genişletme (PRF)", isOn: $queryExpansion)
                Text("İlk sonuçların sık terimlerini sorguya ekleyerek kelime dağarcığı boşluklarını "
                   + "kapatır (recall artar). Eklenen terimler arama üstünde çip olarak gösterilir.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Yanıtı canlı akıt (streaming)", isOn: $streamAnswers)
                Text("Sor ajanının nihai yanıtını token token, yazılır gibi canlı gösterir. "
                   + "Kapalıyken yanıt tamamlanınca tek seferde belirir.")
                    .font(.caption).foregroundStyle(.secondary)

                Divider()
                HStack {
                    Text("Ajan hafızası (\(model.memoryCount))")
                    Spacer()
                    Button("Tümünü temizle") { model.clearMemory() }
                        .disabled(model.memoryCount == 0)
                }
                MemoryList()
                Text("Ajanın oturumlar arası hatırladığı kalıcı bilgiler (tercih, kişi, talimat).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("AI (OpenRouter)", systemImage: "sparkles") }
            .padding()
            .onAppear { model.refreshStatus(); model.loadMemories() }

            Form {
                Toggle("Ek içeriğini indeksle (PDF/metin)", isOn: $indexAttachmentContent)
                Text("Eklerin İÇİNDEKİ metni (PDF metin katmanı ve düz metin: txt, md, csv, tsv, log, rtf) "
                   + "aranabilir kılar. Görseller ve taranmış PDF'ler (OCR) HARİÇtir — yalnız hazır "
                   + "metin okunur. Çıkarım pahalı olabilir; bu yüzden varsayılan kapalıdır.")
                    .font(.caption).foregroundStyle(.secondary)

                Divider()

                Text("İndekslenen ek içeriği: \(model.attachmentContentCount) mail")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)

                Button {
                    model.runAttachmentContentPass()
                } label: {
                    Label("Ek içeriğini şimdi indeksle", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(model.busy || !indexAttachmentContent)
                Text("Eki olan tüm mevcut mailleri gezip içeriklerini çıkarır. Artımlı indeksleme "
                   + "değişmemiş mailleri atladığından, açtıktan sonra bir kez çalıştırın.")
                    .font(.caption).foregroundStyle(.secondary)

                Button(role: .destructive) {
                    model.clearAttachmentContent()
                } label: {
                    Label("Ek içeriğini temizle", systemImage: "trash")
                }
                .disabled(model.busy || model.attachmentContentCount == 0)
                Text("Toggle'ı kapattıktan sonra indekslenmiş ek içeriğini silmek için kullanın.")
                    .font(.caption).foregroundStyle(.secondary)

                if model.busy, !model.progress.isEmpty {
                    Divider()
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(model.progress).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .tabItem { Label("Ek içeriği", systemImage: "doc.text.magnifyingglass") }
            .padding()
            .onAppear { model.refreshStatus() }

            Form {
                Text("Yinelenen mailler")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("Apple Mail (Gmail/IMAP) aynı maili birden çok yere yazar (Tüm Postalar + Gelen "
                   + "Kutusu + her etiket) → aynı mail için birden çok `.emlx` dosyası. Bunlar indekste "
                   + "kopya satırlar oluşturur; sayıyı şişirir. Bu araç her mail için tek bir kanonik "
                   + "satır bırakıp kopyaları (ve yetim ek/gömme kayıtlarını) siler. Kaynak `.emlx` "
                   + "dosyalarına DOKUNMAZ — yalnızca indeksi sadeleştirir.")
                    .font(.caption).foregroundStyle(.secondary)

                Divider()

                Text(model.duplicateCount > 0
                     ? "\(model.totalCount) satır · \(model.duplicateCount) yinelenen"
                     : "\(model.totalCount) satır · yinelenen yok")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)

                Button {
                    model.dedupeMessages()
                } label: {
                    Label("Yinelenen mailleri temizle", systemImage: "rectangle.stack.badge.minus")
                }
                .disabled(model.busy || model.duplicateCount == 0)

                if model.busy, !model.progress.isEmpty {
                    Divider()
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(model.progress).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .tabItem { Label("Bakım", systemImage: "wrench.and.screwdriver") }
            .padding()
            .onAppear { model.refreshStatus() }
        }
        .frame(width: 480, height: 460)
    }
}

/// Ajanın kayıtlı hafızalarını listeler; her satır tek tek silinebilir.
private struct MemoryList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.memories.isEmpty {
            Text("Henüz hatırlanan bir bilgi yok.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(model.memories) { memory in
                        HStack(alignment: .top, spacing: 8) {
                            Text(memory.text).font(.system(size: 12))
                                .foregroundStyle(Theme.ink).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(memory.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.mono(10)).foregroundStyle(Theme.faint)
                            Button { model.deleteMemory(memory.id) } label: {
                                Image(systemName: "trash").font(.system(size: 11))
                            }
                            .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Bu hafızayı sil")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    }
                }
            }
            .frame(maxHeight: 140)
        }
    }
}
