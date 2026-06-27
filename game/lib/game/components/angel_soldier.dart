import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

/// Soldier lifecycle states.
enum SoldierState { alive, ghost, dead, burning }

/// Base class for all angel soldiers.
/// Extends SpriteComponent — loads default orb sprite via [loadVisuals()].
/// Subclasses override [loadVisuals()] to swap in custom sprites.
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

  // ── Ghost sprite ──
  Sprite? _ghostSprite;

  // ── Melee overrides ──
  bool get isMelee => false;
  double get meleeRange => 0;
  int get meleeDamage => 0;
  double get meleeInterval => 0;

  // ── Getters ──
  bool get isAlive => state == SoldierState.alive;
  bool get isActiveCombatant => state == SoldierState.alive && !isReviving;
  bool get hasArrivedAtGhost => isReviving && _hasArrived;

  AngelSoldier({required this.userId, required this.username})
      : super(size: Vector2(64, 64));

  /// Override in subclass to load a custom sprite (e.g. sprite sheet).
  /// Default: loads the floating orb placeholder.
  Future<void> loadVisuals() async {
    sprite = await Sprite.load('default_soldier.png');
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    anchor = Anchor.bottomCenter;
    await loadVisuals();
    _ghostSprite = await Sprite.load('ghost_soul.png');
  }

  // ── Revive API ──

  void setReviveTarget(Vector2 ghostPosition) {
    _reviveTarget = ghostPosition.clone();
    isReviving = true;
    _hasArrived = false;
    moveTarget = ghostPosition.clone();
  }

  void cancelRevive() {
    _reviveTarget = null;
    isReviving = false;
    _hasArrived = false;
    moveTarget = null;
  }

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

  bool takeDamage(int amount) {
    if (state != SoldierState.alive) return false;
    hp -= amount;
    if (hp <= 0) {
      state = SoldierState.ghost;
      return true;
    }
    return false;
  }

  // ── Update ──

  @override
  void update(double dt) {
    super.update(dt);

    if (state == SoldierState.dead) return;

    if (state == SoldierState.ghost) {
      moveTarget = null;
      if (reviveBeamTimer > 0) reviveBeamTimer += dt;
      return;
    }

    if (state == SoldierState.burning) return;

    time += dt;

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

  // ── Render — sprite is drawn by SpriteComponent.render() ──
  // Overlays (name, HP, magic circle, ghost) go in afterChildrenRendered.

  @override
  void afterChildrenRendered(Canvas canvas) {
    if (state == SoldierState.dead) return;

    if (state == SoldierState.ghost) {
      if (reviveBeamTimer > 0) {
        renderReviveBeam(canvas);
        renderMagicCircle(canvas);
      } else if (isBeingRevived) {
        renderMagicCircle(canvas);
        renderReviveProgress(canvas, reviveProgress);
        renderGhost(canvas);
      } else {
        renderGhost(canvas);
      }
      return;
    }

    if (state == SoldierState.burning) return;

    // Alive — name label
    final cx = size.x / 2;
    final ns = TextStyle(
      color: const Color(0xFFFFFFFF), fontSize: 8, fontWeight: FontWeight.bold,
      shadows: [const Shadow(color: Color(0xFF000000), blurRadius: 2, offset: Offset(1, 1))]);
    final tp = TextPainter(
      text: TextSpan(text: username.length > 6 ? '${username.substring(0, 6)}..' : username, style: ns),
      textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, size.y - 80));

    // HP bar
    if (hp < 3) {
      canvas.drawRect(Rect.fromLTWH(cx - 8, size.y - 76, 16, 3), Paint()..color = const Color(0x66000000));
      canvas.drawRect(Rect.fromLTWH(cx - 8, size.y - 76, 16 * (hp / 3), 3), Paint()..color = const Color(0xFF44AA44));
    }

    if (isReviving) renderMagicCircle(canvas);
  }

  // ── Render helpers (public for subclass access) ──

  /// Golden anime-style magic circle.
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

  /// Progress bar above ghost.
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

  /// Big golden UFO beam.
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

  /// Ghost soul sprite — drawn with translucency on top of the soldier's sprite.
  void renderGhost(Canvas canvas) {
    if (_ghostSprite == null) return;
    final cx = size.x / 2;
    final drift = sin(time * 1.2) * 2.0;
    final twinkle = sin(time * 2.0) * 0.05 + 0.4;
    canvas.save();
    canvas.translate(cx + drift, size.y);
    _ghostSprite!.render(
      canvas,
      size: size,
      overridePaint: Paint()..color = const Color(0x99AACCFF).withValues(alpha: twinkle),
    );
    // Ghost name label
    final ns = TextStyle(color: const Color(0x88AACCFF), fontSize: 8, fontWeight: FontWeight.bold,
      shadows: [const Shadow(color: Color(0x44000000), blurRadius: 2, offset: Offset(1, 1))]);
    final tp = TextPainter(text: TextSpan(text: username.length > 6 ? '${username.substring(0, 6)}..' : username, style: ns), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -size.y - 8));
    canvas.restore();
  }
}
