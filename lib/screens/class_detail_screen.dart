import 'dart:io';

import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../services/zip_share_service.dart';
import '../widgets/app_snackbar.dart';
import 'camera_screen.dart';

/// Ekran 2 — Sınıf detayı ve fotoğraf galerisi.
class ClassDetailScreen extends StatefulWidget {
  final String className;

  const ClassDetailScreen({super.key, required this.className});

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen> {
  final StorageService _storage = StorageService.instance;
  final ZipShareService _zip = ZipShareService.instance;

  ClassFolder? _folder;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final folder = await _storage.loadClass(widget.className);
      if (!mounted) return;
      setState(() {
        _folder = folder;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackbar.error(context, 'Sınıf yüklenemedi: $e');
    }
  }

  Future<void> _openCamera() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CameraScreen(className: widget.className),
      ),
    );
    await _load();
  }

  Future<void> _shareAll() async {
    final folder = _folder;
    if (folder == null || folder.photos.isEmpty || _busy) return;

    setState(() => _busy = true);
    try {
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 1, 1);

      final result = await _zip.shareClass(folder, sharePositionOrigin: origin);
      if (!mounted) return;
      AppSnackbar.success(
        context,
        '${result.photoCount} fotoğraf ZIP olarak hazırlandı.',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePhoto(StudentPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fotoğrafı sil'),
        content: Text(
          '${photo.schoolNumber} numaralı öğrencinin fotoğrafı silinecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _storage.deletePhoto(widget.className, photo.schoolNumber);
    await _load();
    if (!mounted) return;
    AppSnackbar.success(context, 'Fotoğraf silindi.');
  }

  void _showPhoto(StudentPhoto photo) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _PhotoPreviewDialog(
        photo: photo,
        className: widget.className,
        onDelete: () {
          Navigator.of(ctx).pop();
          _deletePhoto(photo);
        },
        onRetake: () {
          Navigator.of(ctx).pop();
          _openCamera();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folder = _folder;
    final photos = folder?.sortedPhotos ?? const <StudentPhoto>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(folder?.name ?? widget.className),
        actions: [
          IconButton(
            tooltip: 'Tümünü ZIP Yap ve Paylaş',
            onPressed: photos.isEmpty || _busy ? null : _shareAll,
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.folder_zip_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : photos.isEmpty
              ? _buildEmpty(theme)
              : _buildGrid(theme, photos),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCamera,
        icon: const Icon(Icons.photo_camera_rounded),
        label: const Text('Fotoğraf Çek'),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.photo_camera_back_rounded,
                size: 42,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Bu sınıfta fotoğraf yok',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Öğrencilerin vesikalık fotoğraflarını çekmek için “Fotoğraf '
              'Çek” düğmesine dokunun. Her çekimde okul numarasını girerek '
              'kaydedin — kamera açık kalır, art arda çekim yapabilirsiniz.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(ThemeData theme, List<StudentPhoto> photos) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${photos.length} fotoğraf · 300×400 px · '
                    '${_storageBalance(photos)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.70,
            ),
            itemCount: photos.length,
            itemBuilder: (context, index) {
              final photo = photos[index];
              return _PhotoTile(
                photo: photo,
                onTap: () => _showPhoto(photo),
              );
            },
          ),
        ),
      ],
    );
  }

  String _storageBalance(List<StudentPhoto> photos) {
    if (photos.isEmpty) return '20–50 KB hedefi';
    final total = photos.fold<int>(0, (sum, p) => sum + p.sizeInBytes);
    final avg = total / photos.length / 1024;
    return 'ort. ${avg.toStringAsFixed(0)} KB';
  }
}

// -----------------------------------------------------------------------------

class _PhotoTile extends StatelessWidget {
  final StudentPhoto photo;
  final VoidCallback onTap;

  const _PhotoTile({required this.photo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(14),
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Ink.image(
                image: FileImage(photo.file),
                fit: BoxFit.cover,
                child: const SizedBox.expand(),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
              color: scheme.surfaceContainerHigh,
              child: Row(
                children: [
                  Icon(
                    Icons.badge_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      photo.schoolNumber,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${photo.sizeInKb.toStringAsFixed(0)}K',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.outline,
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

/// Tam ekran fotoğraf önizlemesi + sil / yeniden çek.
class _PhotoPreviewDialog extends StatelessWidget {
  final StudentPhoto photo;
  final String className;
  final VoidCallback onDelete;
  final VoidCallback onRetake;

  const _PhotoPreviewDialog({
    required this.photo,
    required this.className,
    required this.onDelete,
    required this.onRetake,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Okul No: ${photo.schoolNumber}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '$className · ${photo.sizeInKb.toStringAsFixed(0)} KB',
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
                  tooltip: 'Kapat',
                ),
              ],
            ),
          ),
          Flexible(
            child: Container(
              color: scheme.surfaceContainerHighest,
              padding: const EdgeInsets.all(12),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: Image.file(
                  photo.file,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(
                      Icons.broken_image_rounded,
                      size: 48,
                      color: scheme.outline,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 19),
                    label: const Text('Sil'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onRetake,
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                    label: const Text('Yeniden Çek'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
