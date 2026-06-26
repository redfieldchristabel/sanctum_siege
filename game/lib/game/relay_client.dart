import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ══════════════════════════════════════════════════
//  Typed Event System — sealed class hierarchy
// ══════════════════════════════════════════════════

/// Tagged union — every possible relay message.
sealed class RelayEvent {
  const RelayEvent();
}

// ── TikTok viewer events ─────────────────────────
class JoinEvent extends RelayEvent {
  final String userId;
  final String username;
  final bool isGifter;
  const JoinEvent(this.userId, this.username, [this.isGifter = false]);
}

class LeaveEvent extends RelayEvent {
  final String userId;
  const LeaveEvent(this.userId);
}

class LikeEvent extends RelayEvent {
  final String userId;
  final String username;
  final int count;
  const LikeEvent(this.userId, this.username, this.count);
}

class GiftEvent extends RelayEvent {
  final String userId;
  final String username;
  final String giftName;
  final int count;
  final int lobbyPoints;
  const GiftEvent(this.userId, this.username, this.giftName, this.count, this.lobbyPoints);
}

class CommentEvent extends RelayEvent {
  final String userId;
  final String username;
  final String text;
  const CommentEvent(this.userId, this.username, this.text);
}

// ── Game admin events ────────────────────────────
class SpawnWaveEvent extends RelayEvent {
  final String? difficulty;
  const SpawnWaveEvent([this.difficulty]);
}

class SpawnAngelEvent extends RelayEvent {
  final int count;
  final String? name;
  const SpawnAngelEvent(this.count, [this.name]);
}

class StartGameEvent extends RelayEvent {
  const StartGameEvent();
}

class DevConfigEvent extends RelayEvent {
  final String key;
  final dynamic value;
  const DevConfigEvent(this.key, this.value);
}

// ── Lobby events ────────────────────────────────
class LobbyUpdateEvent extends RelayEvent {
  const LobbyUpdateEvent();
}

class LobbyClearEvent extends RelayEvent {
  const LobbyClearEvent();
}

class LobbyJoinEvent extends RelayEvent {
  final String username;
  final int points;
  final bool isGifter;
  const LobbyJoinEvent(this.username, this.points, this.isGifter);
}

class LobbyPointsEvent extends RelayEvent {
  final String username;
  final int points;
  const LobbyPointsEvent(this.username, this.points);
}

class StartMatchEvent extends RelayEvent {
  const StartMatchEvent();
}

/// Dev command: instantly kill an angel by username.
class KillEvent extends RelayEvent {
  final String username;
  const KillEvent(this.username);
}

// ── Gift → lobby point conversion ───────────────
int giftPoints(String giftName, int count) {
  final lower = giftName.toLowerCase();
  if (lower.contains('capsule') || lower.contains('lion')) return 500 * count;
  if (lower.contains('donut') || lower.contains('diamond')) return 50 * count;
  if (lower.contains('rose') || lower.contains('flower')) return 10 * count;
  return count; // default: 1 pt per gift
}

// ══════════════════════════════════════════════════
//  RelayClient — pure WebSocket passthrough
// ══════════════════════════════════════════════════

class RelayClient {
  final String url;
  WebSocket? _ws;
  Timer? _reconnectTimer;
  bool _disposed = false;

  /// Single typed callback — implementers switch on [RelayEvent].
  final void Function(RelayEvent event) onEvent;

  RelayClient({required this.url, required this.onEvent});

  Future<void> connect() async {
    if (_disposed) return;
    try {
      _ws = await WebSocket.connect(url);
      print('[ws] connected to $url');

      _ws!.listen(
        (raw) {
          if (_disposed) return;
          final event = _parse(raw as String);
          if (event != null) onEvent(event);
        },
        onError: (e) {
          print('[ws] error: $e');
          _scheduleReconnect();
        },
        onDone: () {
          print('[ws] disconnected');
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (e) {
      print('[ws] connect failed: $e');
      _scheduleReconnect();
    }
  }

  /// Parse raw JSON into a typed [RelayEvent].
  RelayEvent? _parse(String raw) {
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      final event = msg['event'] as String?;
      final data = msg['data'] as Map<String, dynamic>?;
      if (event == null || data == null) return null;

      return switch (event) {
        'join' => JoinEvent(
            data['userId'] as String? ?? '',
            data['username'] as String? ?? '',
            data['isGifter'] as bool? ?? false,
          ),
        'leave' => LeaveEvent(data['userId'] as String? ?? ''),
        'like' => LikeEvent(
            data['userId'] as String? ?? '',
            data['username'] as String? ?? '',
            (data['count'] as num?)?.toInt() ?? 1,
          ),
        'gift' => GiftEvent(
            data['userId'] as String? ?? '',
            data['username'] as String? ?? '',
            data['giftName'] as String? ?? '',
            (data['count'] as num?)?.toInt() ?? 1,
            (data['lobbyPoints'] as num?)?.toInt() ?? 0,
          ),
        'comment' => CommentEvent(
            data['userId'] as String? ?? '',
            data['username'] as String? ?? '',
            data['text'] as String? ?? '',
          ),
        'spawn_wave' => SpawnWaveEvent(data['difficulty'] as String?),
        'spawn_angel' => SpawnAngelEvent(
            (data['count'] as num?)?.toInt() ?? 1,
            data['name'] as String?,
          ),
        'game_start' => const StartGameEvent(),
        'dev_config' => DevConfigEvent(
            data['key'] as String? ?? '',
            data['value'],
          ),
        'lobby_update' => const LobbyUpdateEvent(),
        'lobby_clear' => const LobbyClearEvent(),
        'lobby_join' => LobbyJoinEvent(
            data['username'] as String? ?? 'Hero',
            (data['points'] as num?)?.toInt() ?? 0,
            data['isGifter'] as bool? ?? true,
          ),
        'lobby_points' => LobbyPointsEvent(
            data['username'] as String? ?? '',
            (data['points'] as num?)?.toInt() ?? 0,
          ),
        'start_match' => const StartMatchEvent(),
        'kill' => KillEvent(data['username'] as String? ?? ''),
        _ => null,
      };
    } catch (e) {
      print('[ws] parse error: $e');
      return null;
    }
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _reconnectTimer = null;
      if (!_disposed) connect();
    });
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _ws?.close();
  }
}
