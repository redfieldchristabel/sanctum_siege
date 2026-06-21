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
        super(size: Vector2(6, 12)) {
    position = Vector2(startX, startY);
    angle = atan2(targetY - startY, targetX - startX) + pi / 2;
  }

  /// Create an angel projectile (light bolt).
  factory Projectile.angel({
    required double startX,
    required double startY,
    required double targetX,
    required double targetY,
  }) {
    return Projectile._(
      startX: startX,
      startY: startY,
      targetX: targetX,
      targetY: targetY,
      isAngel: true,
      speed: 280,
    );
  }

  /// Create a devil projectile (dark bolt).
  factory Projectile.devil({
    required double startX,
    required double startY,
    required double targetX,
    required double targetY,
  }) {
    return Projectile._(
      startX: startX,
      startY: startY,
      targetX: targetX,
      targetY: targetY,
      isAngel: false,
      speed: 220,
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
    if (position.y < -30 || position.y > 1310 || position.x < -30 || position.x > 750) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    if (_isAngel) {
      // Golden light bolt
      final glow = Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            const Color(0x44FFFF88),
            const Color(0x00000000),
          ],
        ).createShader(Rect.fromLTWH(-8, -10, 16, 20));
      canvas.drawRect(Rect.fromLTWH(-8, -10, 16, 20), glow);
      canvas.drawOval(Rect.fromLTWH(-3, -6, 6, 12), Paint()..color = const Color(0xFFFFFF88));
      canvas.drawOval(Rect.fromLTWH(-1.5, -4, 3, 8), Paint()..color = const Color(0xFFFFFFFF));
    } else {
      // Dark red bolt
      canvas.drawOval(Rect.fromLTWH(-3, -6, 6, 12), Paint()..color = const Color(0xFFFF4400));
      canvas.drawOval(Rect.fromLTWH(-1.5, -4, 3, 8), Paint()..color = const Color(0xFFFF2200));
    }
  }
}
