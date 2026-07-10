import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'package:kelivo_sync_server/routes/ws.dart';
import 'package:kelivo_sync_server/services/relay_service.dart';

void main() {
  const testSecret = 'test-jwt-secret-for-ws';

  String makeToken(int userId, {Duration? expiry}) {
    final jwt = JWT({'userId': userId});
    return jwt.sign(
      SecretKey(testSecret),
      expiresIn: expiry ?? const Duration(hours: 1),
    );
  }

  group('WebSocket handler integration', () {
    late HttpServer server;
    late RelayService relay;
    late String wsUrl;

    setUp(() async {
      // Set JWT_SECRET for the handler.
      // Note: Platform.environment is unmodifiable; the handler reads it at
      // message time, so we rely on the process env. These tests require
      // JWT_SECRET to be set before running.
      relay = RelayService();
      final handler = wsHandler(relay);

      server = await shelf_io.serve(handler, 'localhost', 0);
      wsUrl = 'ws://localhost:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('rejects connection without token message', () async {
      final channel = IOWebSocketChannel.connect(wsUrl);
      channel.sink.add(jsonEncode({'notoken': true}));

      final messages = <String>[];
      await for (final msg in channel.stream) {
        messages.add(msg as String);
      }

      expect(messages, hasLength(1));
      final decoded = jsonDecode(messages.first) as Map<String, dynamic>;
      expect(decoded['error'], equals('Token required'));
    });

    test(
      'authenticates with valid token',
      () async {
        final token = makeToken(42);
        final channel = IOWebSocketChannel.connect(wsUrl);
        channel.sink.add(jsonEncode({'token': token}));

        final completer = Completer<String>();
        late StreamSubscription sub;
        sub = channel.stream.listen((msg) {
          completer.complete(msg as String);
          sub.cancel();
        });

        final response = await completer.future.timeout(
          const Duration(seconds: 5),
        );
        final decoded = jsonDecode(response) as Map<String, dynamic>;

        expect(decoded['status'], equals('authenticated'));
        expect(decoded['userId'], equals(42));
        expect(relay.isOnline(42), isTrue);

        await channel.sink.close();
        // Give time for cleanup.
        await Future.delayed(const Duration(milliseconds: 100));
        expect(relay.isOnline(42), isFalse);
      },
      skip: Platform.environment['JWT_SECRET'] != testSecret
          ? 'JWT_SECRET must be "$testSecret"'
          : null,
    );

    test(
      'rejects expired token',
      () async {
        // Create an already-expired token.
        final jwt = JWT({'userId': 1});
        final token = jwt.sign(
          SecretKey(testSecret),
          expiresIn: const Duration(seconds: -1),
        );

        final channel = IOWebSocketChannel.connect(wsUrl);
        channel.sink.add(jsonEncode({'token': token}));

        final messages = <String>[];
        await for (final msg in channel.stream) {
          messages.add(msg as String);
        }

        expect(messages, hasLength(1));
        final decoded = jsonDecode(messages.first) as Map<String, dynamic>;
        expect(decoded['error'], isNotNull);
      },
      skip: Platform.environment['JWT_SECRET'] != testSecret
          ? 'JWT_SECRET must be "$testSecret"'
          : null,
    );

    test(
      'relay receives events after authentication',
      () async {
        final token = makeToken(42);
        final channel = IOWebSocketChannel.connect(wsUrl);
        channel.sink.add(jsonEncode({'token': token}));

        final messages = <Map<String, dynamic>>[];
        final authCompleter = Completer<void>();

        channel.stream.listen((msg) {
          final decoded = jsonDecode(msg as String) as Map<String, dynamic>;
          if (decoded.containsKey('status') &&
              decoded['status'] == 'authenticated') {
            authCompleter.complete();
          } else {
            messages.add(decoded);
          }
        });

        await authCompleter.future.timeout(const Duration(seconds: 5));

        // Push an event through the relay.
        relay.sendToUser(42, {
          'taskId': 't-1',
          'eventType': 'chunk',
          'content': 'hello',
        });

        // Give time for message delivery.
        await Future.delayed(const Duration(milliseconds: 200));

        expect(messages, hasLength(1));
        expect(messages.first['taskId'], equals('t-1'));
        expect(messages.first['eventType'], equals('chunk'));
        expect(messages.first['content'], equals('hello'));

        await channel.sink.close();
      },
      skip: Platform.environment['JWT_SECRET'] != testSecret
          ? 'JWT_SECRET must be "$testSecret"'
          : null,
    );
  });
}
