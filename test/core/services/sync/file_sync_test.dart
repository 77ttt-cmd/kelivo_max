import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo_max/core/models/sync_enums.dart';
import 'package:kelivo_max/core/services/sync/sync_category_handler.dart';

void main() {
  group('File sync handler', () {
    test('files handler has correct category', () {
      final handler = syncHandlerFor(SyncCategory.files);
      expect(handler.category, SyncCategory.files);
    });

    test('files handler is a SyncCategoryHandler', () {
      final handler = syncHandlerFor(SyncCategory.files);
      expect(handler, isA<SyncCategoryHandler>());
    });
  });

  group('File hash deduplication logic', () {
    test('only upload files not on server', () {
      final localHashes = ['hash1', 'hash2', 'hash3'];
      final serverExists = {'hash1': true, 'hash2': false, 'hash3': true};
      final toUpload = localHashes
          .where((h) => serverExists[h] != true)
          .toList();
      expect(toUpload, ['hash2']);
    });

    test('all files already on server yields empty upload list', () {
      final localHashes = ['hash1', 'hash2'];
      final serverExists = {'hash1': true, 'hash2': true};
      final toUpload = localHashes
          .where((h) => serverExists[h] != true)
          .toList();
      expect(toUpload, isEmpty);
    });

    test('no files on server yields full upload list', () {
      final localHashes = ['hash1', 'hash2', 'hash3'];
      final serverExists = <String, bool>{
        'hash1': false,
        'hash2': false,
        'hash3': false,
      };
      final toUpload = localHashes
          .where((h) => serverExists[h] != true)
          .toList();
      expect(toUpload, localHashes);
    });

    test('empty local hashes yields empty upload list', () {
      final localHashes = <String>[];
      final serverExists = <String, bool>{};
      final toUpload = localHashes
          .where((h) => serverExists[h] != true)
          .toList();
      expect(toUpload, isEmpty);
    });

    test('missing hash in server map treated as not existing', () {
      // If checkFilesExist response doesn't include a hash, treat as missing.
      final localHashes = ['hash1', 'hash2'];
      final serverExists = <String, bool>{'hash1': true};
      // hash2 is not in serverExists map — serverExists['hash2'] is null.
      final toUpload = localHashes
          .where((h) => serverExists[h] != true)
          .toList();
      expect(toUpload, ['hash2']);
    });
  });

  group('File change record structure', () {
    test('file change record uses hash as recordId', () {
      // Simulating the record structure from FilesSyncHandler.collectLocalChanges.
      final hash = 'abc123def456';
      final record = <String, dynamic>{
        'recordId': hash,
        'payload': {'hash': hash, 'path': '/some/path/image.png', 'size': 1024},
        'updatedAt': 1234567890,
      };

      expect(record['recordId'], hash);
      expect((record['payload'] as Map)['hash'], hash);
      expect((record['payload'] as Map)['path'], isNotEmpty);
      expect((record['payload'] as Map)['size'], isPositive);
    });

    test('empty hashes are filtered before server check', () {
      // Simulating the hash filtering from uploadPendingFiles.
      final localChanges = <Map<String, dynamic>>[
        {'recordId': 'hash1', 'payload': {}},
        {'recordId': '', 'payload': {}},
        {'recordId': 'hash3', 'payload': {}},
      ];
      final hashes = localChanges
          .map((c) => c['recordId'] as String)
          .where((h) => h.isNotEmpty)
          .toList();
      expect(hashes, ['hash1', 'hash3']);
    });
  });
}
