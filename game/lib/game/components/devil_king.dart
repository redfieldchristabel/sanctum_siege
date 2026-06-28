import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

/// The Devil King — permanent, stays at the top, very aggressive.
/// Fires rapidly (400px range, 0.6s). When he dies = player wins.
class DevilKing extends PositionComponent {
  int hp = 100;
  final int maxHp = 100;

  DevilKing() : super(size: Vector2(56, 68));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    anchor = Anchor.bottomCenter;
    scale = Vector2.all(2.0);
  }

  @override
  void update(double dt) {
    super.update(dt);
    priority = 100 + position.y.toInt();
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

    // Red platform (pops against dark sky)
    canvas.drawOval(
      Rect.fromLTWH(cx - 30, size.y - 4, 60, 14),
      Paint()..color = const Color(0xFF882222),
    );
    canvas.drawOval(
      Rect.fromLTWH(cx - 26, size.y - 6, 52, 10),
      Paint()..color = const Color(0xFFCC3333),
    );
    canvas.drawOval(
      Rect.fromLTWH(cx - 22, size.y - 8, 44, 8),
      Paint()..color = const Color(0xFFFF4444),
    );

    // Name label
    final nameStyle = TextStyle(
      color: const Color(0xFFFFFFFF),
      fontSize: 10,
      fontWeight: FontWeight.bold,
      shadows: [const Shadow(color: Color(0xFF000000), blurRadius: 3, offset: Offset(1, 1))],
    );
    final tp = TextPainter(
      text: TextSpan(text: "DEVIL KING", style: nameStyle),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, size.y - 58));

    // Dark aura
    final aura = Paint()
      ..shader = RadialGradient(
        center: Alignment.center, radius: 1.0,
        colors: [const Color(0x33AA0000), const Color(0x00000000)],
      ).createShader(Rect.fromLTWH(cx - 30, size.y - 70, 60, 70));
    canvas.drawRect(Rect.fromLTWH(cx - 30, size.y - 70, 60, 70), aura);

    // Body (dark armor)
    final bodyPath = Path()
      ..moveTo(cx - 16, size.y - 6)
      ..lineTo(cx + 16, size.y - 6)
      ..lineTo(cx + 13, size.y - 38)
      ..lineTo(cx - 13, size.y - 38)
      ..close();
    canvas.drawPath(bodyPath, Paint()..color = const Color(0xFF1A0A0A));

    // Armor plate
    canvas.drawRect(Rect.fromLTWH(cx - 10, size.y - 32, 20, 18), Paint()..color = const Color(0xFF2A1515));
    canvas.drawRect(Rect.fromLTWH(cx - 10, size.y - 32, 20, 2), Paint()..color = const Color(0xFF8B6914));
    canvas.drawRect(Rect.fromLTWH(cx - 10, size.y - 14, 20, 2), Paint()..color = const Color(0xFF8B6914));

    // Shoulder pauldrons
    canvas.drawRect(Rect.fromLTWH(cx - 19, size.y - 34, 6, 8), Paint()..color = const Color(0xFF2A1515));
    canvas.drawRect(Rect.fromLTWH(cx + 13, size.y - 34, 6, 8), Paint()..color = const Color(0xFF2A1515));

    // Head
    final headY = size.y - 46;
    canvas.drawOval(Rect.fromLTWH(cx - 8, headY - 8, 16, 16), Paint()..color = const Color(0xFFCC8866));

    // Crown (spiky, dark)
    final crownPath = Path()
      ..moveTo(cx - 10, headY - 7)
      ..lineTo(cx - 8, headY - 16)
      ..lineTo(cx - 4, headY - 11)
      ..lineTo(cx, headY - 18)
      ..lineTo(cx + 4, headY - 11)
      ..lineTo(cx + 8, headY - 16)
      ..lineTo(cx + 10, headY - 7)
      ..close();
    canvas.drawPath(crownPath, Paint()..color = const Color(0xFF8B0000));
    canvas.drawPath(crownPath, Paint()
      ..color = const Color(0xFFFF4400)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);

    // Eyes (intense red)
    canvas.drawCircle(Offset(cx - 5, headY), 2.5, Paint()..color = const Color(0xFFFF0000));
    canvas.drawCircle(Offset(cx + 5, headY), 2.5, Paint()..color = const Color(0xFFFF0000));
    final eyeGlow = Paint()
      ..shader = RadialGradient(
        center: Alignment.center, radius: 1.0,
        colors: [const Color(0x44FF0000), const Color(0x00000000)],
      ).createShader(Rect.fromLTWH(cx - 12, headY - 6, 24, 12));
    canvas.drawRect(Rect.fromLTWH(cx - 12, headY - 6, 24, 12), eyeGlow);

    // Wings (large, bat-like)
    for (final flip in [-1, 1]) {
      final w = Path()
        ..moveTo(cx + flip * 12, size.y - 36)
        ..lineTo(cx + flip * 34, size.y - 14)
        ..lineTo(cx + flip * 28, size.y - 40)
        ..lineTo(cx + flip * 12, size.y - 28)
        ..close();
      canvas.drawPath(w, Paint()..color = const Color(0xFF0A0000));
      canvas.drawPath(w, Paint()
        ..color = const Color(0x44AA0000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1);
    }

    // Scepter
    canvas.drawLine(Offset(cx - 22, size.y - 20), Offset(cx - 22, size.y - 64),
      Paint()..color = const Color(0xFF4A3A2A)..strokeWidth = 2.5);
    canvas.drawCircle(Offset(cx - 22, size.y - 66), 5, Paint()..color = const Color(0xFFFF0000));
    final gemGlow = Paint()
      ..shader = RadialGradient(
        center: Alignment.center, radius: 1.0,
        colors: [const Color(0x66FF0000), const Color(0x00000000)],
      ).createShader(Rect.fromLTWH(cx - 28, size.y - 72, 12, 12));
    canvas.drawCircle(Offset(cx - 22, size.y - 66), 5, gemGlow);

    // HP bar
    const barW = 44.0;
    canvas.drawRect(Rect.fromLTWH(cx - barW / 2, size.y + 6, barW, 5), Paint()..color = const Color(0x66000000));
    canvas.drawRect(Rect.fromLTWH(cx - barW / 2, size.y + 6, barW * (hp / maxHp), 5), Paint()..color = const Color(0xFFCC2222));
    canvas.drawRect(Rect.fromLTWH(cx - barW / 2, size.y + 6, barW, 5), Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }
}
