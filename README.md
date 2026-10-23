# e-Okul Vesikalık

Okul ortamında öğrencilerin vesikalık fotoğraflarını çekip **doğrudan MEB
e-Okul sistemine yüklenebilecek** standartlarda arşivleyen Flutter uygulaması.

Hedef cihaz: **Xiaomi Mi Note 10 Lite** (Android 10 / MIUI 12) ve üzeri.

---

## Ne yapar?

* Sınıf bazlı klasör yönetimi (`eOkulFoto/5-A/1042.jpg`)
* Kılavuz çerçeveli tam ekran kamera; yüz/baş-çene hizalama kılavuzları
* Çekim sonrası otomatik **kırpma → 300×400 px ölçekleme → 20–50 KB JPEG sıkıştırma**
* Okul numarası ile kayıt; aynı numara varsa üzerine yazma uyarısı
* **Kamera açık kalır** — art arda öğrenci çekimi (seri çekim)
* Sınıfın tüm fotoğraflarını tek ZIP'te toplayıp WhatsApp / Drive / e-posta ile paylaşım
* Galeriden fotoğraf silme ve yeniden çekme

---

## e-Okul uyumluluğu

| Kriter | Uygulanan değer | Nerede |
|---|---|---|
| Boyut | **300 × 400 px** (tam 3:4 dikey) | `lib/services/image_processing_service.dart` |
| Alt boyut seçeneği | 133 × 171 px (aynı 3:4 oran) | aynı dosya, `targetWidth` / `targetHeight` |
| Format | JPEG (`.jpg`) | — |
| Dosya boyutu | **20 KB – 50 KB** (üst sınırda 49 KB güvenlik payı) | `minBytes` / `maxBytes` |
| Dosya adı | `[Okul_Numarası].jpg` → `1042.jpg` | `lib/services/storage_service.dart` |
| ZIP adı | `[Sınıf_Adı]_eOkul_Fotograflari.zip` | `lib/services/zip_share_service.dart` |

> **Neden 300×400?** İstenen "temiz 3:4 dikey oran" ile birebir aynı orandır ve
> e-Okul'a yüklendiğinde bozulma olmadan kabul edilir. 133×171 px tercih
> ederseniz yalnızca `targetWidth`/`targetHeight` sabitlerini değiştirin —
> kırpma, ölçekleme ve sıkıştırma otomatik uyum sağlar.

### Sıkıştırma algoritması

1. EXIF yönüne göre görüntü düzeltilir (`img.bakeOrientation`).
2. Kılavuz çerçeve, önizlemedeki `BoxFit.cover` dönüşümü hesaba katılarak
   çekilen görüntüdeki gerçek bölgeye eşlenir.
3. Bölge 3:4 oranına sabitlenerek kırpılır, 300×400'e ölçeklenir.
4. JPEG kalitesi **ikili arama** ile 35–100 aralığında taranır; `49 KB`
   altında kalan **en yüksek** kalite seçilir.
5. Sonuç `20 KB` altındaysa (çok düz kareler) görüntü 1.5× ve 2× çözünürlükte
   yeniden kodlanarak aralığa taşınır.
6. Hiçbir kombinasyon aralığa girmezse üst sınırı aşmayan en iyi sürüm
   kaydedilir ve kullanıcıya gerçek boyut bildirilir.

Tüm ağır işler `compute()` ile ayrı isolate'te çalışır — arayüz donmaz.

---

## Depolama

Android 11+ **scoped storage** uyumlu, izinsiz çalışır:

```
Android/data/com.eokul.fotograf/files/eOkulFoto/
├── 5-A/
│   ├── 1042.jpg
│   └── 1043.jpg
└── 8-B/
    └── 2201.jpg
```

* `WRITE_EXTERNAL_STORAGE` **istenmez** (Android 11+ kendi dizininde gerek yok).
* Dosyalar dosya yöneticisinden erişilebilir (ZIP paylaşımı buradan yapılır).
* Uygulama kaldırıldığında Android bu dizini temizler — önemli arşivleri
  ZIP olarak dışa aktarın.

---

## Kurulum ve derleme

### Gereksinimler

* **Flutter 3.38.0+** (Dart 3.10.0+)
* Android SDK (Flutter'ın önerdiği sürüm), JDK 17
* Gradle 8.12, AGP 8.9.1, Kotlin 2.1.0 — proje içinde tanımlı

```bash
flutter --version
flutter doctor -v
```

### Tek komutla release APK

Proje elle yazıldığı için `gradlew` ve `gradle-wrapper.jar` gibi **ikili**
dosyalar depoda yoktur. Bunları Flutter SDK'dan güvenle kopyalayan bir
bootstrap betiği vardır — `flutter create .` gibi mevcut dosyaları **ezmez**:

```bash
bash tool/bootstrap.sh
```

Windows'ta:

```powershell
powershell -ExecutionPolicy Bypass -File tool\bootstrap.ps1
```

Sonra:

```bash
flutter pub get
flutter build apk --release
```

Çıktı:

```
build/app/outputs/flutter-apk/app-release.apk
```

Cihaza kurmak için:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

APK'yı cihaza kopyalayıp dosya yöneticisinden de kurabilirsiniz
("Bilinmeyen kaynaklar" iznini vermeniz gerekir).

### Boyut optimizasyonu (opsiyonel)

```bash
flutter build apk --release --split-per-abi
```

`app-arm64-v8a-release.apk` Mi Note 10 Lite için yeterlidir ve daha küçüktür.

---

## İmzalı Release APK

Play Store veya kalıcı kurulum için kendi anahtarınızla imzalayın.

```bash
keytool -genkey -v -keystore eokul-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`android/key.properties` dosyası oluşturun (bu dosyayı **asla** sürüm
kontrolüne eklemeyin):

```properties
storePassword=PAROLA
keyPassword=PAROLA
keyAlias=upload
storeFile=../eokul-upload.jks
```

`key.properties` yoksa build **debug anahtarıyla** imzalanır — cihazda
çalışır ama dağıtıma uygun değildir.

---

## MIUI / HyperOS notları

Uygulama bu cihazlara özel olarak şu önlemleri alır:

* **Kamera izni kalıcı reddedildiyse** net mesaj + "Ayarlar" yönlendirmesi.
* **Kamera servisi kilitlenirse** 3 denemeli, artan beklemeli yeniden başlatma.
* **Uygulama arka plana geçince** kamera serbest bırakılır; dönüşte yeniden
  başlatılır (siyah ekran / donma önlenir).
* **Otomatik odak** varsayılan; desteklenmeyen cihazlarda sessizce atlanır.
* **Şeffaf "kaydediliyor" katmanı** — çift dokunuşla yinelenen çekimi engeller.

### İzin sorunları

Fotoğraflar uygulama dizinine yazıldığı için galeri izni **gerekmez**.
Kamera izni reddedilirse: **Ayarlar → Uygulamalar → e-Okul Vesikalık →
İzinler → Kamera → İzin ver**.

---

## Proje yapısı

```
lib/
├── main.dart                          # Giriş noktası, tema, yön kilidi
├── theme/app_theme.dart               # Material 3 açık/koyu tema
├── models/                            # (rezerve)
├── screens/
│   ├── home_screen.dart               # Ekran 1 — sınıf yönetimi
│   ├── class_detail_screen.dart       # Ekran 2 — galeri, sil / yeniden çek
│   └── camera_screen.dart             # Ekran 3 — kamera, kılavuz, onay
├── services/
│   ├── camera_service.dart            # Kamera yaşam döngüsü + MIUI önlemleri
│   ├── image_processing_service.dart  # Kırp / ölçekle / 20-50 KB sıkıştır
│   ├── permission_service.dart        # Kamera + depolama izinleri
│   ├── storage_service.dart           # eOkulFoto/[Sınıf]/[No].jpg
│   └── zip_share_service.dart         # ZIP oluştur + paylaşım menüsü
└── widgets/
    ├── app_snackbar.dart              # Tutarlı geri bildirim
    ├── class_card.dart                # Sınıf kartı + hızlı eylemler
    └── guide_overlay.dart             # Vesikalık kılavuz maskesi
```

---

## GitHub Actions ile otomatik APK

`.github/workflows/build-apk.yml` her `push` ve manuel tetiklemede release
APK üretir. Oluşan APK "Actions → çalıştırma → Artifacts" bölümünden indirilir.

Repository → Settings → Secrets and variables → Actions altında imzalama
için şu secret'ları tanımlarsanız APK imzalı üretilir:

* `KEYSTORE_BASE64` — `keytool` ile oluşturduğunuz `.jks` dosyasının base64 hâli
* `KEYSTORE_PASSWORD`
* `KEY_PASSWORD`
* `KEY_ALIAS`

---

## Lisans

Bu proje okul içi kullanım için geliştirilmiştir.
