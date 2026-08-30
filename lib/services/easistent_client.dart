import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;

import '../models/meal_option.dart';

/// Client for the eAsistent school platform.
///
/// Login flow:
/// 1. POST /p/ajax_prijava with credentials
/// 2. Follow the redirect URL from the response JSON
/// 3. Extract the `ses` cookie set on moj.easistent.com
/// 4. Parse accessToken, activeChildId from the ses cookie JSON
/// 5. Use these as headers for subsequent requests
class EAsistentClient {
  static const defaultOrigin = 'https://www.easistent.com';

  /// Server root. Overridable so the test suite can point the client at a
  /// local stand-in and exercise the real cookie, redirect and submit paths
  /// without touching a live account — see `test/easistent_client_test.dart`.
  final String origin;

  String get _loginUrl => '$origin/p/ajax_prijava';
  // /prehrana now 307s here; naming the real target saves a round-trip.
  String get _mealPageUrl => '$origin/prehrana/dijaki';
  String get _mealListUrl => '$origin/dijaki/ajax_prehrana_obroki_seznam';
  String get _mealSelectUrl => '$origin/dijaki/ajax_prehrana_obroki_prijava';

  /// Per-request ceiling. Without this every call could hang forever: the
  /// Monday 18:00 alarm gets a few seconds of wall clock from the OS, and a
  /// socket that never answers meant the submit silently never happened.
  final Duration requestTimeout;

  /// Ceiling on one login/fetch/submit including all of its redirect hops.
  final Duration totalTimeout;

  /// eAsistent's login bounces through two or three hops. Ten is generous
  /// and still terminates: the loop had no cap at all, so a server-side
  /// redirect cycle span forever.
  static const _maxRedirects = 10;

  final String username;
  final String password;

  String? accessToken;
  String? childId;
  String? refreshToken;

  late HttpClient _httpClient;
  final Map<String, String> _headers = {};
  // Manual cookie store keyed by domain
  final Map<String, List<Cookie>> _cookies = {};

  bool _loggedIn = false;

  /// True once the session cookies are established. Deliberately not tied to
  /// [accessToken]: eAsistent no longer exposes it (see [login]).
  bool get isLoggedIn => _loggedIn;

  EAsistentClient({
    required this.username,
    required this.password,
    this.origin = defaultOrigin,
    this.requestTimeout = const Duration(seconds: 20),
    this.totalTimeout = const Duration(seconds: 45),
  }) {
    _httpClient = HttpClient()
      ..autoUncompress = true
      // Don't auto-follow redirects so we can capture cookies at each hop
      ..maxConnectionsPerHost = 4;
  }

  /// Full login sequence. Throws on failure.
  Future<void> login() async {
    // 1. POST login
    final loginBody = {
      'uporabnik': username,
      'geslo': password,
      'pin': '',
      'captcha': '',
      'koda': '',
    };

    final loginResp = await _post(_loginUrl, loginBody);
    final dynamic loginJson;
    try {
      loginJson = jsonDecode(loginResp.body);
    } on FormatException catch (e) {
      // Say which step failed and what came back. A bare FormatException
      // here is indistinguishable from the ses-cookie one below.
      final head = loginResp.body.length > 120
          ? '${loginResp.body.substring(0, 120)}...'
          : loginResp.body;
      throw Exception(
          'Login failed: /ajax_prijava did not return JSON '
          '(HTTP ${loginResp.statusCode}). Body starts: "$head" [$e]');
    }

    if (loginJson['errfields'] != null &&
        (loginJson['errfields'] as List).isNotEmpty) {
      throw Exception('Login failed: ${loginJson['errfields']}');
    }

    final redirectUrl = loginJson['data']?['prijava_redirect'] as String?;
    if (redirectUrl == null) {
      throw Exception('Login failed: no redirect URL in response');
    }

    // 2. GET the redirect URL (this sets the ses cookie on moj.easistent.com)
    await _get(redirectUrl);

    // 3. Extract ses cookie from moj.easistent.com
    final mojCookies = _cookies['moj.easistent.com'] ?? [];
    final sesCookie = mojCookies.cast<Cookie?>().firstWhere(
          (c) => c!.name == 'ses',
          orElse: () => null,
        );

    // The ses cookie used to be URL-encoded JSON carrying accessToken and
    // activeChildId. eAsistent now issues an opaque, encrypted "v1." token,
    // so those fields cannot be read out of it any more. The meal endpoints
    // authenticate from the easistent_session / easistent_auth_token cookies
    // alone — verified against the live site — so treat the tokens as a
    // bonus, not a requirement. Parsing is still attempted so that an
    // account still being served the old format keeps sending the headers.
    if (sesCookie != null) {
      try {
        final sesJson = jsonDecode(Uri.decodeComponent(sesCookie.value));
        accessToken = sesJson['accessToken'] as String?;
        childId = sesJson['activeChildId']?.toString();
        refreshToken = sesJson['refreshToken'] as String?;
      } on FormatException {
        // Opaque token — expected on current eAsistent. Cookies carry the
        // session, so there is nothing to recover here.
      }
    }

    // 4. Set headers for future requests. The auth pair is only sent when the
    // old-format cookie actually yielded them.
    _headers.addAll({
      if (accessToken != null) 'Authorization': accessToken!,
      if (childId != null) 'X-Child-Id': childId!,
      'X-Client-Version': '13',
      'X-Client-Platform': 'web',
      'X-Requested-With': 'XMLHttpRequest',
    });
    _loggedIn = true;
  }

  /// Clear session state and re-login with existing credentials.
  Future<void> relogin() async {
    accessToken = null;
    childId = null;
    refreshToken = null;
    _loggedIn = false;
    _headers.clear();
    _cookies.clear();
    await login();
  }

  /// Fetch the meal page HTML. Optionally fetch a specific [week].
  Future<String> getMealPage({int? week}) async {
    final resp = await _get(_mealPageUrl);
    var html = resp.body;

    if (week != null) {
      final weekResp = await _post(_mealListUrl, {
        'qversion': '1',
        'teden': week.toString(),
        'smer': 'false',
      });
      final parts = weekResp.body.split('\x1f');
      html = parts.length >= 3 ? parts[2] : weekResp.body;
    }

    return html;
  }

  /// Find the current week number from the meal page HTML.
  int? findCurrentWeek(String html) {
    // Scope to #dijaki-prehrana-teden select first
    final selectRe = RegExp(
      r'id="dijaki-prehrana-teden"[^>]*>(.+?)</select>',
      dotAll: true,
    );
    final selectMatch = selectRe.firstMatch(html);
    if (selectMatch == null) return null;

    final weekRe = RegExp(r'value="(\d+)"[^>]*selected="selected"');
    final weekMatch = weekRe.firstMatch(selectMatch.group(1)!);
    if (weekMatch == null) return null;

    return int.tryParse(weekMatch.group(1)!);
  }

  /// Select a meal for a given date.
  Future<bool> selectMeal({
    required String date,
    required String menuId,
    required String locationId,
    String mealType = 'malica',
  }) =>
      _setMeal(
        date: date,
        menuId: menuId,
        locationId: locationId,
        mealType: mealType,
        action: 'prijava',
      );

  /// Cancel (odjava) an existing meal order for a given date.
  Future<bool> cancelMeal({
    required String date,
    required String menuId,
    required String locationId,
    String mealType = 'malica',
  }) =>
      _setMeal(
        date: date,
        menuId: menuId,
        locationId: locationId,
        mealType: mealType,
        action: 'odjava',
      );

  /// Both meal actions hit the same endpoint and differ only in `akcija`.
  Future<bool> _setMeal({
    required String date,
    required String menuId,
    required String locationId,
    required String mealType,
    required String action,
  }) async {
    final resp = await _post(_mealSelectUrl, {
      'tip_prehrane': mealType,
      'id_meni': menuId,
      'datum': date,
      'akcija': action,
      'id_lokacija': locationId,
    });

    // An expired session answers with the HTML login page, not JSON. The
    // unguarded `jsonDecode` here surfaced that as a bare FormatException —
    // the same opaque failure the login path used to produce, and on the
    // one call that actually places an order.
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      if (resp.statusCode == 200 && resp.body.contains('prijava')) {
        throw SessionExpiredException();
      }
      throw Exception(
          'Meal $action failed: server did not return JSON '
          '(HTTP ${resp.statusCode}). ${_bodyHead(resp.body)}');
    }

    if (data['status'] == 'ok') return true;
    if (data['status'] == 'logout') throw SessionExpiredException();
    throw Exception('Meal $action failed: ${data['errfields']}');
  }

  static String _bodyHead(String body) {
    final trimmed = body.trim();
    return trimmed.length > 120
        ? 'Body starts: "${trimmed.substring(0, 120)}..."'
        : 'Body: "$trimmed"';
  }

  /// Parse meal table HTML into a map of date → list of meal options.
  Map<String, List<MealOption>> parseMealTable(String html) {
    final document = html_parser.parse(html);

    // Extract dates from column headers: id="dijaki-prehrana-dan-YYYY-MM-DD"
    final dateRe = RegExp(r'dijaki-prehrana-dan-(\d{4}-\d{2}-\d{2})');
    final dates = <String>[];
    for (final div
        in document.querySelectorAll('div[id^="dijaki-prehrana-dan-"]')) {
      final match = dateRe.firstMatch(div.attributes['id'] ?? '');
      if (match != null) dates.add(match.group(1)!);
    }

    final menu = <String, List<MealOption>>{};
    for (final date in dates) {
      menu[date] = [];
    }

    // Parse each meal cell by id pattern:
    // ednevnik-seznam_ur_teden-td-{mealType}-{menuId}-{date}-{locationId}
    // mealType varies by school: malica, kosilo, etc.
    final cellRe = RegExp(
        r'ednevnik-seznam_ur_teden-td-([a-zA-Z_]+)-(\d+)-(\d{4}-\d{2}-\d{2})-(\d+)$');
    for (final td in document
        .querySelectorAll('td[id^="ednevnik-seznam_ur_teden-td-"]')) {
      final tdId = td.attributes['id'] ?? '';
      final match = cellRe.firstMatch(tdId);
      if (match == null) continue;

      final mealType = match.group(1)!;
      final menuId = match.group(2)!;
      final date = match.group(3)!;
      final locationId = match.group(4)!;

      if (!menu.containsKey(date)) continue;

      // Menu name: first div with font-size in style
      final nameDiv = td
          .querySelectorAll('div')
          .where((d) => (d.attributes['style'] ?? '').contains('font-size'))
          .firstOrNull;
      final menuName = nameDiv?.text.trim() ?? '';

      // Food description: div.bold
      final descDiv = td.querySelector('div.bold');
      final description = descDiv?.text.trim() ?? '';

      // Status from the action div (id ends with -akcija)
      String status;
      final actionDiv = td
          .querySelectorAll('div')
          .where((d) => (d.attributes['id'] ?? '').endsWith('-akcija'))
          .firstOrNull;

      if (actionDiv != null) {
        final actionText = actionDiv.text;
        if (actionText.contains('Naročen')) {
          status = 'ordered';
        } else {
          status = 'available';
        }
      } else {
        final errorSpan = td
            .querySelectorAll('span.error')
            .where((s) => s.text.contains('Odjavljen'))
            .firstOrNull;
        status = errorSpan != null ? 'cancelled' : 'none';
      }

      menu[date]!.add(MealOption(
        menuId: menuId,
        menuName: menuName,
        description: description,
        status: status,
        locationId: locationId,
        mealType: mealType,
      ));
    }

    return menu;
  }

  /// Fetch and parse the weekly menu. Optionally fetch a specific [week].
  Future<Map<String, List<MealOption>>> getWeeklyMenu({int? week}) async {
    final html = await getMealPage(week: week);
    return parseMealTable(html);
  }

  // ── HTTP helpers with manual cookie handling ──
  //
  // `_get` and `_post` were near-identical: both built a request, attached
  // cookies and headers, then ran the same twenty-line redirect loop. Only
  // the first request differed. Sharing `_send` means a fix to the redirect
  // handling — the cap and the timeouts below — lands on both paths.

  Future<_Response> _get(String url) => _send(url);

  Future<_Response> _post(String url, Map<String, String> body) =>
      _send(url, body: body);

  Future<_Response> _send(String url, {Map<String, String>? body}) async {
    Future<_Response> run() async {
      var currentUri = Uri.parse(url);
      var response = await _open(currentUri, body: body);
      _storeCookies(response, currentUri);

      // Redirects are followed by hand so cookies can be captured at each
      // hop — the `ses` cookie is only set partway through the login bounce.
      var hops = 0;
      while (response.isRedirect ||
          (response.statusCode >= 300 && response.statusCode < 400)) {
        if (++hops > _maxRedirects) {
          throw Exception(
              'Too many redirects (>$_maxRedirects) starting at $url');
        }
        final location = response.headers.value('location');
        if (location == null) break;

        final redirectUri = currentUri.resolve(location);
        await response.drain<void>();

        // A redirect is always followed with GET: the login POST answers
        // 302 to a page, and re-POSTing the credentials to it would be wrong.
        response = await _open(redirectUri);
        currentUri = redirectUri;
        _storeCookies(response, currentUri);
      }

      final text = await response.transform(utf8.decoder).join();
      return _Response(response.statusCode, text);
    }

    try {
      return await run().timeout(totalTimeout);
    } on TimeoutException {
      throw Exception(
          'Request to $url timed out after ${totalTimeout.inSeconds}s');
    }
  }

  /// Issue a single request — no redirect following, no timeout on the body.
  Future<HttpClientResponse> _open(Uri uri, {Map<String, String>? body}) async {
    final request = body == null
        ? await _httpClient.getUrl(uri)
        : await _httpClient.postUrl(uri);
    request.followRedirects = false;

    _applyCookies(request, uri);
    _headers.forEach((k, v) => request.headers.set(k, v));

    if (body != null) {
      request.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      request.write(body.entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&'));
    }

    return request.close().timeout(requestTimeout);
  }

  void _applyCookies(HttpClientRequest request, Uri uri) {
    // Try exact host and parent domains
    for (final domain in _cookies.keys) {
      if (uri.host == domain || uri.host.endsWith('.$domain')) {
        for (final cookie in _cookies[domain]!) {
          request.cookies.add(cookie);
        }
      }
    }
  }

  void _storeCookies(HttpClientResponse response, Uri uri) {
    for (final cookie in response.cookies) {
      final domain = cookie.domain ?? uri.host;
      final cleanDomain = domain.startsWith('.') ? domain.substring(1) : domain;
      _cookies.putIfAbsent(cleanDomain, () => []);
      // Replace existing cookie with same name
      _cookies[cleanDomain]!.removeWhere((c) => c.name == cookie.name);
      _cookies[cleanDomain]!.add(cookie);
    }
  }

  /// Release the underlying socket pool. The client was never closed, so
  /// each login leaked its keep-alive connections until the isolate died.
  void close() {
    _httpClient.close(force: true);
    _loggedIn = false;
  }
}

/// The session cookies are no longer valid; the caller should re-login.
///
/// Previously signalled by a plain `Exception('Session expired, ...')`, which
/// callers had to string-match to distinguish from a real failure.
class SessionExpiredException implements Exception {
  @override
  String toString() => 'Session expired, please login again';
}

class _Response {
  final int statusCode;
  final String body;
  _Response(this.statusCode, this.body);
}
