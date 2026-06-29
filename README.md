<p align="center">
  <img src="branding/trova-wordmark.png" alt="Trova" width="420">
</p>

<p align="center"><strong>Postanın gömüsü. Mac'inde kalır.</strong></p>

# Trova

Apple Mail'in yerel deposunu tarayıp indeksleyen ve doğal dille sorgulanabilen
bir e-posta arama/özetleme aracı. Apple Mail'e bağladığınız tüm hesaplar
(iCloud, Gmail, Exchange, IMAP…) zaten `~/Library/Mail/` altında yerel olarak
senkronlandığı için **hiçbir hesaba yeniden bağlanmaya gerek yoktur** — tek
gereksinim Full Disk Access iznidir.

## Durum: Faz 0 (CLI + tam metin arama) ✅

- `~/Library/Mail/V<n>/` deposunu bulup tüm `.emlx` dosyalarını gezer.
- `.emlx` ayrıştırıcı: MIME çok parçalılık, `base64`/`quoted-printable`,
  IANA charset çözümü (Türkçe `iso-8859-9`/`windows-1254` dahil), RFC 2047
  encoded-word başlıkları, HTML→metin.
- SQLite + **FTS5** tam metin indeksi. Türkçe için ön ek (prefix) eşleme:
  "fatura" → "faturanız", "faturası" da bulunur.

## Faz 1: anlamsal arama (NLContextualEmbedding + hibrit) ⚠️

- `EmbeddingProvider` protokolü (pluggable) + yerel `NLContextualEmbedding`
  sağlayıcısı (512-d, offline, Türkçe). Vektörler SQLite'ta BLOB olarak saklanır.
- `vectorSearch`: Accelerate (`vDSP`) ile kaba kuvvet kosinüs.
- `Searcher`: FTS + vektör sonuçlarını **RRF** (Reciprocal Rank Fusion) ile birleştirir.
- CLI: `eidx embed`, `eidx search --mode fts|semantic|hybrid`.

### Embedding sağlayıcıları
İki sağlayıcı vardır; `EmbeddingProvider` protokolü ardında değişebilirler:

1. **Yerel `NLContextualEmbedding`** (varsayılan, offline, ücretsiz). Ama bu bir
   **token kodlayıcısıdır**, cümle getirme için eğitilmemiştir: mean-pool ham
   kosinüsleri birbirine çok yakın çıkar (~0.81–0.88) ve sıralama kalitesi zayıftır
   (ölçülerek doğrulandı). `semantic` mod tek başına güvenilmez; `hybrid`'de FTS taşır.
2. **Bulut API (OpenRouter/OpenAI/Voyage)** — yüksek kaliteli, eğitimli çok dilli
   modeller. Ortam değişkenleriyle açılır (mail içeriği API'ye gider):

```sh
# OpenRouter — embedding + LLM için TEK anahtar (önerilen)
export EIDX_EMBED_PROVIDER=openrouter
export OPENROUTER_API_KEY=sk-or-...
# export EIDX_EMBED_MODEL=openai/text-embedding-3-small   # veya qwen/qwen3-embedding-0.6b

# veya OpenAI
export EIDX_EMBED_PROVIDER=openai
export OPENAI_API_KEY=sk-...
# export EIDX_EMBED_MODEL=text-embedding-3-large   # opsiyonel
# export EIDX_EMBED_DIM=1024                        # opsiyonel (boyut küçültme)

# veya Voyage (Türkçe için güçlü)
export EIDX_EMBED_PROVIDER=voyage
export VOYAGE_API_KEY=...

eidx embed --reset    # sağlayıcı/boyut değişince mutlaka --reset ile yeniden üret
```

OpenRouter OpenAI-uyumlu `/embeddings` sunduğundan aynı `OPENROUTER_API_KEY` hem
gömme hem `ask` (LLM) için kullanılabilir.

API yapılandırılmışsa `embed` ve `search` otomatik onu kullanır; yoksa yerel modele düşer.
`custom` sağlayıcısıyla (OpenAI-uyumlu) herhangi bir uç nokta de verilebilir
(`EIDX_EMBED_BASE_URL`).

## Faz 2: AI agent (OpenRouter) ✅

`eidx ask "<soru>"`: hibrit ile geniş aday kümesi getirir → adayları LLM'e verir →
LLM alakaya göre sıralar, alakasızları eler ve Türkçe özet yazar. Getirme yalnızca
iyi *recall* sağlar (FTS); nihai *alaka sıralaması* LLM'dedir — bu, zayıf embedding'i
telafi eder.

```sh
export OPENROUTER_API_KEY=sk-or-...
export EIDX_LLM_MODEL=anthropic/claude-sonnet-4.6   # opsiyonel; araç-çağırma destekli model olmalı

eidx ask "geçen ay gelen kira ve ev ile ilgili mailleri özetle"   # tek-tur
eidx agent "kira sözleşmem ne zaman doluyor, son yazışmaya göre"   # çok adımlı ajan
```

### Çok adımlı ajan (function-calling)
`agent` / app'teki **Sor**, OpenRouter'ın araç-çağırma API'siyle yerel bir **ajan döngüsü**
çalıştırır (LangChain gibi bir Python runtime'a gerek yok). Sohbet (takip soruları) destekler;
adımları app'te canlı izlenir. Araç-çağırma destekli bir model gerekir (örn.
`anthropic/claude-sonnet-4.6`). Çok tur → tek-turdan daha maliyetli.

**Ajan araçları:**
- `search_mail` — hibrit/anlamsal/kelime arama (tarih filtresi).
- `read_mail` — bir mailin tam gövdesi.
- `find_by_sender` — bir göndericiden gelen mailler + toplam sayı.
- `list_thread` / `summarize_thread` — konunun mailleri (özet listesi / tam gövdeler).
- `read_attachment` — PDF/görsel/metin ekten içerik çıkarır (**Vision OCR tr/en**, PDFKit),
  tamamen yerel. "Mart faturasındaki tutar neydi?" gibi sorular için.

## Faz 3: Native macOS app (Trova) 🚧 iskelet

`app/` altında SwiftUI uygulaması. Çekirdek motoru (`TrovaCore`) aynen
kullanır ve CLI ile **aynı veritabanını** paylaşır. Özellikler: Full Disk Access
kapısı, İndeksle/Gömme düğmeleri, "Ara" (fts/anlamsal/hibrit) ve "Sor (AI)"
sekmeleri, sonuç listesi + detay paneli, Ayarlar'da sağlayıcı/anahtar yapılandırması.

```sh
brew install xcodegen          # bir kez
cd app && xcodegen generate    # project.yml → Trova.xcodeproj
open Trova.xcodeproj         # Xcode'da ⌘R ile çalıştır (otomatik imza)
```

> İlk çalıştırmada **Trova.app**'e Full Disk Access verin (uygulama içinden
> "Sistem Ayarları'nı Aç" düğmesi yönlendirir). Sandbox kapalıdır (gereklilik).
> `.xcodeproj` üretilen dosyadır, sürüm kontrolüne `project.yml` girer.

**Arayüz — "Indigo Console":** 3 panelli (kenar çubuğu · sonuçlar · okuma), indigo aksan,
başlıklar SF Pro Rounded, sayılar SF Mono. İmza öğesi: AI sonuçlarında alaka skorunu gösteren
**sinyal çubukları**. Gönderen avatarları, ek/konu çipleri. Tasarım sistemi `DesignSystem.swift`.

App şunları destekler:
- **Artımlı indeksleme** — değişmeyen `.emlx`'ler mtime ile atlanır.
- **Canlı ilerleme + İptal** — uzun index/embed işlemlerinde.
- **Keychain** — API anahtarları güvenli saklanır (UserDefaults değil).
- **Otomatik senkron (FSEvents)** — "Otomatik" anahtarıyla yeni mailler gelince
  artımlı indeksleme tetiklenir.
- **Güvenli HTML render** — detayda biçimli görünüm; izleme pikselleri ve
  script'ler temizlenir (gizlilik).
- **Embedding chunk'lama** — uzun mailler parçalanıp vektörleri ortalanır.
- **Konuşma (thread) gruplama** — konu normalleştirilir (Re:/Fwd:/Yan:/İlt: atılır);
  detayda "Bu konudaki N mail" listesi, tıklanınca o maile geçer.
- **Ek (attachment) araması** — ek dosya adları FTS'e indekslenir (dosya adıyla mail
  bulunur), listede ataç ikonu, detayda ek rozetleri.
- **Tarih/hesap filtreleri** — arama çubuğunun altında hesap ve tarih aralığı
  (Tüm zamanlar / 7 gün / 30 gün / 1 yıl); FTS + anlamsal + hibritte çalışır.

> Bu sürümde parser çıktısı değiştiği için (`parserVersion`), **İndeksle**'ye bir kez
> basınca mevcut tüm mailler thread/ek alanlarını dolduracak şekilde bir kez yeniden
> taranır (ilerleme çubuğuyla); sonrası yine artımlıdır.

### Kalan (fikirler)
- Developer ID ile imzalama (başka makineye dağıtım); ekleri açma/önizleme;
  References grafiğiyle daha kesin threadleme; hesap görünen adlarını gösterme.

## Kurulum

```sh
swift build -c release
```

> **Full Disk Access gerekli.** Sistem Ayarları → Gizlilik ve Güvenlik →
> Full Disk Access → kullandığınız terminal uygulamasını (Terminal/iTerm) ekleyip
> açın. Native app aşamasında bu izin uygulamanın kendisine verilecektir.

## Kullanım

```sh
eidx doctor                              # erişim ve depo durumunu kontrol et
eidx index                               # tüm kutuları indeksle (--limit N ile sınırlanır)
eidx embed                               # anlamsal gömme üret (yerel veya API)
eidx search "kira sözleşmesi"            # hibrit arama (FTS + anlamsal, varsayılan)
eidx search "ev taşınma" --mode semantic # sadece anlamsal
eidx search "fatura" --mode fts          # sadece anahtar kelime
eidx accounts                            # hesap bazında kayıt sayısı
```

Veritabanı varsayılan olarak
`~/Library/Application Support/EmailIndexer/index.sqlite` altında tutulur
(`--db <yol>` ile değiştirilebilir).

## Mimari kısıtlar

- **App sandbox kapalı olmalı.** Sandbox'lı (App Store) bir uygulama TCC korumalı
  `~/Library/Mail/`'i okuyamaz. Bu yüzden doğrudan dağıtım hedeflenir.
- **Gizlilik:** Mailler hassastır. Embedding'ler yerelde (offline) üretilir;
  yalnızca nihai özet/sıralama için kısa parçalar OpenRouter'a gider.

## Geliştirme

```sh
swift test    # birim testleri (.emlx ayrıştırma + FTS arama)
```
