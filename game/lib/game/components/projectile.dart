import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

/// A projectile that flies toward a target position.
/// Bigger, brighter, with a visible trail so it's easy to see on stream.
class Projectile extends PositionComponent {
  final double _vx, _vy;
  final bool _isAngel;
  double _lifetime = 0;

  Projectile._({
    required double startX,
    required double startY,
    required double targetX,
    required double targetY,
    required bool isAngel,
    double speed = 320,
  })  : _isAngel = isAngel,
        _vx = _calcDx(startX, startY, targetX, targetY, speed),
        _vy = _calcDy(startX, startY, targetX, targetY, speed),
        super(size: Vector2(32, 40)) {
    position = Vector2(startX, startY);
    angle = atan2(targetY - startY, targetX - startX) + pi / 2;
    anchor = Anchor.center;
  }

  factory Projectile.angel({
    required double startX, required double startY,
    required double targetX, required double targetY,
  }) {
    return Projectile._(
      startX: startX, startY: startY,
      targetX: targetX, targetY: targetY,
      isAngel: true, speed: 320,
    );
  }

  factory Projectile.devil({
    required double startX, required double startY,
    required double targetX, required double targetY,
  }) {
    return Projectile._(
      startX: startX, startY: startY,
      targetX: targetX, targetY: targetY,
      isAngel: false, speed: 260,
    );
  }

  static double _calcDx(double sx, double sy, double tx, double ty, double s) {
    final dx = tx - sx;
    final dy = ty - sy;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < 1) return 0;
    return (dx / dist) * s;
  }

  static double _calcDy(double sx, double sy, double tx, double ty, double s) {
    final dx = tx - sx;
    final dy = ty - sy;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < 1) return 0;
    return (dy / dist) * s;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _lifetime += dt;
    position.x += _vx * dt;
    position.y += _vy * dt;
    // Remove when fully off-screen (with buffer for projectile size)
    if (position.x < -60 || position.x > 780 || position.y < -60 || position.y > 1340) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.save();
    canvas.translate(0, 0);
    canvas.rotate(angle);

    final glowAlpha = (sin(_lifetime * 12) * 0.3 + 0.5).clamp(0.2, 0.8);

    if (_isAngel) {
      // ── Trail glow ──
      final trail = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0x00FFF44F),
            const Color(0x55FFF44F),
            const Color(0x00FFF44F),
          ],
        ).createShader(const Rect.fromLTWH(-4, -30, 8, 60));
      canvas.drawRect(const Rect.fromLTWH(-4, -30, 8, 60), trail);

      // ── Outer glow ──
      final glow = Paint()
        ..shader = RadialGradient(
          center: Alignment.center, radius: 1.0,
          colors: [
            Color.fromRGBO(255, 255, 100, glowAlpha),
            const Color(0x00000000),
          ],
        ).createShader(const Rect.fromLTWH(-18, -22, 36, 44));
      canvas.drawRect(const Rect.fromLTWH(-18, -22, 36, 44), glow);

      // ── Bolt body ──
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-5, -18, 10, 36), const Radius.circular(5)),
        Paint()..color = const Color(0xFFFFDD44));

      // ── Bright core ──
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-2, -15, 4, 30), const Radius.circular(2)),
        Paint()..color = const Color(0xFFFFFFAA));

      // ── Tip spark ──
      canvas.drawCircle(const Offset(0, -18), 6,
        Paint()..color = Color.fromRGBO(255, 255, 150, glowAlpha));
    } else {
      // ── Trail glow (dark red) ──
      final trail = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0x00FF4422),
            const Color(0x55FF4422),
            const Color(0x00FF4422),
          ],
        ).createShader(const Rect.fromLTWH(-4, -30, 8, 60));
      canvas.drawRect(const Rect.fromLTWH(-4, -30, 8, 60), trail);

      // ── Outer glow ──
      final glow = Paint()
        ..shader = RadialGradient(
          center: Alignment.center, radius: 1.0,
          colors: [
            Color.fromRGBO(255, 68, 34, glowAlpha * 0.8),
            const Color(0x00000000),
          ],
        ).createShader(const Rect.fromLTWH(-18, -22, 36, 44));
      canvas.drawRect(const Rect.fromLTWH(-18, -22, 36, 44), glow);

      // ── Bolt body ──
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-5, -18, 10, 36), const Radius.circular(5)),
        Paint()..color = const Color(0xFFFF4422));

      // ── Bright core ──
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-2, -15, 4, 30), const Radius.circular(2)),
        Paint()..color = const Color(0xFFFF8866));

      // ── Tip spark ──
      canvas.drawCircle(const Offset(0, -18), 6,
        Paint()..color = Color.fromRGBO(255, 100, 50, glowAlpha));
    }

    canvas.restore();
  }
}
