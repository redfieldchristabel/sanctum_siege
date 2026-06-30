import 'dart:math';
import 'package:flame/components.dart';

import 'angel_soldier.dart';

/// Angel Knight — melee-class soldier with pixel art sprite.
/// Has 8 rotation directions for idle/walk, a Fight animation for attacks,
/// and a Revive animation for the revive ritual.
class AngelKnight extends AngelSoldier {
  // 8 rotation sprites, indexed by direction:
  // 0=east, 1=south-east, 2=south, 3=south-west,
  // 4=west, 5=north-west, 6=north, 7=north-east
  final List<Sprite> _dirSprites = [];

  /// Fight (sword swing) animation frames — north-facing, 9 frames.
  final List<Sprite> _fightFrames = [];

  /// Revive ritual animation frames — south-facing, 9 frames.
  final List<Sprite> _reviveFrames = [];

  int _currentDir = 6; // start facing north (toward Demon King)

  // Animation state machine
  bool _isAttacking = false;
  double _attackTimer = 0;
  bool _isAnimatingRevive = false;
  double _reviveTimer = 0;

  static const double attackDuration = 0.6;
  static const double reviveDuration = 0.9;

  AngelKnight({required super.userId, required super.username}) {
    hp = 15;
    moveSpeed = 40.0;
    size = Vector2(184, 184);
  }

  @override
  bool get isMelee => true;

  @override
  int get maxHp => 15;

  @override
  double get meleeRange => 40.0;

  @override
  int get meleeDamage => 2;

  @override
  double get meleeInterval => 0.8;

  @override
  Future<void> loadVisuals() async {
    // Load 8 rotation sprites (order matches atan2 mapping)
    const dirNames = [
      'east', 'south-east', 'south', 'south-west',
      'west', 'north-west', 'north', 'north-east',
    ];
    for (final name in dirNames) {
      _dirSprites.add(await Sprite.load('angel_knight/rotations/$name.png'));
    }

    // Load Fight (sword swing) frames
    for (int i = 0; i < 9; i++) {
      _fightFrames.add(
        await Sprite.load(
          'angel_knight/fight/frame_${i.toString().padLeft(3, '0')}.png',
        ),
      );
    }

    // Load Revive ritual frames
    for (int i = 0; i < 9; i++) {
      _reviveFrames.add(
        await Sprite.load(
          'angel_knight/revive/frame_${i.toString().padLeft(3, '0')}.png',
        ),
      );
    }

    sprite = _dirSprites[6]; // north-facing (toward Demon King)
  }

  /// Pick the closest direction sprite based on movement angle.
  void _updateDirection() {
    if (moveTarget == null) return;
    final dx = moveTarget!.x - position.x;
    final dy = moveTarget!.y - position.y;
    if (dx.abs() < 1 && dy.abs() < 1) return;

    // atan2 returns -pi..pi. Normalize to 0..2pi, split into 8 sectors.
    final a = (atan2(dy, dx) + pi * 2) % (pi * 2);
    _currentDir = ((a + pi / 8) / (pi / 4)).floor() % 8;
  }

  /// Called by the game when the knight lands a melee hit.
  void triggerAttack() {
    if (!_isAttacking && !_isAnimatingRevive) {
      _isAttacking = true;
      _attackTimer = 0;
    }
  }

  /// Called by the base when this soldier starts reviving a ghost.
  void triggerReviveAnim() {
    if (!_isAnimatingRevive) {
      _isAnimatingRevive = true;
      _reviveTimer = 0;
    }
  }

  @override
  void onRevive() {
    _isAttacking = false;
    _isAnimatingRevive = false;
  }

  @override
  void setReviveTarget(Vector2 ghostPosition) {
    super.setReviveTarget(ghostPosition);
    triggerReviveAnim();
  }

  @override
  void cancelRevive() {
    super.cancelRevive();
    _isAnimatingRevive = false;
    sprite = _dirSprites[_currentDir];
  }

  /// Get the sprite for the current frame in a frame list.
  int _getFrameIndex(double elapsed, double duration, int frameCount) {
    return ((elapsed / duration) * frameCount).floor().clamp(0, frameCount - 1);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (state != SoldierState.alive) return;

    if (_isAnimatingRevive) {
      // Play revive animation
      _reviveTimer += dt;
      final idx = _getFrameIndex(_reviveTimer, reviveDuration, _reviveFrames.length);
      sprite = _reviveFrames[idx];
      if (_reviveTimer >= reviveDuration) {
        _isAnimatingRevive = false;
        sprite = _dirSprites[_currentDir];
      }
    } else if (_isAttacking) {
      // Play fight (sword swing) animation
      _attackTimer += dt;
      final idx = _getFrameIndex(_attackTimer, attackDuration, _fightFrames.length);
      sprite = _fightFrames[idx];
      if (_attackTimer >= attackDuration) {
        _isAttacking = false;
        sprite = _dirSprites[_currentDir];
      }
    } else {
      // Static directional sprite based on movement
      _updateDirection();
      sprite = _dirSprites[_currentDir];
    }
  }
}
