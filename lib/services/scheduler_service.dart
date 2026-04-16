import 'dart:convert';
import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/meal_option.dart';
import 'easistent_client.dart';
import 'meal_predictor.dart';
import 'scheduler_debug_log.dart';
import 'widget_service.dart';

const _autoSubmitAlarmId = 42;
const _menuCheckAlarmId = 43;
const _ratingAlarmId = 44;
const _channelId = 'meal_picker_notifications';
const _channelName = 'Meal Picker';
const _reminderNotifId = 1000;
const _resultNotifId = 1001;
const _menuAvailableNotifId = 1002;
const _ratingNotifId = 1003;

final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Callback invoked when user taps a notification. Set by the app at startup.
void Function(String? payload)? onNotificationTap;

/// Top-level callback for auto-submit alarm.
@pragma('vm:entry-point')
Future<void> _autoSubmitCallback() async {
  await SchedulerDebugLog.log('alarm', 'auto-submit callback fired');
  await _handleAutoSubmit();
}

/// Top-level callback for daily menu-availability check.
@pragma('vm:entry-point')
Future<void> _menuCheckCallback() async {
  await SchedulerDebugLog.log('alarm', 'menu-check callback fired');
  await _handleMenuCheck();
}

/// Top-level callback for daily 13:00 meal rating reminder.
@pragma('vm:entry-point')
Future<void> _ratingReminderCallback() async {
  await SchedulerDebugLog.log('alarm', 'rating-reminder callback fired');
  await _handleRatingReminder();
}

/// Per-isolate init guard for `_notificationsPlugin`. Background isolates
/// have their own copy of this variable; main isolate has its own.
bool _pluginInitialized = false;
const _androidInitSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
const _androidChannel = AndroidNotificationChannel(
  _channelId,
  _channelName,
  description: 'Weekly meal reminders and auto-submit results',
  importance: Importance.high,
);
const _androidNotifDetails = AndroidNotificationDetails(
  _channelId,
  _channelName,
  channelDescription: 'Weekly meal reminders and auto-submit results',
  importance: Importance.high,
  priority: Priority.high,
);
const _notifDetails = NotificationDetails(android: _androidNotifDetails);

/// Ensure the plugin + channel are initialized in the current isolate.
/// Safe to call from main or background isolates, any number of times.
Future<FlutterLocalNotificationsPlugin> _ensurePlugin() async {
  if (_pluginInitialized) return _notificationsPlugin;
  try {
    if (Platform.isAndroid) {
      final android = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_androidChannel);
    }
    await _notificationsPlugin.initialize(
      const InitializationSettings(android: _androidInitSettings),
      onDidReceiveNotificationResponse: (response) {
        onNotificationTap?.call(response.payload);
      },
    );
    _pluginInitialized = true;
  } catch (e) {
    await SchedulerDebugLog.log('notif', 'ensurePlugin failed: $e');
  }
  return _notificationsPlugin;
}

/// Initialize timezone, notifications plugin, and alarm manager.
Future<void> initScheduler() async {
  await SchedulerDebugLog.log('init', 'initScheduler start');
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Europe/Ljubljana'));

  try {
    await _ensurePlugin();
  } catch (e) {
    // Fallback: if init throws, try cancelAll + re-init once (handles
    // corrupted notification storage on some OEMs).
    await SchedulerDebugLog.log('init', 'ensurePlugin threw: $e — retry');
    try {
      final android = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.cancelAll();
    } catch (_) {}
    _pluginInitialized = false;
    await _ensurePlugin();
  }

  try {
    await AndroidAlarmManager.initialize();
    await SchedulerDebugLog.log('init', 'AndroidAlarmManager.initialize OK');
  } catch (e) {
    await SchedulerDebugLog.log(
        'init', 'AndroidAlarmManager.initialize failed: $e');
  }
}

/// Request POST_NOTIFICATIONS (Android 13+) AND SCHEDULE_EXACT_ALARM
/// (Android 12+, needed for `AndroidAlarmManager.periodic(exact: true)`).
///
/// The exact-alarm permission is NOT granted automatically on Android 12+
/// for general apps. If it's denied, `AndroidAlarmManager.periodic` calls
/// will silently fail to fire — which is the most common reason
/// notifications never arrive on recent Android. Returns a record flagging
/// whether either permission is still missing after the request.
Future<({bool notificationsGranted, bool exactAlarmGranted})>
    requestNotificationPermission() async {
  var notif = true;
  var exact = true;
  try {
    if (Platform.isAndroid) {
      final n = await Permission.notification.request();
      notif = n.isGranted;
      await SchedulerDebugLog.log('perm', 'notifications: $n');

      // scheduleExactAlarm only exists on Android 12+. On older APIs the
      // permission_handler maps it to granted automatically.
      final e = await Permission.scheduleExactAlarm.request();
      exact = e.isGranted;
      await SchedulerDebugLog.log('perm', 'scheduleExactAlarm: $e');
    }
  } catch (e) {
    await SchedulerDebugLog.log('perm', 'request threw: $e');
  }
  return (notificationsGranted: notif, exactAlarmGranted: exact);
}

/// Schedule the Monday 16:00 reminder notification and the Monday 18:00
/// auto-submit alarm.
Future<void> scheduleWeeklyTasks() async {
  try {
    // Cancel any existing to avoid duplicates
    await cancelScheduledTasks();
    await _ensurePlugin();

    // 1. Monday 16:00 reminder via flutter_local_notifications (repeats weekly)
    final now = tz.TZDateTime.now(tz.local);
    var nextMonday16 = _nextWeekday(now, DateTime.monday, 16, 0);

    try {
      await _notificationsPlugin.zonedSchedule(
        _reminderNotifId,
        'Meni za naslednji teden',
        'Preveri izbire do 18:00',
        nextMonday16,
        _notifDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      await SchedulerDebugLog.log('schedule',
          'weekly reminder scheduled for $nextMonday16');
    } catch (e) {
      await SchedulerDebugLog.log(
          'schedule', 'zonedSchedule failed: $e');
    }

    // 2. Monday 18:00 auto-submit via periodic alarm (every ~7 days).
    final nextMonday18 = _nextWeekday(now, DateTime.monday, 18, 0);
    final startTime = DateTime(
      nextMonday18.year,
      nextMonday18.month,
      nextMonday18.day,
      nextMonday18.hour,
      nextMonday18.minute,
    );

    try {
      final ok = await AndroidAlarmManager.periodic(
        const Duration(days: 7),
        _autoSubmitAlarmId,
        _autoSubmitCallback,
        startAt: startTime,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );
      await SchedulerDebugLog.log(
          'schedule', 'auto-submit alarm scheduled for $startTime (ok=$ok)');
    } catch (e) {
      await SchedulerDebugLog.log(
          'schedule', 'auto-submit alarm register failed: $e');
    }

    // 3. Daily 12:00 menu-availability check.
    final tomorrow12 = _nextTime(now, 12, 0);
    final menuCheckStart = DateTime(
      tomorrow12.year,
      tomorrow12.month,
      tomorrow12.day,
      tomorrow12.hour,
      tomorrow12.minute,
    );

    try {
      final ok = await AndroidAlarmManager.periodic(
        const Duration(days: 1),
        _menuCheckAlarmId,
        _menuCheckCallback,
        startAt: menuCheckStart,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );
      await SchedulerDebugLog.log(
          'schedule', 'menu-check alarm scheduled for $menuCheckStart (ok=$ok)');
    } catch (e) {
      await SchedulerDebugLog.log(
          'schedule', 'menu-check alarm register failed: $e');
    }

    // 4. Daily 13:00 meal rating reminder.
    final next13 = _nextTime(now, 13, 0);
    final ratingStart = DateTime(
      next13.year,
      next13.month,
      next13.day,
      next13.hour,
      next13.minute,
    );

    try {
      final ok = await AndroidAlarmManager.periodic(
        const Duration(days: 1),
        _ratingAlarmId,
        _ratingReminderCallback,
        startAt: ratingStart,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );
      await SchedulerDebugLog.log(
          'schedule', 'rating alarm scheduled for $ratingStart (ok=$ok)');
    } catch (e) {
      await SchedulerDebugLog.log(
          'schedule', 'rating alarm register failed: $e');
    }

    // If it's a weekday and past 13:00, the periodic alarm's startAt is
    // tomorrow so today's check was missed. Fire it immediately.
    if (now.weekday <= DateTime.friday) {
      final today13 =
          tz.TZDateTime(tz.local, now.year, now.month, now.day, 13, 0);
      if (now.isAfter(today13)) {
        _handleRatingReminder(); // fire-and-forget for today
      }
    }
  } catch (_) {
    // Non-fatal — app works without background scheduling
  }
}

/// Cancel all scheduled notifications and alarms.
Future<void> cancelScheduledTasks() async {
  try {
    await _notificationsPlugin.cancelAll();
  } catch (_) {}
  try {
    await AndroidAlarmManager.cancel(_autoSubmitAlarmId);
  } catch (_) {}
  try {
    await AndroidAlarmManager.cancel(_menuCheckAlarmId);
  } catch (_) {}
  try {
    await AndroidAlarmManager.cancel(_ratingAlarmId);
  } catch (_) {}
}

/// Auto-submit logic run by the alarm in a background isolate.
///
/// Flow:
/// 1. Safety-check: only runs on Mondays 17:30–20:00
/// 2. De-duplicate via weekly marker file (autosubmit_marker.txt)
/// 3. Load credentials, training data, and preferences from disk
///    (background isolate has no access to the main isolate's state)
/// 4. Login to eAsistent, fetch next week's menu
/// 5. Skip days already submitted from this app (submission_log.json)
/// 6. Use MealPredictor to pick the best option per remaining day
/// 7. Submit picks, log results, write marker, show notification
Future<void> _handleAutoSubmit() async {
  try {
    // Evaluate the weekday/hour gate in Europe/Ljubljana, not device-local
    // time. Device locale may differ from the scheduled tz, which would
    // silently reject a correctly scheduled fire for travelers.
    tz.initializeTimeZones();
    final now = tz.TZDateTime.now(tz.getLocation('Europe/Ljubljana'));

    // Safety check: only act on Mondays between 17:30 and 20:00
    if (now.weekday != DateTime.monday || now.hour < 17 || now.hour >= 20) {
      return;
    }

    // Check duplicate marker for this week
    final dir = await getApplicationDocumentsDirectory();
    final markerFile = File('${dir.path}/autosubmit_marker.txt');
    final mondayStr = _mondayDateStr(now);

    if (markerFile.existsSync()) {
      final marker = await markerFile.readAsString();
      if (marker.trim() == mondayStr) return; // Already submitted this week
    }

    // Load credentials from disk (background isolate, no CredentialsStore cache)
    final credsFile = File('${dir.path}/credentials.json');
    if (!credsFile.existsSync()) return;

    final credsData =
        jsonDecode(await credsFile.readAsString()) as Map<String, dynamic>;
    final username = credsData['username'] as String?;
    final password = credsData['password'] as String?;
    if (username == null || password == null) return;

    // Load training data, preferences, and ratings from disk
    final trainingFile = File('${dir.path}/training_data.json');
    final prefsFile = File('${dir.path}/preferences.json');
    final ratingsFile = File('${dir.path}/meal_ratings.json');

    List<dynamic> trainingData = [];
    Map<String, dynamic> preferences = {};
    List<dynamic> ratings = [];

    if (trainingFile.existsSync()) {
      trainingData =
          jsonDecode(await trainingFile.readAsString()) as List<dynamic>;
    }
    if (prefsFile.existsSync()) {
      preferences =
          jsonDecode(await prefsFile.readAsString()) as Map<String, dynamic>;
    }
    if (ratingsFile.existsSync()) {
      try {
        ratings =
            jsonDecode(await ratingsFile.readAsString()) as List<dynamic>;
      } catch (_) {}
    }

    // Build predictor
    final predictor = MealPredictor.fromData(
      trainingData: trainingData,
      preferences: preferences,
      ratings: ratings,
    );

    // Login and fetch next week's menu
    final client = EAsistentClient(username: username, password: password);
    await client.login();

    final html = await client.getMealPage();
    final currentWeek = client.findCurrentWeek(html);
    if (currentWeek == null) {
      await _showResultNotification('Auto-submit', 'Teden ni bil najden');
      return;
    }

    // Fetch next week
    final menu = await client.getWeeklyMenu(week: currentWeek + 1);
    if (menu.isEmpty) {
      await _showResultNotification(
          'Auto-submit', 'Ni menijev za naslednji teden');
      return;
    }

    // Load existing submission log to check for manual submissions
    final logFile = File('${dir.path}/submission_log.json');
    List<dynamic> logData = [];
    if (logFile.existsSync()) {
      try {
        logData = jsonDecode(await logFile.readAsString()) as List<dynamic>;
      } catch (_) {}
    }
    final alreadySubmittedDates = <String>{
      for (final entry in logData)
        if (entry is Map<String, dynamic> && entry['date'] is String)
          entry['date'] as String,
    };

    // Load absence ranges to skip absent days
    final absenceFile = File('${dir.path}/absences.json');
    List<dynamic> absenceData = [];
    if (absenceFile.existsSync()) {
      try {
        absenceData =
            jsonDecode(await absenceFile.readAsString()) as List<dynamic>;
      } catch (_) {}
    }

    // Filter to days that need auto-submit. Value is a meal option to
    // select, OR null to request Odjava (cancel whatever is ordered).
    final daysToSubmit = <String, MealOption?>{};
    for (final entry in menu.entries) {
      final date = entry.key;
      final options = entry.value;

      // Skip only if already submitted from this app
      if (alreadySubmittedDates.contains(date)) continue;

      // Skip absent days
      if (_isDateAbsent(absenceData, date)) continue;
      // Ignore eAsistent's 'ordered' status — school auto-assigns Menu 1
      // as default, which we always want to override with AI/manual picks.
      // Just need at least one option that's available or ordered (overridable).
      if (!options.any((o) =>
          o.status == 'available' || o.status == 'ordered')) {
        continue;
      }

      final result = predictor.pickBestOrOdjava(options);
      if (result.recommendOdjava) {
        // Every option scored strongly negative — recommend Odjava for
        // this day only if the server knows an ordered meal to cancel.
        final ordered =
            options.where((o) => o.status == 'ordered').firstOrNull;
        if (ordered != null) {
          daysToSubmit[date] = null; // null ⇒ cancel
        }
        continue;
      }
      final bestId = result.menuId;
      if (bestId == null) continue;
      daysToSubmit[date] = options.firstWhere((o) => o.menuId == bestId);
    }

    // If nothing left to submit, notify and bail
    if (daysToSubmit.isEmpty) {
      await markerFile.writeAsString(mondayStr);
      await _showResultNotification('Auto-submit', 'Že oddano — preskočim.');
      return;
    }

    // Submit AI picks for remaining days
    var submitted = 0;
    var errors = 0;

    for (final entry in daysToSubmit.entries) {
      final date = entry.key;
      final bestOpt = entry.value;

      try {
        if (bestOpt == null) {
          // Odjava recommendation — cancel whatever is ordered.
          final ordered = menu[date]!
              .where((o) => o.status == 'ordered')
              .firstOrNull;
          if (ordered == null) continue;
          await client.cancelMeal(
            date: date,
            menuId: ordered.menuId,
            locationId: ordered.locationId,
            mealType: ordered.mealType,
          );
          submitted++;
          logData.add({
            'date': date,
            'menuName': 'Odjava',
            'menuId': '__odjava__',
            'description': 'AI odjava od ${ordered.menuName}',
            'submittedAt': DateTime.now().toIso8601String(),
            'auto': true,
          });
        } else {
          await client.selectMeal(
            date: date,
            menuId: bestOpt.menuId,
            locationId: bestOpt.locationId,
            mealType: bestOpt.mealType,
          );
          submitted++;
          logData.add({
            'date': date,
            'menuName': bestOpt.menuName,
            'description': bestOpt.description,
            'submittedAt': DateTime.now().toIso8601String(),
            'auto': true,
          });
        }
        await logFile.writeAsString(jsonEncode(logData));
      } catch (_) {
        errors++;
      }
    }

    // Write marker to prevent re-submission this week
    await markerFile.writeAsString(mondayStr);

    // Update home-screen widget with fresh data
    try {
      await updateHomeWidget(menu: menu, predictor: predictor);
    } catch (_) {}

    // Show result notification
    final msg = errors > 0
        ? 'Oddano: $submitted, napake: $errors'
        : 'Uspešno oddano: $submitted izbir';
    await _showResultNotification('Auto-submit', msg);
  } catch (e) {
    await _showResultNotification('Auto-submit napaka', e.toString());
  }
}

/// Daily check (runs at 12:00): are next week's menu descriptions populated?
///
/// Uses menu_available_marker.txt keyed by next week's Monday date to notify
/// at most once per week. When descriptions first appear, sends a push
/// notification so the user can review/override AI picks before auto-submit.
Future<void> _handleMenuCheck() async {
  try {
    final dir = await getApplicationDocumentsDirectory();

    // Weekly marker keyed by next week's Monday in Europe/Ljubljana.
    tz.initializeTimeZones();
    final nowTz = tz.TZDateTime.now(tz.getLocation('Europe/Ljubljana'));
    final nextMon = _nextWeekMondayStr(nowTz);
    final markerFile = File('${dir.path}/menu_available_marker.txt');
    if (markerFile.existsSync()) {
      final marker = await markerFile.readAsString();
      if (marker.trim() == nextMon) return; // Already notified for this week
    }

    // Load credentials
    final credsFile = File('${dir.path}/credentials.json');
    if (!credsFile.existsSync()) return;
    final credsData =
        jsonDecode(await credsFile.readAsString()) as Map<String, dynamic>;
    final username = credsData['username'] as String?;
    final password = credsData['password'] as String?;
    if (username == null || password == null) return;

    // Login and fetch next week's menu
    final client = EAsistentClient(username: username, password: password);
    await client.login();

    final html = await client.getMealPage();
    final currentWeek = client.findCurrentWeek(html);
    if (currentWeek == null) return;

    final menu = await client.getWeeklyMenu(week: currentWeek + 1);
    if (menu.isEmpty) return;

    // Check if any day has real (non-empty) descriptions
    var hasDescriptions = false;
    for (final options in menu.values) {
      for (final opt in options) {
        if (opt.description.trim().isNotEmpty) {
          hasDescriptions = true;
          break;
        }
      }
      if (hasDescriptions) break;
    }

    if (!hasDescriptions) return; // Not populated yet

    // Descriptions are live — write marker and notify
    await markerFile.writeAsString(nextMon);
    await _showResultNotification(
      'Jedilnik objavljen',
      'Jedilnik za naslednji teden je na voljo -- preveri izbire!',
      notifId: _menuAvailableNotifId,
    );
  } catch (_) {
    // Non-fatal — will retry tomorrow
  }
}

/// Daily 13:00 rating reminder: show a notification asking the user to rate
/// today's meal. Only fires on weekdays and only if today has a submission
/// in the log but no rating yet.
Future<void> _handleRatingReminder() async {
  try {
    tz.initializeTimeZones();
    final now = tz.TZDateTime.now(tz.getLocation('Europe/Ljubljana'));

    // Only on weekdays (Mon-Fri)
    if (now.weekday > DateTime.friday) return;

    final dir = await getApplicationDocumentsDirectory();
    final todayStr = _fmtDate(now);

    // Check if there's a real meal submission for today (skip Odjava/absence)
    final logFile = File('${dir.path}/submission_log.json');
    if (!logFile.existsSync()) return;
    List<dynamic> logData;
    try {
      logData = jsonDecode(await logFile.readAsString()) as List<dynamic>;
    } catch (_) {
      return;
    }
    final hasRealSubmission = logData.any((e) =>
        e is Map<String, dynamic> &&
        e['date'] == todayStr &&
        e['menuId'] != '__odjava__' &&
        e['menuId'] != '__odsoten__');
    if (!hasRealSubmission) return;

    // Check if already rated today
    final ratingsFile = File('${dir.path}/meal_ratings.json');
    if (ratingsFile.existsSync()) {
      try {
        final ratings =
            jsonDecode(await ratingsFile.readAsString()) as List<dynamic>;
        if (ratings.any((r) =>
            r is Map<String, dynamic> && r['date'] == todayStr)) {
          return; // Already rated
        }
      } catch (_) {}
    }

    // Show rating prompt notification with payload so the app opens the
    // rating dialog when tapped.
    final plugin = await _ensurePlugin();
    await plugin.show(
      _ratingNotifId,
      'Kako ti je bila danes malica?',
      'Oceni z 1-5 zvezdicami',
      _notifDetails,
      payload: 'rate_meal',
    );
    await SchedulerDebugLog.log('notif', 'rating reminder shown');
  } catch (e) {
    await SchedulerDebugLog.log('notif', 'rating reminder failed: $e');
  }
}

/// Show a notification from the background isolate.
Future<void> _showResultNotification(String title, String body,
    {int? notifId}) async {
  try {
    final plugin = await _ensurePlugin();
    await plugin.show(notifId ?? _resultNotifId, title, body, _notifDetails);
    await SchedulerDebugLog.log(
        'notif', 'shown id=${notifId ?? _resultNotifId} title=$title');
  } catch (e) {
    await SchedulerDebugLog.log('notif', 'show failed: $e');
  }
}

/// Get TZDateTime for the next occurrence of [weekday] at [hour]:[minute].
tz.TZDateTime _nextWeekday(
    tz.TZDateTime from, int weekday, int hour, int minute) {
  var date = tz.TZDateTime(
      tz.local, from.year, from.month, from.day, hour, minute);
  // Move forward to the target weekday
  while (date.weekday != weekday) {
    date = date.add(const Duration(days: 1));
  }
  // If in the past, jump to next week
  if (date.isBefore(from)) {
    date = date.add(const Duration(days: 7));
  }
  return date;
}

/// Get next occurrence of [hour]:[minute] (today if not yet passed, else tomorrow).
tz.TZDateTime _nextTime(tz.TZDateTime from, int hour, int minute) {
  var date =
      tz.TZDateTime(tz.local, from.year, from.month, from.day, hour, minute);
  if (date.isBefore(from)) date = date.add(const Duration(days: 1));
  return date;
}

/// Get "YYYY-MM-DD" for this week's Monday.
String _mondayDateStr(DateTime now) {
  final monday = now.subtract(Duration(days: now.weekday - 1));
  return _fmtDate(monday);
}

/// Get "YYYY-MM-DD" for NEXT week's Monday.
String _nextWeekMondayStr(DateTime now) {
  final daysUntilNextMon = (DateTime.monday - now.weekday + 7) % 7;
  final nextMon = now.add(Duration(days: daysUntilNextMon == 0 ? 7 : daysUntilNextMon));
  return _fmtDate(nextMon);
}

/// Check if a date falls within any absence range.
bool _isDateAbsent(List<dynamic> absenceData, String date) {
  for (final r in absenceData) {
    if (r is! Map<String, dynamic>) continue;
    final from = r['from'] as String? ?? '';
    final to = r['to'] as String? ?? '';
    if (date.compareTo(from) >= 0 && date.compareTo(to) <= 0) return true;
  }
  return false;
}

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
