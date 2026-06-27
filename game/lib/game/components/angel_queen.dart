import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

/// The Angel Queen — permanent, stays at the bottom, does NOT fight.
/// Uses pixel art sprite with breathing idle animation.
/// If she dies = game over.
class AngelQueen extends PositionComponent {
  int hp = 80;
  final int maxHp = 80;
  SpriteAnimationComponent? _anim;

  AngelQueen() : super(size: Vector2(128, 128));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // Sprite has 35px transparent padding below feet.
    // Use bottomCenter anchor + position offset to keep feet at y:1220.
    anchor = Anchor.bottomCenter;
    debugMode = true;

    // Load 4 breathing idle frames concurrently
    final frameFutures = List.generate(4, (i) {
      final frameNumber = i.toString().padLeft(3, '0');
      final future = Sprite.load(
          'angel_queen/animations/Breathing_Idle/south/frame_$frameNumber.png');
      return future.then((sprite) => SpriteAnimationFrame(sprite, 0.4));
    });
    final frames = await Future.wait(frameFutures);

    _anim = SpriteAnimationComponent(
      animation: SpriteAnimation(frames, loop: true),
      size: size,
      anchor: Anchor.bottomCenter,
    );
    // Child position is relative to parent's top-left corner.
    // Since parent uses bottomCenter anchor, the child needs to be
    // at position (size.x/2, size.y) to align with the parent's anchor.
    _anim!.position = Vector2(size.x / 2, size.y);
    add(_anim!);
  }

  bool takeDamage(int amount) {
    hp -= amount;
    if (hp <= 0) {
      removeFromParent();
      return true;
    }
    return false;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final cx = size.x / 2;
    const barW = 44.0;
    final barY = size.y - 14.0;
    canvas.drawRect(Rect.fromLTWH(cx - barW / 2, barY, barW, 4),
        Paint()..color = const Color(0x88000000));
    canvas.drawRect(
      Rect.fromLTWH(cx - barW / 2, barY, barW * (hp / maxHp), 4),
      Paint()..color = const Color(0xFF44AA44),
    );
    canvas.drawRect(Rect.fromLTWH(cx - barW / 2, barY, barW, 4),
        Paint()
          ..color = const Color(0xFF000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }
}
