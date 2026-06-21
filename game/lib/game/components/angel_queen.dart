import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

/// The Angel Queen — permanent, stays at the bottom, does NOT fight.
/// If she dies = game over.
class AngelQueen extends PositionComponent {
  int hp = 80;
  final int maxHp = 80;

  AngelQueen() : super(size: Vector2(56, 80));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    anchor = Anchor.bottomCenter;
  }

  bool takeDamage(int amount) {
    hp -= amount;
    if (hp <= 0) {
      removeFromParent();
      return true;
    }
    return false;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final cx = size.x / 2;

    // Bright blue pedestal (pops against gold background)
    canvas.drawOval(
      Rect.fromLTWH(cx - 30, size.y - 4, 60, 14),
      Paint()..color = const Color(0xFF2255AA),
    );
    canvas.drawOval(
      Rect.fromLTWH(cx - 26, size.y - 6, 52, 10),
      Paint()..color = const Color(0xFF3377DD),
    );
    canvas.drawOval(
      Rect.fromLTWH(cx - 22, size.y - 8, 44, 8),
      Paint()..color = const Color(0xFF44AAFF),
    );

    // Blue glow aura
    final aura = Paint()
      ..shader = RadialGradient(
        center: Alignment.center, radius: 1.0,
        colors: [
          const Color(0x55AADDFF),
          const Color(0x00000000),
        ],
      ).createShader(const Rect.fromLTWH(-30, -76, 60, 80));
    canvas.drawRect(const Rect.fromLTWH(-30, -76, 60, 80), aura);

    // Body (white robes)
    final bodyPath = Path()
      ..moveTo(cx - 14, size.y - 6)
      ..lineTo(cx + 14, size.y - 6)
      ..lineTo(cx + 11, size.y - 36)
      ..lineTo(cx - 11, size.y - 36)
      ..close();
    canvas.drawPath(bodyPath, Paint()..color = const Color(0xFFFFF5E0));
    canvas.drawRect(Rect.fromLTWH(cx - 14, size.y - 6, 28, 3), Paint()..color = const Color(0xFFD4AF37));

    // Head
    final headY = size.y - 44;
    canvas.drawOval(Rect.fromLTWH(cx - 7, headY - 7, 14, 14), Paint()..color = const Color(0xFFFFE0BD));

    // Crown
    final crownPath = Path()
      ..moveTo(cx - 9, headY - 6)
      ..lineTo(cx - 7, headY - 14)
      ..lineTo(cx - 3, headY - 10)
      ..lineTo(cx, headY - 16)
      ..lineTo(cx + 3, headY - 10)
      ..lineTo(cx + 7, headY - 14)
      ..lineTo(cx + 9, headY - 6)
      ..close();
    canvas.drawPath(crownPath, Paint()..color = const Color(0xFFFFD700));
    canvas.drawPath(crownPath, Paint()
      ..color = const Color(0xFFDAA520)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);

    // Halo
    canvas.drawCircle(Offset(cx, headY - 12), 12, Paint()
      ..color = const Color(0x44AADDFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);

    // Eyes
    canvas.drawCircle(Offset(cx - 4, headY), 1.8, Paint()..color = const Color(0xFF88CCFF));
    canvas.drawCircle(Offset(cx + 4, headY), 1.8, Paint()..color = const Color(0xFF88CCFF));

    // Wings
    for (final flip in [-1, 1]) {
      final w = Path()
        ..moveTo(cx + flip * 10, size.y - 36)
        ..lineTo(cx + flip * 30, size.y - 20)
        ..lineTo(cx + flip * 26, size.y - 38)
        ..lineTo(cx + flip * 10, size.y - 28)
        ..close();
      canvas.drawPath(w, Paint()..color = const Color(0xFFF0E6D0));
      canvas.drawPath(w, Paint()
        ..color = const Color(0x44AADDFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1);
    }

    // Staff
    canvas.drawLine(Offset(cx + 20, size.y - 20), Offset(cx + 20, size.y - 64),
      Paint()..color = const Color(0xFFD4AF37)..strokeWidth = 2.5);
    canvas.drawCircle(Offset(cx + 20, size.y - 66), 6, Paint()..color = const Color(0xFFFFFF88));

    // Name label
    final nameStyle = TextStyle(
      color: const Color(0xFFFFFFFF),
      fontSize: 10,
      fontWeight: FontWeight.bold,
      shadows: [
        const Shadow(color: Color(0xFF000000), blurRadius: 3, offset: Offset(1, 1)),
      ],
    );
    final tp = TextPainter(
      text: TextSpan(text: "QUEEN", style: nameStyle),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, headY - 22));

    // HP bar
    const barW = 44.0;
    final barY = headY - 18;
    canvas.drawRect(Rect.fromLTWH(cx - barW / 2, barY, barW, 4), Paint()..color = const Color(0x88000000));
    canvas.drawRect(
      Rect.fromLTWH(cx - barW / 2, barY, barW * (hp / maxHp), 4),
      Paint()..color = const Color(0xFF44AA44),
    );
    canvas.drawRect(Rect.fromLTWH(cx - barW / 2, barY, barW, 4), Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }
}
