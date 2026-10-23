import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../services/zip_share_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/class_card.dart';
import 'camera_screen.dart';
import 'class_detail_screen.dart';

/// Ekran 1 — Sınıf yönetimi.
///
/// Sınıflar diskteki klasörlerden okunur; fotoğraf sayısı canlı olarak
/// klasör içeriğinden gelir. Ayrı bir veritabanı gerekmez.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final StorageService _storage = StorageService.instance;
  final ZipShareService _zip = ZipShareService.instance;

  List<ClassFolder> _classes = const <ClassFolder>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final classes = await _storage.loadClasses();
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Sınıflar yüklenemedi: $e';
        _loading = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Eylemler
  // ---------------------------------------------------------------------------

  Future<void> _addClass() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _AddClassDialog(),
    );
    if (name == null || !mounted) return;

    final created = await _storage.createClass(name);
    if (!mounted) return;

    if (!created) {
      AppSnackbar.warning(
        context,
        'Bu isimde bir sınıf zaten var.',
      );
      return;
    }

    await _load();
    if (!mounted) return;

    final folder = await _storage.loadClass(name);
    if (folder == null || !mounted) return;

    AppSnackbar.success(context, '${folder.name} sınıfı oluşturuldu.');
  }

  Future<void> _deleteClass(ClassFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${folder.name} sınıfını sil'),
        content: Text(
          folder.photoCount == 0
              ? 'Bu sınıf klasörü silinecek.'
              : 'Bu sınıftaki ${folder.photoCount} fotoğraf da kalıcı olarak '
                  'silinecek. Bu işlem geri alınamaz.',
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

    await _storage.deleteClass(folder.name);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    AppSnackbar.success(context, '${folder.name} silindi.');
  }

  Future<void> _shareClass(ClassFolder folder) async {
    if (folder.photoCount == 0) {
      AppSnackbar.warning(context, 'Bu sınıfta henüz fotoğraf yok.');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BusyDialog(message: 'ZIP arşivi hazırlanıyor…'),
    );

    try {
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 1, 1);

      final result = await _zip.shareClass(
        folder,
        sharePositionOrigin: origin,
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${result.photoCount} fotoğraf ZIP olarak hazırlandı '
            '(${result.sizeInMb.toStringAsFixed(1)} MB).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      AppSnackbar.error(context, 'ZIP oluşturulamadı: $e');
    }
  }

  Future<void> _openClass(ClassFolder folder) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClassDetailScreen(className: folder.name),
      ),
    );
    await _load();
  }

  Future<void> _openCamera(ClassFolder folder) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CameraScreen(className: folder.name),
      ),
    );
    await _load();
  }

  // ---------------------------------------------------------------------------
  // Arayüz
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalPhotos =
        _classes.fold<int>(0, (sum, c) => sum + c.photoCount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('e-Okul Vesikalık'),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(theme, totalPhotos),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addClass,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Yeni Sınıf Ekle'),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, int totalPhotos) {
    if (_loading && _classes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Icon(
            Icons.error_outline_rounded,
            size: 56,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tekrar Dene'),
            ),
          ),
        ],
      );
    }

    if (_classes.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 120),
        children: [
          const SizedBox(height: 88),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.groups_2_rounded,
              size: 46,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Henüz sınıf eklenmedi',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Başlamak için sağ alttaki “Yeni Sınıf Ekle” düğmesine dokunun '
            've örneğin 5-A yazın. Sonra sınıfın içinden öğrencilerin '
            'vesikalık fotoğraflarını çekebilirsiniz.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      itemCount: _classes.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
            child: Row(
              children: [
                _StatChip(
                  icon: Icons.school_rounded,
                  label: '${_classes.length} sınıf',
                ),
                const SizedBox(width: 8),
                _StatChip(
                  icon: Icons.photo_camera_rounded,
                  label: '$totalPhotos fotoğraf',
                ),
              ],
            ),
          );
        }

        final folder = _classes[index - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ClassCard(
            folder: folder,
            onTap: () => _openClass(folder),
            onCapture: () => _openCamera(folder),
            onShare: () => _shareClass(folder),
            onDelete: () => _deleteClass(folder),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Yardımcı widget'lar
// -----------------------------------------------------------------------------

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Yeni sınıf adı soran diyalog. "5-A" gibi kısa adlar önerilir.
class _AddClassDialog extends StatefulWidget {
  const _AddClassDialog();

  @override
  State<_AddClassDialog> createState() => _AddClassDialogState();
}

class _AddClassDialogState extends State<_AddClassDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  static final RegExp _pattern =
      RegExp(r'^[0-9]{1,2}\s*[-/ ]?\s*[A-Za-zÇĞİÖŞÜçğıöşü]{1,3}$');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Sınıf adı boş olamaz.');
      return;
    }
    if (!_pattern.hasMatch(raw)) {
      setState(() {
        _error = 'Örnek biçim: 5-A, 8/B, 12 A';
      });
      return;
    }
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Yeni Sınıf Ekle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sınıf adını girin. Bu ad, cihazdaki klasör adı olarak da '
            'kullanılacak.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Sınıf adı',
              hintText: '5-A',
              errorText: _error,
              prefixIcon: const Icon(Icons.class_rounded),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Oluştur'),
        ),
      ],
    );
  }
}

/// İşlem sürerken gösterilen basit modal.
class _BusyDialog extends StatelessWidget {
  final String message;

  const _BusyDialog({required this.message});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 18),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
