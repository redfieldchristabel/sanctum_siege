import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

/// A projectile that flies toward a target position.
/// Angels fire holy bolts (light), devils fire dark bolts.
class Projectile extends PositionComponent {
  final double _vx, _vy;
  final bool _isAngel;

  Projectile._({
    required double startX,
    required double startY,
    required double targetX,
    required double targetY,
    required bool isAngel,
    double speed = 280,
  })  : _isAngel = isAngel,
        _vx = _calcDx(startX, startY, targetX, targetY, speed),
        _vy = _calcDy(startX, startY, targetX, targetY, speed),
        super(size: Vector2(20, 28)) {
    position = Vector2(startX, startY);
    angle = atan2(targetY - startY, targetX - startX) + pi / 2;
  }

  factory Projectile.angel({
    required double startX, required double startY,
    required double targetX, required double targetY,
  }) {
    return Projectile._(
      startX: startX, startY: startY,
      targetX: targetX, targetY: targetY,
      isAngel: true, speed: 280,
    );
  }

  factory Projectile.devil({
    required double startX, required double startY,
    required double targetX, required double targetY,
  }) {
    return Projectile._(
      startX: startX, startY: startY,
      targetX: targetX, targetY: targetY,
      isAngel: false, speed: 220,
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
    position.x += _vx * dt;
    position.y += _vy * dt;
    if (position.y < -40 || position.y > 1320 || position.x < -40 || position.x > 760) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.rotate(angle);

    if (_isAngel) {
      // Big golden bolt with glow
      final glow = Paint()
        ..shader = RadialGradient(
          center: Alignment.center, radius: 1.0,
          colors: [
            const Color(0x66FFFF44),
            const Color(0x00000000),
          ],
        ).createShader(const Rect.fromLTWH(-16, -18, 32, 36));
      canvas.drawRect(const Rect.fromLTWH(-16, -18, 32, 36), glow);

      final body = Paint()..color = const Color(0xFFFFFF66);
      canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(-4, -14, 8, 28), const Radius.circular(4)), body);
      canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(-2, -12, 4, 24), const Radius.circular(2)),
        Paint()..color = const Color(0xFFFFFFFF));
      // Tip glow
      canvas.drawCircle(const Offset(0, -14), 5, Paint()..color = const Color(0x66FFFF88));
    } else {
      // Dark red bolt
      final body = Paint()..color = const Color(0xFFFF4422);
      canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(-4, -14, 8, 28), const Radius.circular(4)), body);
      canvas.drawRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(-2, -12, 4, 24), const Radius.circular(2)),
        Paint()..color = const Color(0xFFFF6644));
      // Tip glow
      canvas.drawCircle(const Offset(0, -14), 5, Paint()..color = const Color(0x66FF2200));
    }

    canvas.restore();
  }
}
