# eAsistent Meal Picker App (Flutter)

Flutter Android app that auto-selects weekly school meals on the Slovenian eAsistent platform using an AI predictor trained on user preferences. Works with any school — meal structure is detected dynamically from HTML.

There is also a **Python desktop version** (separate repo) with a PyQt5 GUI, CLI selector, and Windows Task Scheduler integration.

## Architecture

```
lib/
├── main.dart                        # App entry, theme, floating glass nav bar, rating dialog, feature tour
├── theme.dart                       # Catppuccin Mocha dark theme, GlassCard/GlassBar/PillChip widgets
├── models/
│   └── meal_option.dart             # MealOption data class (menuId, name, desc, status, locationId, mealType)
├── screens/
│   ├── onboarding_screen.dart       # First-launch onboarding: welcome, login, AI setup, history scraping, quiz
│   ├── menu_screen.dart             # Main tab — weekly menu display, AI picks, meal submission
│   ├── training_screen.dart         # Quiz-style training — user picks from randomized options
│   ├── stats_screen.dart            # Statistics — AI accuracy, pick distribution, rating trends
│   ├── health_screen.dart           # Health scoring — nutritional analysis of meal descriptions
│   ├── log_screen.dart              # Submission history log with filters
│   └── settings_screen.dart         # Preferences — liked/disliked keywords, menu type rankings
└── services/
    ├── easistent_client.dart        # HTTP client — login, fetch HTML, parse meals, submit via AJAX
    ├── meal_predictor.dart          # Scoring engine — keyword TF-IDF + menu type bias + preferences
    ├── preference_learner.dart      # Derives auto-preferences from training data (frequency analysis)
    ├── health_scorer.dart           # Nutritional scoring of meal descriptions
    ├── training_store.dart          # Persists training data (JSON), seeds from assets/ on first run
    ├── preferences_store.dart       # Persists preferences (JSON), seeds from assets/ on first run
    ├── credentials_store.dart       # Persists eAsistent login credentials (JSON)
    ├── submission_log.dart          # Persists submission log entries (JSON)
    ├── rating_store.dart            # Persists 1-5 star meal ratings (JSON)
    ├── absence_store.dart           # Tracks absence/odsoten state per day
    ├── onboarding_store.dart        # File-flag for first-launch onboarding completion
    ├── meal_structure_store.dart    # Detects and persists school's meal structure (types, menu names)
    ├── scheduler_service.dart       # Background scheduling — notifications + auto-submit alarm
    └── widget_service.dart          # Android home-screen widget data updates
```

## Key Flows

### First-Launch Onboarding (onboarding_screen.dart)
1. Welcome screen -> login credentials -> "Set up AI?" prompt
2. If yes: scrape up to 15 past weeks of meal history as training data with progress bar
3. Optional training quiz (up to 20 rounds, can stop anytime)
4. Mark onboarding complete -> show interactive feature tour -> enter app

### Feature Tour (main.dart)
- 6-step spotlight overlay highlighting each nav bar tab
- Glassmorphism tooltip card with icon, title, Slovenian description
- Auto-switches tabs, advances on tap, "Preskoci" to skip

### Dynamic Meal Structure (meal_structure_store.dart)
- After login, detects school's meal types from HTML cell IDs (malica, kosilo, etc.)
- Parses menu names, counts, and IDs dynamically — no hardcoding
- Stores detected structure locally, auto-updates if school changes offerings
- Settings screen syncs menu ranking with detected structure

### Menu Display & Selection (menu_screen.dart)
1. Login with stored credentials -> fetch meal HTML -> parse into `Map<date, List<MealOption>>`
2. AI predictor scores each option -> highlights best pick per day
3. User taps option -> `selectMeal()` API call -> refresh display
4. After menu loads, probe-based lock detection runs in background
5. On locked days: Meni 1 + Odjava remain toggleable, higher menus frozen
6. Submit button warns about locked-day changes with day list before submitting

### Lock Detection (menu_screen.dart `_probeLockedDays`)
eAsistent locks meal options server-side with no HTML indicator. Detection works by:
- Attempting to switch each day to a different option via API
- If server rejects -> day is partially locked (higher menus frozen, Meni 1 + Odjava still available)
- If server accepts -> immediately revert to original selection
- Uses `_probeGeneration` counter to cancel stale probes on refresh

### AI Predictor (meal_predictor.dart)
- Tokenizes Slovenian meal descriptions, removes allergen codes
- Builds keyword frequency model from training data (chosen vs not-chosen)
- Incorporates meal ratings (1-5 stars) as weighted training signal
- Combines: keyword score + menu type bias + explicit preferences (liked/disliked keywords)
- `pickBest()` returns highest-scoring available option for a day

### Auto-Submit (scheduler_service.dart)
- Monday 16:00: reminder notification via `flutter_local_notifications`
- Monday 18:00: background alarm via `android_alarm_manager_plus`
  - Loads credentials/training/preferences from disk (background isolate)
  - Logs in, fetches next week's menu, skips already-submitted days
  - Uses predictor to pick best option per remaining day
  - Submits, logs results, writes weekly dedup marker
- Daily 12:00: checks if next week's menu descriptions are published, notifies user
- Daily 13:00: meal rating reminder notification (skips Odjava/absent days)

### Training (training_screen.dart)
- Presents randomized options from the description pool
- User pick -> saved to training data -> preferences auto-derived -> predictor rebuilt
- AI pick indicator shows current model's preference for comparison

### Meal Rating (main.dart `showRatingDialog`)
- Daily 13:00 notification prompts user to rate today's meal (1-5 stars)
- Ratings stored in `rating_store.dart`, fed back into predictor as weighted training signal
- Can also be triggered manually from the UI

### Home Widget (widget_service.dart)
- Android home-screen widget showing today's and tomorrow's meal
- Updated after login, menu fetch, and auto-submit
- Falls back to: explicit selection -> ordered status -> AI pick

## Build & Run

```bash
flutter pub get
flutter build apk --release    # Output: build/app/outputs/flutter-apk/app-release.apk
flutter run                    # Debug on connected device
```

### iOS (branch `iphone`)

```bash
cd ios && pod install && cd ..
flutter build ios --release    # Signed build, needs an Apple ID team in Xcode
./scripts/build_ipa.sh         # Unsigned build/MealPicker.ipa for SideStore/AltStore
```

iOS differences from Android, all in `scheduler_service.dart`:

- `android_alarm_manager_plus` has no iOS implementation and iOS cannot run
  Dart at a wall-clock time in the background. The alarm block is Android-only;
  iOS schedules the Monday 18:00 prompt and the 13:00 rating reminders as
  local notifications, and `runForegroundCatchUp()` does the real work on app
  launch and resume (wired to `WidgetsBindingObserver` in `main.dart`).
- `_handleAutoSubmit(relaxedGate: true)` widens the Monday 17:00-20:00 gate to
  Monday-Friday for that catch-up. The weekly marker file still limits it to
  one submit per week.
- The home widget is an Android AppWidget with no WidgetKit extension, so
  `updateHomeWidget` and `setAppGroupId` are guarded to Android. Keep it that
  way: adding an iOS extension would consume a second App ID, and a free
  Apple ID allows only 3 sideloaded apps and 10 App IDs per 7 days.
- Notifications need both Android and Darwin settings — iOS reminders are
  silent without `DarwinInitializationSettings` / `DarwinNotificationDetails`.

## CLI Test Scripts (bin/)

```bash
dart run bin/test_login.dart          # Test eAsistent login + meal parsing
dart run bin/test_predictor.dart      # Test predictor scoring against live data
dart run bin/test_training_flow.dart  # Verify training -> predictor improvement
```

These require a `config.json` in the project root with eAsistent credentials: `{"username": "...", "password": "..."}`.

## Key Dependencies

- `http` + `html` — eAsistent API calls and HTML parsing
- `android_alarm_manager_plus` — background periodic alarms
- `flutter_local_notifications` — push notifications
- `timezone` — Europe/Ljubljana timezone handling
- `permission_handler` — notification permission on Android 13+
- `path_provider` — local file storage
- `home_widget` — Android home-screen widget

## Conventions

- Catppuccin Mocha dark theme throughout (glassmorphism via BackdropFilter)
- Reusable glass widgets: GlassCard, GlassBar, PillChip (defined in theme.dart)
- Floating glass pill nav bar with 6 tabs: Meni, Trening, Statistika, Zdravje, Dnevnik, Nastavitve
- All notification/scheduler operations wrapped in try-catch (non-fatal)
- Slovenian UI text (menu labels, notifications, dialogs)
- Status values: `ordered`, `available`, `cancelled`, `none`
- Training data and preferences seeded from `assets/` on first launch, then stored locally
- Menu colors assigned by name pattern: number-based cycling, keyword hints (fit, vegan, veg, xxl)
- Dynamic meal type support: `MealOption.mealType` parsed from HTML cell IDs
