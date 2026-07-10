import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo_max/core/models/sync_enums.dart';
import 'package:kelivo_max/core/services/sync/sync_category_handler.dart';

void main() {
  group('syncHandlerFor factory exhaustiveness', () {
    test('every SyncCategory has a matching handler', () {
      for (final cat in SyncCategory.values) {
        final handler = syncHandlerFor(cat);
        expect(handler, isA<SyncCategoryHandler>());
        expect(
          handler.category,
          cat,
          reason: '${cat.name} handler should report its own category',
        );
      }
    });

    test('handler count matches SyncCategory value count', () {
      final handlers = SyncCategory.values.map(syncHandlerFor).toList();
      expect(handlers.length, SyncCategory.values.length);
    });

    test('each handler returns a unique category', () {
      final categories = SyncCategory.values
          .map(syncHandlerFor)
          .map((h) => h.category)
          .toSet();
      expect(categories.length, SyncCategory.values.length);
    });
  });

  group('SyncCategory string conversion', () {
    test('all SyncCategory values round-trip through toKey/fromKey', () {
      for (final cat in SyncCategory.values) {
        final key = cat.toKey();
        expect(
          key,
          isNotEmpty,
          reason: '${cat.name} toKey should not be empty',
        );
        final restored = SyncCategoryExt.fromKey(key);
        expect(
          restored,
          cat,
          reason: '${cat.name} should round-trip via key "$key"',
        );
      }
    });

    test('toKey returns the enum name', () {
      expect(SyncCategory.chats.toKey(), 'chats');
      expect(SyncCategory.providers.toKey(), 'providers');
      expect(SyncCategory.assistants.toKey(), 'assistants');
      expect(SyncCategory.quickPhrases.toKey(), 'quickPhrases');
      expect(SyncCategory.mcp.toKey(), 'mcp');
      expect(SyncCategory.searchServices.toKey(), 'searchServices');
      expect(SyncCategory.ttsServices.toKey(), 'ttsServices');
      expect(SyncCategory.settings.toKey(), 'settings');
      expect(SyncCategory.files.toKey(), 'files');
    });

    test('fromKey returns null for unknown key', () {
      expect(SyncCategoryExt.fromKey('nonexistent'), isNull);
      expect(SyncCategoryExt.fromKey(''), isNull);
      expect(SyncCategoryExt.fromKey('Chats'), isNull); // case-sensitive
    });
  });

  group('SyncDirection string conversion', () {
    test('all SyncDirection values round-trip through toKey/fromKey', () {
      for (final dir in SyncDirection.values) {
        final key = dir.toKey();
        expect(key, isNotEmpty);
        final restored = SyncDirectionExt.fromKey(key);
        expect(
          restored,
          dir,
          reason: '${dir.name} should round-trip via key "$key"',
        );
      }
    });

    test('toKey returns the enum name', () {
      expect(SyncDirection.pullOnly.toKey(), 'pullOnly');
      expect(SyncDirection.bidirectional.toKey(), 'bidirectional');
    });

    test('fromKey returns null for unknown key', () {
      expect(SyncDirectionExt.fromKey('invalid'), isNull);
      expect(SyncDirectionExt.fromKey(''), isNull);
      expect(SyncDirectionExt.fromKey('pull_only'), isNull); // wrong format
    });
  });

  group('SyncCategory enum completeness', () {
    test('has expected number of categories', () {
      // If a new category is added, this test will fail as a reminder to
      // update the handler factory and sync-related code.
      expect(SyncCategory.values.length, 9);
    });

    test('contains all known categories', () {
      final names = SyncCategory.values.map((c) => c.name).toSet();
      expect(
        names,
        containsAll([
          'chats',
          'providers',
          'assistants',
          'quickPhrases',
          'mcp',
          'searchServices',
          'ttsServices',
          'settings',
          'files',
        ]),
      );
    });
  });

  group('SyncDirection enum completeness', () {
    test('has exactly two directions', () {
      expect(SyncDirection.values.length, 2);
    });

    test('contains pullOnly and bidirectional', () {
      final names = SyncDirection.values.map((d) => d.name).toSet();
      expect(names, containsAll(['pullOnly', 'bidirectional']));
    });
  });
}
