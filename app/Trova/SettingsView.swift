import SwiftUI
import TrovaCore

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
    @AppStorage("menuBarExtra") private var menuBarExtra = true
    @AppStorage(SettingsKeys.notifyNewMail) private var notifyNewMail = false
    @AppStorage(SettingsKeys.autoDigest) private var autoDigest = false
    @AppStorage(SettingsKeys.autoDigestHour) private var autoDigestHour = 8
    @AppStorage(SettingsKeys.autoDigestMinute) private var autoDigestMinute = 0

    @Environment(AppModel.self) private var model

    // Bildirim izni reddedilmiş mi — açılışta ve toggle değişince async kontrol edilir (.task/onChange).
    @State private var notificationDenied = false

    // Anahtarlar init'te DEĞİL, açıldıktan sonra ana thread dışında yüklenir (aşağıdaki .task).
    // Senkron `Keychain.get` init'ten çağrılsaydı, yeniden imzalama sonrası onay diyaloğu
    // beklerken ana thread kilitlenir ve pencere hiç açılmazdı (donma). Yüklenene dek boş.
    @State private var embedKey = ""
    @State private var llmKey = ""
    @State private var keysLoaded = false

    /// DatePicker(.hourAndMinute) için Date↔(saat,dakika) köprüsü: yalnız saat/dakika bileşenleri
    /// okunur/yazılır (gün önemsiz). Yazarken @AppStorage Int'leri güncellenir; zamanlayıcı bunları okur.
    private var digestTime: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents(); comps.hour = autoDigestHour; comps.minute = autoDigestMinute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                autoDigestHour = comps.hour ?? 8
                autoDigestMinute = comps.minute ?? 0
            }
        )
    }

    var body: some View {
        TabView {
            Form {
                Toggle("Menü çubuğunda göster", isOn: $menuBarExtra)
                    .help("Trova simgesini menü çubuğunda gösterir; oradan hızlı arama, bugün "
                        + "brifingi ve indeksleme tek tıkla erişilir.")
                Text("Menü çubuğu eki; yeni mail geldiğinde ikonda rozet gösterir ve ana pencereyi "
                   + "hızlıca öne getirmenizi sağlar.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Yeni mail bildirimi", isOn: $notifyNewMail)
                    .help("Otomatik senkron açıkken yeni mail geldiğinde macOS bildirimi ve Dock "
                        + "rozeti gösterir.")
                    .onChange(of: notifyNewMail) { _, enabled in
                        // Rozeti anında yeni duruma göre tazele (kapatınca varsa iz kalmaz).
                        model.syncDockBadge()
                        if enabled {
                            Task {
                                let granted = await MailNotifier.requestAuthorizationIfNeeded()
                                notificationDenied = !granted
                            }
                        } else {
                            notificationDenied = false
                        }
                    }
                Text("Otomatik senkron açıkken yeni mail geldiğinde macOS bildirimi ve Dock rozeti "
                   + "gösterir.")
                    .font(.caption).foregroundStyle(.secondary)
                if notificationDenied {
                    Text("Bildirim izni reddedilmiş — Sistem Ayarları > Bildirimler'den açabilirsiniz.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Toggle("Günlük brifingi otomatik oluştur", isOn: $autoDigest)
                    .help("Belirlenen saatte Bugün brifingini oluşturur ve bildirim gösterir "
                        + "(uygulama açıkken).")
                    .onChange(of: autoDigest) { _, enabled in
                        model.setAutoDigest(enabled)
                        if enabled {
                            // Toggle açılınca bildirim izni iste (Iter 63 kalıbı).
                            Task {
                                let granted = await MailNotifier.requestAuthorizationIfNeeded()
                                notificationDenied = !granted
                            }
                        }
                    }
                if autoDigest {
                    DatePicker("Brifing saati", selection: digestTime,
                               displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                }
                Text("Belirlenen saatte Bugün brifingini oluşturur ve bildirim gösterir "
                   + "(uygulama açıkken).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("Genel", systemImage: "gearshape") }
            .padding()

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
                        // keysLoaded kontrolü: async yükleme sırasında alanın boştan gerçek
                        // anahtara dolması onChange'i tetikler; bu ilk doldurmayı yeniden
                        // Keychain'e YAZMAMAK için yükleme bitmeden kaydetmiyoruz.
                        .onChange(of: embedKey) { _, value in
                            guard keysLoaded else { return }
                            Keychain.set(value, for: KeychainKeys.embedKey)
                        }
                    if !keysLoaded { keyLoadingIndicator }
                    TextField("Model (opsiyonel)", text: $embedModel)
                    TextField("Boyut (opsiyonel)", text: $embedDim)
                }
                if embedProvider == "local" {
                    Text("Cihaz-üstü Apple modeli (NLContextualEmbedding) — çok dilli, anahtar gerekmez, "
                       + "hiçbir veri dışarı çıkmaz. Model varlıkları bir kez indirilir.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        if model.downloadingLocalEmbedAssets {
                            ProgressView().controlSize(.small)
                            Text("Yerel model indiriliyor…").font(.caption).foregroundStyle(.secondary)
                        } else if model.localEmbedAssetsReady {
                            Label("Yerel model hazır", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(.green)
                        } else {
                            Button("Yerel model varlıklarını indir") { model.downloadLocalEmbedAssets() }
                                .controlSize(.small)
                            Text("(indirilmemiş)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if embedProvider != "local" {
                    Text("Sağlayıcı/boyut değişince mailleri yeniden gömün (Gömme düğmesi).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: embedProvider) { _, _ in model.refreshProviders() }
            .tabItem { Label("Embedding", systemImage: "wand.and.stars") }
            .padding()

            Form {
                SecureField("OpenRouter API anahtarı", text: $llmKey)
                    // Bkz. embedKey: async yüklemedeki ilk doldurmayı yeniden yazma.
                    .onChange(of: llmKey) { _, value in
                        guard keysLoaded else { return }
                        Keychain.set(value, for: KeychainKeys.llmKey)
                    }
                if !keysLoaded { keyLoadingIndicator }
                TextField("Model", text: $llmModel)
                Text("Örn. anthropic/claude-sonnet-4.6, openai/gpt-4o-mini. "
                   + "Anahtar Keychain'de saklanır.")
                    .font(.caption).foregroundStyle(.secondary)

                ConnectionTestSection()

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
        .task {
            // Anahtarları ANA THREAD DIŞINDA yükle: yeniden imzalama sonrası Keychain onay
            // diyaloğu beklerken senkron okuma pencereyi/paneli kilitlerdi. Gelene dek alanlar
            // boş kalır; keysLoaded sonradan true olur ve onChange kaydetmeye başlar.
            embedKey = await Keychain.readAsync(KeychainKeys.embedKey)
            llmKey = await Keychain.readAsync(KeychainKeys.llmKey)
            keysLoaded = true
            // Bildirim açıksa mevcut izin durumunu kontrol et: reddedilmişse toggle altında uyar.
            if notifyNewMail {
                notificationDenied = await MailNotifier.authorizationStatus() == .denied
            }
        }
    }

    /// Anahtarlar arka planda yüklenirken gösterilen küçük ilerleme satırı.
    private var keyLoadingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Anahtar yükleniyor…").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// "Bağlantıyı test et" bölümü: yapılandırılmış LLM/embedding sağlayıcısına canlı istek atıp
/// gerçek sonucu (✓ çalışıyor / ✗ geçersiz anahtar · model yok · ağ hatası) satır satır gösterir.
private struct ConnectionTestSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.testConnection()
        } label: {
            if model.isTestingConnection {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Test ediliyor…")
                }
            } else {
                Label("Bağlantıyı test et", systemImage: "bolt.horizontal.circle")
            }
        }
        .disabled(model.isTestingConnection)

        if !model.connectionResults.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.connectionResults, id: \.service) { result in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: result.status == .ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.status == .ok ? Color.green : Color.red)
                        Text(result.detail)
                            .font(.caption).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.top, 2)
        }

        Text("Yapılandırılmış sağlayıcılara minik birer canlı istek atar; gerçek sonucu gösterir.")
            .font(.caption).foregroundStyle(.secondary)
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
