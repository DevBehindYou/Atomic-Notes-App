// Wire-format tests for the Note model that need neither Hive nor the network.
// The Server enforces versions; these check the App sends and reads them.

import 'package:atomic_notes/database/note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Note remote format', () {
    test('toRemote sends the base version and leaves updated_at to the Server', () {
      final note = Note(
        id: newId(),
        title: 'title',
        serverVersion: 3,
        items: [TodoItem(text: 'milk', done: true)],
      );
      final map = note.toRemote('user-1');
      expect(map['base_version'], 3);
      expect(map.containsKey('updated_at'), isFalse);
      expect(map['user_id'], 'user-1');
      expect(map['items'], equals([
        {'t': 'milk', 'd': true},
      ]));
    });

    test('fromRemote reads the Server version and both to-do key styles', () {
      final note = Note.fromRemote({
        'id': 'abc',
        'kind': 'todo',
        'title': 'list',
        'body': '',
        'items': [
          {'text': 'one', 'done': true},
          {'t': 'two', 'd': false},
        ],
        'pinned': true,
        'deleted': false,
        'created_at': '2026-09-15T10:00:00Z',
        'updated_at': '2026-09-15T11:00:00.500Z',
        'version': 7,
      });
      expect(note.serverVersion, 7);
      expect(note.dirty, isFalse);
      expect(note.kind, NoteKind.todo);
      expect(note.pinned, isTrue);
      expect(note.items.map((i) => i.text), ['one', 'two']);
      expect(note.items.map((i) => i.done), [true, false]);
      expect(note.updatedAt, DateTime.utc(2026, 9, 15, 11, 0, 0, 500));
    });

    test('a row without a version is treated as never synced', () {
      final note = Note.fromRemote({'id': 'abc', 'kind': 'text'});
      expect(note.serverVersion, 0);
    });
  });

  group('Note local format', () {
    test('Hive map round trip keeps the dirty flag and Server version', () {
      final note = Note(id: newId(), title: 'a', body: 'b', dirty: true, serverVersion: 5);
      final restored = Note.fromMap(note.toMap());
      expect(restored.dirty, isTrue);
      expect(restored.serverVersion, 5);
      expect(restored.title, 'a');
      expect(restored.body, 'b');
    });

    test('copy is independent of the original', () {
      final note = Note(id: newId(), items: [TodoItem(text: 'x')]);
      final copy = note.copy();
      copy.items.first.text = 'changed';
      copy.title = 'other';
      expect(note.items.first.text, 'x');
      expect(note.title, '');
    });

    test('touch marks a note dirty', () {
      final note = Note(id: newId());
      expect(note.dirty, isFalse);
      note.touch();
      expect(note.dirty, isTrue);
    });
  });

  group('newId', () {
    test('produces distinct RFC 4122 version 4 ids', () {
      final pattern = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      final ids = {for (var i = 0; i < 50; i++) newId()};
      expect(ids.length, 50);
      expect(ids.every(pattern.hasMatch), isTrue);
    });
  });
}
