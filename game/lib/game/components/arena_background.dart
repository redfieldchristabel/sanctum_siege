import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

/// Procedural pixel-art-style arena background.
/// 5 vertical zones, drawn at 720×1280 on a fixed viewport.
///
/// Once real sprites arrive (via Gemini), replace this with
/// a SpriteComponent loading `assets/images/arena_background.png`.
class ArenaBackground extends PositionComponent {
  ArenaBackground() : super(size: Vector2(720, 1280));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    _drawSky(canvas);            // y: 0 – 250
    _drawRamparts(canvas);        // y: 250 – 400
    _drawBattlefield(canvas);     // y: 400 – 800
    _drawSanctuary(canvas);       // y: 800 – 1100
    _drawBastion(canvas);         // y: 1100 – 1280
  }

  // ─── Zone 1: Devil Sky ──────────────────────────────────────

  void _drawSky(Canvas c) {
    _gradientRect(c, 0, 250, const Color(0xFF1A0303), const Color(0xFF2D0A08));

    // Blood moon (subtle)
    final moonPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.3, 0.15),
        radius: 0.08,
        colors: [
          const Color(0x66FF2222),
          const Color(0x33CC0000),
          const Color(0x00000000),
        ],
      ).createShader(const Rect.fromLTWH(0, 0, 720, 250));
    c.drawRect(const Rect.fromLTWH(0, 0, 720, 250), moonPaint);

    // Storm wisps
    var rng = Random(42);
    for (int i = 0; i < 12; i++) {
      final x = rng.nextDouble() * 720;
      final y = rng.nextDouble() * 200;
      final w = 20 + rng.nextDouble() * 60;
      final alpha = (30 + rng.nextDouble() * 40).toInt();
      c.drawOval(
        Rect.fromLTWH(x, y, w, 6 + rng.nextDouble() * 8),
        Paint()..color = Color.fromARGB(alpha, 60, 10, 10),
      );
    }

    // Tiny stars (reddish)
    rng = Random(7);
    for (int i = 0; i < 40; i++) {
      final x = rng.nextDouble() * 720;
      final y = rng.nextDouble() * 200;
      final r = 1.0 + rng.nextDouble() * 1.5;
      c.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = Color.fromARGB(
          80 + rng.nextInt(80),
          200 + rng.nextInt(55),
          40 + rng.nextInt(30),
          30 + rng.nextInt(30),
        ),
      );
    }
  }

  // ─── Zone 2: Devil Ramparts ─────────────────────────────────

  void _drawRamparts(Canvas c) {
    // Main wall
    _gradientRect(c, 250, 400, const Color(0xFF3D2B1F), const Color(0xFF332218));

    // Horizontal stone lines
    for (double y = 260; y < 400; y += 14) {
      c.drawLine(
        Offset(0, y),
        Offset(720, y),
        Paint()
          ..color = const Color(0x15443322)
          ..strokeWidth = 1,
      );
    }

    // Vertical stone cracks
    for (double x = 15; x < 720; x += 35 + Random(9).nextDouble() * 20) {
      c.drawLine(
        Offset(x, 260),
        Offset(x, 390),
        Paint()
          ..color = const Color(0x0A221100)
          ..strokeWidth = 1,
      );
    }

    // Battlement wall top
    c.drawRect(
      const Rect.fromLTWH(0, 248, 720, 4),
      Paint()..color = const Color(0xFF5C3A21),
    );

    // Battlement teeth
    for (double x = 10; x < 720; x += 60) {
      c.drawRect(
        Rect.fromLTWH(x, 250, 20, 12),
        Paint()..color = const Color(0xFF5A4A3A),
      );
      // Tooth highlight
      c.drawRect(
        Rect.fromLTWH(x + 2, 251, 16, 3),
        Paint()..color = const Color(0x22664433),
      );
    }

    // Glowing rune / light at rampart center
    final runePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, 0.5),
        radius: 0.3,
        colors: [
          const Color(0x44FF4400),
          const Color(0x00000000),
        ],
      ).createShader(const Rect.fromLTWH(300, 280, 120, 80));
    c.drawRect(const Rect.fromLTWH(300, 280, 120, 80), runePaint);
  }

  // ─── Zone 3: Muddy Battlefield ──────────────────────────────

  void _drawBattlefield(Canvas c) {
    _gradientRect(c, 400, 800, const Color(0xFF5C4033), const Color(0xFF4A3020));

    // Ground line separator
    c.drawRect(
      const Rect.fromLTWH(0, 400, 720, 3),
      Paint()..color = const Color(0xFF6B5030),
    );
    c.drawRect(
      const Rect.fromLTWH(0, 403, 720, 1),
      Paint()..color = const Color(0xFF3A2515),
    );

    // Dirt path texture (wider center)
    _gradientRect(c, 410, 790, const Color(0x15553A25), const Color(0x00000000));

    // Scattered rocks
    var rng = Random(13);
    for (int i = 0; i < 30; i++) {
      final x = 20 + rng.nextDouble() * 680;
      final y = 420 + rng.nextDouble() * 360;
      final size = 3 + rng.nextDouble() * 7;
      c.drawOval(
        Rect.fromLTWH(x, y, size, size * 0.7),
        Paint()..color = Color.fromARGB(
          100 + rng.nextInt(80),
          60 + rng.nextInt(30),
          50 + rng.nextInt(20),
          40 + rng.nextInt(20),
        ),
      );
    }

    // Grass tufts
    rng = Random(21);
    for (int i = 0; i < 25; i++) {
      final x = 10 + rng.nextDouble() * 700;
      final y = 430 + rng.nextDouble() * 350;
      _drawGrassTuft(c, x, y, rng);
    }

    // Dead tree stump (decorative, non-interactive)
    _drawStump(c, 580, 520);
    _drawStump(c, 140, 680);

    // Crude wooden stakes / spikes at transition zone
    for (double x = 80; x < 720; x += 130) {
      final spikeH = 10 + Random(x.toInt()).nextDouble() * 8;
      c.drawRect(
        Rect.fromLTWH(x, 410 - spikeH, 3, spikeH),
        Paint()..color = const Color(0xFF4A3520),
      );
      c.drawRect(
        Rect.fromLTWH(x - 1, 410 - spikeH, 5, 2),
        Paint()..color = const Color(0xFF6A5540),
      );
    }
  }

  // ─── Zone 4: Angel Sanctuary ────────────────────────────────

  void _drawSanctuary(Canvas c) {
    _gradientRect(c, 800, 1100, const Color(0xFFD4C5A9), const Color(0xFFC8B898));

    // Ground line
    c.drawRect(
      const Rect.fromLTWH(0, 800, 720, 2),
      Paint()..color = const Color(0xFFB8A888),
    );

    // Holy radiance (central glow) — dimmed so units are visible
    final holyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, 0.6),
        radius: 0.35,
        colors: [
          const Color(0x33FFFFDD),
          const Color(0x18FFF8DC),
          const Color(0x00000000),
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(const Rect.fromLTWH(200, 830, 320, 250));
    c.drawRect(const Rect.fromLTWH(200, 830, 320, 250), holyPaint);

    // Light rays
    for (double angle = -0.3; angle <= 0.3; angle += 0.12) {
      final rayPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.center,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0x22FFFFCC),
            const Color(0x00000000),
          ],
        ).createShader(Rect.fromLTWH(300, 850, 120, 200));
      c.save();
      c.translate(360, 850);
      c.rotate(angle);
      c.translate(-360, -850);
      c.drawRect(Rect.fromLTWH(300, 850, 120, 200), rayPaint);
      c.restore();
    }

    // Small sparkling dots
    final rng = Random(31);
    for (int i = 0; i < 25; i++) {
      final x = 80 + rng.nextDouble() * 560;
      final y = 830 + rng.nextDouble() * 230;
      final r = 1.0 + rng.nextDouble() * 2.0;
      c.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = Color.fromARGB(
          60 + rng.nextInt(100),
          255, 255, 200 + rng.nextInt(55),
        ),
      );
    }
  }

  // ─── Zone 5: Golden Bastion ─────────────────────────────────

  void _drawBastion(Canvas c) {
    _gradientRect(c, 1100, 1280, const Color(0xFF8B7355), const Color(0xFF7A6345));

    // Golden trim line
    c.drawRect(
      const Rect.fromLTWH(0, 1098, 720, 4),
      Paint()..color = const Color(0xFFD4AF37),
    );
    c.drawRect(
      const Rect.fromLTWH(0, 1102, 720, 1),
      Paint()..color = const Color(0xFFB8962F),
    );

    // Marble/stone texture lines
    for (double y = 1110; y < 1275; y += 20) {
      c.drawLine(
        Offset(0, y),
        Offset(720, y),
        Paint()
          ..color = const Color(0x157A6345)
          ..strokeWidth = 1,
      );
    }

    // Pillars
    for (double x = 30; x < 720; x += 120) {
      // Pillar body
      c.drawRect(
        Rect.fromLTWH(x, 1100, 14, 65),
        Paint()..color = const Color(0xFF9B8365),
      );
      // Pillar highlight
      c.drawRect(
        Rect.fromLTWH(x + 2, 1100, 3, 65),
        Paint()..color = const Color(0x33BBA080),
      );
      // Pillar shadow
      c.drawRect(
        Rect.fromLTWH(x + 11, 1100, 3, 65),
        Paint()..color = const Color(0x33443322),
      );
      // Pillar capital
      c.drawRect(
        Rect.fromLTWH(x - 2, 1098, 18, 5),
        Paint()..color = const Color(0xFFB8962F),
      );
      c.drawRect(
        Rect.fromLTWH(x - 4, 1163, 22, 4),
        Paint()..color = const Color(0xFF8B7355),
      );
    }

    // Decorative arch hints between pillars
    for (double x = 30; x < 720; x += 120) {
      final arcPaint = Paint()
        ..color = const Color(0x22D4AF37)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      c.drawArc(
        Rect.fromLTWH(x - 5, 1100, 24, 20),
        pi,
        pi,
        false,
        arcPaint,
      );
    }

    // Base floor line
    c.drawRect(
      const Rect.fromLTWH(0, 1275, 720, 5),
      Paint()..color = const Color(0xFF6A5535),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────

  void _gradientRect(Canvas c, double y1, double y2, Color top, Color bottom) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [top, bottom],
      ).createShader(Rect.fromLTWH(0, y1, 720, y2 - y1));
    c.drawRect(Rect.fromLTWH(0, y1, 720, y2 - y1), paint);
  }

  void _drawGrassTuft(Canvas c, double x, double y, Random rng) {
    for (int i = 0; i < 3; i++) {
      final dx = (rng.nextDouble() - 0.5) * 6;
      final dh = -(4 + rng.nextDouble() * 8);
      c.drawLine(
        Offset(x + dx, y),
        Offset(x + dx, y + dh),
        Paint()
          ..color = Color.fromARGB(
            100 + rng.nextInt(80),
            40 + rng.nextInt(30),
            70 + rng.nextInt(30),
            20 + rng.nextInt(15),
          )
          ..strokeWidth = 1.5,
      );
    }
  }

  void _drawStump(Canvas c, double x, double y) {
    // Dark oval stump
    c.drawOval(
      Rect.fromLTWH(x - 8, y - 3, 16, 10),
      Paint()..color = const Color(0xFF3A2515),
    );
    // Top ring
    c.drawOval(
      Rect.fromLTWH(x - 7, y - 4, 14, 5),
      Paint()..color = const Color(0xFF5A4535),
    );
    // Inner ring
    c.drawOval(
      Rect.fromLTWH(x - 4, y - 3, 8, 3),
      Paint()..color = const Color(0xFF3A2515),
    );
  }
}
