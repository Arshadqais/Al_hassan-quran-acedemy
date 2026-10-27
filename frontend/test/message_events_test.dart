import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/message_events.dart';

void main() {
  test(
    'Chat authenticates in a frame and receives changes without credentials in URLs',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final changed = Completer<void>(), expired = Completer<void>();
      var changes = 0;
      WebSocket? socket;
      final listener = server.listen((request) async {
        expect(request.uri.query, isEmpty);
        socket = await WebSocketTransformer.upgrade(request);
        final first = await socket!.first;
        expect(jsonDecode(first as String)['token'], 'test-only-session');
        socket!.add(jsonEncode({'type': 'ready'}));
        socket!.add(jsonEncode({'type': 'messages_changed'}));
      });
      final events = MessageEvents(
        baseUrl: 'http://127.0.0.1:${server.port}',
        token: 'test-only-session',
        onChanged: () {
          changes++;
          if (changes == 2) changed.complete();
        },
        onExpired: () => expired.complete(),
        onConnected: (_) {},
      );
      try {
        await events.connect();
        await changed.future.timeout(const Duration(seconds: 5));
        await socket!.close(4401, 'Session ended');
        await expired.future.timeout(const Duration(seconds: 5));
      } finally {
        events.close();
        await listener.cancel();
        await server.close(force: true);
      }
    },
  );
  test('Chat reconnects after a connection interruption', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final reconnected = Completer<void>();
    var count = 0;
    final sockets = <WebSocket>[];
    final listener = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      await socket.first;
      socket.add(jsonEncode({'type': 'ready'}));
      count++;
      if (count == 1) await socket.close(1001, 'Test restart');
    });
    final events = MessageEvents(
      baseUrl: 'http://127.0.0.1:${server.port}',
      token: 'test-session',
      onChanged: () {
        if (count >= 2 && !reconnected.isCompleted) reconnected.complete();
      },
      onExpired: () {},
      onConnected: (_) {},
    );
    try {
      await events.connect();
      await reconnected.future.timeout(const Duration(seconds: 8));
    } finally {
      events.close();
      for (final s in sockets) {
        await s.close();
      }
      await listener.cancel();
      await server.close(force: true);
    }
  });
}
