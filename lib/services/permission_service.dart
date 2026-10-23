import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// İzin isteme sonucu.
enum PermissionOutcome {
  /// İzin verildi.
  granted,

  /// Reddedildi; tekrar istenebilir.
  denied,

  /// Kalıcı olarak reddedildi; yalnızca uygulama ayarlarından açılabilir.
  permanentlyDenied,

  /// Platform bu izni desteklemiyor.
  unsupported,
}

/// Kamera ve depolama izinlerini yönetir.
///
/// Not: Fotoğraflar uygulamaya ait özel dizine (`getExternalStorageDirectory`)
/// yazıldığı için Android 11+ üzerinde depolama izni GEREKMEZ. İzinler yine
/// de tanımlıdır ve Android 9 ve altında / bazı MIUI sürümlerinde istendiği
/// için burada yönetilir.
class PermissionService {
  PermissionService._();

  static final PermissionService instance = PermissionService._();

  /// Kamera iznini zorunlu olarak ister.
  ///
  /// MIUI bazen ilk istekte diyaloğu göstermeden "denied" döndüğü için
  /// bir kez daha denenir.
  Future<PermissionOutcome> requireCamera() async {
    var outcome = await _request(Permission.camera);

    if (outcome == PermissionOutcome.denied) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      outcome = await _request(Permission.camera);
    }

    return outcome;
  }

  /// Depolama izinlerini ister. Sonuç "granted" olmasa bile uygulama kendi
  /// dizinine yazabildiği için kritik değildir.
  Future<PermissionOutcome> ensureStorage() async {
    if (!Platform.isAndroid) return PermissionOutcome.unsupported;

    // Android 13+ : READ_MEDIA_IMAGES ; Android <= 12 : READ/WRITE_STORAGE.
    // permission_handler her ikisini de tek çağrıda çözer: desteklenmeyen
    // izin "granted" ya da "restricted" olarak döner, hata fırlatmaz.
    try {
      final statuses = await <Permission>[
        Permission.photos,
        Permission.storage,
      ].request();

      var sawDenied = false;
      for (final status in statuses.values) {
        if (status.isGranted || status.isLimited) {
          return PermissionOutcome.granted;
        }
        if (status.isPermanentlyDenied) {
          sawDenied = true;
        }
      }
      return sawDenied
          ? PermissionOutcome.permanentlyDenied
          : PermissionOutcome.denied;
    } catch (_) {
      return PermissionOutcome.unsupported;
    }
  }

  /// Uygulama ayarlarını açar.
  Future<bool> openSettings() => openAppSettings();

  /// İzin durumunun şu an "kalıcı reddedildi" olup olmadığını döndürür.
  Future<bool> isCameraPermanentlyDenied() async {
    try {
      final status = await Permission.camera.status;
      return status.isPermanentlyDenied || status.isRestricted;
    } catch (_) {
      return false;
    }
  }

  Future<PermissionOutcome> _request(Permission permission) async {
    try {
      final status = await permission.status;
      if (status.isGranted || status.isLimited) {
        return PermissionOutcome.granted;
      }
      if (status.isPermanentlyDenied || status.isRestricted) {
        return PermissionOutcome.permanentlyDenied;
      }

      final result = await permission.request();
      if (result.isGranted || result.isLimited) {
        return PermissionOutcome.granted;
      }
      if (result.isPermanentlyDenied || result.isRestricted) {
        return PermissionOutcome.permanentlyDenied;
      }
      return PermissionOutcome.denied;
    } catch (_) {
      return PermissionOutcome.unsupported;
    }
  }
}
