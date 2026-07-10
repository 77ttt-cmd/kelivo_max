import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../services/changelog_service.dart';

Router changesRouter() {
  final router = Router();

  router.get('/changes', _getChangesHandler);
  router.post('/changes', _postChangesHandler);

  return router;
}

Future<Response> _getChangesHandler(Request request) async {
  try {
    final userId = request.context['userId'] as int;

    final sinceParam = request.url.queryParameters['since'];
    final since = int.tryParse(sinceParam ?? '') ?? 0;

    final categoriesParam = request.url.queryParameters['categories'];
    if (categoriesParam == null || categoriesParam.trim().isEmpty) {
      return Response(
        400,
        body: jsonEncode({'error': 'categories query parameter is required'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final categories = categoriesParam
        .split(',')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();

    if (categories.isEmpty) {
      return Response(
        400,
        body: jsonEncode({
          'error': 'categories must contain at least one value',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final result = await ChangelogService.getChanges(userId, since, categories);

    final latestSeq = result.entries.isNotEmpty
        ? result.entries.last.serverSeq
        : since;

    return Response.ok(
      jsonEncode({
        'entries': result.entries.map((e) => e.toJson()).toList(),
        'latestSeq': latestSeq,
        'hasMore': result.hasMore,
      }),
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Internal server error'}),
      headers: {'content-type': 'application/json'},
    );
  }
}

const _validCategories = {
  'chats',
  'providers',
  'assistants',
  'quickPhrases',
  'mcp',
  'searchServices',
  'ttsServices',
  'settings',
  'files',
};

Future<Response> _postChangesHandler(Request request) async {
  try {
    final userId = request.context['userId'] as int;
    final bodyStr = await request.readAsString();
    final body = jsonDecode(bodyStr) as Map<String, dynamic>;

    final entries =
        (body['entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (entries.isEmpty) {
      return Response(
        400,
        body: jsonEncode({'error': 'entries array required'}),
        headers: {'content-type': 'application/json'},
      );
    }

    // Validate categories.
    for (final entry in entries) {
      final cat = entry['category'] as String?;
      if (cat == null || !_validCategories.contains(cat)) {
        return Response(
          400,
          body: jsonEncode({'error': 'Unknown category: $cat'}),
          headers: {'content-type': 'application/json'},
        );
      }
    }

    final result = await ChangelogService.pushChanges(userId, entries);
    return Response.ok(
      jsonEncode({
        'accepted': result.accepted,
        'skipped': result.skipped,
        'latestSeq': result.latestSeq,
      }),
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Internal server error'}),
      headers: {'content-type': 'application/json'},
    );
  }
}
