<p align="center">
  <img src="branding/trova-wordmark.png" alt="Trova" width="420">
</p>

<p align="center"><strong>Postanın gömüsü. Mac'inde kalır.</strong></p>

# Trova

Apple Mail'in yerel deposunu indeksleyen, **doğal dille sorgulanabilen** ve bir yapay
zekâ ajanıyla mailleri bulup özetleyen **yerel-öncelikli native macOS** uygulaması.

Apple Mail'e bağladığınız tüm hesaplar (iCloud, Gmail, Exchange, IMAP…) zaten
`~/Library/Mail/V*/*.emlx` altında yerele senkronlandığı için **hiçbir hesaba yeniden
bağlanmaya gerek yoktur** — tek gereksinim Full Disk Access iznidir.

**Gizlilik:** Her şey varsayılan olarak yerelde çalışır. Embedding'ler yerelde
üretilebilir; yalnızca bir bulut sağlayıcı yapılandırırsanız özet/sıralama için kısa
parçalar API'ye gider. Mail HTML'i gösterilmeden önce temizlenir — uzak görseller
(izleme pikselleri), script ve olay işleyicileri kaldırılır. **Yanıtla / Yeni e-posta**
yalnızca oluşturma penceresini açar (otomatik **göndermez**); yıldızlama Trova-yereldir
(Apple Mail'e yazmaz).

Üç parça, tek SQLite indeksi:

- **`TrovaCore`** — çekirdek motor (SwiftPM kütüphanesi): ayrıştırma, indeksleme, arama, ajan.
- **`trova`** — hızlı iterasyon ve betikleme için CLI.
- **Trova.app** — 6 bölümlü native uygulama.

## Uygulama (Trova.app)

3 panelli arayüz (kenar çubuğu · liste · okuma). Kenar çubuğundan altı bölüm —
**Sor · Ara · Bugün · Kişiler · Genel Bakış · Ekler** (⌘1–6):

- **Sor (AI ajanı)** — OpenRouter araç-çağırma ile çok adımlı, **sohbetli** ajan: arar,
  ilgili maili okur, bulduğuna göre yeniden arar, sonra kaynaklı yanıtlar. Yanıt **token
  token akar (streaming)**, adımları canlı izlenir. Oturumlar arası **kalıcı hafıza**,
  **self-critique** (yanıttaki iddiaları kaynak maillerle doğrulama, ayar açıksa), takip
  sorularını anlayan sohbet geçmişi. Tüm sohbet Markdown'a dışa aktarılabilir.
- **Ara** — kelime / anlamsal / hibrit. Güçlü sorgu dili:
  - Türkçe **doğal dil tarih** filtresi: `son 7 gün fatura`, `dün toplantı`, `geçen ay maaş`;
    ayrıca tek tıkla **hızlı tarih çipleri** (bugün · 7g · 30g · bu yıl).
  - **Alan operatörleri** (Türkçe birincil, İngilizce eş anlamlı): `kimden:`/`from:` (gönderen),
    `kutu:`/`mailbox:` (posta kutusu), `ek:`/`attachment:` (ek türü). Değer tırnaklı olabilir ve
    operatör adı büyük/küçük harf duyarsızdır — örn. `kimden:"Ali Veli" kutu:INBOX ek:pdf fatura`.
    Ayrıca `has:attachment` / `has:ek` (herhangi ek) ve tür belirteçleri `has:pdf` · `ek:görsel` ·
    `tür:tablo` (PDF · Görsel · Tablo · Belge · Sunum · Arşiv · Ses · Video · Kod).
    Gelişmiş sözdizimi: `"tam ifade"` ve `-dışlanan` terim.
  - **Snippet + terim vurgusu**, opsiyonel **PRF sorgu genişletme**, thread çeşitlendirme,
    opsiyonel **AI yeniden sıralama (reranking)**.
  - **Süzme + düzen**: okunmadı · bayraklı · yıldızlı filtreleri, gönderen **facet'iyle daraltma**,
    **sıralama** (alaka / yeni / eski) + sonuç sayacı, tek tıkla **filtreleri temizle** ve isteğe
    bağlı **konuşmalara göre gruplama** (thread'leri katlanabilir tek başlıkta topla). **Yeni**
    sıralamasında sonuçlar **tarih başlıkları** (Bugün · Dün · Bu Hafta · Bu Ay · Daha Eski) altında toplanır.
  - **Çoklu seçim + toplu aksiyon**: seçili mailleri toplu **yıldızla** ya da Markdown/CSV **dışa aktar**.
  - **Akıllı Klasörler** (kenar çubuğu): kalıcı **Okunmamışlar** ve **Yıldızlılar** sanal klasörleri
    ile **kayıtlı aramalar** — hepsi **canlı sayaçlı**; kayıtlı aramada sağ tık **Çalıştır / Sil**.
    Ayrıca **son aramalar**.
- **Bugün** — proaktif brifing: LLM günlük özet + **yanıt gerekiyor** / **yanıt bekliyor**
  triyajı (yerel Gönderilenler avantajıyla). Her öğede hızlı aksiyon (Yanıtla · Mail'de Aç · Yıldızla),
  bir öğeyi **gizle/geri al** (yeni yanıt gelince tekrar belirir) ve digest'i Markdown'a dışa aktarma.
- **Kişiler** — en çok yazışılanlar (ad/adres ile **aranabilir**); bir kişiyi açınca tüm mailleri
  + **mini analitik** (toplam · ekli · ilk–son iletişim). Listeyi Markdown'a aktarın.
- **Genel Bakış** — istatistik kartları + son 12 ayın **aylık hacim** ve **gelen/gönderilen**
  grafikleri, **haftanın günü** dağılımı ve en çok yazışılanlar (Swift Charts).
- **Ekler** — ekleri ada ve **türe** göre arayıp tek tıkla aç, satırda **Hızlı Bak** (hover'da beliren
  göz ya da sağ tık) ile önizle veya doğrudan Finder'a **sürükle-bırak**; opt-in **ek içeriği araması**
  (PDF metni + düz metin) ile ek içinde geçen kelimeleri de bulur.

Okuma panelinde güvenli HTML render ve **konuşma zaman çizelgesi** — thread mailleri Message-ID ile
tekilleştirilip kronolojik dikey bir akışta gösterilir; tek tıkla **"Konuyu özetle"** veya konuşmanın
tamamını **Markdown/CSV dışa aktar**. Ayrıca **eki açma** (ek çiplerinde sağ tık **Hızlı Bak** ya da
Finder'a **sürükle-bırak**), **"Mail'de Aç"** (native Mail.app
`message://` derin-linki), **Yanıtla / Yeni e-posta** (`mailto:`), **AI yanıt taslağı** (oku → taslak →
Mail'de yanıtla), **Trova-yerel yıldızlama**, **Benzer mailler** (embedding tabanlı more-like-this) ve
maili **Markdown kopyala/dışa aktar**. AI çıktıları blok-markdown olarak render edilir (başlık · liste · kod).

Hız ve canlılık: **⌘K komut paleti** (bulanık arama), **⌘1–6** bölümler, ↑/↓ ile liste gezinme,
**⌘/** kısayol kılavuzu. **FSEvents** ile `~/Library/Mail` izlenir; yeni mail geldiğinde **artımlı
indeksleme otomatik** tetiklenir ve kenar çubuğunda **"N yeni mail"** rozeti belirir. İlk çalıştırmadaki
**Sağlık paneli** Full Disk Access / indeks / anahtar / embedding durumunu adım adım yönlendirir.

**Ayarlar → Genel** (hepsi açılıp kapatılabilir): **menü çubuğu eki** — yeni mail geldiğinde ikonu
dolan bir `MenuBarExtra` penceresi (yeni mail sayısı, **hızlı arama**, Bugün brifingi ve İndeksle tek
tıkla); yeni mail geldiğinde **macOS bildirimi + Dock rozeti** (opt-in); ve **otomatik günlük brifing**
(opt-in) — seçtiğiniz saatte Bugün brifingini oluşturur ve "Günlük brifing hazır" bildirimi gönderir
(uygulama açıkken).

```sh
brew install xcodegen          # bir kez
cd app && xcodegen generate    # project.yml → Trova.xcodeproj
open Trova.xcodeproj           # Xcode'da ⌘R (otomatik imza)
```

> İlk çalıştırmada **Trova.app**'e Full Disk Access verin (Sağlık paneli "Sistem Ayarları'nı
> Aç" ile yönlendirir). Sandbox **kapalıdır** (gereklilik — aşağıya bakın), bu nedenle uygulama
> App Store'da yer almaz; doğrudan dağıtım hedeflenir. `.xcodeproj` üretilen dosyadır; sürüm
> kontrolüne `project.yml` girer.

## Çekirdek (TrovaCore)

- **`.emlx` ayrıştırıcı**: MIME çok parçalılık, `base64` / `quoted-printable`, IANA charset
  çözümü (Türkçe `iso-8859-9` / `windows-1254` dahil), RFC 2047 encoded-word başlıkları,
  HTML→metin ve ek (attachment) çıkarımı.
- **SQLite + FTS5** tam metin indeksi (GRDB; şema **v14**'e kadar otomatik göç ettirilir). Türkçe için
  ön ek (prefix) eşleme: "fatura" → "faturanız", "faturası" da bulunur. Ek dosya adları da indekslenir.
- **Anlamsal arama**: `EmbeddingProvider` protokolü (pluggable). Vektörler BLOB olarak
  saklanır; `vDSP` ile kosinüs benzerliği. `Searcher`, FTS ile vektörü **RRF** (Reciprocal
  Rank Fusion) ile birleştirir.
- **Artımlı indeksleme** (mtime + `parserVersion`), **thread gruplama**, **OCR'lı ek okuma**
  (Vision tr/en + PDFKit, tamamen yerel).
- **Message-ID tekilleştirme**: Gmail/IMAP aynı maili birden çok kutuya kopyaladığında bile
  her mail tek kanonik satır olur (aşağıdaki Bakım bölümüne bakın).

### Embedding sağlayıcıları

1. **Yerel `NLContextualEmbedding`** (offline, ücretsiz) — varsayılan. Bir token kodlayıcısıdır;
   mean-pool sıralama kalitesi **ölçülen şekliyle zayıftır**. `semantic` tek başına güvenilmez;
   `hybrid`'de FTS taşır, reranking/PRF telafi eder.
2. **Bulut API (OpenRouter / OpenAI / Voyage)** — yüksek kaliteli çok dilli modeller, **önerilen**.
   OpenRouter OpenAI-uyumlu `/embeddings` sunduğundan tek `OPENROUTER_API_KEY` hem gömme hem
   `ask`/`agent` (LLM) için kullanılabilir. (Uygulamada Ayarlar'dan, CLI'da ortam değişkenleriyle.)

## CLI (`trova`)

```sh
swift build -c release

trova doctor                               # erişim + depo durumunu kontrol et (varsayılan komut)
trova index                                # tüm kutuları indeksle (--limit N ile sınırla)
trova embed                                # anlamsal gömme üret (yerel veya API; --reset, --batch N)
trova search "kira sözleşmesi"             # hibrit arama (FTS + anlamsal, varsayılan)
trova search "ev taşınma" --mode semantic  # sadece anlamsal
trova search "fatura" --mode fts           # sadece anahtar kelime
trova count "son 7 gün fatura"             # sorguya uyan mail SAYISI (operatör + tarih ayrıştırılır)
trova ask "geçen ay kira ile ilgili mailleri özetle"   # tek-tur özet (OpenRouter)
trova agent "kira sözleşmem ne zaman doluyor"          # çok adımlı ajan (OpenRouter)
trova accounts                             # hesap bazında kayıt sayısı
trova attachments fatura --kind pdf        # ekleri ada/türe/göndericiye göre listele
trova pinned                               # Trova-yerel yıldızlı mailleri listele
```

Ortak `--db <yol>` seçeneği ile farklı bir veritabanı kullanılabilir. `ask` ve `agent`
OpenRouter anahtarı ister; diğer komutlar yerel çalışır.

## Yapılandırma (ortam değişkenleri)

CLI ayarları ortam değişkenleriyle verilir; **uygulamada anahtarlar Keychain'de saklanır**
ve modeller Ayarlar'dan seçilir. Değişkenler tarihsel nedenle `EIDX_*` önekini korur.

| Değişken | Ne işe yarar |
|---|---|
| `EIDX_EMBED_PROVIDER` | `openai` · `voyage` · `openrouter` · `custom` (ayarlı değilse yerel model) |
| `OPENROUTER_API_KEY` | OpenRouter anahtarı — embedding **ve** LLM için tek anahtar (önerilen) |
| `OPENAI_API_KEY` / `VOYAGE_API_KEY` | İlgili sağlayıcının embedding anahtarı |
| `EIDX_EMBED_API_KEY` | Genel embedding anahtarı (özellikle `custom` için) |
| `EIDX_EMBED_MODEL` | Embedding modeli (varsayılanlar: OpenAI `text-embedding-3-small`, Voyage `voyage-3.5`) |
| `EIDX_EMBED_DIM` | Embedding boyutu (opsiyonel) |
| `EIDX_EMBED_BASE_URL` | OpenAI-uyumlu özel uç nokta (`custom` sağlayıcı için zorunlu) |
| `EIDX_LLM_API_KEY` | LLM anahtarı (yoksa `OPENROUTER_API_KEY` kullanılır) |
| `EIDX_LLM_MODEL` | LLM modeli; varsayılan `anthropic/claude-sonnet-4.6` (araç-çağırma destekli olmalı) |
| `EIDX_LLM_BASE_URL` | LLM uç noktası; varsayılan `https://openrouter.ai/api/v1` |

```sh
# OpenRouter — embedding + LLM için TEK anahtar (önerilen)
export EIDX_EMBED_PROVIDER=openrouter
export OPENROUTER_API_KEY=sk-or-...
export EIDX_LLM_MODEL=anthropic/claude-sonnet-4.6

# veya OpenAI / Voyage (Türkçe için güçlü)
export EIDX_EMBED_PROVIDER=openai   # OPENAI_API_KEY [+ EIDX_EMBED_MODEL / EIDX_EMBED_DIM]
export EIDX_EMBED_PROVIDER=voyage   # VOYAGE_API_KEY
```

> Veritabanı `~/Library/Application Support/Trova/index.sqlite` altında tutulur. CLI ve
> uygulama **aynı indeksi** paylaşır (eski `EmailIndexer/` klasörü ilk çalıştırmada otomatik taşınır).

## Bakım / İpuçları

Gmail ve bazı IMAP hesapları aynı maili birden çok kutuya (Tüm Postalar, etiketler…) yazar;
bu da `.emlx` kopyalarına ve şişen sayımlara yol açar. Trova mailleri **Message-ID** ile
tekilleştirir; yine de geçmiş indekslerden artık kalmışsa:

> **Ayarlar → Bakım → "Yinelenen mailleri temizle"** her mail için tek kanonik satır bırakıp
> kopyaları (ve yetim ek/gömme kayıtlarını) siler. Kaynak `.emlx` dosyalarına dokunmaz.

Aynı sekmede ajan hafızasını ve opt-in ek içeriği indeksini de yönetebilirsiniz.

## Mimari kısıtlar ve sınırlamalar

- **App sandbox kapalı olmalı.** Sandbox'lı (App Store) bir uygulama TCC korumalı
  `~/Library/Mail/`'i okuyamaz. Bu yüzden Trova **non-sandboxed**'dır, **App Store'da yer almaz**
  ve **Full Disk Access** ister; doğrudan dağıtım hedeflenir.
- **Yerel embedding kalitesi sınırlıdır.** Anlamsal arama için ciddi sonuç isteyenlerin bir
  bulut sağlayıcı yapılandırması önerilir.
- **Gizlilik dengesi:** Yerel çalışırken hiçbir veri dışarı çıkmaz; bir bulut LLM/embedding
  yapılandırırsanız ilgili mail parçaları o sağlayıcıya gönderilir.
- **Olgunluk:** Sürüm `0.1.0`, kişisel/hobi bir proje; arayüz ve şema değişebilir.

## Geliştirme

```sh
swift build        # çekirdek + CLI
swift test         # 614 birim testi (ayrıştırma, arama, ajan araçları, dışa aktarma, parser'lar…)
```

Gereksinimler: **macOS 14+ (Sonoma)**, **Swift 6** araç zinciri (Package.swift / project.yml),
ve uygulamayı derlemek için **Xcode** + **XcodeGen**.

## Lisans

Henüz bir lisans eklenmemiştir. (Depoda `LICENSE` dosyası bulunana kadar tüm hakları saklıdır.)
