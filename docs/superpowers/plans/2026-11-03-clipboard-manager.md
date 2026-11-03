# Clipps — Windows Clipboard Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Flutter Windows desktop app that captures every text copy at the OS level, stores it in SQLite with a timestamp, and lets the user browse, search, filter by date, manually save, and delete clips.

**Architecture:** Four layers at the spec's paths: SQLite access in `DbHelper`, rules and UI state in a `ChangeNotifier` provider, Material UI in `lib/screens`, and OS integration split between a small C++ hook in the Windows runner (`AddClipboardFormatListener` → `WM_CLIPBOARDUPDATE` → MethodChannel) and a Dart `ClipboardWatcher` that reads the text with Flutter's `Clipboard.getData`. Closing the window hides it to the tray so capture keeps running in the background.

**Tech Stack:** Flutter (stable) for Windows, Dart, `sqflite_common_ffi`, `path_provider`, `path`, `provider`, `characters`, `integration_test`; Win32 C++ in `windows/runner`.

**Spec:** `docs/superpowers/specs/2026-11-03-clipboard-manager-design.md`

## Global Constraints

- Target Windows desktop only: `flutter create --platforms=windows --project-name clipps .` in the repo root (`C:\Users\MIKE\Documents\CLIPPS`).
- Persistence is SQLite through the sqflite API, using `sqflite_common_ffi` (`databaseFactoryFfi`). The `sqflite` plugin itself has no Windows implementation; the ffi package gives the same API. No other storage.
- Clips are kept indefinitely. Rows are removed only by an explicit user delete. No size cap, no auto-pruning.
- Text clips only. Non-text clipboard content is ignored.
- State management: `provider` package with a `ChangeNotifier`.
- Files at the spec's paths: `lib/main.dart`, `lib/screens/*`, `lib/providers/clipboard_provider.dart`, `lib/database/db_helper.dart`, `lib/models/clipboard_model.dart`. Dart OS integration in `lib/services/clipboard_watcher.dart`; native code in `windows/runner/`.
- MethodChannel name `clipps/clipboard`, native→Dart method `clipboardChanged` (no arguments).
- Production DB file: `clipps.db` in `getApplicationSupportDirectory()`.
- Toolchain: Flutter stable SDK on PATH and Visual Studio 2022 with the "Desktop development with C++" workload. The machine currently has no `flutter` on PATH; Task 1 Step 1 checks this.
- History order everywhere: newest `created_at` first, ties broken by higher `id` first.

## Review Focus

1. **Same text copied twice, or Windows firing several `WM_CLIPBOARDUPDATE` for one copy** → exactly one history entry; two events racing must not both insert. Pinned in Task 2 (`addClip` dedupe and serialization tests).
2. **Clipboard holds an image or files, or is locked by another app when read** → nothing is saved, nothing crashes, no empty row. Pinned in Task 4 (watcher null and throw tests) and Task 2 (whitespace test).
3. **Search text containing `%`, `_` or `\`** (e.g. `50%`, `snake_case`) → matched literally, not as SQL wildcards. Pinned in Task 1.
4. **Date range ending on a day** → clips copied at any time on the end day (e.g. 23:59) are included. Pinned in Task 2.
5. **Very large clip (MB of text, or emoji at the cut point)** → stored intact; list shows a short preview without freezing or splitting a character. Pinned in Task 1 (`preview` test) and Task 3 (large-clip widget test).

---

### Task 1: Project scaffold, ClipboardModel and DbHelper

**Files:**
- Create (scaffold): whole Flutter project via `flutter create`
- Create: `lib/models/clipboard_model.dart`
- Create: `lib/database/db_helper.dart`
- Test: `test/database/db_helper_test.dart`, `test/models/clipboard_model_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class ClipboardModel { final int id; final String content; final DateTime createdAt; const ClipboardModel({required this.id, required this.content, required this.createdAt}); factory ClipboardModel.fromMap(Map<String, Object?> map); String get preview; }`
  - `class DbHelper { static Future<DbHelper> open(DatabaseFactory factory, String path); Future<ClipboardModel> insertClip(String content, DateTime createdAt); Future<ClipboardModel?> latestClip(); Future<List<ClipboardModel>> getClips({String text = '', DateTime? from, DateTime? before}); Future<int> deleteClips(Iterable<int> ids); Future<void> close(); }`
  - Table `clips(id INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT NOT NULL, created_at INTEGER NOT NULL)` + `CREATE INDEX idx_clips_created_at ON clips(created_at)`, DB version 1. `created_at` is `millisecondsSinceEpoch`.

- [ ] **Step 1: Check the toolchain**

Run: `flutter doctor -v`
Expected: `[√] Flutter` and `[√] Visual Studio - develop Windows apps`. If `flutter` is not found or Visual Studio is missing, stop and report to the user; installing the SDK is their call.

- [ ] **Step 2: Scaffold, add dependencies, init git**

```bash
flutter create --platforms=windows --project-name clipps .
flutter pub add sqflite_common_ffi path_provider path provider characters
git init
git add -A
git commit -m "chore: scaffold clipps Flutter Windows app"
```
Add under `dev_dependencies` in `pubspec.yaml` (needed in Task 4): `integration_test: { sdk: flutter }`. Delete the generated counter test `test/widget_test.dart`.

- [ ] **Step 3: Write the failing tests**

`test/models/clipboard_model_test.dart` (helper: `ClipboardModel _clip(String c) => ClipboardModel(id: 1, content: c, createdAt: DateTime(2026));`):
```dart
test('fromMap reads id, content and millisecond timestamp', () {
  final m = ClipboardModel.fromMap({'id': 7, 'content': 'hi', 'created_at': 1700000000000});
  expect(m.id, 7);
  expect(m.content, 'hi');
  expect(m.createdAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
});
test('preview keeps short content as-is', () {
  expect(_clip('short').preview, 'short');
});
test('preview cuts long content to 500 characters without splitting emoji', () {
  final m = _clip('a' * 499 + '👍🏽' * 10);
  expect(m.preview.characters.length, 500);
  expect(m.preview.endsWith('👍🏽'), isTrue);
});
```
`test/database/db_helper_test.dart` — `setUpAll(sqfliteFfiInit)`; `setUp` opens `DbHelper.open(databaseFactoryFfi, inMemoryDatabasePath)`; `tearDown` closes:
```dart
test('insertClip returns the stored clip with an id', ...);          // id > 0, content and createdAt round-trip
test('getClips returns newest first, id breaks ties', ...);          // insert t1, t3, t2, t3 → order [t3(2nd), t3(1st), t2, t1]
test('latestClip is null when empty and newest otherwise', ...);
test('getClips text filter is case-insensitive substring', ...);     // 'Hello World' found by 'world'
test('getClips treats % _ and \\ literally', ...);                   // rows '50% off', '50 off', 'snake_case', 'snakeXcase', r'a\b', 'ab'; '%' → ['50% off'], '_' → ['snake_case'], r'\' → [r'a\b']
test('getClips from is inclusive and before is exclusive', ...);     // rows at 10:00, 11:00, 12:00; from 11:00 before 12:00 → [11:00]
test('deleteClips removes only the given ids and returns count', ...);// delete 2 of 3 → returns 2, one left
test('deleteClips with no ids returns 0', ...);
test('stores 5 MB of text intact', ...);                             // 'x' * 5 * 1024 * 1024 round-trips with equal length
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `flutter test test/models test/database`
Expected: FAIL — `ClipboardModel` / `DbHelper` not defined.

- [ ] **Step 5: Implement `ClipboardModel` in `lib/models/clipboard_model.dart` and `DbHelper` in `lib/database/db_helper.dart`**

`preview`: `content.characters.take(500).toString()`. `open` uses `factory.openDatabase(path, options: OpenDatabaseOptions(version: 1, onCreate: ...))` with the schema above. Text filter: `content LIKE ? ESCAPE '\'` with `\`, `%`, `_` each prefixed by `\` and the term wrapped in `%…%`; skip the clause when `text` is empty. `from` → `created_at >= ?`, `before` → `created_at < ?`. Order `created_at DESC, id DESC`. `deleteClips` builds `id IN (?,?,…)` and returns 0 without querying when `ids` is empty.

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/models test/database`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add ClipboardModel and SQLite DbHelper"
```

---

### Task 2: ClipboardProvider (state and capture rules)

**Files:**
- Create: `lib/providers/clipboard_provider.dart`
- Test: `test/providers/clipboard_provider_test.dart`

**Interfaces:**
- Consumes: `DbHelper` (all methods), `ClipboardModel` from Task 1.
- Produces:
  - `class ClipboardProvider extends ChangeNotifier { ClipboardProvider(DbHelper db, {DateTime Function() clock = DateTime.now}); List<ClipboardModel> get clips; String get searchText; DateTimeRange? get dateRange; Set<int> get selectedIds; Future<void> load(); Future<bool> addClip(String content); Future<void> setSearchText(String text); Future<void> setDateRange(DateTimeRange? range); void toggleSelected(int id); void clearSelection(); Future<void> deleteSelected(); Future<void> deleteClip(int id); }`
  - `addClip` returns `true` when saved, `false` when skipped. `DateTimeRange` is from `package:flutter/material.dart`.

- [ ] **Step 1: Write the failing tests** (real `DbHelper` on `databaseFactoryFfi` + `inMemoryDatabasePath`; `clock: () => now` over a mutable test-local `DateTime now` so tests can stamp clips at chosen times)

```dart
test('addClip saves with clock time and shows it first', ...);       // returns true; clips.first.content == 'a', createdAt == clock()
test('addClip stores content unchanged, including surrounding whitespace', ...); // '  a\n' stored as '  a\n'
test('addClip skips empty and whitespace-only text', ...);           // '', '  \n\t' → false, clips empty
test('addClip skips text equal to the most recent clip', ...);       // 'a','a' → second false, 1 row; 'a','b','a' → 3 rows
test('concurrent addClip of the same text stores one row', () async {
  final results = await Future.wait([p.addClip('x'), p.addClip('x')]);
  expect(results, [true, false]);
  expect((await db.getClips()).length, 1);
});
test('dedupe compares against the newest clip even when a filter hides it', ...); // add 'a', setSearchText('zzz'), addClip('a') → false
test('setSearchText filters clips', ...);
test('setDateRange includes the whole end day', ...);                // clock-stamped clips on Jan 1 00:00, Jan 2 23:59, Jan 3 00:00; range Jan 1–Jan 2 → first two
test('setDateRange(null) clears the date filter', ...);
test('new clip that fails the active filter is saved but not listed', ...);
test('toggleSelected adds then removes an id', ...);
test('deleteSelected removes selected rows and clears selection', ...);
test('deleteClip removes one row and drops it from selection', ...);
test('mutations notify listeners', ...);                             // listener count increments after addClip, setSearchText, toggleSelected, deleteSelected
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/providers`
Expected: FAIL — `ClipboardProvider` not defined.

- [ ] **Step 3: Implement `ClipboardProvider` in `lib/providers/clipboard_provider.dart`**

Serialize `addClip` calls through a private `Future` chain so each call's dedupe check sees the previous call's insert. Dedupe against `db.latestClip()`, never against the filtered `clips`. `setDateRange` maps to `from: DateTime(start.y, start.m, start.d)`, `before: DateTime(end.y, end.m, end.d + 1)`. Every mutation reloads with the current filters, then `notifyListeners()`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/providers`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ClipboardProvider with dedupe, filters and selection"
```

---

### Task 3: History UI and app wiring

**Files:**
- Create: `lib/screens/home_screen.dart`
- Modify: `lib/main.dart` (replace generated counter app)
- Test: `test/screens/home_screen_test.dart`

**Interfaces:**
- Consumes: `ClipboardProvider` (Task 2), `DbHelper.open` (Task 1).
- Produces:
  - `class HomeScreen extends StatelessWidget` reading `ClipboardProvider` via `context.watch`.
  - `class ClippsApp extends StatelessWidget` (MaterialApp, title `Clipps`, home `HomeScreen`).
  - `Future<void> startApp(String dbPath)` in `lib/main.dart`: `WidgetsFlutterBinding.ensureInitialized()`, `sqfliteFfiInit()`, open `DbHelper` with `databaseFactoryFfi`, create provider, `await load()`, `runApp(ChangeNotifierProvider.value(value: provider, child: const ClippsApp()))`. `main()` calls `startApp(p.join((await getApplicationSupportDirectory()).path, 'clipps.db'))`.
  - Widget keys used by tests: `Key('manualInput')`, `Key('saveClip')`, `Key('search')`, `Key('dateRange')`, `Key('clearDateRange')`, `Key('deleteSelected')`, `Key('clip-<id>')` on each row, `Key('select-<id>')` on each row's checkbox, `Key('delete-<id>')` on each row's delete button.

UI copy (exact): button `Save Clip`; manual field hint `Paste or type text to save`; search hint `Search clips`; empty state `No clips yet`; filtered-empty state `No clips match`; delete-selected tooltip `Delete selected`; dialog title `Delete N clip(s)?` (N = count), body `This permanently removes them.`, buttons `Cancel` / `Delete`. Row title is `clip.preview` with `maxLines: 3, overflow: TextOverflow.ellipsis`; subtitle is `createdAt.toLocal()` formatted `yyyy-MM-dd HH:mm:ss` (`toString().substring(0, 19)` is fine). The `deleteSelected` action is disabled when nothing is selected. The per-row delete button also confirms with the same dialog (N = 1).

- [ ] **Step 1: Write the failing widget tests**

Pump `ChangeNotifierProvider.value(value: provider, child: const MaterialApp(home: HomeScreen()))` with a provider on `databaseFactoryFfiNoIsolate` + `inMemoryDatabasePath`. Wrap DB-touching calls (`load`, taps that trigger DB work) in `tester.runAsync` followed by `pump()`.
```dart
testWidgets('shows "No clips yet" when history is empty', ...);
testWidgets('Save Clip stores manual text, lists it first, clears the field', ...);
testWidgets('Save Clip with blank text saves nothing', ...);
testWidgets('typing in search filters the list; no hits shows "No clips match"', ...);
testWidgets('select two clips, confirm Delete: both gone from list and DB', ...);
testWidgets('Cancel in delete dialog keeps clips', ...);
testWidgets('row delete button removes just that clip after confirm', ...);
testWidgets('a 2 MB clip renders as a 500-character preview', (tester) async {
  // add 'y' * 2 * 1024 * 1024, then:
  final title = tester.widget<Text>(find.descendant(of: find.byKey(Key('clip-$id')), matching: find.byType(Text)).first);
  expect(title.data!.length, 500);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/screens`
Expected: FAIL — `HomeScreen` not defined.

- [ ] **Step 3: Implement `HomeScreen` in `lib/screens/home_screen.dart`, then `ClippsApp`/`startApp`/`main` in `lib/main.dart`**

Layout: AppBar (title `Clipps`, `deleteSelected` action), then a row with the multi-line manual field (`minLines: 1, maxLines: 4`) and `Save Clip`, then a row with the search field, a date-range button (`showDateRangePicker`, label shows the chosen range or `Any date`) and a clear-range icon shown only when a range is set, then the `ListView.builder` of clips. Each row: leading `Checkbox` bound to `selectedIds`, title/subtitle as above, trailing delete `IconButton`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test`
Expected: all PASS (Tasks 1–3).

- [ ] **Step 5: Check it runs**

Run: `flutter run -d windows`
Expected: window titled `Clipps` opens; typing text and pressing `Save Clip` adds a row with a timestamp; restarting the app still shows the row. (No automatic capture yet.)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add history screen with manual save, search, date filter and delete"
```

---

### Task 4: OS clipboard hook (native listener + Dart watcher)

**Files:**
- Create: `lib/services/clipboard_watcher.dart`
- Modify: `windows/runner/flutter_window.h`, `windows/runner/flutter_window.cpp`
- Modify: `lib/main.dart` (`startApp` starts the watcher)
- Test: `test/services/clipboard_watcher_test.dart`, `integration_test/clipboard_capture_test.dart`

**Interfaces:**
- Consumes: `ClipboardProvider.addClip` (Task 2), `startApp` (Task 3).
- Produces:
  - `class ClipboardWatcher { ClipboardWatcher({required Future<void> Function(String text) onText, Future<String?> Function()? readText, MethodChannel channel = const MethodChannel('clipps/clipboard')}); void start(); void stop(); }` — default `readText` is `(await Clipboard.getData(Clipboard.kTextPlain))?.text`.
  - Native: on `WM_CLIPBOARDUPDATE`, the runner invokes `clipboardChanged` on `clipps/clipboard`.

- [ ] **Step 1: Write the failing watcher tests**

Simulate native calls with `TestWidgetsFlutterBinding.ensureInitialized()` and
`TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage('clipps/clipboard', const StandardMethodCodec().encodeMethodCall(MethodCall('clipboardChanged')), (_) {})`; inject `readText`.
```dart
test('clipboardChanged reads text and passes it to onText', ...);      // readText → 'hello'; onText receives ['hello']
test('null clipboard text (image/files) is ignored', ...);             // onText never called
test('readText throwing PlatformException is ignored and later events still work', ...);
test('unknown method names are ignored', ...);
test('no callbacks after stop()', ...);
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services`
Expected: FAIL — `ClipboardWatcher` not defined.

- [ ] **Step 3: Implement `ClipboardWatcher` in `lib/services/clipboard_watcher.dart`**

`start()` sets `channel.setMethodCallHandler`; `stop()` sets it to `null`. Catch `PlatformException` from `readText` and `debugPrint` it; skip `null`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services`
Expected: all PASS.

- [ ] **Step 5: Add the native listener in `windows/runner/flutter_window.{h,cpp}`**

- Header: include `<flutter/method_channel.h>` and `<flutter/standard_method_codec.h>`; add member `std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> clipboard_channel_;`.
- `OnCreate`, after `RegisterPlugins`: create the channel on `flutter_controller_->engine()->messenger()` named `clipps/clipboard` with `flutter::StandardMethodCodec::GetInstance()`, then `AddClipboardFormatListener(GetHandle())`.
- `MessageHandler`, at the top, before `HandleTopLevelWindowProc`: `case WM_CLIPBOARDUPDATE:` → `clipboard_channel_->InvokeMethod("clipboardChanged", nullptr); return 0;` (guard on non-null channel).
- `OnDestroy`, before the controller is reset: `RemoveClipboardFormatListener(GetHandle())` and `clipboard_channel_ = nullptr`.

- [ ] **Step 6: Start the watcher in `startApp`**

After `load()`: `ClipboardWatcher(onText: (t) async { await provider.addClip(t); }).start();`

- [ ] **Step 7: Write the end-to-end test `integration_test/clipboard_capture_test.dart`**

```dart
testWidgets('text copied to the OS clipboard appears in history', (tester) async {
  final dir = await Directory.systemTemp.createTemp('clipps_it');
  await startApp(p.join(dir.path, 'clips.db'));
  final marker = 'clipps-it-${DateTime.now().microsecondsSinceEpoch}';
  await Clipboard.setData(ClipboardData(text: marker));   // goes through the real OS clipboard and WM_CLIPBOARDUPDATE
  for (var i = 0; i < 50 && find.text(marker).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.text(marker), findsOneWidget);
});
```
Use `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`. This test overwrites the user's clipboard; that is expected.

- [ ] **Step 8: Run all tests**

Run: `flutter test` then `flutter test integration_test -d windows`
Expected: all PASS.

- [ ] **Step 9: Manual check**

Run: `flutter run -d windows`. Copy text in Notepad → it appears at the top within a second. Copy the same text again → no second row. Copy an image (Win+Shift+S) → no row, no error. Copy in Excel (sets many formats) → one row.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: capture OS clipboard changes via WM_CLIPBOARDUPDATE platform channel"
```

---

### Task 5: Background running (close to tray, single instance)

**Files:**
- Modify: `windows/runner/flutter_window.h`, `windows/runner/flutter_window.cpp`, `windows/runner/main.cpp`

**Interfaces:**
- Consumes: the runner changes from Task 4.
- Produces: native behavior only; no Dart API.

Behavior (exact):
- Closing the window (X, Alt+F4) hides it; the process, Dart isolate and capture keep running.
- A tray icon (the app icon, `IDI_APP_ICON` from `resource.h`, tooltip `Clipps — clipboard history`) is added in `OnCreate` and removed in `OnDestroy` (`Shell_NotifyIcon` `NIM_ADD` / `NIM_DELETE`, callback message `WM_APP + 1`).
- Tray left-click: show, restore and foreground the window. Tray right-click: popup menu `Open` / `Quit` (call `SetForegroundWindow` before `TrackPopupMenu`, use `TPM_RETURNCMD`). `Quit` sets a `quitting_` flag and posts `WM_CLOSE`, which then takes the normal destroy path and exits.
- Handle `WM_CLOSE` and the tray message at the top of `MessageHandler`, before `HandleTopLevelWindowProc`.
- Single instance, in `main.cpp` before creating the window: `CreateMutexW(nullptr, TRUE, L"Local\\clipps_single_instance")`; on `ERROR_ALREADY_EXISTS`, `FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"clipps")`, show/restore/foreground it if found, and return `EXIT_SUCCESS`. (Check the title string passed to `window.Create` in `main.cpp` and use the same one.)

- [ ] **Step 1: Implement the behavior above**

- [ ] **Step 2: Build**

Run: `flutter build windows`
Expected: build succeeds with no C++ warnings introduced.

- [ ] **Step 3: Manual check** (run `build\windows\x64\runner\Release\clipps.exe`)

1. Close the window → it disappears, tray icon remains, process still in Task Manager.
2. Copy text in Notepad while hidden → left-click tray icon → window shows with that clip at the top.
3. Launch `clipps.exe` again while hidden → no second process; the existing window comes to front.
4. Right-click tray → `Quit` → tray icon gone, process exits.
5. Relaunch → history from steps 2 is still there.

- [ ] **Step 4: Re-run the test suites** (quit the app from the tray first — the single-instance mutex would make the integration test exit)

Run: `flutter test` then `flutter test integration_test -d windows`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: keep capturing in background via tray and single instance"
```
