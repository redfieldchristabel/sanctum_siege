import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'guild_lobby_controller.dart';

/// Writes lobby player data to [shared_preferences] on every point change
/// so top gifters don't lose their rank if the app crashes or is closed.
///
/// Persistence lifecycle (Section 3 of the spec):
///   On class assignment → filter: strip non-gifters, strip active 18,
///   keep unselected gifters as the next-match seed.
///   On restore → seed the master registry so unspent gifter balances survive.
class PersistentStorage {
  static const String _key = 'sanctum_siege_lobby_roster';

  /// Save the crash-resilient next-match seed to disk.
  ///
  /// Receives the full [masterRegistry] and the set of [selectedUsernames]
  /// (the 18 who entered the match), then filters to keep only unselected
  /// gifters — these are the paying viewers who didn't make the cut and
  /// deserve to carry their points into the next match.
  static Future<void> saveLobbyState(
    Map<String, LobbyPlayer> masterRegistry,
    Set<String> selectedUsernames,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final list = <Map<String, dynamic>>[];

    for (final entry in masterRegistry.entries) {
      final p = entry.value;

      // Strip non-gifters (free clickers don't carry points)
      if (!p.isGifter) continue;

      // Strip selected players (active combatants got their turn)
      if (selectedUsernames.contains(p.username)) continue;

      // Keep: unselected gifters (paying supporters who didn't make the 18)
      list.add({
        'username': p.username,
        'profilePicUrl': p.profilePicUrl,
        'points': p.points,
        'isGifter': p.isGifter,
        'soldierClass': p.soldierClass,
        'isFollower': p.isFollower,
      });
    }

    await prefs.setString(_key, jsonEncode(list));
    print('[persist] saved ${list.length} unselected gifters to disk');
  }

  /// Recover saved players into the controller's master registry.
  /// Call this from [AngelGuildScreen.initState].
  ///
  /// Restored players are seeded into the master registry and the
  /// 3-phase allocation algorithm places them in display slots.
  static Future<void> restoreLobbyState(GuildLobbyController ctrl) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final restored = decoded.map((e) {
        final m = e as Map<String, dynamic>;
        return LobbyPlayer(
          username: m['username'] as String? ?? '',
          profilePicUrl: m['profilePicUrl'] as String? ?? '',
          points: m['points'] as int? ?? 0,
          isGifter: m['isGifter'] as bool? ?? false,
          isFollower: m['isFollower'] as bool? ?? false,
          soldierClass: m['soldierClass'] as String?,
        );
      }).toList();

      if (restored.isNotEmpty) {
        ctrl.restoreRegistry(restored);
        print('[persist] restored ${restored.length} unselected gifters');
      }
    } catch (e) {
      // Corrupted data — ignore, start fresh
    }
  }

  /// Wipe the disk save (call on explicit `lobby_clear`).
  static Future<void> clearSavedLobby() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
