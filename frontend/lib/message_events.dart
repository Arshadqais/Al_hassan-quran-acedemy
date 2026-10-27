import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The session token is sent in a frame, never in a URL or access log.
class MessageEvents {
  final String baseUrl, token;
  final void Function() onChanged, onExpired;
  final void Function(bool) onConnected;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  bool _closed = false;
  int _delay = 2;
  MessageEvents({
    required this.baseUrl,
    required this.token,
    required this.onChanged,
    required this.onExpired,
    required this.onConnected,
  });
  Future<void> connect() async {
    if (_closed) return;
    try {
      final base = Uri.parse(baseUrl);
      final uri = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/api/ws/messages',
        query: null,
        fragment: null,
      );
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 15));
      if (_closed) {
        await channel.sink.close();
        return;
      }
      channel.sink.add(jsonEncode({'token': token}));
      _subscription = channel.stream.listen(
        (raw) {
          try {
            final event = jsonDecode(raw as String);
            if (event['type'] == 'ready') {
              _delay = 2;
              onConnected(true);
              onChanged();
            }
            if (event['type'] == 'messages_changed') onChanged();
          } catch (_) {
            /* Ignore unsupported notifications. */
          }
        },
        onError: (_) => reconnect(),
        onDone: () {
          if (channel.closeCode == 4401) {
            onExpired();
            close();
          } else {
            reconnect();
          }
        },
      );
    } catch (_) {
      reconnect();
    }
  }

  void reconnect() {
    if (_closed || _retry?.isActive == true) return;
    onConnected(false);
    _subscription?.cancel();
    _channel?.sink.close();
    _retry = Timer(Duration(seconds: _delay), connect);
    _delay = (_delay * 2).clamp(2, 30);
  }

  void close() {
    _closed = true;
    _retry?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
  }
}
