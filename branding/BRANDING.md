# Trova — Marka Kılavuzu

> **Trova** · Apple Mail arşivini doğal dille arayan, tamamen yerel macOS asistanı.
> (Eski kod adı: *MailSeek* / CLI `eidx`.)

---

## İsim

**Trova** — "bul + hazine".
- Köken: Latince **trove** (*trésor trouvé*, "bulunmuş hazine") + Esperanto **trovi** ("bulmak").
  Arama eylemini ve aramanın *değerli sonucunu* tek kelimede birleştirir.
- Telaffuz: **TRO-va** (TR ve EN konuşanlar için aynı, doğal). 2 hece, yalnızca harf.
- Neden bu yön: gizlilik/yerel-öncelikli yazılım dünyası (Obsidian, Reor, Raycast)
  kısa, çağrışımsal, betimleyici-olmayan isimleri ödüllendiriyor. "Mail / Inbox / AI /
  Vault / Recall" gibi doygun ve hukuken zayıf kelimelerden bilinçle kaçınıldı.
- Çakışma: bu kategoride (macOS e-posta/arama) temiz. Açık-kaynak `mailseek` CLI'ı,
  oyun *Trove*'u ve Proton'un AI asistanı *Lumo*'su gibi çakışmaları aşar.

### Tagline (betimleme isimde değil, burada)
- TR: **"Postanın gömüsü. Mac'inde kalır."**
- TR (uzun): *"Apple Mail arşivini doğal dille ara — hiçbir şey cihazından çıkmaz."*
- EN: **"Find anything in your mail. Nothing leaves your Mac."**

---

## Logo

**Konsept: mesaj-takımyıldızı.** Düğümler = mesajlar, ince kenarlar = thread bağları.
Merkezdeki **amber→mercan düğüm aranan/bulunan mesajı** temsil eder ve hafif bir
ışıltıyla "aydınlanır". Dört kategori klişesinden (büyüteç · zarf · asma kilit · ✨ sparkle)
bilinçle kaçınılmıştır.

### Varyantlar (bu klasörde)
| Dosya | Kullanım |
|---|---|
| `trova-icon.svg` / `trova-icon-1024.png` | **Ana** app icon — indigo gece zemini (Dark/Default) |
| `trova-icon-light.svg` / `trova-icon-light-1024.png` | Krem zemin — açık temalı bağlamlar, baskı, web |
| `trova-wordmark.svg` / `trova-wordmark.png` | Yatay lockup (icon + "trova") |
| `trova.icns` | Finder/dağıtım ikonu (16→1024 tam set) |
| `../app/Trova/Assets.xcassets/AppIcon.appiconset/` | Uygulamaya gömülü macOS app icon (build'de aktif) |

---

## Renk paleti

| Rol | İsim | Hex |
|---|---|---|
| Zemin (gece) üst | Indigo Night | `#252158` |
| Zemin (gece) alt | Indigo Abyss | `#12102B` |
| Wordmark / metin | Indigo Ink | `#211D4A` |
| Sönük düğüm | Lavender Node | `#8C90E0` → `#7C80D6` |
| **Vurgu — çekirdek** | **Amber Core** | `#FFC24D` |
| **Vurgu — kenar** | **Coral Find** | `#F0563C` |
| Zemin (light) | Paper Cream | `#F7F4ED` → `#EAE4D5` |
| Koyu düğüm (light üstü) | Indigo Deep | `#2E2A57` |

> Tek vurgu rengi **amber→mercan** gradyanıdır; her şeyi sıcak tutar. İndigo, app'in
> mevcut **"Indigo Console"** temasıyla (DesignSystem.swift accent'i) köprü kurar.

---

## Tipografi
- **Wordmark & başlıklar:** SF Pro Rounded (app zaten kullanıyor) — alternatif: Inter.
  `trova` küçük harf yazılır (yaklaşılabilir/sıcak ton; -6 letter-spacing).
- **Sayılar / teknik:** SF Mono (app'in sayaç/skor tipiyle uyumlu).
- **Gövde:** SF Pro / Inter.

---

## Kullanım kuralları
- **Clear space:** icon yüksekliğinin en az ¼'ü kadar boşluk bırak.
- **Yapma:** glyph'i döndürme; amber çekirdeği başka renge boyama; zemini düz tek
  renge indirgeme (gradyan kalsın); icona dış gölge/bevel ekleme (sistem ekler).
- **Minimum boyut:** 128 px'e kadar net okunur (test edildi); altında wordmark'ı düşür,
  yalnız icon kullan.

---

## macOS 26 (Tahoe) "Liquid Glass" üretim notları
Bu SVG'ler Icon Composer'a aktarım için hazır temel; final teslimde:
1. **Icon Composer** (Xcode 26 ile gelir, ücretsiz) ile katmanla:
   **1 background** (indigo gradyan, full-bleed) + **1–2 foreground** (takımyıldız + amber çekirdek).
2. Foreground katmanlarının **arka planını şeffaf** bırak; **gölge/specular ekleme** —
   sistem uygular (bu yüzden SVG'deki yumuşak ışıltı yalnız standalone önizleme içindir).
3. **`.icon` olarak Save** edip Xcode'a ekle (PNG'yi `Assets.xcassets`'e atma — margin bozulur).
   App Store gönderimi ayrıca alfasız **1024×1024 PNG** ister.
4. **Default / Dark / Mono** (Clear + Tinted) modlarını test et. Mono için: amber çekirdek +
   takımyıldız tek-ton siluete indirgenebilir (kontrast korunur).
5. Canvas 1024×1024 squircle; köşeyi sen çizme, sistem maskesine güven.

---

## İsim geçişi (rename) — UYGULANDI (2026-06-29)
Kod tabanı tamamen Trova'ya taşındı, 60 test yeşil, app imzasız derlendi:
- ✅ Çekirdek kütüphane: `EmailIndexerCore → TrovaCore` (`Sources/`, `Tests/`, tüm `import`'lar).
- ✅ CLI: `eidx → trova` (komut adı, target/product, `Sources/eidx → Sources/trova`,
  `Eidx.swift → Trova.swift`, `struct Eidx → Trova`).
- ✅ App: `MailSeek → Trova` (`app/MailSeek → app/Trova`, `MailSeekApp.swift → TrovaApp.swift`,
  display name, `project.yml`); bundle **`com.trova.Trova`**; Swift paketi adı **`Trova`**.
- ✅ DB göçü: `TrovaCore/TrovaPaths.defaultDatabaseURL()` — eski
  `~/Library/Application Support/EmailIndexer/` klasörü ilk çalıştırmada otomatik `Trova/`'ya
  taşınır (mevcut **90 MB / 7338 mail korunur**; çalıştırılarak doğrulandı).
- ✅ App icon: `AppIcon.appiconset` (16→1024 macOS set) + `trova.icns`; `project.yml`'de
  `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon`.
- ⚠️ **`EIDX_*` ortam değişkenleri kasıtlı korundu** (`EIDX_LLM_MODEL`, `EIDX_EMBED_*` …) —
  kullanıcının `.zshrc`'sini kırmamak için API yüzeyi sabit. Sadece `eidx` komut adı değişti.
- ⚠️ Keychain servis adı `MailSeek → Trova` olduğundan, daha önce kaydedilmiş API anahtarları
  bir kez yeniden girilmelidir (eski anahtarlar silinmez, sadece yeni servis altında görünmez).
- ⏳ Kalan: `.icon` Liquid Glass katmanlı varyant (Icon Composer GUI gerektirir);
  Developer ID imzası (başka makineye dağıtım).
