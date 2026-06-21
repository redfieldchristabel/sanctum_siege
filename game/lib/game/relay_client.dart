import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// WebSocket client that connects to the relay server and parses game events.
///
/// Events received from the relay:
///   { event: "join",       data: { userId, username },  source: "dev"|"tiktok" }
///   { event: "leave",      data: { userId },            source: ... }
///   { event: "like",       data: { userId, count },     source: ... }
///   { event: "gift",       data: { userId, giftName, count }, source: ... }
///   { event: "comment",    data: { userId, username, text }, source: ... }
///   { event: "spawn_wave", data: { difficulty? },       source: ... }
///   { event: "spawn_angel", data: { count },            source: ... }
///   { event: "dev_config", data: { key, value },        source: "dev" }
class RelayClient {
  final String url;
  WebSocket? _ws;
  Timer? _reconnectTimer;
  bool _disposed = false;

  /// Called when any event arrives.
  final void Function(String event, Map<String, dynamic> data, String source)
      onEvent;

  RelayClient({required this.url, required this.onEvent});

  Future<void> connect() async {
    if (_disposed) return;
    try {
      _ws = await WebSocket.connect(url);
      print('[relay] connected to $url');

      _ws!.listen(
        (raw) {
          if (_disposed) return;
          try {
            final msg = jsonDecode(raw as String) as Map<String, dynamic>;
            final event = msg['event'] as String?;
            final data = msg['data'] as Map<String, dynamic>?;
            final source = msg['source'] as String? ?? 'unknown';
            if (event != null && data != null) {
              onEvent(event, data, source);
            }
          } catch (e) {
            print('[relay] bad message: $e');
          }
        },
        onError: (e) {
          print('[relay] error: $e');
          _scheduleReconnect();
        },
        onDone: () {
          print('[relay] disconnected');
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (e) {
      print('[relay] connect failed: $e');
      _scheduleReconnect();
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
