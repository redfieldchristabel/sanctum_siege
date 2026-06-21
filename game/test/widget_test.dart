import 'package:flutter_test/flutter_test.dart';
import 'package:game/game/sanctum_siege_game.dart';

void main() {
  test('SanctumSiegeGame instantiates without error', () {
    final game = SanctumSiegeGame();
    expect(game, isNotNull);
    expect(game.isLoaded, isFalse);
    game.onRemove();
  });
}
