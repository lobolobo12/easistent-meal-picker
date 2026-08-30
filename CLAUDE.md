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
├── util/
│   ├── dates.dart                   # Slovenian day names + YYYY-MM-DD formatting, shared by every screen
│   ├── training_data.dart           # Duplicate-row collapsing (pure Dart, shared with the CLI harness)
│   └── allergens.dart               # Tells an allergen declaration from a real ingredient list
├── widgets/
│   └── explain_sheet.dart           # "Why this score?" breakdown, opened by long-pressing a meal card
├── screens/
│   ├── onboarding_screen.dart       # First-launch onboarding: welcome, login, AI setup, history scraping, quiz
│   ├── menu_screen.dart             # Main tab — weekly menu display, AI picks, meal submission
│   ├── training_screen.dart         # Quiz-style training — user picks from randomized options
│   ├── stats_screen.dart            # Statistics — AI accuracy, pick distribution, rating trends
│   ├── health_screen.dart           # Health scoring — nutritional analysis of meal descriptions
│   ├── log_screen.dart              # Submission history log with filters
│   └── settings_screen.dart         # Preferences — liked/disliked keywords, menu type rankings
└── services/
    ├── app_files.dart               # Filenames + JsonFile/MarkerFile (atomic writes, corrupt-file recovery)
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
- All knobs live in `PredictorTuning`; `PredictorTuning.legacy` preserves the
  pre-refactor keyword model so changes can be A/B'd rather than guessed at

**The model must beat "always pick the usual menu".** It once did not: with
the shipped weighting it scored 3/6 walk-forward where that trivial baseline
scored 5/6 — the keyword signal carried the largest weight (1.0) while built
from 56 observations, and it overrode a menu preference held 86% of the time
(weighted 0.3). The keyword weight is now scaled by
`days / (days + keywordEvidenceK)`, so the menu habit leads early and the
keywords take over as they earn it; `wMenuType` is 1.0. That baseline is
printed by the harness on every run, and
`test/meal_predictor_test.dart` reproduces the failure so it cannot return.

**Do not tune this model by eye.** `dart run bin/eval_predictor.dart` walks the
training data forward — train on days `[0, i)`, predict day `i` — and prints
top-1 and mean rank per variant. Two things it has already caught:

- Feeding it the stored `preferences.json` leaks the answer, because the
  `auto_*` keywords in that file were derived from every day including the one
  being predicted. It scored a flat 6/6 until each fold re-derived them from
  its own training slice. Real out-of-sample is 3/6.
- Keyword shrinkage looked like a certain win (vocabulary 25 → 118 tokens) but
  scored 2/6, 2/6, 4/6, 3/6 across k = 1, 2, 4, 8 — non-monotonic, swinging two
  days out of six. On seven days of data the harness cannot separate these
  variants, so the shipped keyword model is deliberately unchanged.

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

### Training Weights (util/training_data.dart)
- A training day carries an optional `weight`; submitting used to append the
  same day three times instead
- Duplicating rows inflated the raw token counts as well as the rates, so a
  manually submitted day slipped past `minTokenFreq` while an identical
  scraped day could not — the model behaved differently depending on data
  provenance. The frequency floor now counts sightings, the rates use weight
- `TrainingStore.load()` collapses on read, so existing devices migrate
  themselves; `bin/eval_predictor.dart` applies the same collapsing
- A day where you overrode the AI is weighted `kCorrectionWeight`; one where
  you accepted it is not. **Unmeasured** — the stored data never recorded
  which days were corrections, so there is no history to evaluate it against

### Allergen vs Ingredient Brackets (util/allergens.dart)
eAsistent descriptions carry two kinds of bracket and they must not be
treated alike:

    "pariška salama (pšenica, mlečni izdelek, ki vsebuje laktozo)"   allergens
    "mehiška solata (paradižnik, paprika, fižol, cvetača, koruza..)" ingredients

`stripAllergenDeclarations` drops the first and keeps the second, working
term by term so a mixed bracket splits correctly. Terms match whole, never as
substrings — "zelena" alone is celery, "zelena solata" is a green salad.
An unrecognised term keeps its bracket, so a gap in the list is never worse
than the old behaviour.

Both `health_scorer.scoreMeal` and `meal_predictor.tokenize` use it. The
health scorer used to read the allergen list as nutrition: two chocolate
pastries scored 4/10 because "jajca" appeared in their allergen declaration.
The predictor used to discard every bracket, losing five real vegetables from
that salad.

**Fixing this exposed that the allergen list was compensating for gaps in the
food keywords** — Slovenian case endings do not substring-match. `tuna` misses
"tunino", `jajc` misses "jajčni" (c and č are different letters), `korenje`
misses "korenčkom". Those meals only scored protein because the allergen
bracket happened to say "ribe" or "jajca". Adding a keyword is cheap; check
the score distribution over `assets/training_data.json` before and after.

### New Menu Detection (menu_screen `_NewMenusBanner`)
- `MealPredictor.knownMenus` exposes the normalized menus the model has any
  history for
- A menu the model has never seen scores 0, which looks identical to one it
  has learned to dislike. The banner names them and offers the Trening tab
- Stays quiet when the model knows nothing at all, since onboarding already
  covers a fresh install
- Built for the school-year rollover: `normalizeMenuName` absorbs a changed
  price ("Meni 5 (XXL +0,70€)" → "(XXL+0,80 EUR)"), but a genuine rename
  strands months of preference silently

### Pick Confidence (MealPredictor.rankDay)
- Returns the winner, the runner-up, and the margin as a fraction of the
  day's score range
- Under `DayRanking.closeThreshold` the pick is shown as `AI · tesno` rather
  than `AI`, and the explanation names the alternative
- `isCandidate` is explicit: the unattended submit ranks only `available`
  options so it cannot overwrite a real choice, while the menu screen also
  ranks `ordered` ones so its highlight and its closeness flag describe the
  same set

### Score Explanation (widgets/explain_sheet.dart)
- Long-press any meal card on the Meni tab
- `MealPredictor.explain()` returns the same arithmetic `scoreOption` runs,
  labelled per signal, with the words behind each one
- The factors are asserted to sum to the score in tests: a breakdown that
  does not reconcile is a plausible-looking fiction, worse than showing nothing
- Also reports keyword maturity, so the UI can admit how little the model
  knows rather than presenting a thin model confidently

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

## Tests

```bash
flutter test    # 138 tests, no device and no live account needed
```

- `test/auto_submit_test.dart` — **the Monday rehearsal.** Drives the real
  `_handleAutoSubmit` against a fake eAsistent on localhost, with only the
  server origin and the clock replaced. Covers the weekday/hour gate, the
  weekly marker, absence and already-logged skipping, what the trained model
  actually orders, and that a hung server or corrupt file cannot take the run
  down. This is how the unattended path gets exercised without placing a real
  order.
- `test/easistent_client_test.dart` — login (including the opaque `v1.` ses
  cookie), cookie replay, exact submit form fields, session expiry, timeouts,
  redirect cap. Also against the local fake, so the real cookie jar and
  redirect code run.
- `test/fixtures/fake_easistent.dart` — the stand-in server. Not a mock of the
  client's internals: the client talks to it over a real socket.
- `test/meal_predictor_test.dart`, `test/json_store_test.dart`,
  `test/dates_test.dart`, `test/easistent_parser_test.dart`.

Two seams in `scheduler_service.dart` exist only for this:
`schedulerClientFactory` and `schedulerClockOverride`, both
`@visibleForTesting`.

## CLI Test Scripts (bin/)

```bash
dart run bin/eval_predictor.dart      # Walk-forward accuracy of the predictor
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
- Persisted files go through `AppFiles` constants and `JsonFile`, never a
  hand-written path. The background alarm reads the same files and a typo in
  one copy fails silently at 18:00 with nobody watching
- Network calls carry a timeout. The auto-submit runs unattended, so a socket
  that never answers must fail rather than hang
- Slovenian UI text (menu labels, notifications, dialogs)
- Status values: `ordered`, `available`, `cancelled`, `none`
- Training data and preferences seeded from `assets/` on first launch, then stored locally
- Menu colors assigned by name pattern: number-based cycling, keyword hints (fit, vegan, veg, xxl)
- Dynamic meal type support: `MealOption.mealType` parsed from HTML cell IDs
