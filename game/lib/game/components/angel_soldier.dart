import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

/// Soldier lifecycle states.
enum SoldierState { alive, ghost, dead, burning }

/// Angel soldier — walks toward nearest devil, stops in range to shoot.
/// Can also walk to a ghost and perform a revive ritual.
class AngelSoldier extends PositionComponent {
  final String userId;
  final String username;
  double _time = 0;
  int hp = 3;

  SoldierState state = SoldierState.alive;

  /// If non-null, walk toward this position instead of default upward.
  Vector2? moveTarget;

  // ── Revive state (reviver — the soldier doing the revive) ──

  /// Position of the ghost this soldier is walking to revive.
  Vector2? _reviveTarget;

  /// True when this soldier is actively reviving a ghost.
  bool isReviving = false;

  /// True once the reviver has reached the ghost and is channeling.
  bool _hasArrived = false;

  // ── Revive state (ghost — being revived) ──

  /// Set by the game when a revive session targets this ghost.
  bool isBeingRevived = false;

  /// Revive progress 0.0-1.0, set by the game each frame.
  double reviveProgress = 0.0;

  /// Countdown for the UFO beam after revive completes.
  double reviveBeamTimer = 0;

  /// True when this soldier is alive (not ghost/burning/dead).
  /// Used for enemy targeting — revivers CAN be targeted and killed.
  bool get isAlive => state == SoldierState.alive;

  /// True when this soldier is an active combatant (alive and not reviving).
  /// Used for movement and shooting — revivers stand still.
  bool get isActiveCombatant => state == SoldierState.alive && !isReviving;

  /// True when the reviver has reached the ghost and is channeling.
  bool get hasArrivedAtGhost => isReviving && _hasArrived;

  AngelSoldier({required this.userId, required this.username})
      : super(size: Vector2(32, 40));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    anchor = Anchor.bottomCenter;
  }

  /// Tell this soldier to walk to a ghost and revive it.
  void setReviveTarget(Vector2 ghostPosition) {
    _reviveTarget = ghostPosition.clone();
    isReviving = true;
    _hasArrived = false;
    moveTarget = ghostPosition.clone();
  }

  /// Cancel the revive (e.g. reviver died).
  void cancelRevive() {
    _reviveTarget = null;
    isReviving = false;
    _hasArrived = false;
    moveTarget = null;
  }

  /// Called when the revive completes — restore this ghost to alive.
  void revive({bool fullHp = false}) {
    state = SoldierState.alive;
    hp = fullHp ? 5 : 3;
    moveTarget = null;
    _reviveTarget = null;
    isReviving = false;
    _hasArrived = false;
    isBeingRevived = false;
    reviveBeamTimer = 0;
    reviveProgress = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (state == SoldierState.dead) return;

    if (state == SoldierState.ghost) {
      moveTarget = null; // safety: stop any stale movement
      // Tick beam timer if active
      if (reviveBeamTimer > 0) {
        reviveBeamTimer += dt;
      }
      return;
    }

    if (state == SoldierState.burning) return;

    _time += dt;

    // ── Revive movement: walk to ghost or channel ──
    if (isReviving) {
      if (!_hasArrived && _reviveTarget != null) {
        // Walking toward the ghost
        final dx = _reviveTarget!.x - position.x;
        final dy = _reviveTarget!.y - position.y;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist > 20) {
          final speed = 35.0;
          position.x += (dx / dist) * speed * dt;
          position.y += (dy / dist) * speed * dt;
          moveTarget = _reviveTarget;
        } else {
          // Close enough — arrived, start channeling
          _hasArrived = true;
          _reviveTarget = null;
          moveTarget = position.clone();
        }
      }
      // If arrived (channeling), just stay still — don't cancel
      return;
    }

    // ── Normal combat movement ──
    if (moveTarget != null) {
      final dx = moveTarget!.x - position.x;
      final dy = moveTarget!.y - position.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist > 5) {
        final speed = 35.0;
        position.x += (dx / dist) * speed * dt;
        position.y += (dy / dist) * speed * dt;
      }
    } else {
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
      if (reviveBeamTimer > 0) {
        // UFO beam playing on the ghost
        _renderReviveBeam(canvas);
        _renderMagicCircle(canvas);
      } else if (isBeingRevived) {
        // Magic circle around the ghost during revive channel
        _renderMagicCircle(canvas);
        _renderReviveProgress(canvas, reviveProgress);
        _renderGhost(canvas);
      } else {
        _renderGhost(canvas);
      }
      return;
    }

    // Magic circle under the reviving soldier
    if (isReviving) {
      _renderMagicCircle(canvas);
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

  /// Golden anime-style magic circle on the ground.
  void _renderMagicCircle(Canvas canvas) {
    final cx = size.x / 2;
    final pulse = sin(_time * 3.0) * 0.2 + 0.8;
    final rotation = _time * 1.5;

    canvas.save();
    canvas.translate(cx, size.y - 4);
    canvas.rotate(rotation);

    // Golden concentric rings
    for (int i = 0; i < 3; i++) {
      final r = 20.0 + i * 7.0 + sin(_time * 2.0 + i) * 3.0;
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..color = Color.fromRGBO(
            255, 200, 50,
            (pulse * 0.4 - i * 0.08).clamp(0.05, 0.5),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 - i * 0.4,
      );
    }

    // Rune lines (4-point star)
    for (int i = 0; i < 4; i++) {
      final angle = pi / 2 * i + rotation;
      canvas.drawLine(
        Offset.zero,
        Offset(cos(angle) * 22, sin(angle) * 22),
        Paint()
          ..color = Color.fromRGBO(255, 220, 100, pulse * 0.5)
          ..strokeWidth = 1.5,
      );
    }

    // Center golden glow
    canvas.drawCircle(
      Offset.zero,
      6 + sin(_time * 4.0) * 2.0,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            const Color(0xCCFFDD44).withValues(alpha: pulse * 0.7),
            const Color(0x00000000),
          ],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 10)),
    );

    canvas.restore();
  }

  /// Progress bar for revive progress, rendered above the ghost.
  void _renderReviveProgress(Canvas canvas, double progress) {
    final cx = size.x / 2;
    final barWidth = 30.0;
    final barHeight = 4.0;
    final barY = -8.0; // above the ghost

    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - barWidth / 2, barY, barWidth, barHeight),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0x66000000),
    );

    // Fill
    final fillWidth = barWidth * progress.clamp(0.0, 1.0);
    if (fillWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - barWidth / 2, barY, fillWidth, barHeight),
          const Radius.circular(2),
        ),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [
              Color(0xFFFFDD44),
              Color(0xFFFFFF88),
              Color(0xFFFFDD44),
            ],
          ).createShader(Rect.fromLTWH(cx - barWidth / 2, barY, barWidth, barHeight)),
      );
    }
  }

  /// Big golden UFO-like beam on revive completion.
  void _renderReviveBeam(Canvas canvas) {
    final cx = size.x / 2;
    final beamPulse = sin(_time * 20.0) * 0.2 + 0.8;
    final beamWidth = (sin(_time * 20.0) * 6.0 + 24.0) * beamPulse;

    // Main golden beam (big as the magic circle)
    final beamRect = Rect.fromLTWH(cx - beamWidth / 2, -80, beamWidth, size.y + 60);
    canvas.drawRect(
      beamRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0x00FFDD44),
            Color(0x88FFEE88),
            Color(0xCCFFFFAA),
            Color(0x88FFEE88),
            Color(0x00FFDD44),
          ],
        ).createShader(beamRect),
    );

    // Outer golden glow
    canvas.drawRect(
      Rect.fromLTWH(cx - beamWidth, -80, beamWidth * 2, size.y + 60),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0x00000000),
            Color(0x44FFDD44),
            Color(0x00000000),
          ],
        ).createShader(Rect.fromLTWH(cx - beamWidth, -80, beamWidth * 2, size.y + 60)),
    );
  }

  void _renderGhost(Canvas canvas) {
    final cx = size.x / 2;
    final drift = sin(_time * 1.2) * 2.0;
    final twinkle = sin(_time * 2.0) * 0.05 + 0.4;

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

    final headY = size.y - 26;
    canvas.drawOval(
        Rect.fromLTWH(cx - 5 + drift, headY - 5, 10, 10),
        Paint()
          ..color = const Color(0x99CCDDFF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1));

    canvas.drawCircle(Offset(cx - 3 + drift, headY), 1.5,
        Paint()..color = const Color(0x88FFFFFF));
    canvas.drawCircle(Offset(cx + 3 + drift, headY), 1.5,
        Paint()..color = const Color(0x88FFFFFF));

    final nameStyle = TextStyle(
      color: const Color(0x88AACCFF),
      fontSize: 8,
      fontWeight: FontWeight.bold,
      shadows: [
        const Shadow(color: Color(0x44000000), blurRadius: 2, offset: Offset(1, 1))
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
