# Clipps v2 Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add source app/window title per clip, a Ctrl+AltGr+`.` global hotkey, delete-protected pinned clips, and always-on start at login to the existing Clipps app.

**Architecture:** Data first (model + DB v2 migration), then provider state, then UI, then native work in two tasks: source capture on the existing clipboard channel, then hotkey + autostart + hidden launch. The native runner sends everything over the existing `clipps/clipboard` MethodChannel, whose single Dart handler is `ClipboardWatcher`.

**Tech Stack:** Flutter 3.47.9 (Windows), Dart 3.13, `sqflite_common_ffi`, `provider`, Win32 C++ in `windows/runner` (Visual Studio 2026).

**Spec:** `docs/superpowers/specs/2026-11-03-clipps-v2-features-design.md` (builds on `docs/superpowers/specs/2026-11-03-clipboard-manager-design.md`)

## Global Constraints

- Flutter is at `C:\Users\MIKE\dev\flutter\bin`; prepend it to PATH in each shell.
- Existing history must survive: DB version 1 → 2 via `onUpgrade` only adding columns; nothing is dropped or rewritten.
- Clips are kept indefinitely; rows are removed only by explicit user delete; pinned rows are never deleted.
- Copies flagged private are never stored (existing native check stays as is).
- Source fields are display only — no search/filter by source.
- Runner C++ sources stay pure ASCII (`\uXXXX` escapes); Release build has 0 C++ warnings.
- Do not change `ProductName` or `CompanyName` in `Runner.rc` (they set the DB folder).
- Channel: `clipps/clipboard`. Native → Dart methods: `clipboardChanged` (arg `{"sourceApp": String?, "sourceTitle": String?}`), `focusSearch` (no arg), `hotkeyUnavailable` (no arg).
- Exact copy: `Pin`, `Unpin`, `Unpin to delete`, `Shortcut Ctrl+Alt+. is already used by another app`, subtitle separator ` · ` (U+00B7 with spaces) and app/title separator ` — ` (U+2014 with spaces).
- Hotkey: `RegisterHotKey(hwnd, 1, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_OEM_PERIOD)`.
- Autostart: Release builds only (`#ifdef NDEBUG`), `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, value `Clipps`, `REG_SZ` `"<full exe path>" --hidden`, rewritten every launch, failures ignored.
- Work on a branch `feat/clipps-v2` off `main`; commit per task.

## Review Focus

1. **Upgrading a real v1 database that already holds clips** → every old row is still there with `pinned = 0` and no source, and new clips work. Pinned in Task 1 (`upgrade from v1 keeps rows` test on a real file).
2. **Copying the same text again while an older copy is pinned** → dedupe compares with the most recently copied clip, not the pinned top row. Pinned in Task 2 (`dedupe ignores pins` test).
3. **Delete selected with a pinned clip somehow in the selection** → the pinned clip survives (SQL guard), the rest are deleted. Pinned in Task 1 (`deleteClips never removes pinned rows`) and Task 2 (`togglePin removes from selection`).
4. **Clipboard owned by a background app (title must not leak from another window) or owner unknown** → app name only / no source; clip still saved. Pinned in Task 4 (watcher tests for null/empty fields; native same-process check per spec).
5. **Start at login while Clipps is already running, or hotkey taken by another app** → no pop-up at login; persistent warning line instead of a missed SnackBar. Pinned in Task 5 (scripted second `--hidden` instance check; `hotkeyUnavailable` widget test).

---

### Task 1: ClipSource, model fields, DB v2

**Files:**
- Create: `lib/models/clip_source.dart`
- Modify: `lib/models/clipboard_model.dart`, `lib/database/db_helper.dart`
- Test: `test/models/clipboard_model_test.dart`, `test/database/db_helper_test.dart`

**Interfaces:**
- Consumes: existing `DbHelper` (`open`, `insertClip`, `latestClip`, `getClips`, `deleteClips`, `close`, `@visibleForTesting rawDb`).
- Produces:
  - `class ClipSource { const ClipSource({this.app, this.title}); final String? app; final String? title; }` with `==`/`hashCode`.
  - `ClipboardModel` gains `final String? sourceApp; final String? sourceTitle; final bool pinned;` (constructor params optional, defaults `null`/`null`/`false`) and `String? get sourceLabel` → `'App — Title'`, `'App'`, or `null` (title without app → `null`).
  - `DbHelper.insertClip(String content, DateTime createdAt, {ClipSource source = const ClipSource()})`; `Future<void> setPinned(int id, bool pinned)`; `getClips` orders `pinned DESC, created_at DESC, id DESC`; `latestClip` keeps `created_at DESC, id DESC`; `deleteClips` adds `AND pinned = 0`.
  - Schema v2: columns `source_app TEXT`, `source_title TEXT`, `pinned INTEGER NOT NULL DEFAULT 0`.

- [ ] **Step 1: Create branch**

```bash
git switch -c feat/clipps-v2
```

- [ ] **Step 2: Write the failing tests**

Model:
```dart
test('fromMap reads source and pinned', ...);   // {'source_app':'Google Chrome','source_title':'Inbox','pinned':1} → fields set, pinned true
test('fromMap defaults when columns are null/0', ...); // sourceApp null, sourceTitle null, pinned false
test('sourceLabel formats app and title', () {
  expect(_m(app: 'Google Chrome', title: 'Inbox - Gmail').sourceLabel, 'Google Chrome \u2014 Inbox - Gmail');
  expect(_m(app: 'Google Chrome').sourceLabel, 'Google Chrome');
  expect(_m(title: 'Orphan title').sourceLabel, isNull);
  expect(_m().sourceLabel, isNull);
});
```
DbHelper:
```dart
test('insertClip stores source', ...);              // ClipSource(app:'A', title:'T') round-trips via getClips
test('setPinned pins and unpins', ...);
test('pinned clips sort first, newest pinned first, and still obey filters', ...); // 3 clips, pin oldest two; order [pinned newer, pinned older, unpinned]; text filter that excludes a pinned clip hides it
test('latestClip ignores pins', ...);               // pin an old clip; latestClip is the newest by created_at
test('deleteClips never removes pinned rows', ...); // delete [pinnedId, plainId] → returns 1, pinned still present
test('upgrade from v1 keeps rows', () async {
  // temp file; create v1 schema with databaseFactoryFfi directly (version 1, the v1 CREATE TABLE/INDEX SQL),
  // insert 2 rows, close; then DbHelper.open on the same path:
  // both rows present, pinned false, sourceApp/sourceTitle null; insertClip with a source works.
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/models test/database`
Expected: FAIL — `ClipSource` undefined / missing fields.

- [ ] **Step 4: Implement**

`open`: `version: 2`; `onCreate` creates the v2 table (+ existing index); `onUpgrade: (db, oldVersion, _)` runs the three `ALTER TABLE clips ADD COLUMN …` statements from the spec when `oldVersion < 2`. Keep `onConfigure` (`secure_delete`). Empty source strings are stored as `NULL`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test`
Expected: all PASS (existing tests too).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: store clip source and pinned flag (DB v2)"
```

---

### Task 2: Provider — source, pins, hotkey state

**Files:**
- Modify: `lib/providers/clipboard_provider.dart`
- Test: `test/providers/clipboard_provider_test.dart`

**Interfaces:**
- Consumes: Task 1 `ClipSource`, `DbHelper.insertClip(..., {source})`, `setPinned`, `ClipboardModel.pinned`.
- Produces:
  - `Future<bool> addClip(String content, {ClipSource source = const ClipSource()})` (same serialization and dedupe).
  - `Future<void> togglePin(int id)` — flips the listed clip's `pinned` (no-op if `id` not in `clips`), removes `id` from selection, reloads, notifies.
  - `int get searchFocusRequests` + `void requestSearchFocus()` (increments, notifies).
  - `bool get hotkeyUnavailable` + `void markHotkeyUnavailable()` (sets true, notifies).

- [ ] **Step 1: Write the failing tests**

```dart
test('addClip stores the source', ...);
test('dedupe ignores pins', ...);           // add 'a', add 'b', pin 'a'; addClip('b') → false; addClip('a') → true (newest is 'b')
test('togglePin pins, unpins and removes from selection', ...);
test('requestSearchFocus increments and notifies', ...);
test('markHotkeyUnavailable sets flag and notifies', ...);
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/providers`
Expected: FAIL — new members undefined.

- [ ] **Step 3: Implement the members above in `lib/providers/clipboard_provider.dart`**

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: provider support for clip source, pins and hotkey state"
```

---

### Task 3: UI — source subtitle, pin controls, search focus, warning line

**Files:**
- Modify: `lib/screens/home_screen.dart`
- Test: `test/screens/home_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 `ClipboardModel.sourceLabel`, `pinned`; Task 2 `togglePin`, `searchFocusRequests`, `hotkeyUnavailable`.
- Produces: widget keys `pin-<id>` (pin button), `hotkeyWarning` (warning line); existing keys unchanged.

UI rules (exact):
- Subtitle: `'<yyyy-MM-dd HH:mm:ss>'` plus `' \u00B7 <sourceLabel>'` when `sourceLabel != null`; `maxLines: 1`, ellipsis.
- Trailing: `Row(mainAxisSize: MainAxisSize.min)` with pin button then delete button. Pin: `Icons.push_pin` + tooltip `Unpin` when pinned, `Icons.push_pin_outlined` + tooltip `Pin` otherwise.
- Pinned row: `tileColor` = `colorScheme.secondaryContainer` with alpha 0.35; checkbox `onChanged: null`; delete `onPressed: null`, tooltip `Unpin to delete`.
- Search field becomes a private `StatefulWidget` owning a `FocusNode` and `TextEditingController` (disposed); when `searchFocusRequests` changes from the last value it saw, it requests focus and selects all text (post-frame).
- When `hotkeyUnavailable`, a single line `Shortcut Ctrl+Alt+. is already used by another app` (key `hotkeyWarning`, error colour) sits directly under the app bar, above the manual input.

- [ ] **Step 1: Write the failing widget tests** (same real-DB pattern as the existing file)

```dart
testWidgets('subtitle shows app and title', ...);          // expect find.text containing '\u00B7 Google Chrome \u2014 Inbox'
testWidgets('subtitle shows only timestamp without source', ...); // subtitle has no '\u00B7'
testWidgets('pin button pins: tooltip Unpin, row moves to top, checkbox and delete disabled', ...);
testWidgets('pinned delete button tooltip is "Unpin to delete"', ...);
testWidgets('requestSearchFocus focuses the search field and selects its text', ...);
testWidgets('hotkeyUnavailable shows the warning line', ...);
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/screens`
Expected: FAIL — keys/texts not found.

- [ ] **Step 3: Implement the UI rules above in `lib/screens/home_screen.dart`**

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test` then `flutter analyze`
Expected: all PASS; no issues.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: show clip source, pin controls, search focus and hotkey warning"
```

---

### Task 4: Native source capture over the channel

**Files:**
- Create: `windows/runner/clipboard_source.h`, `windows/runner/clipboard_source.cpp`
- Modify: `windows/runner/flutter_window.h`, `windows/runner/flutter_window.cpp`, `windows/runner/CMakeLists.txt`, `windows/runner/Runner.rc` (FileDescription only), `lib/services/clipboard_watcher.dart`, `lib/main.dart`
- Test: `test/services/clipboard_watcher_test.dart`, `integration_test/clipboard_capture_test.dart`

**Interfaces:**
- Consumes: Task 2 `addClip(content, {source})`; Task 1 `ClipSource`.
- Produces:
  - C++: `struct ClipboardSource { std::wstring app; std::wstring title; };` and `ClipboardSource GetClipboardSource();` (empty string = unknown).
  - Dart: `ClipboardWatcher.onText` type `Future<void> Function(String text, ClipSource source)`.

- [ ] **Step 1: Write the failing watcher tests** (existing `handlePlatformMessage` pattern, now with arguments)

```dart
test('clipboardChanged passes the source map through', ...);   // {'sourceApp':'A','sourceTitle':'T'} → onText('hello', ClipSource(app:'A', title:'T'))
test('missing or null argument means no source', ...);          // MethodCall('clipboardChanged') → ClipSource()
test('empty strings become null', ...);                          // {'sourceApp':'', 'sourceTitle':''} → ClipSource()
```
Update the existing watcher tests to the new `onText` signature.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services`
Expected: FAIL — signature mismatch.

- [ ] **Step 3: Implement the Dart side**

Watcher parses `call.arguments` (a `Map?`) into `ClipSource`, mapping `''` to `null`; retry/error handling unchanged. `main.dart` wires `onText: (t, s) async { await provider.addClip(t, source: s); }`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test`
Expected: all PASS.

- [ ] **Step 5: Implement `GetClipboardSource()` in `clipboard_source.cpp`**

Follow the spec's lookup chain exactly (owner → pid → `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` → `QueryFullProcessImageNameW` → `GetFileVersionInfoSizeW`/`GetFileVersionInfoW`/`VerQueryValueW` FileDescription via the first `\VarFileInfo\Translation` entry, else the exe file name; title from `GetForegroundWindow()`+`GetWindowTextW` only when its pid equals the owner's). Close the process handle on every path. Add `clipboard_source.cpp` to `add_executable` and `"version.lib"` to `target_link_libraries` in `windows/runner/CMakeLists.txt`. Set `Runner.rc` `FileDescription` to `Clipps` (so self-copies read "Clipps").

- [ ] **Step 6: Send the source from `flutter_window.cpp`**

On `WM_CLIPBOARDUPDATE`, store `GetClipboardSource()` in a new member `pending_source_` (latest update wins) before `SetTimer`. When the timer decides `kPublic`, call `InvokeMethod("clipboardChanged", std::make_unique<flutter::EncodableValue>(map))` where `map` is a `flutter::EncodableMap` with keys `sourceApp`/`sourceTitle` → `Utf8FromUtf16(...)` strings, or `EncodableValue()` (null) when empty. Include `utils.h`.

- [ ] **Step 7: Extend the integration test**

After the marker appears, also `expect(find.textContaining('\u00B7 Clipps'), findsOneWidget)` — a copy made by the app itself is owned by Clipps.

- [ ] **Step 8: Build and run everything**

Run: `flutter build windows` (expect 0 `warning C` lines; `grep -nP '[^\x00-\x7F]' windows/runner/*.cpp windows/runner/*.h` prints nothing), `flutter test`, `flutter test integration_test -d windows` (no clipps process before or after).
Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add -A && git commit -m "feat: capture source app and window title for each clip"
```

---

### Task 5: Global hotkey, start at login, hidden launch

**Files:**
- Modify: `windows/runner/flutter_window.h`, `windows/runner/flutter_window.cpp`, `windows/runner/main.cpp`, `lib/services/clipboard_watcher.dart`, `lib/main.dart`
- Test: `test/services/clipboard_watcher_test.dart`

**Interfaces:**
- Consumes: Task 2 `requestSearchFocus()`, `markHotkeyUnavailable()`.
- Produces:
  - `ClipboardWatcher({..., VoidCallback? onFocusSearch, VoidCallback? onHotkeyUnavailable})` dispatching `focusSearch` / `hotkeyUnavailable`.
  - C++: `FlutterWindow(const flutter::DartProject& project, bool start_hidden)`.

- [ ] **Step 1: Write the failing watcher tests**

```dart
test('focusSearch calls onFocusSearch', ...);
test('hotkeyUnavailable calls onHotkeyUnavailable', ...);
test('focusSearch without a callback is ignored', ...);
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services`
Expected: FAIL — unknown named parameters.

- [ ] **Step 3: Implement the watcher dispatch and wire it in `main.dart`** (`onFocusSearch: provider.requestSearchFocus`, `onHotkeyUnavailable: provider.markHotkeyUnavailable`)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test`
Expected: all PASS.

- [ ] **Step 5: Implement the native side**

- `flutter_window`: register the hotkey in `OnCreate` (remember success in a member); `UnregisterHotKey(hwnd, 1)` on `WM_DESTROY` alongside the existing listener removal; on `WM_HOTKEY` with id 1: if `IsWindowVisible(hwnd) && GetForegroundWindow() == hwnd` hide, else `ShowAndForeground(hwnd)` then `InvokeMethod("focusSearch", nullptr)`. In the first-frame callback: `if (!start_hidden_) Show();` and, if registration failed, `InvokeMethod("hotkeyUnavailable", nullptr)`.
- `main.cpp`: `bool hidden = wcsstr(command_line, L"--hidden") != nullptr;`. In the single-instance branch, only surface the existing window when `!hidden`. Under `#ifdef NDEBUG`, before creating the window, write the Run value per Global Constraints using `GetModuleFileNameW` and `RegSetKeyValueW` (ignore the result). Pass `hidden` to `FlutterWindow`.

- [ ] **Step 6: Build, then scripted checks against `build\windows\x64\runner\Release\clipps.exe`** (PowerShell P/Invoke; stop any clipps process at the end)

1. Launch with `--hidden` → process runs, `IsWindowVisible` false after 5 s.
2. Registry: `HKCU\...\Run\Clipps` equals `"<exe full path>" --hidden`.
3. Launch a second instance with `--hidden` → it exits within 5 s, one clipps process, window still hidden.
4. Hotkey: `SendInput` Ctrl+Alt+`.` (VK_CONTROL, VK_MENU, VK_OEM_PERIOD) → window visible and foreground; send again → hidden.
5. Launch a second instance without `--hidden` → existing window becomes visible (v1 behaviour).

Expected: all five hold. Record results in the report; physical AltGr press is left for the user.

- [ ] **Step 7: Run all suites**

Run: `flutter test`, `flutter test integration_test -d windows` (quit the running app first — the single-instance mutex would make the test exit), `flutter build windows` with 0 warnings and the ASCII grep empty.
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat: global hotkey, start at login and hidden launch"
```
