import 'package:flutter/material.dart';

import '../services/storage_service.dart';

/// Ana ekrandaki sınıf kartı: ad, fotoğraf sayısı ve hızlı eylemler.
class ClassCard extends StatelessWidget {
  final ClassFolder folder;
  final VoidCallback onTap;
  final VoidCallback onCapture;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const ClassCard({
    super.key,
    required this.folder,
    required this.onTap,
    required this.onCapture,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasPhotos = folder.photoCount > 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.groups_rounded,
                      color: scheme.onPrimaryContainer,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folder.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          hasPhotos
                              ? '${folder.photoCount} öğrenci fotoğrafı'
                              : 'Henüz fotoğraf çekilmedi',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: hasPhotos
                                ? scheme.onSurfaceVariant
                                : scheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Seçenekler',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (value) {
                      switch (value) {
                        case 'share':
                          onShare();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'share',
                        enabled: hasPhotos,
                        child: const ListTile(
                          leading: Icon(Icons.folder_zip_rounded),
                          title: Text('ZIP Olarak Paylaş'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(
                            Icons.delete_outline_rounded,
                            color: scheme.error,
                          ),
                          title: Text(
                            'Sınıfı Sil',
                            style: TextStyle(color: scheme.error),
                          ),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: onCapture,
                      icon: const Icon(Icons.photo_camera_rounded, size: 19),
                      label: const Text(
                        'Fotoğraf Çek',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: hasPhotos ? onShare : null,
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text(
                        'ZIP / Paylaş',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: 'Sınıfı aç',
                    onPressed: onTap,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
