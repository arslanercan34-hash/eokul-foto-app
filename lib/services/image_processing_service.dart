import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Kılavuz çerçevenin, **ekranda görünen önizleme alanına** göre normalize
/// (0..1) konumu.
///
/// Kameranın çektiği görüntü ile önizlemenin en-boy oranı farklı olabilir
/// (örn. önizleme 16:9, çekim 4:3). Bu yüzden asıl eşleme, [ImageProcessingService]
/// içinde `BoxFit.cover` mantığıyla yapılır; burada yalnızca ekranda görünen
/// alan tarif edilir.
@immutable
class GuideCrop {
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Önizleme alanının en-boy oranı (genişlik / yükseklik).
  final double previewAspect;

  const GuideCrop({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.previewAspect,
  })  : assert(left >= 0 && left < 1),
        assert(top >= 0 && top < 1),
        assert(right > 0 && right <= 1),
        assert(bottom > 0 && bottom <= 1),
        assert(previewAspect > 0);

  double get width => right - left;
  double get height => bottom - top;

  @override
  String toString() =>
      'GuideCrop(${left.toStringAsFixed(3)}, ${top.toStringAsFixed(3)}, '
      '${right.toStringAsFixed(3)}, ${bottom.toStringAsFixed(3)}, '
      'aspect ${previewAspect.toStringAsFixed(3)})';
}

/// İşlenmiş vesikalık fotoğraf.
@immutable
class ProcessedPhoto {
  /// Doğrudan diske yazılabilecek JPEG baytları.
  final Uint8List bytes;
  final int width;
  final int height;
  final int quality;

  const ProcessedPhoto({
    required this.bytes,
    required this.width,
    required this.height,
    required this.quality,
  });

  int get sizeInBytes => bytes.lengthInBytes;
  double get sizeInKb => bytes.lengthInBytes / 1024;
}

/// Fotoğraf işlenirken oluşan, kullanıcıya gösterilebilecek hata.
class PhotoProcessingException implements Exception {
  final String message;
  const PhotoProcessingException(this.message);

  @override
  String toString() => message;
}

/// Vesikalık üretim hattı:
///   1) EXIF yönüne göre düzelt
///   2) kılavuz çerçeveyi çekilen görüntüye eşle (cover mantığı)
///   3) 3:4 oranına sabitleyerek kırp
///   4) e-Okul çözünürlüğüne ölçekle (300x400)
///   5) 20 KB – 50 KB aralığına düşene kadar JPEG kalitesini ayarla
class ImageProcessingService {
  const ImageProcessingService();

  // ---------------------------------------------------------------------------
  // e-Okul standardı
  //
  // e-Okul vesikalık için temiz 3:4 dikey oranı kabul eder. 300x400 px bu
  // oranı koruyan yüksek kaliteli karşılığıdır. 133x171 px tercih edilirse
  // aşağıdaki iki sabiti değiştirmek yeterlidir (oran birebir aynı kalır).
  // ---------------------------------------------------------------------------
  static const int targetWidth = 300;
  static const int targetHeight = 400;

  /// e-Okul üst sınırı 50 KB. Güvenlik payı için 49 KB hedeflenir.
  static const int maxBytes = 49 * 1024;

  /// Alt sınır 20 KB — çok küçük dosyalar e-Okul'da reddedilebilir.
  static const int minBytes = 20 * 1024;

  /// Hedef en-boy oranı (genişlik / yükseklik) = 3:4.
  static const double targetAspect = targetWidth / targetHeight;

  /// Ağır işi (decode / kırp / ölçekle / kodla) ana isolate dışında çalıştırır.
  static Future<ProcessedPhoto> process({
    required String sourcePath,
    required GuideCrop crop,
  }) async {
    final result = await compute(_processInIsolate, <String, dynamic>{
      'path': sourcePath,
      'left': crop.left,
      'top': crop.top,
      'right': crop.right,
      'bottom': crop.bottom,
      'previewAspect': crop.previewAspect,
    });

    final error = result['error'];
    if (error is String) {
      throw PhotoProcessingException(error);
    }

    return ProcessedPhoto(
      bytes: result['bytes'] as Uint8List,
      width: result['width'] as int,
      height: result['height'] as int,
      quality: result['quality'] as int,
    );
  }
}

// -----------------------------------------------------------------------------
// Isolate gövdesi (üst düzey fonksiyon olmak zorunda)
// -----------------------------------------------------------------------------

Map<String, dynamic> _processInIsolate(Map<String, dynamic> args) {
  final path = args['path'] as String;
  final previewAspect = args['previewAspect'] as double;

  try {
    final file = File(path);
    if (!file.existsSync()) {
      return <String, dynamic>{'error': 'Çekilen fotoğraf dosyası bulunamadı.'};
    }

    final raw = file.readAsBytesSync();
    img.Image? decoded = img.decodeImage(raw);
    if (decoded == null) {
      return <String, dynamic>{'error': 'Fotoğraf çözümlenemedi (bozuk görüntü).'};
    }

    // Kamera sensörü görüntüyü dönük üretebilir; EXIF yönüne göre düzelt.
    decoded = img.bakeOrientation(decoded);

    final cropped = _cropToGuide(
      decoded,
      left: args['left'] as double,
      top: args['top'] as double,
      right: args['right'] as double,
      bottom: args['bottom'] as double,
      previewAspect: previewAspect,
    );
    if (cropped == null) {
      return <String, dynamic>{'error': 'Kırpma alanı görüntü dışında kaldı.'};
    }

    final base = img.copyResize(
      cropped,
      width: ImageProcessingService.targetWidth,
      height: ImageProcessingService.targetHeight,
      interpolation: img.Interpolation.cubic,
    );

    final primary = _encodeIntoWindow(base);
    if (primary != null) return primary;

    // 300x400'de 20 KB altında kalındıysa (çok düz bir kare olabilir):
    // daha büyük çözünürlükte kodlayarak dosyayı aralığa taşımayı dene.
    for (final scale in <double>[1.5, 2.0]) {
      final w = (ImageProcessingService.targetWidth * scale).round();
      final h = (ImageProcessingService.targetHeight * scale).round();
      final larger = img.copyResize(
        cropped,
        width: w,
        height: h,
        interpolation: img.Interpolation.cubic,
      );
      final result = _encodeIntoWindow(larger);
      if (result != null) return result;
    }

    // Hiçbir kombinasyon aralığa girmediyse: üst sınırı aşmayan en iyi sürüm.
    var quality = 60;
    var bytes = img.encodeJpg(base, quality: quality);
    while (bytes.lengthInBytes > ImageProcessingService.maxBytes &&
        quality > 30) {
      quality -= 5;
      bytes = img.encodeJpg(base, quality: quality);
    }

    return <String, dynamic>{
      'bytes': bytes,
      'width': ImageProcessingService.targetWidth,
      'height': ImageProcessingService.targetHeight,
      'quality': quality,
    };
  } catch (e) {
    return <String, dynamic>{'error': 'Fotoğraf işlenirken hata oluştu: $e'};
  }
}

/// Ekranda görünen alanı, çekilen görüntüde birebir karşılık gelen bölgeye
/// çevirir ve 3:4 oranına sabitleyerek kırpar.
///
/// Önizleme `BoxFit.cover` ile çizildiğinden, kaynak görüntünün bir kısmı
/// ekran dışında kalır. Aynı "cover" mantığı burada da uygulanır:
///  * kaynak, önizlemeden daha geniş  → yatayda kırpılır
///  * kaynak, önizlemeden daha uzun   → dikeyde kırpılır
img.Image? _cropToGuide(
  img.Image source, {
  required double left,
  required double top,
  required double right,
  required double bottom,
  required double previewAspect,
}) {
  final srcW = source.width.toDouble();
  final srcH = source.height.toDouble();
  if (srcW <= 0 || srcH <= 0) return null;

  final srcAspect = srcW / srcH;

  // Görüntünün kaçta kaçı ekranda görünüyor?
  double visibleW;
  double visibleH;
  double offsetX;
  double offsetY;

  if (srcAspect > previewAspect) {
    // Görüntü daha geniş: yanlardan kırpılıyor.
    visibleH = 1.0;
    visibleW = previewAspect / srcAspect;
    offsetX = (1.0 - visibleW) / 2;
    offsetY = 0.0;
  } else {
    // Görüntü daha uzun: üstten/alttan kırpılıyor.
    visibleW = 1.0;
    visibleH = srcAspect / previewAspect;
    offsetX = 0.0;
    offsetY = (1.0 - visibleH) / 2;
  }

  // Normalize (önizlemeye göre) -> normalize (görüntüye göre).
  final nLeft = offsetX + left * visibleW;
  final nTop = offsetY + top * visibleH;
  final nRight = offsetX + right * visibleW;
  final nBottom = offsetY + bottom * visibleH;

  var x0 = (nLeft * srcW).round();
  var y0 = (nTop * srcH).round();
  var w = ((nRight - nLeft) * srcW).round();
  var h = ((nBottom - nTop) * srcH).round();

  if (w <= 0 || h <= 0) return null;

  // Oranı 3:4'e sabitle: alanı büyütmeden, merkezden daralt.
  final currentAspect = w / h;
  if (currentAspect > ImageProcessingService.targetAspect) {
    final newW = (h * ImageProcessingService.targetAspect).round();
    x0 += ((w - newW) / 2).round();
    w = newW;
  } else if (currentAspect < ImageProcessingService.targetAspect) {
    final newH = (w / ImageProcessingService.targetAspect).round();
    y0 += ((h - newH) / 2).round();
    h = newH;
  }

  // Görüntü sınırlarının içine al.
  if (x0 < 0) {
    w += x0;
    x0 = 0;
  }
  if (y0 < 0) {
    h += y0;
    y0 = 0;
  }
  if (x0 + w > srcW) w = srcW.round() - x0;
  if (y0 + h > srcH) h = srcH.round() - y0;
  if (w <= 0 || h <= 0) return null;

  return img.copyCrop(source, x: x0, y: y0, width: w, height: h);
}

/// JPEG kalitesini ikili arama ile, dosya boyutu [minBytes, maxBytes]
/// aralığına girecek şekilde seçer. Aralığa girmezse null döner.
Map<String, dynamic>? _encodeIntoWindow(img.Image image) {
  const lower = 35;
  const upper = 100;

  // Önce en yüksek kalite: hem en iyi görüntü hem de genelde aralık içi.
  final best = img.encodeJpg(image, quality: upper);
  if (best.lengthInBytes <= ImageProcessingService.maxBytes) {
    if (best.lengthInBytes >= ImageProcessingService.minBytes) {
      return <String, dynamic>{
        'bytes': best,
        'width': image.width,
        'height': image.height,
        'quality': upper,
      };
    }
    return null; // Çok küçük: daha büyük çözünürlük gerekiyor.
  }

  // Üst sınırı aşıyor: kaliteyi düşürerek aralığa gir.
  var lo = lower;
  var hi = upper;
  Uint8List? candidate;
  var candidateQuality = lower;

  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    final encoded = img.encodeJpg(image, quality: mid);
    if (encoded.lengthInBytes <= ImageProcessingService.maxBytes) {
      candidate = encoded;
      candidateQuality = mid;
      lo = mid + 1; // Daha yüksek kalite deneyebiliriz.
    } else {
      hi = mid - 1;
    }
  }

  if (candidate == null) return null; // En düşük kalitede bile çok büyük.
  if (candidate.lengthInBytes < ImageProcessingService.minBytes) return null;

  return <String, dynamic>{
    'bytes': candidate,
    'width': image.width,
    'height': image.height,
    'quality': candidateQuality,
  };
}

/// Ekranda çizilecek kılavuz çerçevenin geometrisi.
///
/// Kırpma koordinatları bu çerçeveden türetildiği için, ekranda görünen alan
/// ile kaydedilen alan birebir örtüşür.
class GuideGeometry {
  const GuideGeometry._();

  /// [area] içine yerleşen 3:4 dikey kılavuz çerçeve.
  static Rect frameInside(Rect area, {double widthFactor = 0.76}) {
    var w = area.width * widthFactor;
    var h = w / ImageProcessingService.targetAspect;

    // Çerçeve dikeyde taşmasın (küçük ekranlar / büyük yazı tipi).
    final maxHeight = area.height * 0.80;
    if (h > maxHeight) {
      h = maxHeight;
      w = h * ImageProcessingService.targetAspect;
    }

    final left = area.left + (area.width - w) / 2;
    final top = area.top + (area.height - h) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }
}
