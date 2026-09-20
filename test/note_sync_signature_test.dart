// Which notes need uploading. A note is sent only when it holds something the
// cloud does not, so an edit that was undone, or a delete that was restored
// before it synced, costs nothing. These need neither Hive nor the network.

import 'package:atomic_notes/database/note.dart';
import 'package:flutter_test/flutter_test.dart';

Note _synced({String title = 'title', String body = 'body'}) => Note.fromRemote({
      'id': 'note-1',
      'kind': 'text',
      'title': title,
      'body': body,
      'items': const [],
      'pinned': false,
      'deleted': false,
      'created_at': '2026-09-20T10:00:00Z',
      'updated_at': '2026-09-20T10:00:00Z',
      'version': 2,
    });

void main() {
  group('content signature', () {
    test('equal content gives an equal signature, whatever else differs', () {
      final a = Note(id: 'a', title: 't', body: 'b', dirty: true, serverVersion: 1);
      final b = Note(id: 'b', title: 't', body: 'b', serverVersion: 9)
        ..updatedAt = DateTime.utc(2001);
      expect(a.contentSig, b.contentSig);
    });

    test('every synced field changes it', () {
      final base = Note(id: 'a', title: 't', body: 'b', items: [TodoItem(text: 'x')]);
      final changed = <String, Note Function()>{
        'title': () => base.copy()..title = 't2',
        'body': () => base.copy()..body = 'b2',
        'kind': () => base.copy()..kind = NoteKind.todo,
        'pinned': () => base.copy()..pinned = true,
        'deleted': () => base.copy()..deleted = true,
        'item text': () => base.copy()..items.first.text = 'y',
        'item done': () => base.copy()..items.first.done = true,
        'item added': () => base.copy()..items.add(TodoItem(text: 'z')),
      };
      for (final entry in changed.entries) {
        expect(entry.value().contentSig, isNot(base.contentSig), reason: entry.key);
      }
    });

    test('it survives a copy and a save to disk', () {
      final note = _synced();
      expect(note.copy().contentSig, note.contentSig);
      expect(Note.fromMap(note.toMap()).contentSig, note.contentSig);
    });
  });

  group('what the cloud holds', () {
    test('a note that came from the cloud starts clean and remembers it', () {
      final note = _synced();
      expect(note.dirty, isFalse);
      expect(note.syncedSig, note.contentSig);
    });

    test('it is kept on disk, and a note from an older app has none', () {
      final note = _synced();
      expect(Note.fromMap(note.toMap()).syncedSig, note.syncedSig);
      final old = Map<String, dynamic>.from(note.toMap())..remove('syncedSig');
      expect(Note.fromMap(old).syncedSig, '');
    });
  });

  group('settleDirty', () {
    test('an edit that is undone needs no upload', () {
      final note = _synced(title: 'one');
      note
        ..title = 'two'
        ..touch();
      expect(note.settleDirty(), isFalse);
      expect(note.dirty, isTrue);

      note
        ..title = 'one'
        ..touch();
      expect(note.settleDirty(), isTrue);
      expect(note.dirty, isFalse);
    });

    test('saving without a change needs no upload', () {
      final note = _synced()..touch();
      expect(note.dirty, isTrue);
      expect(note.settleDirty(), isTrue);
      expect(note.dirty, isFalse);
    });

    test('a delete that is restored before it synced needs no upload', () {
      final note = _synced();
      note
        ..deleted = true
        ..touch();
      expect(note.settleDirty(), isFalse);
      note
        ..deleted = false
        ..touch();
      expect(note.settleDirty(), isTrue);
    });

    test('a restore after the deletion synced is still sent', () {
      final note = _synced();
      note
        ..deleted = true
        ..touch();
      // The deletion reached the cloud.
      note
        ..syncedSig = note.contentSig
        ..dirty = false;
      note
        ..deleted = false
        ..touch();
      expect(note.settleDirty(), isFalse);
      expect(note.dirty, isTrue);
    });

    test('a new note is always sent', () {
      final note = Note.create()..title = 'new';
      expect(note.settleDirty(), isFalse);
      expect(note.dirty, isTrue);
    });

    test('a note whose cloud copy is unknown is sent', () {
      final note = _synced()
        ..syncedSig = ''
        ..touch();
      expect(note.settleDirty(), isFalse);
      expect(note.dirty, isTrue);
    });

    test('a forced upload clears what the cloud is believed to hold', () {
      final note = _synced()
        ..syncedSig = ''
        ..dirty = true;
      expect(note.settleDirty(), isFalse);
      expect(note.dirty, isTrue);
    });
  });
}
