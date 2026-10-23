import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Bir sınıf klasöründeki tek bir öğrenci fotoğrafı.
class StudentPhoto {
  final File file;

  /// Dosya adından türetilen okul numarası (örn. "1042").
  final String schoolNumber;

  const StudentPhoto({required this.file, required this.schoolNumber});

  int get sizeInBytes {
    try {
      return file.lengthSync();
    } catch (_) {
      return 0;
    }
  }

  double get sizeInKb => sizeInBytes / 1024;

  DateTime get modified {
    try {
      return file.lastModifiedSync();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
}

/// Bir sınıfın diskteki karşılığı.
class ClassFolder {
  final String name;
  final Directory directory;
  final List<StudentPhoto> photos;

  const ClassFolder({
    required this.name,
    required this.directory,
    required this.photos,
  });

  int get photoCount => photos.length;

  /// Öğrencileri okul numarasına göre sayısal olarak sıralı döndürür.
  List<StudentPhoto> get sortedPhotos {
    final list = List<StudentPhoto>.from(photos);
    list.sort((a, b) {
      final na = int.tryParse(a.schoolNumber);
      final nb = int.tryParse(b.schoolNumber);
      if (na != null && nb != null) return na.compareTo(nb);
      if (na != null) return -1;
      if (nb != null) return 1;
      return a.schoolNumber.compareTo(b.schoolNumber);
    });
    return list;
  }
}

/// Disk üzerindeki tüm okuma/yazma işlemleri.
///
/// Yerleşim (scoped storage uyumlu, uygulamaya ait özel dizin):
///
///   <external-files>/eOkulFoto/
///   ├── 5-A/
///   │   ├── 1042.jpg
///   │   └── 1043.jpg
///   └── 8-B/
///       └── 2201.jpg
///
/// Android 11+ üzerinde bu dizin `Android/data/<paket>/files/eOkulFoto`
/// altındadır; hiçbir depolama izni gerektirmez, diğer uygulamalarca
/// okunamaz ve uygulama kaldırıldığında sistem tarafından temizlenir.
class StorageService {
  StorageService._();

  static final StorageService instance = StorageService._();

  static const String rootFolderName = 'eOkulFoto';

  /// Dosya adı olarak kullanılamayan karakterler + Türkçe karakterlerin
  /// güvenli karşılıkları (bazı dosya sistemleri NFC/NFD karışıklığı yapar).
  static const Map<String, String> _charMap = <String, String>{
    'ı': 'i',
    'İ': 'I',
    'ş': 's',
    'Ş': 'S',
    'ğ': 'g',
    'Ğ': 'G',
    'ü': 'u',
    'Ü': 'U',
    'ö': 'o',
    'Ö': 'O',
    'ç': 'c',
    'Ç': 'C',
  };

  Directory? _cachedRoot;

  /// Kök dizini döndürür, yoksa oluşturur.
  Future<Directory> rootDirectory() async {
    final cached = _cachedRoot;
    if (cached != null && await cached.exists()) return cached;

    final root = Directory(p.join(await _baseDirectoryPath(), rootFolderName));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    _cachedRoot = root;
    return root;
  }

  /// Android'de uygulamaya ait harici dizin (kullanıcı dosya yöneticisinden
  /// ulaşabilir), iOS/masaüstünde belgeler dizini.
  Future<String> _baseDirectoryPath() async {
    if (Platform.isAndroid) {
      try {
        final external = await getExternalStorageDirectory();
        if (external != null) return external.path;
      } catch (_) {
        // Bazı MIUI sürümlerinde harici dizin sorgusu hata verebilir.
      }
    }
    final docs = await getApplicationDocumentsDirectory();
    return docs.path;
  }

  /// Sınıf adını dosya sistemi için güvenli hale getirir.
  ///
  /// "5-A" -> "5-A", "5/A" -> "5-A", "  8 B  " -> "8-B"
  static String sanitizeClassName(String raw) {
    var name = raw.trim();
    if (name.isEmpty) return 'Sinif';

    final buffer = StringBuffer();
    for (final rune in name.runes) {
      final ch = String.fromCharCode(rune);
      if (_charMap.containsKey(ch)) {
        buffer.write(_charMap[ch]);
        continue;
      }
      if (RegExp(r'[A-Za-z0-9 \-_]').hasMatch(ch)) {
        buffer.write(ch);
      } else {
        buffer.write('-');
      }
    }

    name = buffer
        .toString()
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    name = name.replaceAll(RegExp(r'^[-_.]+|[-_.]+$'), '');

    if (name.isEmpty) name = 'Sinif';
    // Dosya sistemi sınırı 255; güvenli tarafta kal.
    if (name.length > 60) name = name.substring(0, 60).trim();
    return name;
  }

  /// Tüm sınıfları, fotoğraf listeleriyle birlikte döndürür.
  Future<List<ClassFolder>> loadClasses() async {
    final root = await rootDirectory();
    final List<ClassFolder> classes = <ClassFolder>[];

    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue; // geçici/çöp klasörler

      final photos = await _photosIn(entity);
      classes.add(
        ClassFolder(name: name, directory: entity, photos: photos),
      );
    }

    classes.sort((a, b) => _naturalCompare(a.name, b.name));
    return classes;
  }

  /// Tek bir sınıfı okur; klasör yoksa null.
  Future<ClassFolder?> loadClass(String className) async {
    final dir = await classDirectory(className);
    if (!await dir.exists()) return null;
    return ClassFolder(
      name: p.basename(dir.path),
      directory: dir,
      photos: await _photosIn(dir),
    );
  }

  /// Sınıf dizinini döndürür (oluşturmaz).
  Future<Directory> classDirectory(String className) async {
    final root = await rootDirectory();
    return Directory(p.join(root.path, sanitizeClassName(className)));
  }

  /// Yeni sınıf oluşturur. Zaten varsa false döner.
  Future<bool> createClass(String className) async {
    final safe = sanitizeClassName(className);
    if (safe.isEmpty) return false;
    final dir = await classDirectory(safe);
    if (await dir.exists()) return false;
    await dir.create(recursive: true);
    // MIUI/HyperOS medya tarayıcısının klasörü görmesi için (best effort).
    return true;
  }

  /// Sınıfı ve içindeki tüm fotoğrafları siler.
  Future<void> deleteClass(String className) async {
    final dir = await classDirectory(className);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Fotoğrafı [className] klasörüne `[okulNo].jpg` olarak yazar.
  ///
  /// Aynı numara varsa üzerine yazar (yeniden çekim).
  /// Dönüş: yazılan dosya.
  Future<File> savePhoto({
    required String className,
    required String schoolNumber,
    required List<int> bytes,
  }) async {
    final number = schoolNumber.trim();
    if (!RegExp(r'^\d{1,12}$').hasMatch(number)) {
      throw ArgumentError('Okul numarası yalnızca rakamlardan oluşmalıdır.');
    }

    final dir = await classDirectory(className);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final target = File(p.join(dir.path, '$number.jpg'));

    // Yarım kalmış yazma sonucu bozuk JPEG oluşmasın: önce geçici dosya.
    final temp = File('${target.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    if (await target.exists()) {
      await target.delete();
    }
    return temp.rename(target.path);
  }

  /// Tek bir fotoğrafı siler.
  Future<void> deletePhoto(String className, String schoolNumber) async {
    final dir = await classDirectory(className);
    final file = File(p.join(dir.path, '$schoolNumber.jpg'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Okul numarası bu sınıfta zaten kayıtlı mı?
  Future<bool> photoExists(String className, String schoolNumber) async {
    final dir = await classDirectory(className);
    return File(p.join(dir.path, '${schoolNumber.trim()}.jpg')).exists();
  }

  /// Sınıfta kayıtlı numaralar (yeniden çekim uyarısı için).
  Future<Set<String>> existingNumbers(String className) async {
    final cls = await loadClass(className);
    if (cls == null) return <String>{};
    return cls.photos.map((e) => e.schoolNumber).toSet();
  }

  Future<List<StudentPhoto>> _photosIn(Directory dir) async {
    final List<StudentPhoto> photos = <StudentPhoto>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final fileName = p.basename(entity.path);
        if (!fileName.toLowerCase().endsWith('.jpg')) continue;
        final number = p.basenameWithoutExtension(fileName);
        if (!RegExp(r'^\d+$').hasMatch(number)) continue;
        photos.add(StudentPhoto(file: entity, schoolNumber: number));
      }
    } catch (_) {
      // Erişilemeyen klasör listeyi bozmasın.
    }
    return photos;
  }

  /// "5-A" < "10-B" sıralaması için doğal karşılaştırma.
  static int _naturalCompare(String a, String b) {
    final ra = RegExp(r'\d+').allMatches(a).toList();
    final rb = RegExp(r'\d+').allMatches(b).toList();

    if (ra.isNotEmpty && rb.isNotEmpty) {
      final na = int.tryParse(ra.first.group(0)!) ?? 0;
      final nb = int.tryParse(rb.first.group(0)!) ?? 0;
      if (na != nb) return na.compareTo(nb);
    } else if (ra.isNotEmpty) {
      return -1;
    } else if (rb.isNotEmpty) {
      return 1;
    }
    return a.toLowerCase().compareTo(b.toLowerCase());
  }
}
