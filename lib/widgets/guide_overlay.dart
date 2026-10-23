import 'package:flutter/material.dart';

import '../services/image_processing_service.dart';

/// Kameranın üstüne çizilen yarı saydam vesikalık maskesi.
///
/// * Dışarısı karartılır, içerisi net kalır.
/// * 3:4 dikey çerçeve + köşe nişanları.
/// * Baş üstü, çene ve omuz hizasını gösteren kesikli yardımcı çizgiler.
/// * Çerçeve geometrisi [GuideGeometry] ile hesaplanır — kırpma da aynı
///   fonksiyonu kullandığı için ekranda gördüğünüz alan birebir kaydedilir.
class GuideOverlay extends StatelessWidget {
  final String? instruction;

  const GuideOverlay({super.key, this.instruction});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = Rect.fromLTWH(
          0,
          0,
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final frame = GuideGeometry.frameInside(screen);

        return Stack(
          children: [
            // Karartma (çerçevenin dışı).
            Positioned.fill(
              child: CustomPaint(
                painter: _ScrimPainter(frame: frame),
              ),
            ),

            // Çerçeve, köşeler ve rehber çizgiler.
            Positioned.fromRect(
              rect: frame,
              child: CustomPaint(
                painter: _FramePainter(),
              ),
            ),

            // Baş / çene hizası etiketleri.
            Positioned(
              left: frame.left,
              top: frame.top + frame.height * 0.18 - 9,
              child: const _LineLabel(text: 'Baş üstü'),
            ),
            Positioned(
              left: frame.left,
              top: frame.top + frame.height * 0.72 - 9,
              child: const _LineLabel(text: 'Çene'),
            ),

            // Yönerge metni.
            if (instruction != null)
              Positioned(
                left: 24,
                right: 24,
                top: frame.bottom + 18,
                child: Text(
                  instruction!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(blurRadius: 8, color: Colors.black54),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LineLabel extends StatelessWidget {
  final String text;

  const _LineLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Çerçeve dışını karartır, içini tamamen saydam bırakır.
class _ScrimPainter extends CustomPainter {
  final Rect frame;

  _ScrimPainter({required this.frame});

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
        RRect.fromRectAndRadius(frame, const Radius.circular(20)),
      )
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.58),
    );
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter oldDelegate) =>
      oldDelegate.frame != frame;
}

/// Çerçeve çizgileri, köşe nişanları ve yüz hizalama kılavuzları.
class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Ana çerçeve.
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(20)),
      border,
    );

    // Köşe nişanları (daha kalın, vurgulu).
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;

    const len = 26.0;
    const r = 20.0;

    // Sol üst
    canvas.drawLine(Offset(0, r + len), Offset(0, r), corner);
    canvas.drawLine(Offset(r, 0), Offset(r + len, 0), corner);

    // Sağ üst
    canvas.drawLine(Offset(size.width - r - len, 0), Offset(size.width - r, 0), corner);
    canvas.drawLine(Offset(size.width, r), Offset(size.width, r + len), corner);

    // Sol alt
    canvas.drawLine(Offset(0, size.height - r - len), Offset(0, size.height - r), corner);
    canvas.drawLine(Offset(r, size.height), Offset(r + len, size.height), corner);

    // Sağ alt
    canvas.drawLine(
      Offset(size.width - r - len, size.height),
      Offset(size.width - r, size.height),
      corner,
    );
    canvas.drawLine(
      Offset(size.width, size.height - r - len),
      Offset(size.width, size.height - r),
      corner,
    );

    // Yüz hizalama kılavuzları (kesikli).
    _dashedLine(
      canvas,
      Offset(0, size.height * 0.18),
      Offset(size.width, size.height * 0.18),
    );
    _dashedLine(
      canvas,
      Offset(0, size.height * 0.72),
      Offset(size.width, size.height * 0.72),
    );

    // Omuz hizası (çeneden sonra, daha soluk).
    _dashedLine(
      canvas,
      Offset(size.width * 0.10, size.height * 0.86),
      Offset(size.width * 0.90, size.height * 0.86),
      opacity: 0.35,
    );

    // Çene altı oval önerisi — hafif, yüzü ortalamaya yardımcı.
    final oval = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.18);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.45),
        width: size.width * 0.52,
        height: size.height * 0.54,
      ),
      oval,
    );
  }

  void _dashedLine(
    Canvas canvas,
    Offset from,
    Offset to, {
    double opacity = 0.45,
  }) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    const dash = 7.0;
    const gap = 6.0;

    final total = (to - from).distance;
    if (total <= 0) return;
    final direction = (to - from) / total;

    var travelled = 0.0;
    while (travelled < total) {
      final end = (travelled + dash).clamp(0.0, total);
      canvas.drawLine(
        from + direction * travelled,
        from + direction * end,
        paint,
      );
      travelled += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
