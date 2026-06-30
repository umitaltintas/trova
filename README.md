<p align="center">
  <img src="branding/trova-wordmark.png" alt="Trova" width="420">
</p>

<p align="center"><strong>Postanın gömüsü. Mac'inde kalır.</strong></p>

# Trova

Apple Mail'in yerel deposunu tarayıp indeksleyen, doğal dille sorgulanabilen ve
bir AI ajanıyla mailleri bulup özetleyen **native macOS** uygulaması. Apple Mail'e
bağladığınız tüm hesaplar (iCloud, Gmail, Exchange, IMAP…) zaten `~/Library/Mail/`
altında yerel olarak senkronlandığı için **hiçbir hesaba yeniden bağlanmaya gerek
yoktur** — tek gereksinim Full Disk Access iznidir. Embedding'ler yerelde üretilebilir;
yalnızca tercih ederseniz özet/sıralama için kısa parçalar buluta gider.

İki parça: çekirdek motor **`TrovaCore`** (SwiftPM kütüphanesi) + native uygulama
**Trova** ve hızlı iterasyon için **`trova`** CLI. Hepsi aynı SQLite veritabanını paylaşır.

## Uygulama (Trova.app)

3 panelli **"Indigo Console"** arayüzü (kenar çubuğu · liste · okuma). Kenar çubuğundan
beş bölüm: **Sor · Ara · Bugün · Kişiler · Genel Bakış**.

- **Sor (AI ajanı)** — OpenRouter araç-çağırma ile çok adımlı, **sohbetli** ajan: arar,
  ilgili maili okur, bulduğuna göre yeniden arar, sonra kaynaklı yanıtlar. Adımları canlı
  izlenir. Oturumlar arası **hafıza**, **self-critique** (yanıt doğrulama), geçmiş sohbetler.
  Tüm sohbet Markdown'a dışa aktarılabilir.
- **Ara** — kelime / anlamsal / hibrit. Güçlü sorgu dili:
  - Türkçe **doğal dil tarih** filtresi: `son 7 gün fatura`, `dün toplantı`, `geçen ay maaş`.
  - **Operatörler**: `from:ali`, `gönderen:veli`, `has:attachment` / `has:ek`.
  - **Kayıtlı aramalar** (yer imi), opsiyonel **PRF sorgu genişletme**, thread çeşitlendirme,
    opsiyonel **AI yeniden sıralama (reranking)**.
- **Bugün** — proaktif brifing: LLM günlük özet + **yanıt gerekiyor** / **yanıt bekliyor**
  triyajı (yerel Gönderilenler avantajıyla).
- **Kişiler** — en çok yazışılanlar; bir kişiyi açınca tüm mailleri + **mini analitik**
  (toplam · ekli · ilk–son iletişim).
- **Genel Bakış** — istatistik kartları + son 12 ayın **aylık hacim grafiği** (Swift Charts).

Okuma panelinde: güvenli HTML render (izleme pikseli/script temizlenir), konu (thread) şeridi
ve tek tıkla **"Konuyu özetle"**, **eki açma**, **"Mail'de Aç"** (native Mail.app `message://`
derin-linki), maili/yanıtı **Markdown kopyala/dışa aktar**.

Hız: **⌘K komut paleti** (bulanık arama), **⌘1–5** bölümler. **Sağlık paneli** ilk
çalıştırmada Full Disk Access / indeks / anahtar / embedding durumunu adım adım yönlendirir.

```sh
brew install xcodegen          # bir kez
cd app && xcodegen generate    # project.yml → Trova.xcodeproj
open Trova.xcodeproj           # Xcode'da ⌘R (otomatik imza)
```

> İlk çalıştırmada **Trova.app**'e Full Disk Access verin (uygulamanın Sağlık paneli
> "Sistem Ayarları'nı Aç" ile yönlendirir). Sandbox kapalıdır (gereklilik). `.xcodeproj`
> üretilen dosyadır; sürüm kontrolüne `project.yml` girer.

## Çekirdek

- **`.emlx` ayrıştırıcı**: MIME çok parçalılık, `base64`/`quoted-printable`, IANA charset
  çözümü (Türkçe `iso-8859-9`/`windows-1254` dahil), RFC 2047 encoded-word başlıkları,
  HTML→metin, ek (attachment) çıkarımı.
- **SQLite + FTS5** tam metin indeksi. Türkçe için ön ek (prefix) eşleme: "fatura" →
  "faturanız", "faturası" da bulunur. Ek dosya adları da indekslenir.
- **Anlamsal arama**: `EmbeddingProvider` protokolü (pluggable). Vektörler BLOB olarak
  saklanır; `vDSP` ile kaba kuvvet kosinüs. `Searcher` FTS + vektörü **RRF** ile birleştirir.
- **Artımlı indeksleme** (mtime + `parserVersion`), **thread gruplama**, **OCR'lı ek okuma**
  (Vision tr/en + PDFKit, tamamen yerel).

### Embedding sağlayıcıları
1. **Yerel `NLContextualEmbedding`** (offline, ücretsiz). Bir token kodlayıcısıdır; mean-pool
   sıralama kalitesi **zayıftır** (ölçüldü). `semantic` tek başına güvenilmez; `hybrid`'de FTS
   taşır, reranking/PRF telafi eder.
2. **Bulut API (OpenRouter/OpenAI/Voyage)** — yüksek kaliteli çok dilli modeller (uygulamada
   Ayarlar'dan, CLI'da ortam değişkenleriyle). OpenRouter OpenAI-uyumlu `/embeddings` sunduğundan
   tek `OPENROUTER_API_KEY` hem gömme hem `ask` (LLM) için kullanılabilir.

## CLI (`trova`)

```sh
swift build -c release

trova doctor                              # erişim ve depo durumunu kontrol et
trova index                               # tüm kutuları indeksle (--limit N ile sınırlanır)
trova embed                               # anlamsal gömme üret (yerel veya API; --reset ile sıfırla)
trova search "kira sözleşmesi"            # hibrit arama (FTS + anlamsal, varsayılan)
trova search "ev taşınma" --mode semantic # sadece anlamsal
trova search "fatura" --mode fts          # sadece anahtar kelime
trova ask "geçen ay kira ile ilgili mailleri özetle"   # tek-tur
trova agent "kira sözleşmem ne zaman doluyor"          # çok adımlı ajan
trova accounts                            # hesap bazında kayıt sayısı
```

Ortam değişkenleri (CLI; uygulama Keychain + Ayarlar kullanır):

```sh
# OpenRouter — embedding + LLM için TEK anahtar (önerilen)
export EIDX_EMBED_PROVIDER=openrouter
export OPENROUTER_API_KEY=sk-or-...
export EIDX_LLM_MODEL=anthropic/claude-sonnet-4.6   # araç-çağırma destekli model olmalı

# veya OpenAI / Voyage
export EIDX_EMBED_PROVIDER=openai   # OPENAI_API_KEY, opsiyonel EIDX_EMBED_MODEL / EIDX_EMBED_DIM
export EIDX_EMBED_PROVIDER=voyage   # VOYAGE_API_KEY (Türkçe için güçlü)
```

> Env değişkenleri tarihsel nedenle `EIDX_*` önekini korur; CLI komutu `trova`'dır.
> Veritabanı `~/Library/Application Support/Trova/index.sqlite` altında tutulur
> (eski `EmailIndexer/` klasörü ilk çalıştırmada otomatik taşınır).

## Mimari kısıtlar

- **App sandbox kapalı olmalı.** Sandbox'lı (App Store) bir uygulama TCC korumalı
  `~/Library/Mail/`'i okuyamaz; doğrudan dağıtım hedeflenir.
- **Gizlilik:** Embedding'ler yerelde üretilebilir; yalnızca tercih edilirse özet/sıralama
  için kısa parçalar buluta gider. HTML render uzak görselleri/izleme piksellerini temizler.

## Geliştirme

```sh
swift test    # çekirdek birim testleri (ayrıştırma, arama, ajan araçları, parser'lar…)
```
