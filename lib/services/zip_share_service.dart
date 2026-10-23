import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:archive/archive.dart';
import 'package:cross_file/cross_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'storage_service.dart';

/// ZIP oluşturma sonucu.
class ZipResult {
  final File file;
  final int photoCount;

  const ZipResult({required this.file, required this.photoCount});

  String get fileName => p.basename(file.path);

  double get sizeInMb {
    try {
      return file.lengthSync() / (1024 * 1024);
    } catch (_) {
      return 0;
    }
  }
}

/// Bir sınıfın tüm `.jpg` dosyalarını tek bir ZIP'te toplayıp Android
/// paylaşım menüsünü açar (WhatsApp, Drive, e-posta...).
class ZipShareService {
  ZipShareService._();

  static final ZipShareService instance = ZipShareService._();

  /// ZIP dosyaları burada tutulur (sistem önbelleği, dışarıya açık değil).
  Future<Directory> _cacheDirectory() async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'zips'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// `[Sinif_Adi]_eOkul_Fotograflari.zip` üretir.
  ///
  /// ZIP içine dosyalar düz (klasörsüz) olarak `1042.jpg` biçiminde eklenir;
  /// e-Okul'a yükleme sırasında tek tek seçilebilsin diye.
  Future<ZipResult> buildClassZip(ClassFolder classFolder) async {
    if (classFolder.photos.isEmpty) {
      throw const ZipShareException('Bu sınıfta henüz fotoğraf yok.');
    }

    final archive = Archive();
    var added = 0;

    for (final photo in classFolder.sortedPhotos) {
      try {
        final bytes = await photo.file.readAsBytes();
        final name = '${photo.schoolNumber}.jpg';
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
        added++;
      } catch (_) {
        // Okunamayan tek dosya tüm arşivi düşürmesin.
      }
    }

    if (added == 0) {
      throw const ZipShareException('Fotoğraf dosyaları okunamadı.');
    }

    // JPEG'ler zaten sıkıştırılmış; varsayılan seviye (bestSpeed) yeterli.
    // archive 4.x: encodeBytes() -> Uint8List (non-nullable)
    final Uint8List encoded = ZipEncoder().encodeBytes(archive);
    if (encoded.isEmpty) {
      throw const ZipShareException('ZIP arşivi oluşturulamadı.');
    }

    final dir = await _cacheDirectory();
    final fileName = '${classFolder.name}_eOkul_Fotograflari.zip';
    final file = File(p.join(dir.path, fileName));

    // Eski aynı adlı arşiv varsa üzerine yaz.
    if (await file.exists()) {
      await file.delete();
    }
    await file.writeAsBytes(encoded, flush: true);

    return ZipResult(file: file, photoCount: added);
  }

  /// ZIP'i oluşturup paylaşım menüsünü açar.
  Future<ZipResult> shareClass(
    ClassFolder classFolder, {
    Rect? sharePositionOrigin,
  }) async {
    final result = await buildClassZip(classFolder);

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile(result.file.path, mimeType: 'application/zip'),
        ],
        subject: '${classFolder.name} - e-Okul Fotoğrafları',
        text:
            '${classFolder.name} sınıfı e-Okul vesikalık fotoğrafları '
            '(${result.photoCount} öğrenci).',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );

    return result;
  }
}

/// Kullanıcıya gösterilebilecek ZIP hatası.
class ZipShareException implements Exception {
  final String message;
  const ZipShareException(this.message);

  @override
  String toString() => message;
}
