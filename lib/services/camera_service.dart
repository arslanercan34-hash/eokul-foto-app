import 'dart:async';
import 'dart:ui' show Offset;

import 'package:camera/camera.dart' as cam;
import 'package:flutter/foundation.dart';

/// Kamera erişimiyle ilgili kullanıcıya gösterilebilir hata.
class CameraServiceException implements Exception {
  final String message;

  /// true ise sorun izinlerden kaynaklanıyor (ayarlara yönlendirme önerilir).
  final bool isPermissionIssue;

  const CameraServiceException(this.message, {this.isPermissionIssue = false});

  @override
  String toString() => message;
}

/// Kamera yaşam döngüsünü yöneten ince katman.
///
/// MIUI / HyperOS'a özgü sorunlar burada ele alınır:
///  * Kamera servisi başka uygulama tarafından kilitlenmişse init başarısız
///    olur -> kısa beklemeyle yeniden denenir.
///  * Uygulama arka plana atılıp dönüldüğünde controller ölür -> yeniden
///    başlatılır.
///  * İzin kalıcı olarak reddedildiyse net bir mesaj döner.
class CameraService {
  cam.CameraController? _controller;
  cam.CameraDescription? _description;

  cam.CameraController? get controller => _controller;
  cam.CameraDescription? get description => _description;
  bool get isReady => _controller?.value.isInitialized ?? false;

  /// Kullanılabilir kameraları listeler; hiç yoksa hata fırlatır.
  Future<List<cam.CameraDescription>> discoverCameras() async {
    try {
      final cameras = await cam.availableCameras();
      if (cameras.isEmpty) {
        throw const CameraServiceException(
          'Cihazda kullanılabilir kamera bulunamadı.',
        );
      }
      return cameras;
    } on cam.CameraException catch (e) {
      throw CameraServiceException(
        'Kamera listelenemedi: ${e.description ?? e.code}',
      );
    }
  }

  /// Vesikalık için arka kamera tercih edilir.
  static cam.CameraDescription pickBestCamera(
    List<cam.CameraDescription> cameras,
  ) {
    for (final c in cameras) {
      if (c.lensDirection == cam.CameraLensDirection.back) return c;
    }
    return cameras.first;
  }

  /// Kamerayı başlatır. Zaten hazırsa hiçbir şey yapmaz.
  Future<void> initialize({
    cam.CameraDescription? camera,
    cam.ResolutionPreset preset = cam.ResolutionPreset.high,
    int attempts = 3,
  }) async {
    if (isReady) return;

    final target = camera ?? pickBestCamera(await discoverCameras());

    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        await _disposeQuietly();

        final ctrl = cam.CameraController(
          target,
          preset,
          // MIUI'da kamera servisi bazen ses kanalını açarken kilitlenir.
          enableAudio: false,
          imageFormatGroup: cam.ImageFormatGroup.jpeg,
        );

        await ctrl.initialize().timeout(
              const Duration(seconds: 12),
              onTimeout: () => throw const CameraServiceException(
                'Kamera başlatma zaman aşımına uğradı. '
                'Cihazı yeniden başlatmayı deneyin.',
              ),
            );

        _controller = ctrl;
        _description = target;

        // Vesikalık için otomatik odak şart.
        try {
          await ctrl.setFocusMode(cam.FocusMode.auto);
        } catch (_) {
          // Bazı OEM kameralar odak modunu değiştirmeye izin vermez.
        }
        try {
          await ctrl.setFlashMode(cam.FlashMode.off);
        } catch (_) {}

        return;
      } on CameraServiceException {
        rethrow;
      } on cam.CameraException catch (e) {
        lastError = e;
        await _disposeQuietly();

        // İzin reddedildiyse yeniden denemenin anlamı yok.
        if (_looksLikePermissionError(e)) {
          throw const CameraServiceException(
            'Kamera izni verilmedi. Lütfen ayarlardan kamera iznini açın.',
            isPermissionIssue: true,
          );
        }

        if (attempt < attempts) {
          await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
        }
      } catch (e) {
        lastError = e;
        await _disposeQuietly();
        if (attempt < attempts) {
          await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
        }
      }
    }

    throw CameraServiceException(
      'Kamera başlatılamadı. ${_describe(lastError)}',
    );
  }

  /// Tek kare fotoğraf çeker ve dosya yolunu döndürür.
  Future<cam.XFile> takePicture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      throw const CameraServiceException('Kamera hazır değil.');
    }
    if (ctrl.value.isTakingPicture) {
      throw const CameraServiceException('Önceki çekim hâlâ sürüyor.');
    }

    try {
      return await ctrl.takePicture();
    } on cam.CameraException catch (e) {
      if (_looksLikePermissionError(e)) {
        throw const CameraServiceException(
          'Kamera izni kaldırılmış görünüyor. Ayarlardan kontrol edin.',
          isPermissionIssue: true,
        );
      }
      throw CameraServiceException(
        'Fotoğraf çekilemedi: ${e.description ?? e.code}',
      );
    }
  }

  /// Ekranın dokunulan noktasına odaklanır (0..1 normalize koordinat).
  Future<void> focusAt(Offset point) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    try {
      await ctrl.setFocusPoint(point);
      await ctrl.setExposurePoint(point);
    } catch (_) {
      // Odaklama desteklenmiyorsa sessizce devam et.
    }
  }

  Future<void> setFlashMode(cam.FlashMode mode) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    try {
      await ctrl.setFlashMode(mode);
    } catch (_) {
      // Flaş yoksa yoksay.
    }
  }

  cam.FlashMode get flashMode =>
      _controller?.value.flashMode ?? cam.FlashMode.off;

  /// Uygulama arka plana geçtiğinde çağrılır.
  Future<void> suspend() async {
    await _disposeQuietly();
  }

  /// Uygulama geri döndüğünde çağrılır.
  Future<void> resume() async {
    if (isReady) return;
    final desc = _description;
    if (desc == null) return;
    await initialize(camera: desc);
  }

  /// Serbest bırakır.
  Future<void> dispose() async {
    await _disposeQuietly();
    _description = null;
  }

  Future<void> _disposeQuietly() async {
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null) {
      try {
        await ctrl.dispose();
      } catch (_) {}
    }
  }

  static bool _looksLikePermissionError(cam.CameraException e) {
    final text = '${e.code} ${e.description ?? ''}'.toLowerCase();
    return text.contains('permission') ||
        text.contains('camera_access_denied') ||
        text.contains('denied');
  }

  static String _describe(Object? error) {
    if (error is cam.CameraException) {
      return error.description ?? error.code;
    }
    if (error is CameraServiceException) return error.message;
    return error?.toString() ?? 'Bilinmeyen hata.';
  }
}
