import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'guild_lobby_controller.dart';

/// Writes lobby player data to [shared_preferences] on every point change
/// so top gifters don't lose their rank if the app crashes or is closed.
class PersistentStorage {
  static const String _key = 'sanctum_siege_lobby_roster';

  /// Save all non-null slots to disk.
  static Future<void> saveLobbyState(List<LobbyPlayer?> slots) async {
    final prefs = await SharedPreferences.getInstance();
    final list = <Map<String, dynamic>>[];

    for (final p in slots) {
      if (p == null) continue;
      list.add({
        'username': p.username,
        'profilePicUrl': p.profilePicUrl,
        'points': p.points,
        'isGifter': p.isGifter,
        'soldierClass': p.soldierClass,
      });
    }

    await prefs.setString(_key, jsonEncode(list));
  }

  /// Recover saved players into a controller's slot list.
  /// Call this from [AngelGuildScreen.initState].
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
          soldierClass: m['soldierClass'] as String?,
        );
      }).toList();

      if (restored.isNotEmpty) {
        ctrl.updateLobby(restored);
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
