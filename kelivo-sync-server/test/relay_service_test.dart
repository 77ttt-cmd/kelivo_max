import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:kelivo_sync_server/services/relay_service.dart';

/// A minimal fake [WebSocketChannel] for testing [RelayService].
///
/// Records messages added to the sink and allows controlling the stream.
class _FakeWebSocketChannel implements WebSocketChannel {
  final List<dynamic> sentMessages = [];
  bool closed = false;
  bool throwOnAdd = false;

  final _streamController = StreamController<dynamic>();
  late final _sink = _FakeSink(this);

  @override
  WebSocketSink get sink => _sink;

  @override
  Stream<dynamic> get stream => _streamController.stream;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future.value();

  void addToStream(dynamic data) {
    _streamController.add(data);
  }

  Future<void> dispose() async {
    await _streamController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  final _FakeWebSocketChannel _channel;

  _FakeSink(this._channel);

  @override
  void add(dynamic data) {
    if (_channel.throwOnAdd) {
      throw StateError('Connection closed');
    }
    _channel.sentMessages.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) => Future.value();

  @override
  Future close([int? closeCode, String? closeReason]) {
    _channel.closed = true;
    return Future.value();
  }

  @override
  Future get done => Future.value();
}

void main() {
  group('RelayService', () {
    late RelayService relay;

    setUp(() {
      relay = RelayService();
    });

    group('addConnection / removeConnection', () {
      test('adds a connection and marks user online', () {
        final channel = _FakeWebSocketChannel();
        relay.addConnection(1, channel);

        expect(relay.isOnline(1), isTrue);
        expect(relay.connectionCount(1), equals(1));
        expect(relay.activeUserCount, equals(1));
        expect(relay.totalConnectionCount, equals(1));
      });

      test('supports multiple connections per user', () {
        final ch1 = _FakeWebSocketChannel();
        final ch2 = _FakeWebSocketChannel();
        relay.addConnection(1, ch1);
        relay.addConnection(1, ch2);

        expect(relay.connectionCount(1), equals(2));
        expect(relay.activeUserCount, equals(1));
        expect(relay.totalConnectionCount, equals(2));
      });

      test('supports multiple users', () {
        final ch1 = _FakeWebSocketChannel();
        final ch2 = _FakeWebSocketChannel();
        relay.addConnection(1, ch1);
        relay.addConnection(2, ch2);

        expect(relay.isOnline(1), isTrue);
        expect(relay.isOnline(2), isTrue);
        expect(relay.activeUserCount, equals(2));
        expect(relay.totalConnectionCount, equals(2));
      });

      test('removeConnection decrements count', () {
        final ch1 = _FakeWebSocketChannel();
        final ch2 = _FakeWebSocketChannel();
        relay.addConnection(1, ch1);
        relay.addConnection(1, ch2);

        relay.removeConnection(1, ch1);
        expect(relay.connectionCount(1), equals(1));
        expect(relay.isOnline(1), isTrue);
      });

      test('removing last connection marks user offline', () {
        final channel = _FakeWebSocketChannel();
        relay.addConnection(1, channel);
        relay.removeConnection(1, channel);

        expect(relay.isOnline(1), isFalse);
        expect(relay.connectionCount(1), equals(0));
        expect(relay.activeUserCount, equals(0));
      });

      test('removing non-existent connection is safe', () {
        final channel = _FakeWebSocketChannel();
        // No crash when removing from unknown userId.
        relay.removeConnection(999, channel);
        expect(relay.isOnline(999), isFalse);
      });
    });

    group('isOnline', () {
      test('returns false for unknown user', () {
        expect(relay.isOnline(42), isFalse);
      });

      test('returns true when user has connections', () {
        relay.addConnection(42, _FakeWebSocketChannel());
        expect(relay.isOnline(42), isTrue);
      });
    });

    group('sendToUser', () {
      test('sends JSON-encoded message to all connections of a user', () {
        final ch1 = _FakeWebSocketChannel();
        final ch2 = _FakeWebSocketChannel();
        relay.addConnection(1, ch1);
        relay.addConnection(1, ch2);

        final message = {
          'taskId': 't-1',
          'eventType': 'chunk',
          'content': 'hi',
        };
        relay.sendToUser(1, message);

        final expectedJson = jsonEncode(message);
        expect(ch1.sentMessages, equals([expectedJson]));
        expect(ch2.sentMessages, equals([expectedJson]));
      });

      test('does nothing for offline user', () {
        // No crash, no error.
        relay.sendToUser(999, {'test': true});
      });

      test('does nothing for user with no connections', () {
        final channel = _FakeWebSocketChannel();
        relay.addConnection(1, channel);
        relay.removeConnection(1, channel);

        // User had connections but now has none.
        relay.sendToUser(1, {'test': true});
        expect(channel.sentMessages, isEmpty);
      });

      test('removes failed connections automatically', () {
        final goodChannel = _FakeWebSocketChannel();
        final badChannel = _FakeWebSocketChannel()..throwOnAdd = true;

        relay.addConnection(1, goodChannel);
        relay.addConnection(1, badChannel);
        expect(relay.connectionCount(1), equals(2));

        relay.sendToUser(1, {'data': 'test'});

        // Good channel received the message.
        expect(goodChannel.sentMessages, hasLength(1));

        // Bad channel was auto-removed.
        expect(relay.connectionCount(1), equals(1));
        expect(relay.isOnline(1), isTrue);
      });

      test('user goes offline when all connections fail during send', () {
        final badChannel = _FakeWebSocketChannel()..throwOnAdd = true;
        relay.addConnection(1, badChannel);

        relay.sendToUser(1, {'data': 'test'});

        expect(relay.isOnline(1), isFalse);
        expect(relay.connectionCount(1), equals(0));
      });

      test('does not send to other users', () {
        final ch1 = _FakeWebSocketChannel();
        final ch2 = _FakeWebSocketChannel();
        relay.addConnection(1, ch1);
        relay.addConnection(2, ch2);

        relay.sendToUser(1, {'for': 'user1'});

        expect(ch1.sentMessages, hasLength(1));
        expect(ch2.sentMessages, isEmpty);
      });
    });

    group('counters', () {
      test('activeUserCount and totalConnectionCount start at zero', () {
        expect(relay.activeUserCount, equals(0));
        expect(relay.totalConnectionCount, equals(0));
      });

      test('counters reflect mixed state', () {
        relay.addConnection(1, _FakeWebSocketChannel());
        relay.addConnection(1, _FakeWebSocketChannel());
        relay.addConnection(2, _FakeWebSocketChannel());

        expect(relay.activeUserCount, equals(2));
        expect(relay.totalConnectionCount, equals(3));
      });
    });
  });
}
