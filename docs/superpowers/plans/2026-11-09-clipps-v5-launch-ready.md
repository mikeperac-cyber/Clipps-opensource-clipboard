# Clipps v5: Launch-Ready Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Implementer model: Sonnet 5.5.

**Goal:** Make Clipps presentable to strangers who arrive from an ad: its own icon and name, a trust story (offline, private, pausable), a 2-keystroke "find and copy" flow worth demoing, and a first-run hint — with no change to stored data.

**Architecture:** Small additions to the existing provider/sidebar/home screen, one new native method (`hideWindow`) on the existing `clipps/clipboard` channel, one setting in the existing `settings` table. No schema change, no new dependencies.

**Tech Stack:** Flutter (Windows), provider, sqflite_common_ffi, C++ Win32 runner, Inno Setup.

**Spec:** None separate. The decisions below are the spec (planner's choices, 2026-11-09; the user asked for lightweight, advertising-ready, data-preserving).

## Decisions

1. **Brand:** a real app icon (also used by the tray and installer) and window title `Clipps`.
2. **About dialog:** version, privacy statement, data folder with an `Open data folder` button, and Flutter's built-in open-source licenses page (needed to distribute legally).
3. **Pause capture:** a sidebar switch and a checked `Pause capture` item in the tray menu, kept in step; while on, copies from other apps are not saved (manual Save Clip still works). Saved across restarts. A banner shows while paused and the tray tooltip says so.
4. **Quick copy:** in the search box, `Enter` copies the top listed clip and hides the window; `Esc` hides the window. Together with `Ctrl+Alt+.` this is: shortcut → type → Enter.
5. **First-run hint:** the "No clips yet" empty state explains what to do.
6. **Duplicate marker (user's choice, 2026-11-09):** duplicates are still saved as today, but every live clip whose exact text appears more than once outside Trash shows a `Duplicate` marker.
7. **Export clips (user's choice):** an `Export clips` button in the About dialog writes every clip outside Trash to a CSV file in the Downloads folder, then shows it in Explorer.
8. **Version 3.3.0** everywhere, kept in sync by a test. README rewritten as a product page with a privacy section.

Out of scope (deliberately): code signing, auto-update, Microsoft Store/MSIX, licensing/payments, telemetry, auto-paste into the previous app, image clips, sync.

## Global Constraints

- **Do not change stored data or where it lives.** `kSchemaVersion` stays 4. No migrations. Do not edit `CompanyName` or `ProductName` in `windows/runner/Runner.rc`: path_provider builds the data folder `%APPDATA%\Clipps\clipps\` from them.
- Do not change the installer `AppId`, the DB file name, or the backups folder.
- No new packages in `pubspec.yaml`.
- Version string: `3.3.0` (pubspec `version: 3.3.0+1`).
- Brand colour: `#5B5BD6` (the existing theme seed).
- All new user-facing copy is exactly as written in this plan.
- Run `flutter analyze` and `flutter test` before each commit; both must be clean.

## Review Focus

1. **Upgrade over the installed 3.2.1** must open the same clips, notes, groups and theme. → Task 8 manual check; Global Constraints forbid the risky edits.
2. **Enter with nothing to copy** (no results, Trash view) must neither copy nor hide. → Task 4 test `enter with no results does nothing`.
3. **Pause survives a restart** and the banner shows on next launch. → Task 3 test `pause persists across load`.
4. **Pause must not block manual Save Clip.** → Task 3 test `manual save works while paused`.
5. **Missing native handler** (tests, or an old runner) must not crash Enter/Esc. → Task 4 test `enter copies even without a native hide handler`.

---

### Task 1: App icon and window title

**Files:**
- Modify: `windows/runner/resources/app_icon.ico` (replace)
- Modify: `windows/runner/main.cpp:16` and `:61` (title `clipps` → `Clipps`, both places — line 16 is the single-instance lookup and must match line 61)

**Interfaces:**
- Produces: nothing code-level. The tray (`flutter_window.cpp:139`), window class (`win32_window.cpp:99`) and installer (`SetupIconFile`) already load this file.

- [ ] **Step 1: Generate the icon with a throwaway Pillow script in the scratchpad (do not commit the script).** Draw at 1024×1024, then downscale with LANCZOS to each size. Geometry on a 256 grid (multiply by 4):
  - Background: rounded square (8,8)–(248,248), radius 56, fill `#5B5BD6`.
  - Board: rounded rect (68,56)–(188,216), radius 18, fill `#FFFFFF`.
  - Clip tab: rounded rect (100,40)–(156,76), radius 12, fill `#3E3EA8`.
  - Three text lines: rounded bars x 92–164, height 12, top y 108, 136, 164, fill `#5B5BD6`; the last bar ends at x 140.
  - Save as ICO with sizes 16, 24, 32, 48, 64, 128, 256.
- [ ] **Step 2: Verify**

  Run: `python -c "from PIL import Image; i=Image.open('windows/runner/resources/app_icon.ico'); print(sorted(i.info['sizes']))"`
  Expected: all seven sizes listed; file size is no longer 33772 bytes. Open the 256 px PNG preview once to eyeball it.
- [ ] **Step 3: Change both `L"clipps"` window-title literals in `main.cpp` to `L"Clipps"`.** Do not touch the mutex name or the `Run` value name.
- [ ] **Step 4: Build** `flutter build windows --no-tree-shake-icons`; launch `build\windows\x64\runner\Release\clipps.exe`; confirm the new icon in the taskbar and tray, title `Clipps`, and that launching it a second time brings up the first window (single instance still works).
- [ ] **Step 5: Commit** `feat: Clipps app icon and window title`

---

### Task 2: Version 3.3.0 and About dialog

**Files:**
- Create: `lib/app_info.dart`
- Modify: `pubspec.yaml` (`version: 3.3.0+1`), `installer/clipps.iss` (`AppVersion "3.3.0"`)
- Modify: `lib/providers/clipboard_provider.dart` (add `dataDir`)
- Modify: `lib/screens/sidebar.dart` (About tile)
- Test: `test/version_test.dart` (create), `test/screens/sidebar_test.dart`

**Interfaces:**
- Produces: `const kAppVersion = '3.3.0';` in `lib/app_info.dart`; `String get dataDir` on `ClipboardProvider` = `p.dirname(_db.rawDb.path)` (package `path`).

- [ ] **Step 1: Write failing tests**

```dart
// test/version_test.dart
test('kAppVersion matches pubspec and installer', () {
  final pub = File('pubspec.yaml').readAsStringSync();
  final iss = File('installer/clipps.iss').readAsStringSync();
  expect(pub, contains('version: $kAppVersion+'));
  expect(iss, contains('#define AppVersion "$kAppVersion"'));
});
```

```dart
// test/screens/sidebar_test.dart (use the file's existing pump helper)
testWidgets('About Clipps shows version, privacy and licenses', (t) async {
  // tap Key('aboutClipps'), pumpAndSettle
  expect(find.text('Clipps'), findsWidgets);
  expect(find.text('3.3.0'), findsOneWidget);
  expect(find.textContaining('never sent anywhere'), findsOneWidget);
  expect(find.byKey(const Key('openDataFolder')), findsOneWidget);
  expect(find.text('View licenses'), findsOneWidget); // Flutter's AboutDialog button
});
```

- [ ] **Step 2: Run** `flutter test test/version_test.dart test/screens/sidebar_test.dart` — Expected: FAIL (missing `app_info.dart` / key).
- [ ] **Step 3: Implement.** Bump the three version strings. In the sidebar's bottom area, above the theme control, add `ListTile(key: Key('aboutClipps'), dense: true, leading: Icon(Icons.info_outline), title: Text('About Clipps'), shape: StadiumBorder())` that calls Flutter's `showAboutDialog` with:
  - `applicationName: 'Clipps'`, `applicationVersion: kAppVersion`, `applicationLegalese: '© 2026 Clipps'`
  - `children`: `Text('Clipps works offline. Your clips are stored only on this PC and are never sent anywhere.')`, then `SelectableText(p.dataDir)`, then `TextButton(key: Key('openDataFolder'), child: Text('Open data folder'))` whose handler runs `Process.run('explorer.exe', [dir])` inside `try`/`catch` (explorer exits non-zero even on success; ignore the result).
- [ ] **Step 4: Run** the two tests, then `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: About dialog with privacy, data folder and licenses; version 3.3.0`

---

### Task 3: Pause capture

**Files:**
- Modify: `lib/providers/clipboard_provider.dart`, `lib/main.dart:56-58` (watcher wiring), `lib/screens/sidebar.dart`, `lib/screens/home_screen.dart` (banner)
- Modify: `lib/services/clipboard_watcher.dart` (tray sync), `windows/runner/flutter_window.cpp` + `flutter_window.h` (tray item)
- Test: `test/providers/clipboard_provider_test.dart`, `test/screens/home_screen_test.dart`, `test/services/clipboard_watcher_test.dart`

**Interfaces:**
- Produces: `bool get capturePaused`; `Future<void> setCapturePaused(bool paused)` — saves setting key `capture_paused` as `'true'`/`'false'` via `_db.setSetting`, sets the field, `notifyListeners()`. `load()` reads it (`== 'true'`; missing → `false`).
- `ClipboardWatcher`: new optional ctor callback `VoidCallback? onTogglePause` (called on native method `togglePause`); new `Future<void> setPaused(bool paused)` = `channel.invokeMethod('setPaused', paused)` with `MissingPluginException`/`PlatformException` swallowed.
- Native: a `bool capture_paused_` member. Method handler (the same `SetMethodCallHandler` Task 4 adds — whichever task lands first creates it, the other adds a case) handles `"setPaused"` (bool arg) → store it, set tooltip to `Clipps — capture paused` or back to `Clipps — clipboard history`, `Shell_NotifyIcon(NIM_MODIFY, ...)`. Tray menu gets `constexpr UINT kMenuPause = 3;` item `Pause capture` between Open and Quit, `MF_CHECKED` when paused; choosing it invokes Dart `togglePause`.

- [ ] **Step 1: Write failing tests**

```dart
// provider test
test('pause persists across load', () async {
  await p.setCapturePaused(true);
  final p2 = ClipboardProvider(db);
  await p2.load();
  expect(p2.capturePaused, isTrue);
});
test('manual save works while paused', () async {
  await p.setCapturePaused(true);
  expect(await p.addClip('typed by hand'), isTrue);
});
```

```dart
// home_screen_test
testWidgets('paused shows the banner', (t) async {
  await t.runAsync(() => p.setCapturePaused(true));
  await show(t);
  expect(find.byKey(const Key('pausedBanner')), findsOneWidget);
  expect(find.text('Capture is paused. New copies are not saved.'), findsOneWidget);
});
```

```dart
// clipboard_watcher_test (mock the channel the way the file already does)
test('togglePause from native calls onTogglePause', () async { /* expect callback ran once */ });
test('setPaused sends setPaused with the flag', () async { /* expect call setPaused(true) */ });
```

- [ ] **Step 2: Run** these tests — Expected: FAIL (`capturePaused` undefined).
- [ ] **Step 3: Implement.** Provider members as above. In `main.dart` the watcher's `onText` skips `addClip` when `provider.capturePaused` (manual Save Clip calls `addClip` directly, so it is unaffected). Wire `onTogglePause: () => provider.setCapturePaused(!provider.capturePaused)`; after `start()`, call `watcher.setPaused(provider.capturePaused)` and add a provider listener that calls `setPaused` only when the value differs from the last one sent. Then the native side as in Interfaces. Sidebar: above the About tile, `SwitchListTile(key: Key('pauseCapture'), dense: true, secondary: Icon(Icons.pause_circle_outline), title: Text('Pause capture'), value: p.capturePaused, onChanged: p.setCapturePaused)`. Home screen: when paused, show above the manual input, in the same style as `hotkeyWarning` but `colorScheme.tertiary`, `Text('Capture is paused. New copies are not saved.', key: Key('pausedBanner'))`.
- [ ] **Step 4: Run** `flutter test` — Expected: PASS. Build and check manually: tray right-click shows `Pause capture` unchecked; choose it → checked, sidebar switch on, banner shows, tooltip says paused; flip the sidebar switch off → tray item unchecked.
- [ ] **Step 5: Commit** `feat: pause clipboard capture from the sidebar and tray`

---

### Task 4: Quick copy (Enter / Esc) and first-run hint

**Files:**
- Modify: `windows/runner/flutter_window.cpp` (method handler after the channel is created, ~line 128)
- Modify: `lib/screens/home_screen.dart` (`_SearchField` `onSubmitted`, Esc shortcut, empty-state hint)
- Test: `test/screens/home_screen_test.dart`

**Interfaces:**
- Native: `clipboard_channel_->SetMethodCallHandler` handles `"hideWindow"` → `ShowWindow(GetHandle(), SW_HIDE); result->Success();`, anything else → `result->NotImplemented()`. Clear the handler in `OnDestroy` before resetting the channel.
- Dart: a private `Future<void> _hideWindow()` in `home_screen.dart` that calls `const MethodChannel('clipps/clipboard').invokeMethod<void>('hideWindow')` and swallows `MissingPluginException` and `PlatformException`.

- [ ] **Step 1: Write failing tests** (mock the platform clipboard the same way as the existing `tapping a row copies its full content` test; mock `clipps/clipboard` with `t.binding.defaultBinaryMessenger.setMockMethodCallHandler` and record calls)

```dart
testWidgets('enter copies the top clip and hides the window', (t) async {
  await show(t, clips: ['older', 'newest full text']);
  await t.enterText(find.byKey(const Key('search')), '');
  await t.testTextInput.receiveAction(TextInputAction.done);
  await settle(t);
  expect(copied, 'newest full text');      // full content, not the preview
  expect(nativeCalls, ['hideWindow']);
});
testWidgets('enter with no results does nothing', (t) async {
  await show(t, clips: ['abc']);
  await t.enterText(find.byKey(const Key('search')), 'zzz');
  await settle(t);
  await t.testTextInput.receiveAction(TextInputAction.done);
  await settle(t);
  expect(copied, isNull);
  expect(nativeCalls, isEmpty);
});
testWidgets('enter copies even without a native hide handler', (t) async {
  // no clipps/clipboard mock registered
  await show(t, clips: ['x']);
  await t.enterText(find.byKey(const Key('search')), '');
  await t.testTextInput.receiveAction(TextInputAction.done);
  await settle(t);
  expect(t.takeException(), isNull);
  expect(copied, 'x');
});
testWidgets('escape hides the window', (t) async {
  await show(t);
  await t.sendKeyEvent(LogicalKeyboardKey.escape);
  await settle(t);
  expect(nativeCalls, ['hideWindow']);
});
testWidgets('empty history explains how to start', (t) async {
  await show(t);
  expect(find.text('No clips yet'), findsOneWidget);
  expect(find.text('Copy any text and it appears here. Press Ctrl+Alt+. to open Clipps from anywhere.'), findsOneWidget);
});
```

- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement Dart.** `_SearchField` gets an `onSubmitted` callback; HomeScreen passes one that, only when `p.view != ClipView.trash` and `p.clips.isNotEmpty`, does `Clipboard.setData(ClipboardData(text: p.clips.first.content))` then `_hideWindow()`. Wrap the `Scaffold` in `CallbackShortcuts({SingleActivator(LogicalKeyboardKey.escape): _hideWindow})` inside a `Focus(autofocus: true)` so Esc works when nothing else has focus. Empty state: for `ClipView.all`, no group, not filtered, add under `No clips yet` a `Text(..., key: Key('emptyHint'), textAlign: TextAlign.center)` with `'Copy any text and it appears here. Press Ctrl+Alt+. to open Clipps from anywhere.'`; when `p.hotkeyUnavailable`, show only `'Copy any text and it appears here.'`.
- [ ] **Step 4: Implement native** handler as in Interfaces.
- [ ] **Step 5: Run** `flutter test`, then build and try manually: `Ctrl+Alt+.` → type → `Enter` → window hides → `Ctrl+V` in Notepad pastes the clip; `Esc` hides; a dialog's Esc still closes only the dialog.
- [ ] **Step 6: Commit** `feat: Enter copies the top match and hides, Esc hides, first-run hint`

---

### Task 5: Duplicate marker on rows

**Files:**
- Modify: `lib/database/db_helper.dart`, `lib/providers/clipboard_provider.dart` (`_reload`), `lib/screens/clip_row.dart`
- Test: `test/database/db_helper_test.dart`, `test/screens/home_screen_test.dart`

**Interfaces:**
- DB: `Future<Set<int>> duplicateIds()` — ids of clips outside Trash whose `content` appears more than once outside Trash. One query, no per-row subquery:
  `SELECT id FROM clips WHERE deleted_at IS NULL AND content IN (SELECT content FROM clips WHERE deleted_at IS NULL GROUP BY content HAVING COUNT(*) > 1)`
- Provider: `bool isDuplicate(int id)`, backed by a `Set<int>` refreshed in `_reload()` (so it ignores the current search/filter).

- [ ] **Step 1: Write failing tests**

```dart
test('duplicateIds finds repeats outside Trash only', () async {
  final a = await db.insertClip('same', t0);
  final b = await db.insertClip('other', t1);
  final c = await db.insertClip('same', t2);
  expect(await db.duplicateIds(), {a.id, c.id});
  await db.trashClips([c.id], t3);
  expect(await db.duplicateIds(), isEmpty);  // one copy left outside Trash
});
testWidgets('rows with repeated text show Duplicate', (t) async {
  await show(t, clips: ['same', 'x', 'same']);
  expect(find.text('Duplicate'), findsNWidgets(2));
});
```

  (`show` uses `addClip`, which skips a copy equal to the newest clip, so the `'x'` in between is needed.)
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.** In `ClipRow`, when `view != ClipView.trash` and `provider.isDuplicate(clip.id)`, show next to the tag chips a small chip with key `dupBadge-<id>`, icon `Icons.content_copy` size 14, label `Duplicate`, colour `colorScheme.tertiary`, wrapped in `Tooltip(message: 'This text is saved more than once')`.
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: mark clips whose text is saved more than once`

---

### Task 6: Export clips to CSV

**Files:**
- Create: `lib/services/csv_export.dart`
- Modify: `lib/screens/sidebar.dart` (About dialog button from Task 2)
- Test: `test/services/csv_export_test.dart`

**Interfaces:**
- Consumes: `ClipboardModel`, `ClipGroup` (existing models); `DbHelper.getClips()` with no arguments returns every clip outside Trash; `provider.groups` for group names.
- Produces: `String clipsToCsv(List<ClipboardModel> clips, Map<int, String> groupNames)` (pure) and `Future<String> exportClipsCsv(DbHelper db, Map<int, String> groupNames, Directory dir, DateTime now)` that writes `Clipps-export-YYYY-MM-DD-HHmm.csv` in `dir` and returns its path. Provider: `Future<String> exportClips()` using `getDownloadsDirectory()` from path_provider (fall back to `dataDir` when it returns null).

CSV format: UTF-8 with a BOM (so Excel shows accents), `\r\n` line ends, header `Created,Source app,Window title,Pinned,Group,Tags,Content`. Created = `YYYY-MM-DD HH:mm` local. Pinned = `yes`/blank. Tags joined with `; `. Every field is quoted with `"` and inner `"` doubled. A field starting with `=`, `+`, `-` or `@` gets a leading `'`, so a spreadsheet does not run it as a formula.

- [ ] **Step 1: Write failing tests**

```dart
test('csv quotes commas, quotes and newlines', () {
  final csv = clipsToCsv([clip(content: 'a, "b"\nc')], {});
  expect(csv, startsWith('﻿Created,Source app,Window title,Pinned,Group,Tags,Content\r\n'));
  expect(csv, contains('"a, ""b""\nc"'));
});
test('csv neutralises formulas', () {
  expect(clipsToCsv([clip(content: '=HYPERLINK("x")')], {}), contains('"\'=HYPERLINK(""x"")"'));
});
test('csv fills group name, tags and pinned', () { /* groupId 1 -> 'Work', tags ['link','todo'] -> "link; todo", pinned -> "yes" */ });
test('export writes the file and skips Trash', () async {
  // file-backed temp DB: 2 live clips, 1 trashed; exportClipsCsv(...) into a temp dir
  // expect the file exists, has 3 lines incl. header... (count rows by parsing, contents may hold newlines)
});
```

- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the two functions and `provider.exportClips()`. In the About dialog add `TextButton(key: Key('exportClips'), child: Text('Export clips'))`: on success show a SnackBar `Exported to <path>` and run `Process.run('explorer.exe', ['/select,', path])` in `try`/`catch`; on error show `Export failed: <error>`.
- [ ] **Step 4: Run** `flutter test` — Expected: PASS. Manually export, open the CSV in Excel, check accents and a multi-line clip.
- [ ] **Step 5: Commit** `feat: export clips to CSV from the About dialog`

---

### Task 7: README as a product page

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite** with these sections, keeping the existing "Where your data lives" and "Restore from a backup" sections verbatim at the end:
  - One-line pitch: `Clipps remembers everything you copy on Windows, so you can find it again in two keystrokes.`
  - **Features** (one line each): history with search and date filter; `Ctrl+Alt+.` → type → `Enter` to copy; pin, groups, tags (auto-detected links, emails, phones, code); tasks; notes on clips; Trash with 15-day restore; light/dark theme; pause capture (app or tray); duplicate marker; export to CSV; skips content marked private by password managers; daily backups (newest 7).
  - **Privacy:** the About dialog sentence, plus: no account, no internet connection used, no analytics.
  - **Requirements:** Windows 10 or 11, 64-bit. Installs per user, no admin rights.
  - **Install / Uninstall:** run `Clipps-Setup-3.3.0.exe`; uninstalling keeps your clips in `%APPDATA%\Clipps\clipps\`.
- [ ] **Step 2: Commit** `docs: README as a product page with privacy section`

---

### Task 8: Build the 3.3.0 installer and verify an upgrade keeps data

- [ ] **Step 1:** Note the current row counts from the installed 3.2.1 (in the app: count in All clips, Notes, groups), and copy `%APPDATA%\Clipps\clipps\clipps.db` to the scratchpad as a safety copy.
- [ ] **Step 2:** `flutter build windows --no-tree-shake-icons`, then `ISCC installer\clipps.iss`. Expected: `build\installer\Clipps-Setup-3.3.0.exe`.
- [ ] **Step 3:** Install over 3.2.1. Confirm: same clips, notes, groups and theme; new icon in Start menu, tray, and Apps & features; About shows `3.3.0` and opens the data folder; pause on (from the tray) → copy in Notepad → nothing saved → pause off → copy → saved; quick copy flow works; existing repeated clips show `Duplicate`; Export clips writes a CSV to Downloads that opens in Excel.
- [ ] **Step 4:** Take light and dark screenshots of the main window (with real-looking but non-private clips) for the ad material.
- [ ] **Step 5: Commit** `build: installer version 3.3.0`
