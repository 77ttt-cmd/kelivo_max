import 'dart:convert';

import 'package:shelf/shelf.dart';

Response healthHandler(Request request) {
  return Response.ok(
    jsonEncode({'status': 'ok'}),
    headers: {'content-type': 'application/json'},
  );
}
