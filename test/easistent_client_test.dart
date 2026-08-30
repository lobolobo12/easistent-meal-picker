import 'dart:io';

import 'package:easistent_meal_picker/services/easistent_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/fake_easistent.dart';

void main() {
  late FakeEasistent server;

  setUp(() async {
    server = FakeEasistent();
    await server.start();
  });

  tearDown(() => server.stop());

  EAsistentClient client({
    String user = 'student',
    String pass = 'correct-horse',
    Duration? request,
    Duration? total,
  }) =>
      EAsistentClient(
        username: user,
        password: pass,
        origin: server.origin,
        requestTimeout: request ?? const Duration(seconds: 5),
        totalTimeout: total ?? const Duration(seconds: 10),
      );

  group('login', () {
    test('succeeds and follows the redirect to the session hop', () async {
      final c = client();
      await c.login();

      expect(c.isLoggedIn, isTrue);
      expect(server.requests, containsAllInOrder(
          ['/p/ajax_prijava', '/session']));
      c.close();
    });

    test('survives the opaque v1. ses cookie', () async {
      // This is the exact shape that broke login on the live site: the
      // cookie is no longer JSON, so parsing it must stay optional.
      final c = client();
      await c.login();

      expect(c.isLoggedIn, isTrue);
      expect(c.accessToken, isNull);
      c.close();
    });

    test('rejects bad credentials with a readable message', () async {
      final c = client(pass: 'wrong');
      await expectLater(
        c.login(),
        throwsA(predicate((e) => e.toString().contains('Login failed'))),
      );
      c.close();
    });

    test('an HTML error page does not surface as a raw FormatException',
        () async {
      server.loginResponseOverride = '<html><body>503</body></html>';
      final c = client();
      await expectLater(
        c.login(),
        throwsA(predicate((e) =>
            e.toString().contains('did not return JSON') &&
            !e.toString().startsWith('FormatException'))),
      );
      c.close();
    });
  });

  group('session cookies', () {
    test('are replayed on later requests', () async {
      final c = client();
      await c.login();
      await c.getWeeklyMenu();

      expect(server.lastRequestCookies, contains('easistent_session=abc123'));
      c.close();
    });
  });

  group('submitting a meal', () {
    // This is the path that runs unattended on Monday evening and the one
    // that has never been exercised against the live site on purpose.
    test('sends the exact form the site expects', () async {
      final c = client();
      await c.login();

      final ok = await c.selectMeal(
        date: '2025-09-01',
        menuId: '101',
        locationId: '15856',
      );

      expect(ok, isTrue);
      expect(server.submissions, hasLength(1));
      expect(server.submissions.single, {
        'tip_prehrane': 'malica',
        'id_meni': '101',
        'datum': '2025-09-01',
        'akcija': 'prijava',
        'id_lokacija': '15856',
      });
      c.close();
    });

    test('cancelMeal differs only in the action field', () async {
      final c = client();
      await c.login();

      await c.cancelMeal(
        date: '2025-09-02',
        menuId: '102',
        locationId: '15856',
      );

      expect(server.submissions.single['akcija'], 'odjava');
      expect(server.submissions.single['datum'], '2025-09-02');
      c.close();
    });

    test('carries a non-default meal type through', () async {
      final c = client();
      await c.login();
      await c.selectMeal(
        date: '2025-09-01',
        menuId: '101',
        locationId: '15856',
        mealType: 'kosilo',
      );
      expect(server.submissions.single['tip_prehrane'], 'kosilo');
      c.close();
    });

    test('a logout envelope raises SessionExpiredException', () async {
      server.submitResponse = '{"status":"logout"}';
      final c = client();
      await c.login();

      await expectLater(
        c.selectMeal(
            date: '2025-09-01', menuId: '101', locationId: '15856'),
        throwsA(isA<SessionExpiredException>()),
      );
      c.close();
    });

    test('an HTML login page raises SessionExpiredException, not a parse error',
        () async {
      // The regression this guards: an expired session answers with the
      // login page, and the unguarded jsonDecode turned that into a bare
      // FormatException on the one call that places a real order.
      server.submitResponse =
          '<html><body><form action="/p/prijava"></form></body></html>';
      server.submitContentType = ContentType.html;
      final c = client();
      await c.login();

      await expectLater(
        c.selectMeal(
            date: '2025-09-01', menuId: '101', locationId: '15856'),
        throwsA(isA<SessionExpiredException>()),
      );
      c.close();
    });

    test('a rejection names the failing fields', () async {
      server.submitResponse = '{"status":"error","errfields":["datum"]}';
      final c = client();
      await c.login();

      await expectLater(
        c.selectMeal(
            date: '2025-01-01', menuId: '101', locationId: '15856'),
        throwsA(predicate((e) => e.toString().contains('datum'))),
      );
      c.close();
    });

    test('unparseable non-HTML output reports the status and body', () async {
      server.submitResponse = 'kaboom';
      server.submitContentType = ContentType.text;
      final c = client();
      await c.login();

      await expectLater(
        c.selectMeal(
            date: '2025-09-01', menuId: '101', locationId: '15856'),
        throwsA(predicate((e) =>
            e.toString().contains('did not return JSON') &&
            e.toString().contains('kaboom'))),
      );
      c.close();
    });
  });

  group('fetching the menu', () {
    test('parses the week into days and options', () async {
      final c = client();
      await c.login();
      final menu = await c.getWeeklyMenu();

      expect(menu.keys, containsAll(['2025-09-01', '2025-09-02']));
      expect(menu['2025-09-01'], hasLength(2));
      c.close();
    });

    test('a specific week goes through the 0x1f-separated endpoint',
        () async {
      final c = client();
      await c.login();
      final menu = await c.getWeeklyMenu(week: 36);

      expect(server.requests,
          contains('/dijaki/ajax_prehrana_obroki_seznam'));
      expect(menu['2025-09-01'], isNotEmpty);
      c.close();
    });
  });

  group('hang protection', () {
    test('a server that never answers times out instead of hanging',
        () async {
      // Before the timeout existed this call never returned, which on a
      // Monday evening meant the submit silently never happened.
      server.blackholePath = '/prehrana/dijaki';
      final c = client(
        request: const Duration(milliseconds: 300),
        total: const Duration(milliseconds: 600),
      );
      await c.login();

      await expectLater(
        c.getWeeklyMenu(),
        throwsA(predicate((e) => e.toString().contains('timed out'))),
      );
      c.close();
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('a redirect cycle terminates instead of spinning forever', () async {
      server.redirectLoopPath = '/prehrana/dijaki';
      final c = client();
      await c.login();

      await expectLater(
        c.getWeeklyMenu(),
        throwsA(predicate((e) => e.toString().contains('Too many redirects'))),
      );
      c.close();
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
