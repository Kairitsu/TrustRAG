import 'package:flutter_test/flutter_test.dart';
import 'package:client/features/documents/providers/document_provider.dart';

void main() {
  group('Document tags (folder) model', () {
    test('fromJson parses tags array', () {
      final doc = Document.fromJson({
        'id': 'abc',
        'workspace_id': 'ws1',
        'original_filename': 'test.txt',
        'file_type': 'txt',
        'file_size_bytes': 100,
        'processing_status': 'ready',
        'tags': ['research', 'notes'],
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(doc.tags, ['research', 'notes']);
    });

    test('fromJson handles null tags', () {
      final doc = Document.fromJson({
        'id': 'abc',
        'workspace_id': 'ws1',
        'original_filename': 'test.txt',
        'file_type': 'txt',
        'file_size_bytes': 100,
        'processing_status': 'ready',
        'tags': null,
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(doc.tags, isEmpty);
    });

    test('fromJson handles missing tags key', () {
      final doc = Document.fromJson({
        'id': 'abc',
        'workspace_id': 'ws1',
        'original_filename': 'test.txt',
        'file_type': 'txt',
        'file_size_bytes': 100,
        'processing_status': 'ready',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(doc.tags, isEmpty);
    });

    test('fromJson handles empty tags', () {
      final doc = Document.fromJson({
        'id': 'abc',
        'workspace_id': 'ws1',
        'original_filename': 'test.txt',
        'file_type': 'txt',
        'file_size_bytes': 100,
        'processing_status': 'ready',
        'tags': [],
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(doc.tags, isEmpty);
    });

    test('copyWith replaces tags', () {
      final doc = Document.fromJson({
        'id': 'abc',
        'workspace_id': 'ws1',
        'original_filename': 'test.txt',
        'file_type': 'txt',
        'file_size_bytes': 100,
        'processing_status': 'ready',
        'tags': ['old'],
        'created_at': '2026-01-01T00:00:00Z',
      });
      final updated = doc.copyWith(tags: ['new_folder']);
      expect(updated.tags, ['new_folder']);
      expect(updated.id, doc.id);
      expect(updated.originalFilename, doc.originalFilename);
    });

    test('copyWith preserves tags when not specified', () {
      final doc = Document.fromJson({
        'id': 'abc',
        'workspace_id': 'ws1',
        'original_filename': 'test.txt',
        'file_type': 'txt',
        'file_size_bytes': 100,
        'processing_status': 'ready',
        'tags': ['kept'],
        'created_at': '2026-01-01T00:00:00Z',
      });
      final copy = doc.copyWith();
      expect(copy.tags, ['kept']);
    });
  });

  group('Folder extraction logic', () {
    List<Document> makeDocs(List<List<String>> tagSets) {
      return tagSets.asMap().entries.map((e) {
        return Document.fromJson({
          'id': 'doc-${e.key}',
          'workspace_id': 'ws1',
          'original_filename': 'file-${e.key}.txt',
          'file_type': 'txt',
          'file_size_bytes': 10,
          'processing_status': 'ready',
          'tags': e.value,
          'created_at': '2026-01-01T00:00:00Z',
        });
      }).toList();
    }

    test('extracts unique folder names', () {
      final docs = makeDocs([
        ['a', 'b'],
        ['b', 'c'],
        ['a'],
      ]);
      final folders = <String>{};
      for (final d in docs) {
        folders.addAll(d.tags);
      }
      expect(folders, {'a', 'b', 'c'});
    });

    test('no folders when all docs have empty tags', () {
      final docs = makeDocs([[], [], []]);
      final folders = <String>{};
      for (final d in docs) {
        folders.addAll(d.tags);
      }
      expect(folders, isEmpty);
    });

    test('filters documents by folder', () {
      final docs = makeDocs([
        ['research'],
        ['notes'],
        ['research', 'notes'],
        [],
      ]);
      final filtered = docs.where((d) => d.tags.contains('research')).toList();
      expect(filtered.length, 2);
      expect(filtered[0].id, 'doc-0');
      expect(filtered[1].id, 'doc-2');
    });

    test('null folder shows all documents', () {
      final docs = makeDocs([
        ['research'],
        [],
      ]);
      const String? activeFolder = null;
      final filtered = activeFolder == null
          ? docs
          : docs.where((d) => d.tags.contains(activeFolder)).toList();
      expect(filtered.length, 2);
    });
  });
}
