import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:eokul_fotograf/services/image_processing_service.dart';
import 'package:eokul_fotograf/services/storage_service.dart';

void main() {
  group('e-Okul standartları', () {
    test('çıktı boyutu tam 3:4 oranındadır', () {
      expect(
        ImageProcessingService.targetWidth / ImageProcessingService.targetHeight,
        closeTo(0.75, 1e-9),
      );
    });

    test('dosya boyutu aralığı 20 KB – 50 KB', () {
      expect(ImageProcessingService.minBytes, 20 * 1024);
      // Üst sınır 50 KB'ın altında kalmalı (e-Okul sınırı).
      expect(ImageProcessingService.maxBytes, lessThan(50 * 1024));
      expect(
        ImageProcessingService.maxBytes,
        greaterThan(ImageProcessingService.minBytes),
      );
    });
  });

  group('Kılavuz çerçeve geometrisi', () {
    test('çerçeve 3:4 oranını korur', () {
      final frame = GuideGeometry.frameInside(
        const Rect.fromLTWH(0, 0, 1080, 2400),
      );
      expect(frame.width / frame.height, closeTo(3 / 4, 1e-6));
    });

    test('çerçeve ekran içinde kalır', () {
      const area = Rect.fromLTWH(0, 0, 720, 1280);
      final frame = GuideGeometry.frameInside(area);

      expect(frame.left, greaterThanOrEqualTo(0));
      expect(frame.top, greaterThanOrEqualTo(0));
      expect(frame.right, lessThanOrEqualTo(area.width));
      expect(frame.bottom, lessThanOrEqualTo(area.height));
    });

    test('yatay ekranda çerçeve taşmaz', () {
      const area = Rect.fromLTWH(0, 0, 2400, 1080);
      final frame = GuideGeometry.frameInside(area);
      expect(frame.height, lessThanOrEqualTo(area.height));
      expect(frame.width / frame.height, closeTo(3 / 4, 1e-6));
    });
  });

  group('Sınıf adı temizleme', () {
    test('geçerli adlar korunur', () {
      expect(StorageService.sanitizeClassName('5-A'), '5-A');
      expect(StorageService.sanitizeClassName('8/B'), '8-B');
    });

    test('Türkçe karakterler ASCII karşılığına çevrilir', () {
      expect(StorageService.sanitizeClassName('5-Şube'), '5-Sube');
      expect(StorageService.sanitizeClassName('ÇĞİÖŞÜ'), 'CGIOSU');
      expect(StorageService.sanitizeClassName('5-ığ'), '5-ig');
    });

    test('geçersiz karakterler tireye dönüşür', () {
      expect(StorageService.sanitizeClassName('5/A!!'), '5-A');
      expect(StorageService.sanitizeClassName('5...A'), '5-A');
    });

    test('boş girdi güvenli varsayılana döner', () {
      expect(StorageService.sanitizeClassName(''), 'Sinif');
      expect(StorageService.sanitizeClassName('   '), 'Sinif');
      expect(StorageService.sanitizeClassName('///'), 'Sinif');
    });
  });
}
