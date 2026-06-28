import 'package:flame/components.dart';

import 'angel_soldier.dart';

/// Angel Knight — melee-class soldier with pixel art sprite.
/// Uses sword-slashing attack animation instead of projectiles.
class AngelKnight extends AngelSoldier {
  /// Breathing idle animation frames (south-facing, 9 frames).
  final List<Sprite> _idleFrames = [];

  /// Sword swing attack animation frames (north-facing, 9 frames).
  final List<Sprite> _attackFrames = [];

  double _animTimer = 0;
  int _currentFrame = 0;
  bool _isAttacking = false;
  double _attackTimer = 0;

  static const double idleStepTime = 0.15;
  static const double attackDuration = 0.6; // total time for full swing animation

  AngelKnight({required super.userId, required super.username}) {
    hp = 8;
    moveSpeed = 40.0;
  }

  @override
  bool get isMelee => true;

  @override
  double get meleeRange => 60.0;

  @override
  int get meleeDamage => 2;

  @override
  double get meleeInterval => 0.8;

  @override
  Future<void> loadVisuals() async {
    // Size matches the 92x92 pixel art sprite
    // (overrides the default 64x64 from base)

    // Load breathing idle frames
    for (int i = 0; i < 9; i++) {
      final path = 'angel_knight/frame_${i.toString().padLeft(3, '0')}.png';
      _idleFrames.add(await Sprite.load(path));
    }

    // Load attack (sword swing) frames
    for (int i = 0; i < 9; i++) {
      final path = 'angel_knight/attack/frame_${i.toString().padLeft(3, '0')}.png';
      _attackFrames.add(await Sprite.load(path));
    }

    sprite = _idleFrames[0];
  }

  /// Called by the game when the knight lands a melee hit.
  void triggerAttack() {
    if (!_isAttacking) {
      _isAttacking = true;
      _attackTimer = 0;
      _currentFrame = 0;
    }
  }

  @override
  void onRevive() {
    _animTimer = 0;
    _currentFrame = 0;
    _isAttacking = false;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (state != SoldierState.alive) return;

    _animTimer += dt;

    if (_isAttacking) {
      _attackTimer += dt;
      // Advance through attack frames
      final frameCount = _attackFrames.length;
      final frameTime = attackDuration / frameCount;
      if (_animTimer >= frameTime) {
        _animTimer -= frameTime;
        _currentFrame = (_currentFrame + 1) % frameCount;
        sprite = _attackFrames[_currentFrame];
      }
      // End attack sequence
      if (_attackTimer >= attackDuration) {
        _isAttacking = false;
        _currentFrame = 0;
        _animTimer = 0;
        sprite = _idleFrames[0];
      }
    } else {
      // Breathing idle animation
      if (_animTimer >= idleStepTime) {
        _animTimer -= idleStepTime;
        _currentFrame = (_currentFrame + 1) % _idleFrames.length;
        sprite = _idleFrames[_currentFrame];
      }
    }
  }
}
