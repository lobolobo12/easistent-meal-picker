import 'dart:convert';
import 'dart:io';

import 'meal_week.dart';

/// A stand-in for eAsistent, served over a real socket on localhost.
///
/// This is deliberately not a mock of the client's internals. The client
/// talks to it with its own `HttpClient`, so the parts that actually decide
/// whether Monday's unattended submit works — form encoding, the manual
/// cookie jar, redirect following, the timeouts — all execute for real. Only
/// the far end is fake, so no order is ever placed on a live account.
class FakeEasistent {
  late HttpServer _server;

  /// Every meal action the client submitted, in order.
  final List<Map<String, String>> submissions = [];

  /// Every request path the client hit, in order.
  final List<String> requests = [];

  /// Cookies the client sent back on the most recent request.
  final List<String> lastRequestCookies = [];

  /// What `/dijaki/ajax_prehrana_obroki_prijava` should answer with.
  /// Default is the success envelope.
  String submitResponse = '{"status":"ok"}';
  ContentType submitContentType = ContentType.json;

  /// When set, the login endpoint answers with this instead of success.
  String? loginResponseOverride;

  /// Hang forever on this path instead of responding, to exercise timeouts.
  String? blackholePath;

  /// Bounce this path to itself forever, to exercise the redirect cap.
  String? redirectLoopPath;

  String get origin => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    requests.add(path);
    lastRequestCookies
      ..clear()
      ..addAll(req.cookies.map((c) => '${c.name}=${c.value}'));

    if (path == blackholePath) {
      // Never respond and never close: the client must time out on its own.
      return;
    }

    if (path == redirectLoopPath) {
      req.response.statusCode = HttpStatus.found;
      req.response.headers.set('location', redirectLoopPath!);
      await req.response.close();
      return;
    }

    switch (path) {
      case '/p/ajax_prijava':
        await _login(req);
      case '/session':
        await _session(req);
      case '/prehrana/dijaki':
        await _mealPage(req);
      case '/dijaki/ajax_prehrana_obroki_seznam':
        await _weekList(req);
      case '/dijaki/ajax_prehrana_obroki_prijava':
        await _submit(req);
      default:
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
    }
  }

  Future<void> _login(HttpRequest req) async {
    final form = _parseForm(await _readBody(req));

    if (loginResponseOverride != null) {
      req.response.headers.contentType = ContentType.json;
      req.response.write(loginResponseOverride);
      await req.response.close();
      return;
    }

    if (form['uporabnik'] != 'student' || form['geslo'] != 'correct-horse') {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'errfields': ['uporabnik'],
      }));
      await req.response.close();
      return;
    }

    // Success: hand back a redirect target, exactly as the real site does.
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode({
      'errfields': [],
      'data': {'prijava_redirect': '$origin/session'},
    }));
    await req.response.close();
  }

  /// The hop that establishes the session. The real site sets an opaque
  /// `v1.` token here, which is the shape that used to crash login.
  Future<void> _session(HttpRequest req) async {
    req.response.cookies.add(Cookie('easistent_session', 'abc123'));
    req.response.cookies
        .add(Cookie('ses', 'v1.T1Jsk36gmOpaqueEncryptedBlob'));
    req.response.write('<html><body>ok</body></html>');
    await req.response.close();
  }

  Future<void> _mealPage(HttpRequest req) async {
    req.response.headers.contentType = ContentType.html;
    req.response.write(kMealWeekHtml + kWeekSelectHtml);
    await req.response.close();
  }

  /// The week endpoint answers with 0x1f-separated parts; the HTML is third.
  Future<void> _weekList(HttpRequest req) async {
    await _readBody(req);
    req.response.write('a\x1fb\x1f$kMealWeekHtml');
    await req.response.close();
  }

  Future<void> _submit(HttpRequest req) async {
    submissions.add(_parseForm(await _readBody(req)));
    req.response.headers.contentType = submitContentType;
    req.response.write(submitResponse);
    await req.response.close();
  }

  static Future<String> _readBody(HttpRequest req) =>
      utf8.decoder.bind(req).join();

  static Map<String, String> _parseForm(String body) => {
        for (final pair in body.split('&'))
          if (pair.contains('='))
            Uri.decodeComponent(pair.split('=').first):
                Uri.decodeComponent(pair.split('=').sublist(1).join('=')),
      };
}
