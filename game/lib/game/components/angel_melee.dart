import 'angel_soldier.dart';

/// Angel melee soldier — walks toward nearest devil, slashes in close range.
/// Tankier than Sunfletcher, no projectile, faster walk speed.
/// Uses the default orb sprite until a pixel art sprite sheet is generated.
class AngelMelee extends AngelSoldier {
  AngelMelee({required super.userId, required super.username}) {
    hp = 8;
    moveSpeed = 40.0;
  }

  @override
  bool get isMelee => true;

  @override
  double get meleeRange => 30.0;

  @override
  int get meleeDamage => 2;

  @override
  double get meleeInterval => 0.8;
}
