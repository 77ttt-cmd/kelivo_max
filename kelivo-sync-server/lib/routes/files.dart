import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../services/file_service.dart';

Router fileRouter() {
  final router = Router();

  // Register /exists BEFORE /:hash so shelf_router does not treat "exists"
  // as a hash parameter.
  router.get('/exists', _existsHandler);
  router.post('/', _uploadHandler);
  router.get('/<hash>', _downloadHandler);

  return router;
}

/// Maximum storage per user: 100 MB.
const _maxStorageBytes = 100 * 1024 * 1024;

Future<Response> _uploadHandler(Request request) async {
  final userId = request.context['userId'] as int;

  final Map<String, dynamic> body;
  try {
    final bodyStr = await request.readAsString();
    body = jsonDecode(bodyStr) as Map<String, dynamic>;
  } on FormatException {
    return Response(
      400,
      body: jsonEncode({'error': 'Invalid JSON body'}),
      headers: {'content-type': 'application/json'},
    );
  }

  final hash = body['hash'] as String?;
  final path = body['path'] as String? ?? '';
  final contentType =
      body['contentType'] as String? ?? 'application/octet-stream';
  final base64Content = body['content'] as String?;

  if (hash == null || hash.isEmpty || base64Content == null) {
    return Response(
      400,
      body: jsonEncode({'error': 'hash and content are required'}),
      headers: {'content-type': 'application/json'},
    );
  }

  final List<int> bytes;
  try {
    bytes = base64Decode(base64Content);
  } on FormatException {
    return Response(
      400,
      body: jsonEncode({'error': 'Invalid base64 content'}),
      headers: {'content-type': 'application/json'},
    );
  }

  // Verify SHA256.
  final computedHash = sha256.convert(bytes).toString();
  if (computedHash != hash) {
    return Response(
      400,
      body: jsonEncode({'error': 'Hash mismatch'}),
      headers: {'content-type': 'application/json'},
    );
  }

  // Check quota.
  final used = await FileService.getUserStorageUsed(userId);
  if (used + bytes.length > _maxStorageBytes) {
    return Response(
      413,
      body: jsonEncode({'error': 'Storage quota exceeded'}),
      headers: {'content-type': 'application/json'},
    );
  }

  final isNew = await FileService.storeFile(
    userId: userId,
    hash: hash,
    originalPath: path,
    contentType: contentType,
    bytes: bytes,
  );

  return Response(
    isNew ? 201 : 200,
    body: jsonEncode({'existed': !isNew}),
    headers: {'content-type': 'application/json'},
  );
}

Future<Response> _downloadHandler(Request request, String hash) async {
  final userId = request.context['userId'] as int;

  final meta = await FileService.getFileByHash(userId, hash);
  if (meta == null) {
    return Response.notFound(
      jsonEncode({'error': 'File not found'}),
      headers: {'content-type': 'application/json'},
    );
  }

  final storedPath = meta['storedPath'] as String;
  final contentType = meta['contentType'] as String;
  final size = meta['size'] as int;

  final file = File(storedPath);
  if (!await file.exists()) {
    return Response.notFound(
      jsonEncode({'error': 'File not found on disk'}),
      headers: {'content-type': 'application/json'},
    );
  }

  // Stream file content rather than loading into memory.
  return Response.ok(
    file.openRead(),
    headers: {'content-type': contentType, 'content-length': size.toString()},
  );
}

Future<Response> _existsHandler(Request request) async {
  final userId = request.context['userId'] as int;

  final hashesParam = request.url.queryParameters['hashes'];
  if (hashesParam == null || hashesParam.isEmpty) {
    return Response(
      400,
      body: jsonEncode({'error': 'hashes query parameter is required'}),
      headers: {'content-type': 'application/json'},
    );
  }

  final hashes = hashesParam
      .split(',')
      .map((h) => h.trim())
      .where((h) => h.isNotEmpty)
      .toList();

  if (hashes.isEmpty) {
    return Response(
      400,
      body: jsonEncode({'error': 'hashes query parameter must not be empty'}),
      headers: {'content-type': 'application/json'},
    );
  }

  final result = await FileService.checkExists(userId, hashes);

  return Response.ok(
    jsonEncode(result),
    headers: {'content-type': 'application/json'},
  );
}
