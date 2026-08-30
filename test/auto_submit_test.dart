import 'dart:convert';
import 'dart:io';

import 'package:easistent_meal_picker/services/app_files.dart';
import 'package:easistent_meal_picker/services/easistent_client.dart';
import 'package:easistent_meal_picker/services/scheduler_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'fixtures/fake_easistent.dart';

/// End-to-end rehearsal of the unattended Monday submit.
///
/// This drives the real `_handleAutoSubmit` — the same function the Android
/// alarm and the iOS catch-up call — with only two things replaced: the
/// server it talks to, and the clock it reads. Everything in between is the
/// shipping code: the gate, the weekly marker, credential loading, building
/// the predictor from the stored files, choosing per day, submitting, and
/// writing the log.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();

  late Directory tmp;
  late FakeEasistent server;

  /// Monday 1 September 2025, 18:00 in Ljubljana — when the alarm fires.
  tz.TZDateTime mondayEvening(tz.Location loc) =>
      tz.TZDateTime(loc, 2025, 9, 1, 18, 0);

  setUp(() async {
    // TestWidgetsFlutterBinding installs HttpClient overrides that answer
    // every request with 400 and never open a socket. This suite wants the
    // real client talking to the local stand-in, so take them back off.
    HttpOverrides.global = null;

    tmp = Directory.systemTemp.createTempSync('meal_picker_autosubmit');
    AppFiles.overrideDirForTesting(tmp);

    server = FakeEasistent();
    await server.start();

    schedulerClientFactory = (u, p) => EAsistentClient(
          username: u,
          password: p,
          origin: server.origin,
          requestTimeout: const Duration(seconds: 5),
          totalTimeout: const Duration(seconds: 10),
        );
    schedulerClockOverride = mondayEvening;

    // The notification plugin has no platform side in a test; let its
    // channel answer so the scheduler's guarded calls are no-ops.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => null,
    );
  });

  tearDown(() async {
    await server.stop();
    schedulerClockOverride = null;
    schedulerClientFactory =
        (u, p) => EAsistentClient(username: u, password: p);
    AppFiles.overrideDirForTesting(null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  void writeFile(String name, Object content) => File('${tmp.path}/$name')
      .writeAsStringSync(content is String ? content : jsonEncode(content));

  void giveCredentials() => writeFile(
      AppFiles.credentials,
      {'username': 'student', 'password': 'correct-horse'});

  /// Training that makes Meni 2 ("pica") the clear favourite.
  void giveTrainingData() => writeFile(AppFiles.trainingData, [
        for (var i = 0; i < 3; i++)
          {
            'date': '2025-06-0${i + 1}',
            'options': [
              {
                'menu_id': '101',
                'menu_name': 'Meni 1',
                'description': 'ričet s klobaso',
                'chosen': false,
              },
              {
                'menu_id': '102',
                'menu_name': 'Meni 5 (XXL+0,80 EUR)',
                'description': 'pica margarita, solata',
                'chosen': true,
              },
            ],
          }
      ]);

  group('the Monday run', () {
    test('logs in, picks per day, and submits', () async {
      giveCredentials();
      giveTrainingData();

      await runAutoSubmitForTesting();

      // Two days in the fixture week, both submitted.
      expect(server.submissions, hasLength(2));
      expect(
        server.submissions.map((s) => s['datum']).toSet(),
        {'2025-09-01', '2025-09-02'},
      );
      for (final s in server.submissions) {
        expect(s['akcija'], 'prijava');
        expect(s['id_lokacija'], '15856');
        expect(s['tip_prehrane'], 'malica');
      }
    });

    test('submits what the trained model actually prefers', () async {
      giveCredentials();
      giveTrainingData();

      await runAutoSubmitForTesting();

      // Monday's options are Meni 1 (ričet) and Meni 5 (pica). The model was
      // trained to prefer the pica, which is menu id 102 in the fixture.
      final monday = server.submissions
          .firstWhere((s) => s['datum'] == '2025-09-01');
      expect(monday['id_meni'], '102');
    });

    test('writes a submission log entry per day', () async {
      giveCredentials();
      giveTrainingData();

      await runAutoSubmitForTesting();

      final log = await const JsonFile(AppFiles.submissionLog).readList();
      expect(log, hasLength(2));
      expect(log.every((e) => e['auto'] == true), isTrue);
      expect(log.map((e) => e['date']).toSet(),
          {'2025-09-01', '2025-09-02'});
    });

    test('stamps the weekly marker with this Monday', () async {
      giveCredentials();
      giveTrainingData();

      await runAutoSubmitForTesting();

      expect(await const MarkerFile(AppFiles.autoSubmitMarker).read(),
          '2025-09-01');
    });
  });

  group('things that must stop it', () {
    test('a second run in the same week submits nothing', () async {
      giveCredentials();
      giveTrainingData();

      await runAutoSubmitForTesting();
      final afterFirst = server.submissions.length;
      await runAutoSubmitForTesting();

      expect(server.submissions, hasLength(afterFirst));
    });

    test('days already in the log are skipped', () async {
      giveCredentials();
      giveTrainingData();
      writeFile(AppFiles.submissionLog, [
        {'date': '2025-09-01', 'menuName': 'Meni 1', 'menuId': '101'}
      ]);

      await runAutoSubmitForTesting();

      expect(server.submissions.map((s) => s['datum']), ['2025-09-02']);
    });

    test('days inside an absence range are skipped', () async {
      giveCredentials();
      giveTrainingData();
      writeFile(AppFiles.absences, [
        {'from': '2025-09-01', 'to': '2025-09-01'}
      ]);

      await runAutoSubmitForTesting();

      expect(server.submissions.map((s) => s['datum']), ['2025-09-02']);
    });

    test('no credentials means no requests at all', () async {
      giveTrainingData();

      await runAutoSubmitForTesting();

      expect(server.requests, isEmpty);
      expect(server.submissions, isEmpty);
    });

    test('the wrong day of the week is refused', () async {
      giveCredentials();
      giveTrainingData();
      // Wednesday.
      schedulerClockOverride =
          (loc) => tz.TZDateTime(loc, 2025, 9, 3, 18, 0);

      await runAutoSubmitForTesting();

      expect(server.requests, isEmpty);
    });

    test('Monday before 17:00 is refused', () async {
      giveCredentials();
      giveTrainingData();
      schedulerClockOverride =
          (loc) => tz.TZDateTime(loc, 2025, 9, 1, 9, 0);

      await runAutoSubmitForTesting();

      expect(server.requests, isEmpty);
    });

    test('the relaxed iOS gate does allow a weekday catch-up', () async {
      giveCredentials();
      giveTrainingData();
      schedulerClockOverride =
          (loc) => tz.TZDateTime(loc, 2025, 9, 3, 9, 0);

      await runAutoSubmitForTesting(relaxedGate: true);

      expect(server.submissions, hasLength(2));
    });
  });

  group('failures must not corrupt state', () {
    test('a server that rejects every submit leaves the log empty',
        () async {
      giveCredentials();
      giveTrainingData();
      server.submitResponse = '{"status":"error","errfields":["datum"]}';

      await runAutoSubmitForTesting();

      final log = await const JsonFile(AppFiles.submissionLog).readList();
      expect(log, isEmpty);
    });

    test('a hung server does not hang the alarm', () async {
      giveCredentials();
      giveTrainingData();
      server.blackholePath = '/prehrana/dijaki';
      schedulerClientFactory = (u, p) => EAsistentClient(
            username: u,
            password: p,
            origin: server.origin,
            requestTimeout: const Duration(milliseconds: 300),
            totalTimeout: const Duration(milliseconds: 600),
          );

      // The assertion is that this returns at all.
      await runAutoSubmitForTesting();

      expect(server.submissions, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('a corrupt training file does not stop the submit', () async {
      giveCredentials();
      File('${tmp.path}/${AppFiles.trainingData}')
          .writeAsStringSync('[{"date": "2025-0');

      await runAutoSubmitForTesting();

      // No model to speak of, but the day still gets an order rather than
      // the whole run dying on a half-written file.
      expect(server.submissions, isNotEmpty);
    });
  });
}
