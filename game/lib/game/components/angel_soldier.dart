import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

/// Soldier lifecycle states.
enum SoldierState { alive, ghost, dead, burning }

/// Angel soldier — walks toward nearest devil, stops in range to shoot.
class AngelSoldier extends PositionComponent {
  final String userId;
  final String username;
  double _time = 0;
  int hp = 3;

  SoldierState state = SoldierState.alive;

 /// If non-null, walk toward this position instead of default upward.
  Vector2? moveTarget;

  /// True when this soldier is an active combatant (not ghost/burning/dead).
  bool get isActiveCombatant => state == SoldierState.alive;

  AngelSoldier({required this.userId, required this.username})
      : super(size: Vector2(32, 40));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    anchor = Anchor.bottomCenter;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (state == SoldierState.dead) return;

    if (state == SoldierState.ghost) {
      moveTarget = null; // safety: stop any stale movement
      // position stays exactly where it died — no floating
      return;
    }

    if (state == SoldierState.burning) return;

    _time += dt;

    if (moveTarget != null) {
      // Walk toward target
      final dx = moveTarget!.x - position.x;
      final dy = moveTarget!.y - position.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist > 5) {
        final speed = 35.0; // walk speed
        position.x += (dx / dist) * speed * dt;
        position.y += (dy / dist) * speed * dt;
      }
    } else {
      // No target — default move upward
      position.y -= 25 * dt;
    }

    if (position.y < -50 || position.x < -50 || position.x > 770) {
      removeFromParent();
    }
  }

  bool takeDamage(int amount) {
    if (state != SoldierState.alive) return false;
    hp -= amount;
    if (hp <= 0) {
      state = SoldierState.ghost;
      return true;
    }
    return false;
  }

  @override
  void render(Canvas canvas) {
    if (state == SoldierState.dead) return;

    if (state == SoldierState.ghost) {
      _renderGhost(canvas);
      return;
    }

    final cx = size.x / 2;
    final bob = sin(_time * 2.5) * 1.2;
    final wingFlap = sin(_time * 4.0) * 0.06;

    // Shadow
    canvas.drawOval(Rect.fromLTWH(cx - 8, size.y - 4 - bob, 16, 4),
        Paint()..color = const Color(0x44000000));

    // Body (white/gold tunic)
    final bodyPath = Path()
      ..moveTo(cx - 8, size.y - 6 - bob)
      ..lineTo(cx + 8, size.y - 6 - bob)
      ..lineTo(cx + 6, size.y - 20 - bob)
      ..lineTo(cx - 6, size.y - 20 - bob)
      ..close();
    canvas.drawPath(bodyPath, Paint()..color = const Color(0xFFF0E6C8));
    canvas.drawRect(
        Rect.fromLTWH(cx - 2, size.y - 18 - bob, 4, 10),
        Paint()..color = const Color(0x33FFFFFF));

    // Legs
    canvas.drawRect(Rect.fromLTWH(cx - 6, size.y - 6 - bob, 4, 4),
        Paint()..color = const Color(0xFFD4C5A9));
    canvas.drawRect(Rect.fromLTWH(cx + 2, size.y - 6 - bob, 4, 4),
        Paint()..color = const Color(0xFFD4C5A9));

    // Head
    final headY = size.y - 26 - bob;
    canvas.drawOval(Rect.fromLTWH(cx - 5, headY - 5, 10, 10),
        Paint()..color = const Color(0xFFFFE0BD));
    canvas.drawCircle(
        Offset(cx, headY - 8),
        5,
        Paint()
          ..color = const Color(0x33FFD700)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    canvas.drawCircle(Offset(cx - 3, headY), 1.2,
        Paint()..color = const Color(0xFF88CCFF));
    canvas.drawCircle(Offset(cx + 3, headY), 1.2,
        Paint()..color = const Color(0xFF88CCFF));

    // Wings
    for (final flip in [-1, 1]) {
      final w = Path()
        ..moveTo(cx + flip * 6, size.y - 20 - bob)
        ..lineTo(cx + flip * 18, size.y - 14 - bob + wingFlap * 6)
        ..lineTo(cx + flip * 15, size.y - 22 - bob + wingFlap * 3)
        ..lineTo(cx + flip * 6, size.y - 16 - bob)
        ..close();
      canvas.drawPath(w, Paint()..color = const Color(0xFFE8DDCC));
      canvas.drawPath(
          w,
          Paint()
            ..color = const Color(0x33FFD700)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8);
    }

    // Spear
    canvas.drawLine(
        Offset(cx - 8, size.y - 12 - bob),
        Offset(cx - 8, size.y - 42 - bob),
        Paint()..color = const Color(0xFFD4AF37)..strokeWidth = 1.5);
    final tipPath = Path()
      ..moveTo(cx - 8, size.y - 46 - bob)
      ..lineTo(cx - 11, size.y - 40 - bob)
      ..lineTo(cx - 5, size.y - 40 - bob)
      ..close();
    canvas.drawPath(tipPath, Paint()..color = const Color(0xFFFFFFCC));

    // Name label
    final nameStyle = TextStyle(
      color: const Color(0xFFFFFFFF),
      fontSize: 8,
      fontWeight: FontWeight.bold,
      shadows: [
        const Shadow(color: Color(0xFF000000), blurRadius: 2, offset: Offset(1, 1))
      ],
    );
    final tp = TextPainter(
      text: TextSpan(
          text: username.length > 6
              ? '${username.substring(0, 6)}..'
              : username,
          style: nameStyle),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, headY - 16));

    // HP bar
    if (hp < 3) {
      canvas.drawRect(Rect.fromLTWH(cx - 8, headY - 14, 16, 3),
          Paint()..color = const Color(0x66000000));
      canvas.drawRect(
          Rect.fromLTWH(cx - 8, headY - 14, 16 * (hp / 3), 3),
          Paint()..color = const Color(0xFF44AA44));
    }
  }

  void _renderGhost(Canvas canvas) {
    final cx = size.x / 2;
    final drift = sin(_time * 1.2) * 2.0; // gentle sway while floating
    final twinkle = sin(_time * 2.0) * 0.05 + 0.4; // flickering 0.35–0.45

    // Ghostly afterglow aura
    canvas.drawOval(
      Rect.fromLTWH(cx - 20, size.y - 10, 40, 12),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            const Color(0x33AACCFF).withValues(alpha: twinkle),
            const Color(0x00000000),
          ],
        ).createShader(Rect.fromLTWH(cx - 20, size.y - 10, 40, 12)),
    );

    // Translucent body (blue-white tint)
    final bodyPath = Path()
      ..moveTo(cx - 8 + drift, size.y - 6)
      ..lineTo(cx + 8 + drift, size.y - 6)
      ..lineTo(cx + 6 + drift, size.y - 20)
      ..lineTo(cx - 6 + drift, size.y - 20)
      ..close();
    canvas.drawPath(
        bodyPath,
        Paint()
          ..color = const Color(0x99AACCFF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));

    // Ghostly head
    final headY = size.y - 26;
    canvas.drawOval(
        Rect.fromLTWH(cx - 5 + drift, headY - 5, 10, 10),
        Paint()
          ..color = const Color(0x99CCDDFF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1));

    // Faint glowing eyes
    canvas.drawCircle(Offset(cx - 3 + drift, headY), 1.5,
        Paint()..color = const Color(0x88FFFFFF));
    canvas.drawCircle(Offset(cx + 3 + drift, headY), 1.5,
        Paint()..color = const Color(0x88FFFFFF));

    // Name label (faded)
    final nameStyle = TextStyle(
      color: const Color(0x88AACCFF),
      fontSize: 8,
      fontWeight: FontWeight.bold,
      shadows: [
        const Shadow(
            color: Color(0x44000000), blurRadius: 2, offset: Offset(1, 1))
      ],
    );
    final tp = TextPainter(
      text: TextSpan(
          text: username.length > 6
              ? '${username.substring(0, 6)}..'
              : username,
          style: nameStyle),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(cx + drift - tp.width / 2, headY - 16));

    // Wispy particles floating upward
    for (int i = 0; i < 3; i++) {
      final phase = _time * 1.5 + i * 2.1;
      final px = cx + drift + sin(phase) * 8;
      final py = size.y - 30 - (phase % 25);
      canvas.drawCircle(
          Offset(px, py),
          1.0,
          Paint()
            ..color = const Color(0x44CCDDFF)
                .withValues(alpha: (sin(phase) * 0.5 + 0.5) * 0.4));
    }
  }
}
