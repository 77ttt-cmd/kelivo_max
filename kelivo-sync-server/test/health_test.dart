import 'dart:convert';

import 'package:test/test.dart';
import 'package:shelf/shelf.dart';

import 'package:kelivo_sync_server/routes/health.dart';

void main() {
  test('health endpoint returns ok', () async {
    final request = Request('GET', Uri.parse('http://localhost/health'));
    final response = healthHandler(request);

    expect(response.statusCode, equals(200));
    final body = jsonDecode(await response.readAsString());
    expect(body['status'], equals('ok'));
  });
}
