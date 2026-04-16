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
  static const _loginUrl = 'https://www.easistent.com/p/ajax_prijava';
  static const _mealPageUrl = 'https://www.easistent.com/prehrana';
  static const _mealListUrl =
      'https://www.easistent.com/dijaki/ajax_prehrana_obroki_seznam';
  static const _mealSelectUrl =
      'https://www.easistent.com/dijaki/ajax_prehrana_obroki_prijava';

  final String username;
  final String password;

  String? accessToken;
  String? childId;
  String? refreshToken;

  late HttpClient _httpClient;
  final Map<String, String> _headers = {};
  // Manual cookie store keyed by domain
  final Map<String, List<Cookie>> _cookies = {};

  bool get isLoggedIn => accessToken != null;

  EAsistentClient({required this.username, required this.password}) {
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
    final loginJson = jsonDecode(loginResp.body);

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

    if (sesCookie == null) {
      throw Exception('Login failed: no ses cookie received');
    }

    // ses cookie value is URL-encoded JSON
    final sesJson = jsonDecode(Uri.decodeComponent(sesCookie.value));
    accessToken = sesJson['accessToken'] as String?;
    childId = sesJson['activeChildId']?.toString();
    refreshToken = sesJson['refreshToken'] as String?;

    if (accessToken == null || childId == null) {
      throw Exception(
          'Login failed: missing tokens in ses cookie');
    }

    // 4. Set auth headers for future requests
    _headers.addAll({
      'Authorization': accessToken!,
      'X-Child-Id': childId!,
      'X-Client-Version': '13',
      'X-Client-Platform': 'web',
      'X-Requested-With': 'XMLHttpRequest',
    });
  }

  /// Clear session state and re-login with existing credentials.
  Future<void> relogin() async {
    accessToken = null;
    childId = null;
    refreshToken = null;
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
  }) async {
    final resp = await _post(_mealSelectUrl, {
      'tip_prehrane': mealType,
      'id_meni': menuId,
      'datum': date,
      'akcija': 'prijava',
      'id_lokacija': locationId,
    });
    final data = jsonDecode(resp.body);
    if (data['status'] == 'ok') return true;
    if (data['status'] == 'logout') {
      throw Exception('Session expired, please login again');
    }
    throw Exception('Meal selection failed: ${data['errfields']}');
  }

  /// Cancel (odjava) an existing meal order for a given date.
  Future<bool> cancelMeal({
    required String date,
    required String menuId,
    required String locationId,
    String mealType = 'malica',
  }) async {
    final resp = await _post(_mealSelectUrl, {
      'tip_prehrane': mealType,
      'id_meni': menuId,
      'datum': date,
      'akcija': 'odjava',
      'id_lokacija': locationId,
    });
    final data = jsonDecode(resp.body);
    if (data['status'] == 'ok') return true;
    if (data['status'] == 'logout') {
      throw Exception('Session expired, please login again');
    }
    throw Exception('Meal cancellation failed: ${data['errfields']}');
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

  Future<_Response> _get(String url) async {
    final uri = Uri.parse(url);
    final request = await _httpClient.getUrl(uri);
    request.followRedirects = false;

    // Attach cookies for this domain
    _applyCookies(request, uri);

    // Set auth headers
    _headers.forEach((k, v) => request.headers.set(k, v));

    var response = await request.close();

    // Store cookies from response
    _storeCookies(response, uri);

    var currentUri = uri;

    // Follow redirects manually to capture cookies at each hop
    while (response.isRedirect ||
        (response.statusCode >= 300 && response.statusCode < 400)) {
      final location = response.headers.value('location');
      if (location == null) break;

      final redirectUri = currentUri.resolve(location);
      await response.drain<void>();

      final redirectReq = await _httpClient.getUrl(redirectUri);
      redirectReq.followRedirects = false;
      _applyCookies(redirectReq, redirectUri);
      _headers.forEach((k, v) => redirectReq.headers.set(k, v));
      currentUri = redirectUri;

      response = await redirectReq.close();
      _storeCookies(response, redirectUri);
    }

    final body = await response.transform(utf8.decoder).join();
    return _Response(response.statusCode, body);
  }

  Future<_Response> _post(String url, Map<String, String> body) async {
    final uri = Uri.parse(url);
    final request = await _httpClient.postUrl(uri);
    request.followRedirects = false;

    _applyCookies(request, uri);
    _headers.forEach((k, v) => request.headers.set(k, v));

    request.headers.contentType =
        ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');

    final encoded = body.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    request.write(encoded);

    var response = await request.close();
    _storeCookies(response, uri);

    var currentUri = uri;

    // Follow redirects manually
    while (response.isRedirect ||
        (response.statusCode >= 300 && response.statusCode < 400)) {
      final location = response.headers.value('location');
      if (location == null) break;

      final redirectUri = currentUri.resolve(location);
      await response.drain<void>();

      final redirectReq = await _httpClient.getUrl(redirectUri);
      redirectReq.followRedirects = false;
      _applyCookies(redirectReq, redirectUri);
      _headers.forEach((k, v) => redirectReq.headers.set(k, v));
      currentUri = redirectUri;

      response = await redirectReq.close();
      _storeCookies(response, redirectUri);
    }

    final responseBody = await response.transform(utf8.decoder).join();
    return _Response(response.statusCode, responseBody);
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
}

class _Response {
  final int statusCode;
  final String body;
  _Response(this.statusCode, this.body);
}
