import 'package:flame/flame.dart';
import 'package:flame/components.dart';

import 'angel_soldier.dart';

/// Sunfletcher — ranged angel class. Uses pixel art sprite sheet.
/// Swaps `this.sprite` each frame via manual timer.
/// No child components — single render pass.
/// Ghost sprite is swapped in by AngelSoldier.takeDamage().
class Sunfletcher extends AngelSoldier {
  SpriteAnimation? _anim;
  double _animTimer = 0;
  int _currentFrame = 0;

  Sunfletcher({required super.userId, required super.username});

  @override
  Future<void> loadVisuals() async {
    final image = await Flame.images.load('sunfletcher_sheet.png');
    _anim = SpriteAnimation.fromFrameData(
      image,
      SpriteAnimationData.sequenced(
        amount: 20,
        textureSize: Vector2(512, 512),
        amountPerRow: 5,
        stepTime: 0.1,
        loop: true,
      ),
    );
    sprite = _anim!.frames[0].sprite;
  }

  @override
  void onRevive() {
    _animTimer = 0;
    _currentFrame = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Advance animation frame only when alive (freezes on last frame when ghost)
    if (state == SoldierState.alive && _anim != null) {
      _animTimer += dt;
      const stepTime = 0.1;
      if (_animTimer >= stepTime) {
        _animTimer -= stepTime;
        _currentFrame = (_currentFrame + 1) % _anim!.frames.length;
        sprite = _anim!.frames[_currentFrame].sprite;
      }
    }
  }
}
