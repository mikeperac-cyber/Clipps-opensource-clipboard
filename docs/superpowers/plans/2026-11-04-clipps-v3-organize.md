# Clipps v3 Organize Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 15-day Trash, automatic and manual tags, tasks, groups, daily backups and a polished Material 3 UI to Clipps.

**Architecture:** A pure-Dart auto-tagger first, then the data layer (DB v3 schema, queries, mutations), then provider state, a backup service, and finally the UI in two passes: the polished shell with views and Trash, then the organize actions (tasks, groups, tags). The native runner is not touched.

**Tech Stack:** Flutter 3.47.9 (Windows), Dart 3.13, `sqflite_common_ffi`, `provider`. No new packages.

**Spec:** `docs/superpowers/specs/2026-11-04-clipps-v3-organize-design.md` (builds on the v1 and v2 specs in the same folder)

## Global Constraints

- Flutter is at `C:\Users\MIKE\dev\flutter\bin`; prepend it to PATH. Work on branch `feat/clipps-v3`; one commit per task; commit only your task's files (leave `windows/flutter/generated_plugin*` alone); run `dart format` only on files you change.
- DB version 2 → 3 only adds columns, tables and rows (auto tags). Nothing is dropped or rewritten.
- The only permanent delete is the Trash purge of rows trashed more than 15 days ago: `const kTrashRetention = Duration(days: 15);` (defined once, in `lib/providers/clipboard_provider.dart`). No "Empty Trash".
- Pinned clips can never be trashed.
- Existing widget keys stay: `deleteSelected`, `search`, `dateRange`, `clearDateRange`, `manualInput`, `saveClip`, `hotkeyWarning`, `clip-<id>`, `select-<id>`, `pin-<id>`, `delete-<id>`.
- Exact copy: `Move N clip(s) to Trash?`, `You can restore them for 15 days.`, `Cancel`, `Move to Trash`, `Restore`, `Deleted YYYY-MM-DD · removed in N days`, `All clips`, `Tasks`, `Trash`, `Groups`, `New group`, `New group…`, `Remove from group`, `Rename`, `Delete group`, `Make task`, `Remove task`, `Add to group`, `Edit tags`, `N selected`, `No clips yet`, `No clips match`, `No tasks yet`, `Trash is empty`, `No clips in this group`; mask `••••••••` (8 × U+2022).
- Auto tag names and order: `Link`, `Email`, `Phone`, `Number`, `Code`, `Secret`.
- Theme seed `Color(0xFF5B5BD6)`, `ThemeMode.system`; sidebar 220 px; list width cap 1100 px.

## Review Focus

1. **Upgrading the user's real v2 database (hundreds of clips, pins, sources)** → every row survives, pins and sources unchanged, auto tags backfilled, nothing trashed. Pinned in Task 2 (`upgrade from v2 keeps rows and backfills tags`).
2. **The 15-day boundary** → a clip trashed 14 days 23 hours ago is still restorable; one trashed 15 days and 1 ms ago is gone after purge. Pinned in Task 3 (`purgeTrashedBefore` boundary test) and Task 4 (`purgeExpiredTrash uses 15 days`).
3. **Copying text that is sitting in Trash** → it is saved again as a new live clip (dedupe ignores trashed clips). Pinned in Task 2 (`latestClip ignores trashed clips`).
4. **Secret detection on real-world text** → a long URL, a 40-char git SHA and a sentence are not `Secret`; `sk-…`, `ghp_…`, `AKIA…` and JWTs are; the list never shows a secret's full text unless revealed. Pinned in Task 1 (detector table test) and Task 6 (`secret clip is masked until revealed`).
5. **Group name collisions and deleting a group** → `work` is rejected when `Work` exists; deleting a group keeps its clips (ungrouped). Pinned in Task 3 (`group names are unique ignoring case`, `deleteGroup keeps clips`) and Task 4 (`createGroup rejects duplicates`).

---

### Task 1: Auto-tagger

**Files:**
- Create: `lib/services/auto_tagger.dart`
- Test: `test/services/auto_tagger_test.dart`

**Interfaces:**
- Produces: `const kAutoTags = ['Link', 'Email', 'Phone', 'Number', 'Code', 'Secret'];` and `List<String> detectTags(String text)` returning matches in `kAutoTags` order. Rules exactly as spec §2.

- [ ] **Step 1: Create branch** — `git switch -c feat/clipps-v3`

- [ ] **Step 2: Write the failing table test**

```dart
final cases = <String, List<String>>{
  'see https://example.com/a?b=1': ['Link'],
  'mail me at jane.doe@example.co.uk': ['Email'],
  '+1 (555) 010-2345': ['Phone'],
  '1,234.56': ['Number'],
  '-42': ['Number'],
  'const a = 1;\nconst b = 2;': ['Code'],
  'def run():\n    pass': ['Code'],
  'sk-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789': ['Secret'],   // fake; never use real keys in tests
  'ghp_16C7e42F292c6912E7710c838347Ae178B4a': ['Secret'],
  'AKIAIOSFODNN7EXAMPLE': ['Secret'],
  'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig': ['Secret'],
  'aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY': ['Secret'],         // 32-char mixed token
  'https://chromewebstore.google.com/detail/ldnheaepmnmbjjjahokphckbpgciiaed?utm_source=item-share-cb': ['Link'],
  'e83c5163316f89bfbde7d9ab23ca2e25604af290': [],          // git SHA: no upper case
  'If I were paying for a lot of AI software, I would not try.': [],
  '': [],
};
cases.forEach((input, want) => test('detectTags(${jsonEncode(input)})', () => expect(detectTags(input), want)));
```

- [ ] **Step 3: Run** `flutter test test/services/auto_tagger_test.dart` — expect FAIL (undefined).

- [ ] **Step 4: Implement `detectTags` in `lib/services/auto_tagger.dart`** — one `RegExp` per rule, compiled once as top-level finals.

- [ ] **Step 5: Run** the test file, then `flutter analyze` — expect PASS / no issues.

- [ ] **Step 6: Commit** — `git commit -m "feat: local auto-tagger for links, emails, phones, numbers, code and secrets"`

---

### Task 2: DB v3 schema, model, queries

**Files:**
- Create: `lib/models/clip_view.dart`, `lib/models/clip_group.dart`
- Modify: `lib/models/clipboard_model.dart`, `lib/database/db_helper.dart`
- Test: `test/models/clipboard_model_test.dart`, `test/database/db_helper_test.dart`

**Interfaces:**
- Consumes: Task 1 `detectTags`, `kAutoTags`.
- Produces:
  - `enum ClipView { all, tasks, trash }`; `class ClipGroup { const ClipGroup({required this.id, required this.name}); final int id; final String name; }` (value equality).
  - `enum TaskState { none, open, done }` (in `clipboard_model.dart`).
  - `ClipboardModel` gains `DateTime? deletedAt`, `TaskState taskState` (default `none`), `int? groupId`, `List<String> tags` (default `const []`; auto tags in `kAutoTags` order, then manual tags A–Z), `bool get isSecret` (has tag `Secret`, ignoring case).
  - `DbHelper.open` → version 3; `onConfigure` also runs `PRAGMA foreign_keys = ON` and `PRAGMA journal_mode = WAL` (use `rawQuery` for `journal_mode`, it returns a row). `onCreate` builds the v3 schema; `onUpgrade` for `oldVersion < 3` adds `deleted_at`, `task_state`, `group_id` and creates `groups` and `clip_tags` exactly as spec §1–4, then inserts auto tags (`auto = 1`) for every existing clip.
  - `insertClip(...)` also inserts the clip's auto tags.
  - `getClips({String text = '', DateTime? from, DateTime? before, ClipView view = ClipView.all, int? groupId, String? tag})`: `all` → live rows, order `pinned DESC, created_at DESC, id DESC`; `tasks` → live rows with `task_state IS NOT NULL`, order `task_state ASC, created_at DESC, id DESC`; `trash` → `deleted_at IS NOT NULL`, order `deleted_at DESC, id DESC`. `groupId`/`tag` add `AND` filters. Tags come back via one `group_concat` subquery (separator `\u001F`).
  - `latestClip()` considers live rows only.

- [ ] **Step 1: Write the failing tests**

```dart
test('fromMap reads deletedAt, taskState, groupId and tags', ...);       // tags string 'Link\u001FWork' → ['Link','Work']
test('tags order: auto in kAutoTags order, then manual A-Z', ...);
test('isSecret ignores case', ...);
test('insertClip stores auto tags', ...);                               // 'https://x.io' → tags ['Link']
test('latestClip ignores trashed clips', ...);                         // trash newest via raw update; latestClip is the older live one
test('getClips views: all excludes trash, tasks orders open first, trash orders by deleted_at', ...);
test('getClips filters by groupId and tag', ...);
test('upgrade from v2 keeps rows and backfills tags', () async {
  // temp file; build the exact v2 schema (v1 table + source_app, source_title, pinned) with databaseFactoryFfi at version 2,
  // insert 3 rows (one pinned, one with source, one 'https://a.b'); close; DbHelper.open:
  // 3 rows, pin/source unchanged, deletedAt null, taskState none, the URL row tagged ['Link'].
});
```

- [ ] **Step 2: Run** `flutter test test/models test/database` — expect FAIL.

- [ ] **Step 3: Implement** the interfaces above. Keep `deleteClips` for now (Task 4 switches callers to Trash).

- [ ] **Step 4: Run** `flutter test` — expect all PASS (existing suites included).

- [ ] **Step 5: Commit** — `git commit -m "feat: DB v3 with trash, tasks, groups and tags"`

---

### Task 3: DB mutations

**Files:**
- Modify: `lib/database/db_helper.dart`
- Test: `test/database/db_helper_test.dart`

**Interfaces:**
- Consumes: Task 2 schema and types.
- Produces (all on `DbHelper`):
  - `Future<int> trashClips(Iterable<int> ids, DateTime now)` (only unpinned live rows), `Future<int> restoreClips(Iterable<int> ids)`, `Future<int> purgeTrashedBefore(DateTime cutoff)` (deletes rows with `deleted_at < cutoff`).
  - `Future<void> setTaskState(int id, TaskState state)`.
  - `Future<List<ClipGroup>> listGroups()` (A–Z, ignoring case), `Future<ClipGroup> createGroup(String name)` (throws `DatabaseException` on a duplicate), `Future<void> renameGroup(int id, String name)`, `Future<void> deleteGroup(int id)`, `Future<void> setClipGroup(int clipId, int? groupId)`.
  - `Future<void> addTag(int clipId, String tag)` (manual, `INSERT OR IGNORE`), `Future<void> removeTag(int clipId, String tag)`, `Future<List<String>> tagsInUse()` (live clips only; `kAutoTags` order, then A–Z).
  - `Future<void> backupTo(String path)` (`VACUUM INTO ?`).

- [ ] **Step 1: Write the failing tests**

```dart
test('trashClips skips pinned and returns count', ...);
test('restoreClips brings clips back to all', ...);
test('purgeTrashedBefore boundary', () async {
  // trash A at t0 - (15d - 1h), B at t0 - (15d + 1ms); purgeTrashedBefore(t0 - 15d) → returns 1; A remains in trash, B gone
});
test('purge cascades clip_tags', ...);                     // trashed+purged tagged clip leaves no clip_tags rows
test('setTaskState round-trips', ...);
test('group names are unique ignoring case', ...);         // createGroup('Work') then createGroup('work') throws
test('deleteGroup keeps clips', ...);                      // clip in group → deleteGroup → clip still live, groupId null
test('addTag/removeTag and tagsInUse ignores trashed clips', ...);
test('backupTo writes a readable copy', ...);              // temp path; open the copy; same clip count
```

- [ ] **Step 2: Run** `flutter test test/database` — expect FAIL.

- [ ] **Step 3: Implement** the methods above.

- [ ] **Step 4: Run** `flutter test` — expect all PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat: DB methods for trash, purge, tasks, groups, tags and backup"`

---

### Task 4: Provider state

**Files:**
- Modify: `lib/providers/clipboard_provider.dart`, `lib/database/db_helper.dart` (remove `deleteClips`), `lib/screens/home_screen.dart` (rename two calls only)
- Test: `test/providers/clipboard_provider_test.dart`, `test/database/db_helper_test.dart` (drop `deleteClips` tests)

**Interfaces:**
- Consumes: Task 2–3 `DbHelper` API.
- Produces (on `ClipboardProvider`):
  - `const kTrashRetention = Duration(days: 15);`
  - Getters `ClipView view`, `int? groupId`, `String? tagFilter`, `List<ClipGroup> groups`, `List<String> tagsInUse`.
  - `Future<void> setView(ClipView v)` (clears `groupId` and selection), `Future<void> selectGroup(int id)` (view `all` + group), `Future<void> setTagFilter(String? tag)`.
  - `Future<void> trashSelected()`, `Future<void> trashClip(int id)`, `Future<void> restoreClip(int id)` — replace `deleteSelected`/`deleteClip`; update the two call sites in `home_screen.dart`.
  - `Future<int> purgeExpiredTrash()` (cutoff `clock() - kTrashRetention`); `load()` runs it first, then reloads clips, groups and tags; `void startRetentionTimer()` (hourly purge; cancelled in `dispose`).
  - `Future<void> makeTask(int id)`, `Future<void> setTaskDone(int id, bool done)`, `Future<void> removeTask(int id)`.
  - `Future<bool> createGroup(String name)` (trimmed 1–40 chars; `false` when invalid or duplicate), `Future<bool> renameGroup(int id, String name)`, `Future<void> deleteGroup(int id)` (clears `groupId` if it was selected), `Future<void> setClipGroup(int clipId, int? groupId)`.
  - `Future<bool> addTag(int clipId, String tag)` (trimmed 1–30 chars), `Future<void> removeTag(int clipId, String tag)`.

- [ ] **Step 1: Write the failing tests**

```dart
test('trashClip hides from all and shows in trash', ...);
test('purgeExpiredTrash uses 15 days', ...);   // clock-controlled: trashed 14d23h ago kept, 15d+1ms ago purged
test('load purges expired trash', ...);
test('dedupe re-adds text that is in trash', ...);
test('setView tasks lists open tasks first', ...);
test('selectGroup filters and deleteGroup clears the selection', ...);
test('createGroup rejects duplicates and empty names', ...);  // 'Work' ok; ' work ' false; '' false; 41 chars false
test('addTag validates length and updates tagsInUse', ...);
test('setTagFilter narrows clips', ...);
```

- [ ] **Step 2: Run** `flutter test test/providers` — expect FAIL.

- [ ] **Step 3: Implement** the interfaces; remove `DbHelper.deleteClips` and its tests.

- [ ] **Step 4: Run** `flutter test` and `flutter analyze` — expect PASS / no issues (existing screen tests may need the renamed calls only).

- [ ] **Step 5: Commit** — `git commit -m "feat: provider support for trash retention, views, tasks, groups and tags"`

---

### Task 5: Daily backups

**Files:**
- Create: `lib/services/backup_service.dart`
- Modify: `lib/main.dart`
- Test: `test/services/backup_service_test.dart`

**Interfaces:**
- Consumes: Task 3 `DbHelper.backupTo`; Task 4 `startRetentionTimer`.
- Produces: `class BackupService { BackupService(DbHelper db, String dir, {DateTime Function() clock = DateTime.now}); Future<String?> backupIfDue(); void start(); void stop(); }` — file name `clipps-YYYY-MM-DD.db`; returns the new path or `null` if today's exists; keeps the newest 7 `clipps-*.db` files; errors go to `debugPrint` and return `null`. `start()` runs `backupIfDue` now and every 6 hours.
- `main.dart` `buildApp`: after `load()`, call `provider.startRetentionTimer()` and `BackupService(db, p.join(p.dirname(dbPath), 'backups')).start()`.

- [ ] **Step 1: Write the failing tests** (temp dir, file-backed DB)

```dart
test('creates today\'s backup once', ...);        // second call same day returns null, one file
test('keeps the newest 7 backups', ...);          // pre-create 8 dated files; after backupIfDue: 7 files incl. today, oldest gone
test('ignores unrelated files in the folder', ...);
```

- [ ] **Step 2: Run** `flutter test test/services/backup_service_test.dart` — expect FAIL.

- [ ] **Step 3: Implement** `BackupService` and the `main.dart` wiring.

- [ ] **Step 4: Run** `flutter test` — expect all PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat: daily database backups, newest 7 kept"`

---

### Task 6: Polished shell, views and Trash UI

**Files:**
- Create: `lib/screens/format.dart`, `lib/screens/clip_row.dart`, `lib/screens/sidebar.dart`
- Modify: `lib/screens/home_screen.dart`, `lib/main.dart` (`ClippsApp` theme only)
- Test: `test/screens/format_test.dart`, `test/screens/home_screen_test.dart`

**Interfaces:**
- Consumes: Task 4 provider API; Task 2 `ClipboardModel` fields.
- Produces:
  - `format.dart`: `String relativeTime(DateTime t, DateTime now)` (spec §6; future times → `just now`), `String maskSecret(String text)` (first 4 chars + `••••••••`; ≤ 4 chars → `••••••••`), `int trashDaysLeft(DateTime deletedAt, DateTime now)` (whole days until `deletedAt + kTrashRetention`, rounded up, minimum 1).
  - `ClipRow` widget for one clip; `Sidebar` widget with view items keyed `view-all`, `view-tasks`, `view-trash`.
  - New keys: `reveal-<id>` (eye toggle on secret rows), `restore-<id>`, `taskDone-<id>` (Tasks view leading checkbox, wired to `setTaskDone`), `clearSelection`.

UI rules: spec §6 layout, theme, rows, selection bar and empty states; spec §1 Trash dialog copy and Trash row meta + `Restore`; Trash rows have no checkbox, pin, task, group, tags or delete. Tasks view leading widget is the done checkbox; done text is struck through. Code-tagged previews use `fontFamily: 'Consolas'`. Secret rows show `maskSecret(preview)` until revealed (reveal state lives in the row's `State`, per session).

- [ ] **Step 1: Write the failing tests**

```dart
// format_test.dart (now = 2026-11-04 12:00 local)
expect(relativeTime(now.subtract(const Duration(seconds: 20)), now), 'just now');
expect(relativeTime(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
expect(relativeTime(DateTime(2026, 11, 4, 9, 0), now), '3 h ago');
expect(relativeTime(DateTime(2026, 11, 3, 14, 2), now), 'yesterday 14:02');
expect(relativeTime(DateTime(2026, 10, 30, 8, 5), now), '2026-10-30 08:05');
expect(maskSecret('sk-AbCdEfGhIj'), 'sk-A••••••••');
expect(trashDaysLeft(now.subtract(const Duration(days: 14, hours: 23)), now), 1);
expect(trashDaysLeft(now, now), 15);
```
Widget tests:
```dart
testWidgets('delete asks to move to Trash, then clip appears in Trash with days left', ...);
testWidgets('restore returns the clip to All clips', ...);
testWidgets('secret clip is masked until revealed', ...);   // no Text contains the full key before tapping reveal-<id>
testWidgets('selection shows "N selected" and clearSelection clears it', ...);
testWidgets('empty states per view', ...);                  // 'No clips yet', 'No tasks yet', 'Trash is empty'
testWidgets('tasks view checkbox marks done and strikes through', ...);
```
Update existing screen tests to the new delete flow (Trash instead of hard delete); keep their keys.

- [ ] **Step 2: Run** `flutter test test/screens` — expect FAIL.

- [ ] **Step 3: Implement** the files above. Keep `home_screen.dart` as the shell; rows in `clip_row.dart`; sidebar in `sidebar.dart`.

- [ ] **Step 4: Run** `flutter test`, `flutter analyze` — expect PASS / no issues.

- [ ] **Step 5: Check it builds** — `flutter build windows` succeeds (0 `warning C`).

- [ ] **Step 6: Commit** — `git commit -m "feat: polished Material 3 shell with views, Trash and secret masking"`

---

### Task 7: Organize actions — tasks, groups, tags UI

**Files:**
- Modify: `lib/screens/clip_row.dart`, `lib/screens/sidebar.dart`, `lib/screens/home_screen.dart`
- Test: `test/screens/home_screen_test.dart`

**Interfaces:**
- Consumes: Task 4 provider API; Task 6 widgets.
- Produces keys: `task-<id>` (tooltip `Make task` / `Remove task`), `group-<id>` (popup: `groupOption-<groupId>`, `newGroupOption` → dialog with `groupNameInput`, `Remove from group` as `removeFromGroup`), `tags-<id>` (tooltip `Edit tags`; dialog with chips `removeTag-<tag>`, field `tagInput`, button `addTag`), sidebar `group-item-<id>`, `newGroup` (dialog `groupNameInput`), `groupMenu-<id>` (popup `Rename`, `Delete group`), tag filter chips `tagFilter-<tag>`.

UI rules: spec §2 chip row (one tag at a time; tapping the selected chip clears it), §3 task button, §4 group menu and sidebar groups. Invalid or duplicate names leave the dialog open with error text `Name already used or invalid`.

- [ ] **Step 1: Write the failing widget tests**

```dart
testWidgets('make task then it shows in Tasks view', ...);
testWidgets('add clip to a new group from the row menu, then sidebar group shows it', ...);
testWidgets('duplicate group name shows "Name already used or invalid"', ...);
testWidgets('delete group from sidebar keeps the clip in All clips', ...);
testWidgets('edit tags: add "Work", filter by chip, remove tag', ...);
testWidgets('auto tags appear as chips on the row and in the filter bar', ...);
```

- [ ] **Step 2: Run** `flutter test test/screens` — expect FAIL.

- [ ] **Step 3: Implement** the actions and dialogs.

- [ ] **Step 4: Run** `flutter test`, `flutter analyze`, then `flutter build windows` and `flutter test integration_test -d windows` (no clipps process before or after) — expect all PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat: task, group and tag actions with tag filter chips"`
