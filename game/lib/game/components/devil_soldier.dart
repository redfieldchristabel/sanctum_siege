import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import 'angel_soldier.dart'; // for SoldierState enum

/// Devil soldier — walks toward nearest angel, stops in range to shoot.
/// When killed: burns for 7 seconds, then despawns. No revive.
class DevilSoldier extends PositionComponent {
  final double _phase;
  double _time = 0;
  int hp;

  SoldierState state = SoldierState.alive;
  double _deathTimer = 0;
  static const double burnDuration = 7.0;

  /// If non-null, walk toward this position instead of default downward.
  Vector2? moveTarget;

  /// True when this soldier is an active combatant (not ghost/burning/dead).
  bool get isActiveCombatant => state == SoldierState.alive;

  DevilSoldier({required double phase, this.hp = 3})
      : _phase = phase,
        super(size: Vector2(40, 48));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    anchor = Anchor.bottomCenter;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (state == SoldierState.dead) return;

    // ── Burning death: on fire for 7s, then gone ──
    if (state == SoldierState.burning) {
      moveTarget = null; // stop any movement
      _deathTimer += dt;
      if (_deathTimer >= burnDuration) {
        state = SoldierState.dead;
        removeFromParent();
      }
      return;
    }

    if (state == SoldierState.ghost) {
      // Legacy ghost — should not happen for devils, but handle gracefully
      _deathTimer += dt;
      position.y += 10 * dt;
      if (_deathTimer >= burnDuration) {
        state = SoldierState.dead;
        removeFromParent();
      }
      return;
    }

    _time += dt;

    if (moveTarget != null) {
      // Walk toward target
      final dx = moveTarget!.x - position.x;
      final dy = moveTarget!.y - position.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist > 5) {
        final speed = 30.0;
        position.x += (dx / dist) * speed * dt;
        position.y += (dy / dist) * speed * dt;
      }
    } else {
      // No target — default move downward
      position.y += 25 * dt;
    }

    if (position.y > 1350 || position.x < -50 || position.x > 770) {
      removeFromParent();
    }
  }

  bool takeDamage(int amount) {
    if (state != SoldierState.alive) return false;
    hp -= amount;
    if (hp <= 0) {
      state = SoldierState.burning;
      _deathTimer = 0;
      return true;
    }
    return false;
  }

  @override
  void render(Canvas canvas) {
    if (state == SoldierState.dead) return;

    if (state == SoldierState.burning) {
      _renderBurning(canvas);
      return;
    }

    if (state == SoldierState.ghost) {
      _renderBurning(canvas); // reuse fire render as fallback
      return;
    }

    final cx = size.x / 2;
    final bob = sin(_time * 2.0 + _phase) * 1.5;
    final wingUp = sin(_time * 3.0 + _phase) * 0.05;

    // Shadow
    canvas.drawOval(Rect.fromLTWH(cx - 10, size.y - 4 - bob, 20, 6),
        Paint()..color = const Color(0x44000000));

    // Body
    final bodyPath = Path()
      ..moveTo(cx - 10, size.y - 6 - bob)
      ..lineTo(cx + 10, size.y - 6 - bob)
      ..lineTo(cx + 7, size.y - 24 - bob)
      ..lineTo(cx - 7, size.y - 24 - bob)
      ..close();
    canvas.drawPath(bodyPath, Paint()..color = const Color(0xFF2A1A1A));
    canvas.drawRect(Rect.fromLTWH(cx - 3, size.y - 22 - bob, 6, 14),
        Paint()..color = const Color(0x1A443333));

    // Legs
    canvas.drawRect(Rect.fromLTWH(cx - 8, size.y - 6 - bob, 6, 4),
        Paint()..color = const Color(0xFF1A0A0A));
    canvas.drawRect(Rect.fromLTWH(cx + 2, size.y - 6 - bob, 6, 4),
        Paint()..color = const Color(0xFF1A0A0A));

    // Head
    final headY = size.y - 30 - bob;
    final headPath = Path()
      ..moveTo(cx, headY - 8)
      ..lineTo(cx + 8, headY)
      ..lineTo(cx + 8, headY + 6)
      ..lineTo(cx - 8, headY + 6)
      ..lineTo(cx - 8, headY)
      ..close();
    canvas.drawPath(headPath, Paint()..color = const Color(0xFFCC8866));
    final helmPath = Path()
      ..moveTo(cx, headY - 10)
      ..lineTo(cx + 10, headY - 4)
      ..lineTo(cx + 10, headY + 2)
      ..lineTo(cx - 10, headY + 2)
      ..lineTo(cx - 10, headY - 4)
      ..close();
    canvas.drawPath(helmPath, Paint()..color = const Color(0xFF3A2A1A));

    // Eyes
    canvas.drawCircle(Offset(cx - 4, headY + 1), 1.8,
        Paint()..color = const Color(0xFFFF2200));
    canvas.drawCircle(Offset(cx + 4, headY + 1), 1.8,
        Paint()..color = const Color(0xFFFF2200));
    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [const Color(0x66FF4400), const Color(0x00000000)],
      ).createShader(Rect.fromLTWH(cx - 8, headY - 3, 16, 8));
    canvas.drawRect(Rect.fromLTWH(cx - 8, headY - 3, 16, 8), glowPaint);

    // Wings
    for (final flip in [-1, 1]) {
      final w = Path()
        ..moveTo(cx + flip * 7, size.y - 24 - bob)
        ..lineTo(cx + flip * 22, size.y - 16 - bob + wingUp * 8)
        ..lineTo(cx + flip * 18, size.y - 26 - bob + wingUp * 4)
        ..lineTo(cx + flip * 7, size.y - 18 - bob)
        ..close();
      canvas.drawPath(w, Paint()..color = const Color(0xFF1A0A0A));
      canvas.drawPath(
          w,
          Paint()
            ..color = const Color(0x33AA0000)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }

    // Spear
    canvas.drawLine(
        Offset(cx + 12, size.y - 14 - bob),
        Offset(cx + 12, size.y - 48 - bob),
        Paint()..color = const Color(0xFF6A4A2A)..strokeWidth = 2);
    final tipPath = Path()
      ..moveTo(cx + 12, size.y - 52 - bob)
      ..lineTo(cx + 9, size.y - 46 - bob)
      ..lineTo(cx + 15, size.y - 46 - bob)
      ..close();
    canvas.drawPath(tipPath, Paint()..color = const Color(0xFFCCCCCC));

    // HP bar
    if (hp < 3) {
      canvas.drawRect(Rect.fromLTWH(cx - 10, headY - 14, 20, 3),
          Paint()..color = const Color(0x66000000));
      canvas.drawRect(
          Rect.fromLTWH(cx - 10, headY - 14, 20 * (hp / 3), 3),
          Paint()..color = const Color(0xFFCC2222));
    }
  }

  /// Render the devil burning in flames before despawn.
  void _renderBurning(Canvas canvas) {
    final cx = size.x / 2;
    final progress = (_deathTimer / burnDuration).clamp(0.0, 1.0);
    final fade = 1.0 - progress * 0.7; // slowly fade out
    final flicker = sin(_deathTimer * 15.0) * 0.15 + 0.85;
    final sway = sin(_deathTimer * 3.0) * 2.0;

    // Heat shimmer aura (orange-red glow expanding outward)
    final auraRadius = 16.0 + progress * 12.0;
    canvas.drawOval(
      Rect.fromLTWH(cx - auraRadius, size.y - 20 - auraRadius / 2,
          auraRadius * 2, auraRadius),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            const Color(0x44FF6600).withValues(alpha: flicker * 0.6 * fade),
            const Color(0x00000000),
          ],
        ).createShader(Rect.fromLTWH(
            cx - auraRadius, size.y - 20 - auraRadius / 2,
            auraRadius * 2, auraRadius)),
    );

    // Flame body (overlapping triangles)
    final flameCount = 4;
    for (int i = 0; i < flameCount; i++) {
      final flamePhase = _deathTimer * 8.0 + i * 1.5;
      final height = (10.0 + sin(flamePhase) * 4.0) * fade;
      final width = 4.0 + sin(flamePhase * 1.3) * 2.0;
      final fx = cx - 8 + (16.0 / (flameCount - 1)) * i + sway;
      final fy = size.y - 6;
      final flamePath = Path()
        ..moveTo(fx, fy)
        ..lineTo(fx - width, fy + height)
        ..lineTo(fx + width, fy + height)
        ..close();
      canvas.drawPath(
          flamePath,
          Paint()
            ..color = Color.fromRGBO(
              255,
              (120 + sin(flamePhase) * 60).toInt(),
              0,
              flicker * 0.7 * fade,
            ));
    }

    // Core ember glow
    canvas.drawCircle(
      Offset(cx + sway, size.y - 10),
      6.0 * fade,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            const Color(0xCCFFEE44).withValues(alpha: flicker * fade),
            const Color(0x44FF6600).withValues(alpha: flicker * 0.5 * fade),
            const Color(0x00000000),
          ],
        ).createShader(Rect.fromCircle(
            center: Offset(cx + sway, size.y - 10), radius: 6.0)),
    );

    // Rising ember particles
    for (int i = 0; i < 5; i++) {
      final phase = _deathTimer * 4.0 + i * 1.3;
      final px = cx + sway + sin(phase * 1.7) * 12;
      final py = size.y - 20 - (phase * 8 % 40);
      canvas.drawCircle(
        Offset(px, py),
        1.5 + sin(phase) * 0.8,
        Paint()
          ..color = Color.fromRGBO(
            255,
            (180 + sin(phase * 1.3) * 60).toInt(),
            0,
            (sin(phase) * 0.5 + 0.5) * 0.6 * fade,
          ),
      );
    }

    // Spark flash at death moment
    if (progress < 0.15) {
      final flashIntensity = (1.0 - progress / 0.15) * 0.4;
      canvas.drawCircle(
        Offset(cx + sway, size.y - 10),
        12.0,
        Paint()
          ..color = const Color(0xFFFFFFFF)
              .withValues(alpha: flashIntensity),
      );
    }
  }
}
