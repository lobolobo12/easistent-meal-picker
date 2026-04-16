// ignore_for_file: avoid_print, avoid_relative_lib_imports
import 'dart:convert';
import 'dart:io';
import '../lib/services/easistent_client.dart';

void main() async {
  final configFile = File(r'C:\Users\lovro\easistent-meal-picker\config.json');
  final config = jsonDecode(await configFile.readAsString());

  final client = EAsistentClient(
    username: config['username'],
    password: config['password'],
  );

  print('Logging in as ${config['username']}...');

  try {
    await client.login();
    print('Login successful!');
    print('  accessToken: ${client.accessToken?.substring(0, 20)}...');
    print('  childId: ${client.childId}');

    // Fetch and parse meal page
    print('\nFetching meal page...');
    final html = await client.getMealPage();
    final week = client.findCurrentWeek(html);
    print('  Current week: $week');

    final menu = client.parseMealTable(html);
    print('  Parsed ${menu.length} days\n');

    final sortedDates = menu.keys.toList()..sort();
    for (final date in sortedDates) {
      final options = menu[date]!;
      print('--- $date (${options.length} options) ---');
      for (final opt in options) {
        final desc = opt.description.length > 60
            ? '${opt.description.substring(0, 60)}...'
            : opt.description;
        print('  [${opt.status.padRight(9)}] ${opt.menuName.padRight(20)} $desc');
      }
      print('');
    }
  } catch (e, st) {
    print('ERROR: $e');
    print(st);
    exitCode = 1;
  }
}
