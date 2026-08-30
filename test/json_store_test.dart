import 'dart:convert';
import 'dart:io';

import 'package:easistent_meal_picker/services/app_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('meal_picker_store_test');
    AppFiles.overrideDirForTesting(tmp);
  });

  tearDown(() {
    AppFiles.overrideDirForTesting(null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  const store = JsonFile('probe.json');

  group('read', () {
    test('returns null when the file does not exist', () async {
      expect(await store.read(), isNull);
    });

    test('round-trips a written document', () async {
      await store.write([
        {'date': '2025-09-01', 'menuId': '101'}
      ]);
      expect(await store.read(), [
        {'date': '2025-09-01', 'menuId': '101'}
      ]);
    });

    test('treats an empty file as absent', () async {
      File('${tmp.path}/probe.json').writeAsStringSync('   ');
      expect(await store.read(), isNull);
    });
  });

  group('corrupt file recovery', () {
    // The background alarm writes these files and Android can kill it
    // mid-write. Before this the truncated JSON escaped as an exception from
    // TrainingStore.load() and took the app down on the next launch.
    test('a truncated document reads as null instead of throwing', () async {
      File('${tmp.path}/probe.json').writeAsStringSync('[{"date": "2025-0');
      expect(await store.read(), isNull);
    });

    test('the bad file is quarantined, not deleted', () async {
      File('${tmp.path}/probe.json').writeAsStringSync('[{"date": "2025-0');
      await store.read();

      expect(File('${tmp.path}/probe.json').existsSync(), isFalse);
      final quarantined = File('${tmp.path}/probe.json.corrupt');
      expect(quarantined.existsSync(), isTrue);
      // The user's data is still there to salvage.
      expect(quarantined.readAsStringSync(), '[{"date": "2025-0');
    });

    test('a later write recovers the store', () async {
      File('${tmp.path}/probe.json').writeAsStringSync('not json');
      expect(await store.read(), isNull);
      await store.write({'ok': true});
      expect(await store.read(), {'ok': true});
    });
  });

  group('atomic write', () {
    test('leaves no temp file behind', () async {
      await store.write({'a': 1});
      final leftovers = tmp
          .listSync()
          .map((e) => e.path.split(Platform.pathSeparator).last)
          .toList();
      expect(leftovers, ['probe.json']);
    });

    test('an interrupted write cannot leave a half document', () async {
      await store.write({'generation': 1});

      // Simulate the kill: the temp file exists with partial content, but
      // the rename never ran.
      File('${tmp.path}/probe.json.tmp').writeAsStringSync('{"generation": 2');

      // The real document is untouched and still readable.
      expect(await store.read(), {'generation': 1});
    });
  });

  group('shape helpers', () {
    test('readList drops non-map entries rather than crashing', () async {
      File('${tmp.path}/probe.json')
          .writeAsStringSync(jsonEncode([{'a': 1}, 'junk', 42, null]));
      expect(await store.readList(), [
        {'a': 1}
      ]);
    });

    test('readList returns empty when the document is a map', () async {
      await store.write({'not': 'a list'});
      expect(await store.readList(), isEmpty);
    });

    test('readMap returns empty when the document is a list', () async {
      await store.write([1, 2, 3]);
      expect(await store.readMap(), isEmpty);
    });
  });

  group('MarkerFile', () {
    const marker = MarkerFile('probe_marker.txt');

    test('reads back what was written, trimmed', () async {
      await marker.write('2025-09-01');
      expect(await marker.read(), '2025-09-01');
      expect(await marker.matches('2025-09-01'), isTrue);
      expect(await marker.matches('2025-09-02'), isFalse);
    });

    test('missing marker reads null and matches nothing', () async {
      expect(await marker.read(), isNull);
      expect(await marker.matches('anything'), isFalse);
    });

    test('delete removes it', () async {
      await marker.write('x');
      await marker.delete();
      expect(await marker.read(), isNull);
    });
  });
}
