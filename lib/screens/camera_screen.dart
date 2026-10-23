import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart' as cam;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/camera_service.dart';
import '../services/image_processing_service.dart';
import '../services/permission_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/guide_overlay.dart';

/// Ekran 3 — Kamera ve vesikalık çekimi.
///
/// Akış:
///   1. Tam ekran canlı görüntü + vesikalık kılavuz çerçevesi
///   2. Deklanşör → fotoğraf çekilir, çerçeveye göre kırpılır
///   3. Onay diyaloğu: kırpılmış önizleme + okul numarası alanı
///   4. Kaydet → diske yazılır; **kamera açık kalır**, sıradaki öğrenci için
///      hazırdır (seri çekim).
class CameraScreen extends StatefulWidget {
  final String className;

  /// Yeniden çekim modunda doldurulacak okul numarası.
  final String? initialSchoolNumber;

  const CameraScreen({
    super.key,
    required this.className,
    this.initialSchoolNumber,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  final CameraService _camera = CameraService();
  final StorageService _storage = StorageService.instance;
  final PermissionService _permissions = PermissionService.instance;

  /// Kılavuz çerçevenin konumu (preview alanına göre, global koordinat).
  final GlobalKey _previewKey = GlobalKey();

  bool _initializing = true;
  bool _capturing = false;
  bool _saving = false;
  String? _error;
  bool _permissionBlocked = false;

  /// Son başarılı kaydın numarası (art arda çekimde ipucu olarak gösterilir).
  String? _lastSavedNumber;
  int _savedCount = 0;

  /// Flaş durumu (kapalı → açık → otomatik).
  cam.FlashMode _flashMode = cam.FlashMode.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // MIUI/HyperOS: uygulama arka plana geçince kamera servisi serbest
    // bırakılmazsa geri dönüşte donma/siyah ekran olur.
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (!_saving && !_capturing) {
          _camera.suspend();
        }
        break;
      case AppLifecycleState.resumed:
        if (!_saving && !_capturing) {
          _recoverCamera();
        }
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Kamera yaşam döngüsü
  // ---------------------------------------------------------------------------

  Future<void> _start() async {
    if (mounted) {
      setState(() {
        _initializing = true;
        _error = null;
        _permissionBlocked = false;
      });
    }

    try {
      // Önce izin: MIUI'da izin verilmeden initialize() çağrısı kamera
      // servisini kilitleyebiliyor.
      final outcome = await _permissions.requireCamera();
      if (!mounted) return;

      if (outcome == PermissionOutcome.permanentlyDenied) {
        setState(() {
          _initializing = false;
          _error = 'Kamera izni kalıcı olarak reddedilmiş. '
              'Devam etmek için uygulama ayarlarından kamera iznini açın.';
          _permissionBlocked = true;
        });
        return;
      }

      if (outcome == PermissionOutcome.denied) {
        setState(() {
          _initializing = false;
          _error = 'Kamera izni verilmedi. Vesikalık çekmek için kamera '
              'erişimine izin vermeniz gerekir.';
          _permissionBlocked = false;
        });
        return;
      }

      await _camera.initialize();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = null;
      });
    } on CameraServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = e.message;
        _permissionBlocked = e.isPermissionIssue;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Kamera başlatılamadı: $e';
      });
    }
  }

  Future<void> _recoverCamera() async {
    if (_camera.isReady) return;
    try {
      await _camera.resume();
      if (!mounted) return;
      setState(() => _error = null);
    } catch (_) {
      // Sessiz: kullanıcı "Yeniden Dene" ile tekrar deneyebilir.
    }
  }

  // ---------------------------------------------------------------------------
  // Çekim
  // ---------------------------------------------------------------------------

  /// Ekrandaki kılavuz çerçeveyi, **önizleme alanına göre** normalize eder.
  ///
  /// Görüntünün en-boy oranı ile önizleme oranı farklı olabileceği için
  /// `BoxFit.cover` dönüşümü [ImageProcessingService] içinde uygulanır;
  /// burada yalnızca ekranda görünen alan tarif edilir.
  GuideCrop _currentGuideCrop() {
    final previewBox =
        _previewKey.currentContext?.findRenderObject() as RenderBox?;

    final screenSize = MediaQuery.sizeOf(context);
    final previewRect = previewBox == null
        ? Rect.fromLTWH(0, 0, screenSize.width, screenSize.height)
        : previewBox.localToGlobal(Offset.zero) & previewBox.size;

    if (previewRect.width <= 0 || previewRect.height <= 0) {
      return const GuideCrop(
        left: 0.12,
        top: 0.10,
        right: 0.88,
        bottom: 0.90,
        previewAspect: 0.5625,
      );
    }

    // Kılavuz çerçeve, önizleme alanından türetilir (GuideOverlay ile aynı).
    final frame = GuideGeometry.frameInside(previewRect);

    return GuideCrop(
      left: ((frame.left - previewRect.left) / previewRect.width)
          .clamp(0.0, 1.0),
      top: ((frame.top - previewRect.top) / previewRect.height)
          .clamp(0.0, 1.0),
      right: ((frame.right - previewRect.left) / previewRect.width)
          .clamp(0.0, 1.0),
      bottom: ((frame.bottom - previewRect.top) / previewRect.height)
          .clamp(0.0, 1.0),
      previewAspect: previewRect.width / previewRect.height,
    );
  }

  Future<void> _capture() async {
    if (_capturing || _saving || !_camera.isReady) return;

    setState(() {
      _capturing = true;
      _error = null;
    });

    File? rawFile;
    try {
      final shot = await _camera.takePicture();
      rawFile = File(shot.path);

      final crop = _currentGuideCrop();
      final processed = await ImageProcessingService.process(
        sourcePath: shot.path,
        crop: crop,
      );

      if (!mounted) return;
      setState(() => _capturing = false);

      // Onay diyaloğu: önizleme + okul numarası.
      final number = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PhotoConfirmDialog(
          imageBytes: processed.bytes,
          className: widget.className,
          suggestedNumber: widget.initialSchoolNumber ?? _lastSavedNumber,
          onExists: (n) => _storage.photoExists(widget.className, n),
        ),
      );

      if (number == null || !mounted) {
        // Yeniden çek: kamera hazır bekliyor.
        return;
      }

      await _save(processed, number);
    } on CameraServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _error = e.message;
        _permissionBlocked = e.isPermissionIssue;
      });
    } on PhotoProcessingException catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      AppSnackbar.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      AppSnackbar.error(context, 'Çekim başarısız: $e');
    } finally {
      // Ham kameranın ürettiği geçici dosya artık gereksiz.
      if (rawFile != null) {
        try {
          if (await rawFile.exists()) await rawFile.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _save(ProcessedPhoto photo, String schoolNumber) async {
    setState(() => _saving = true);
    try {
      await _storage.savePhoto(
        className: widget.className,
        schoolNumber: schoolNumber,
        bytes: photo.bytes,
      );

      if (!mounted) return;
      setState(() {
        _saving = false;
        _lastSavedNumber = schoolNumber;
        _savedCount++;
      });

      HapticFeedback.mediumImpact();
      AppSnackbar.success(
        context,
        '$schoolNumber numaralı öğrenci kaydedildi · '
        '${photo.sizeInKb.toStringAsFixed(0)} KB',
      );
      // Kamera açık kalır: sıradaki öğrenci için hazır.
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackbar.error(context, 'Kaydedilemedi: $e');
    }
  }

  void _cycleFlash() {
    const order = <cam.FlashMode>[
      cam.FlashMode.off,
      cam.FlashMode.auto,
      cam.FlashMode.always,
    ];
    final next = order[(order.indexOf(_flashMode) + 1) % order.length];
    setState(() => _flashMode = next);
    _camera.setFlashMode(next);
  }

  // ---------------------------------------------------------------------------
  // Arayüz
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildPreview()),
            if (_error == null && !_initializing) _buildGuideLayer(),
            _buildTopBar(),
            if (_error == null && !_initializing) _buildBottomBar(),
            if (_initializing) _buildInitializing(),
            if (_error != null) _buildError(),
            if (_saving) _buildSavingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _camera.controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    return LayoutBuilder(
      key: _previewKey,
      builder: (context, constraints) {
        // Kamera görüntüsünü ekranı TAM kaplayacak şekilde ölçekle
        // (letterbox yok) — kılavuz çerçeve ile çekilen alan örtüşsün.
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: controller.value.previewSize?.height ??
                  constraints.maxWidth,
              height: controller.value.previewSize?.width ??
                  constraints.maxHeight,
              child: cam.CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGuideLayer() {
    return Positioned.fill(
      child: IgnorePointer(
        child: GuideOverlay(
          instruction: _savedCount == 0
              ? 'Yüzü çerçeveye ortalayın'
              : '$_savedCount fotoğraf kaydedildi · sıradaki öğrenci',
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              tooltip: 'Kapat',
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.groups_rounded,
                    size: 16,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.className,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: _cycleFlash,
              tooltip: 'Flaş',
              icon: Icon(
                switch (_flashMode) {
                  cam.FlashMode.off => Icons.flash_off_rounded,
                  cam.FlashMode.auto => Icons.flash_auto_rounded,
                  _ => Icons.flash_on_rounded,
                },
                color: Colors.white,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final theme = Theme.of(context);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 26),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.72),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_lastSavedNumber != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Son kayıt: Okul No $_lastSavedNumber',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 56),
                _ShutterButton(
                  busy: _capturing || _saving,
                  onPressed: _capture,
                ),
                SizedBox(
                  width: 56,
                  child: IconButton(
                    onPressed: _capturing || _saving ? null : _recoverCamera,
                    tooltip: 'Odağı yenile',
                    icon: Icon(
                      Icons.center_focus_strong_rounded,
                      color: theme.colorScheme.onPrimary,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _capturing
                  ? 'Fotoğraf işleniyor…'
                  : 'Deklanşöre basın, ardından okul numarasını girin',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitializing() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Kamera hazırlanıyor…',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _permissionBlocked
                      ? Icons.lock_outline_rounded
                      : Icons.videocam_off_rounded,
                  size: 52,
                  color: Colors.white54,
                ),
                const SizedBox(height: 20),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 26),
                if (_permissionBlocked)
                  FilledButton.icon(
                    onPressed: () async {
                      await _permissions.openSettings();
                      if (!mounted) return;
                      await _start();
                    },
                    icon: const Icon(Icons.settings_rounded),
                    label: const Text('Ayarları Aç'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Yeniden Dene'),
                  ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text(
                    'Geri Dön',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSavingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Kaydediliyor…',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Deklanşör
// -----------------------------------------------------------------------------

class _ShutterButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onPressed;

  const _ShutterButton({required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Fotoğraf çek',
      child: GestureDetector(
        onTap: busy ? null : onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            color: busy ? Colors.white24 : Colors.white12,
          ),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: busy ? 26 : 56,
              height: busy ? 26 : 56,
              decoration: BoxDecoration(
                shape: busy ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: busy ? BorderRadius.circular(6) : null,
                color: busy ? Colors.white38 : Colors.white,
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Çekim sonrası onay diyaloğu
// -----------------------------------------------------------------------------

/// Çekilen (kırpılmış) fotoğrafın önizlemesi + okul numarası girişi.
///
/// Ekran 3'ün şartı: kaydettikten sonra kamera KAPANMAZ; bu diyalog sadece
/// kendi üstünü kapatır ve kullanıcıya numara sorar.
class PhotoConfirmDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final String className;
  final String? suggestedNumber;

  /// Okul numarası bu sınıfta zaten var mı? (üzerine yazma uyarısı için)
  final Future<bool> Function(String number) onExists;

  const PhotoConfirmDialog({
    super.key,
    required this.imageBytes,
    required this.className,
    required this.onExists,
    this.suggestedNumber,
  });

  @override
  State<PhotoConfirmDialog> createState() => _PhotoConfirmDialogState();
}

class _PhotoConfirmDialogState extends State<PhotoConfirmDialog> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  String? _error;
  bool _overwriteWarning = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.suggestedNumber ?? '');
    // Öneri varsa sonuna imleç gelsin; yoksa boş kalsın.
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _checkDuplicate(String value) async {
    final number = value.trim();
    if (number.isEmpty) {
      setState(() {
        _overwriteWarning = false;
        _error = null;
      });
      return;
    }

    setState(() => _checking = true);
    try {
      final exists = await widget.onExists(number);
      if (!mounted) return;
      setState(() {
        _overwriteWarning = exists;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking = false);
    }
  }

  void _submit() {
    final number = _controller.text.trim();
    if (number.isEmpty) {
      setState(() => _error = 'Okul numarası girin.');
      return;
    }
    if (!RegExp(r'^\d{1,12}$').hasMatch(number)) {
      setState(() => _error = 'Yalnızca rakam kullanın.');
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(number);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 40),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Başlık
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fotoğrafı Kaydet',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${widget.className} · kırpılmış vesikalık',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Vazgeç',
                  ),
                ],
              ),
            ),

            // Kırpılmış önizleme (3:4)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 260,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: Image.memory(
                      widget.imageBytes,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            ),

            // Okul numarası
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                maxLength: 12,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                autofocus: true,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
                decoration: InputDecoration(
                  labelText: 'Okul Numarası',
                  hintText: 'örn. 1042',
                  errorText: _error,
                  counterText: '',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  suffixIcon: _checking
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                onChanged: (value) {
                  if (_error != null) setState(() => _error = null);
                  _checkDuplicate(value);
                },
                onSubmitted: (_) => _submit(),
              ),
            ),

            // Üzerine yazma uyarısı
            if (_overwriteWarning)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 19,
                        color: scheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Bu numarada kayıtlı fotoğraf var. Kaydederseniz '
                          'üzerine yazılacak.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onTertiaryContainer,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.refresh_rounded, size: 19),
                      label: const Text('Yeniden Çek'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.save_rounded, size: 19),
                      label: Text(
                        _overwriteWarning ? 'Üzerine Yaz' : 'Kaydet',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
