import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';
import 'devil_soldier.dart';
import 'devil_king.dart';

/// Soldier lifecycle states.
enum SoldierState { alive, ghost, dead, burning }

/// Base class for all angel soldiers.
/// Extends SpriteComponent — loads default orb sprite via [loadVisuals()].
/// Subclasses override [loadVisuals()] to swap in custom sprites.
///
/// Ghost: swaps to `_ghostSprite` on death (via `SpriteComponent.render()`).
/// Revive: restores the original sprite from `_defaultSprite`.
abstract class AngelSoldier extends SpriteComponent {
  final String userId;
  final String username;
  double time = 0;
  int hp = 3;

  /// Walk speed in px/s. Override in subclass.
  double moveSpeed = 35.0;

  SoldierState state = SoldierState.alive;

  /// If non-null, walk toward this position instead of default upward.
  Vector2? moveTarget;

  // ── Revive state (reviver) ──
  Vector2? _reviveTarget;
  bool isReviving = false;
  bool _hasArrived = false;

  // ── Revive state (ghost) ──
  bool isBeingRevived = false;
  double reviveProgress = 0.0;
  double reviveBeamTimer = 0;

  // ── Cover / Bodyguard State ──
  AngelSoldier? coverTarget;
  bool get isCovering => coverTarget != null;

  // ── Sprites ──
  Sprite? _ghostSprite;
  Sprite? _defaultSprite;

  // ── Melee overrides ──
  bool get isMelee => false;
  double get meleeRange => 0;
  int get meleeDamage => 0;
  double get meleeInterval => 0;

  // ── Getters ──
  bool get isAlive => state == SoldierState.alive;
  bool get isActiveCombatant => state == SoldierState.alive && !isReviving && coverTarget == null;
  bool get hasArrivedAtGhost => isReviving && _hasArrived;
  int get maxHp => 3;

  AngelSoldier({required this.userId, required this.username})
      : super(size: Vector2(64, 64));

  Future<void> loadVisuals() async {
    sprite = await Sprite.load('default_soldier.png');
  }

  void onRevive() {}

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    anchor = Anchor.center;
    await loadVisuals();
    _defaultSprite = sprite;
    _ghostSprite = await Sprite.load('ghost_soul.png');
  }

  // ── Revive API ──

  void setReviveTarget(Vector2 ghostPosition) {
    _reviveTarget = ghostPosition.clone();
    isReviving = true;
    _hasArrived = false;
    moveTarget = ghostPosition.clone();
    coverTarget = null; // Clear guarding if starting a revive
  }

  void cancelRevive() {
    _reviveTarget = null;
    isReviving = false;
    _hasArrived = false;
    moveTarget = null;
    coverTarget = null; // Clear guard assignment upon cancel
  }

  void revive({bool fullHp = false}) {
    state = SoldierState.alive;
    hp = fullHp ? (maxHp + 2) : maxHp;
    moveTarget = null;
    _reviveTarget = null;
    isReviving = false;
    _hasArrived = false;
    isBeingRevived = false;
    reviveBeamTimer = 0;
    reviveProgress = 0;
    coverTarget = null;
    sprite = _defaultSprite;
    paint.color = const Color(0xFFFFFFFF);
    onRevive();
  }

  bool takeDamage(int amount) {
    if (state != SoldierState.alive) return false;
    hp -= amount;
    if (hp <= 0) {
      state = SoldierState.ghost;
      sprite = _ghostSprite;
      cancelRevive();
      return true;
    }
    return false;
  }

  // ── Update ──

  @override
  void update(double dt) {
    super.update(dt);

    if (state == SoldierState.dead) return;

    // 1. VISUAL LAYER SORTING (Z-INDEX)
    if (state == SoldierState.ghost) {
      priority = 1; // Drop ghosts completely flat to the floor beneath active units
      moveTarget = null;
      if (reviveBeamTimer > 0) reviveBeamTimer += dt;
      return;
    } else {
      priority = 100 + position.y.toInt(); // Re-sort sorting lines continuously
    }

    if (state == SoldierState.burning) return;
    time += dt;

    // 2. ANTI-STACKING (SEPARATION COMFORT NUDGES)
    if (state == SoldierState.alive) {
      Vector2 pushForce = Vector2.zero();
      int overlapCount = 0;

      final comrades = parent?.children.whereType<AngelSoldier>() ?? [];
      for (final other in comrades) {
        if (other == this || other.state != SoldierState.alive) continue;

        final dist = position.distanceTo(other.position);
        const personalSpaceRadius = 36.0;

        if (dist < personalSpaceRadius && dist > 0) {
          final pushDirection = (position - other.position)..normalize();
          pushDirection.scale(personalSpaceRadius - dist);
          pushForce += pushDirection;
          overlapCount++;
        }
      }
      if (overlapCount > 0) {
        position += pushForce * dt * 2.5;
      }
    }

    // 3. THE ACTIVE INTERCEPTOR PROTECTION MATRIX
    if (coverTarget != null) {
      if (!coverTarget!.isMounted || !coverTarget!.isAlive) {
        coverTarget = null; // Release bodyguard duties if target vanishes
      } else {
        // Collect all potential active threats on the map
        final enemies = parent?.children.where((c) =>
          (c is DevilSoldier && c.isActiveCombatant) ||
          (c is DevilKing && c.isMounted)
        ) ?? [];

        Component? closestThreat;
        double closestDist = double.infinity;

        // Find the closest threat to the person I am covering
        for (final enemy in enemies) {
          final enemyPos = (enemy as PositionComponent).position;
          final dist = coverTarget!.position.distanceTo(enemyPos);
          if (dist < closestDist) {
            closestDist = dist;
            closestThreat = enemy;
          }
        }

        if (closestThreat != null) {
          // STATE B: Threat Detected! Intercept and lock coordinates directly onto them
          moveTarget = (closestThreat as PositionComponent).position.clone();
        } else {
          // STATE A: Quiet Moments -> Arrive directly at the target's front (slightly above them)
          moveTarget = coverTarget!.position + Vector2(0, -35);
        }

        // Apply active translation drift movement
        if (moveTarget != null) {
          final dx = moveTarget!.x - position.x;
          final dy = moveTarget!.y - position.y;
          final dist = sqrt(dx * dx + dy * dy);
          if (dist > 5) {
            position.x += (dx / dist) * moveSpeed * dt;
            position.y += (dy / dist) * moveSpeed * dt;
          }
        }
        return; // Halt base up-marching logic
      }
    }

    // Revive movement
    if (isReviving) {
      if (!_hasArrived && _reviveTarget != null) {
        final dx = _reviveTarget!.x - position.x;
        final dy = _reviveTarget!.y - position.y;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist > 20) {
          position.x += (dx / dist) * moveSpeed * dt;
          position.y += (dy / dist) * moveSpeed * dt;
          moveTarget = _reviveTarget;
        } else {
          _hasArrived = true;
          _reviveTarget = null;
          moveTarget = position.clone();
        }
      }
      return;
    }

    // Normal combat movement
    if (moveTarget != null) {
      final dx = moveTarget!.x - position.x;
      final dy = moveTarget!.y - position.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist > 5) {
        position.x += (dx / dist) * moveSpeed * dt;
        position.y += (dy / dist) * moveSpeed * dt;
      }
    } else {
      position.y -= 25 * dt;
    }

    if (position.y < -50 || position.x < -50 || position.x > 770) {
      removeFromParent();
    }
  }

  // ── Render ──

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    if (state == SoldierState.dead) return;

    if (state == SoldierState.ghost) {
      if (reviveBeamTimer > 0) {
        renderReviveBeam(canvas);
        renderMagicCircle(canvas);
      } else if (isBeingRevived) {
        renderMagicCircle(canvas);
        renderReviveProgress(canvas, reviveProgress);
        renderGhostLabel(canvas);
      } else {
        renderGhostLabel(canvas);
      }
      return;
    }

    if (state == SoldierState.burning) return;

    // Alive — Name tag enclosed inside high-contrast capsule backgrounds
    final cx = size.x / 2;
    final ns = TextStyle(color: const Color(0xFFFFFFFF), fontSize: 9, fontWeight: FontWeight.bold);
    final tp = TextPainter(
      text: TextSpan(text: username.length > 7 ? '${username.substring(0, 7)}..' : username, style: ns),
      textDirection: TextDirection.ltr)..layout();

    final badgeX = cx - tp.width / 2;
    const badgeY = -28.0;

    final pillRect = Rect.fromLTWH(badgeX - 4, badgeY - 1, tp.width + 8, tp.height + 2);
    canvas.drawRRect(RRect.fromRectAndRadius(pillRect, const Radius.circular(4)), Paint()..color = const Color(0x99000000));
    tp.paint(canvas, Offset(badgeX, badgeY));

    // HP Bar safely padded downward to prevent crowding bounds
    canvas.drawRect(Rect.fromLTWH(cx - 12, -11, 24, 4), Paint()..color = const Color(0x66000000));
    if (hp > 0) {
      final hpRatio = hp / maxHp;
      final hpColor = hpRatio > 0.5 ? const Color(0xFF44AA44)
          : hpRatio > 0.25 ? const Color(0xFFCCAA22)
          : const Color(0xFFCC2222);
      canvas.drawRect(Rect.fromLTWH(cx - 12, -11, 24 * hpRatio, 4), Paint()..color = hpColor);
    }

    if (isReviving) renderMagicCircle(canvas);
  }

  // ── Render helpers ──

  void renderMagicCircle(Canvas canvas) {
    final cx = size.x / 2;
    final pulse = sin(time * 3.0) * 0.2 + 0.8;
    final rotation = time * 1.5;
    canvas.save();
    canvas.translate(cx, size.y - 4);
    canvas.rotate(rotation);
    for (int i = 0; i < 3; i++) {
      final r = 20.0 + i * 7.0 + sin(time * 2.0 + i) * 3.0;
      canvas.drawCircle(Offset.zero, r,
        Paint()..color = Color.fromRGBO(255, 200, 50, (pulse * 0.4 - i * 0.08).clamp(0.05, 0.5))
          ..style = PaintingStyle.stroke..strokeWidth = 2.0 - i * 0.4);
    }
    for (int i = 0; i < 4; i++) {
      final angle = pi / 2 * i + rotation;
      canvas.drawLine(Offset.zero, Offset(cos(angle) * 22, sin(angle) * 22),
        Paint()..color = Color.fromRGBO(255, 220, 100, pulse * 0.5)..strokeWidth = 1.5);
    }
    canvas.drawCircle(Offset.zero, 6 + sin(time * 4.0) * 2.0,
      Paint()..shader = RadialGradient(center: Alignment.center, radius: 1.0,
        colors: [const Color(0xCCFFDD44).withValues(alpha: pulse * 0.7), const Color(0x00000000)])
          .createShader(Rect.fromCircle(center: Offset.zero, radius: 10)));
    canvas.restore();
  }

  void renderReviveProgress(Canvas canvas, double progress) {
    final cx = size.x / 2;
    final barW = 30.0, barH = 4.0, barY = -8.0;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - barW/2, barY, barW, barH), const Radius.circular(2)),
      Paint()..color = const Color(0x66000000));
    final fill = barW * progress.clamp(0.0, 1.0);
    if (fill > 0) canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - barW/2, barY, fill, barH), const Radius.circular(2)),
      Paint()..shader = LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight,
        colors: const [Color(0xFFFFDD44), Color(0xFFFFFF88), Color(0xFFFFDD44)])
          .createShader(Rect.fromLTWH(cx - barW/2, barY, barW, barH)));
  }

  void renderReviveBeam(Canvas canvas) {
    final cx = size.x / 2;
    final bp = sin(time * 20.0) * 0.2 + 0.8;
    final bw = (sin(time * 20.0) * 6.0 + 24.0) * bp;
    canvas.drawRect(Rect.fromLTWH(cx - bw/2, -80, bw, size.y + 60),
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: const [Color(0x00FFDD44), Color(0x88FFEE88), Color(0xCCFFFFAA), Color(0x88FFEE88), Color(0x00FFDD44)])
          .createShader(Rect.fromLTWH(cx - bw/2, -80, bw, size.y + 60)));
    canvas.drawRect(Rect.fromLTWH(cx - bw, -80, bw * 2, size.y + 60),
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: const [Color(0x00000000), Color(0x44FFDD44), Color(0x00000000)])
          .createShader(Rect.fromLTWH(cx - bw, -80, bw * 2, size.y + 60)));
  }

  void renderGhostLabel(Canvas canvas) {
    final drift = sin(time * 1.2) * 2.0;
    canvas.save();
    canvas.translate(size.x / 2 + drift, 0);
    final ns = TextStyle(color: const Color(0xCCCCDDFF), fontSize: 9, fontWeight: FontWeight.bold);
    final tp = TextPainter(text: TextSpan(text: username, style: ns), textDirection: TextDirection.ltr)..layout();

    final pillRect = Rect.fromLTWH(-tp.width / 2 - 4, -14, tp.width + 8, tp.height + 2);
    canvas.drawRRect(RRect.fromRectAndRadius(pillRect, const Radius.circular(4)), Paint()..color = const Color(0x99000000));

    tp.paint(canvas, Offset(-tp.width / 2, -13));
    canvas.restore();
  }
}
