# Clipps v4: Notes on Clips and Theme Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add many timestamped notes per clip (with a per-clip scratchpad and a Notes view) and a Light / Dark / System theme setting that is saved.

**Architecture:** DB v4 adds two tables (`notes`, `settings`) and nothing else. The data layer and provider get note and theme methods; the UI adds a notes button on rows, a per-clip dialog, a Notes sidebar view and a theme control. No native code changes.

**Tech Stack:** Flutter 3.47.9 (Windows), Dart 3.13, `sqflite_common_ffi`, `provider`. No new packages.

**Spec:** `docs/superpowers/specs/2026-11-09-clipps-v4-notes-theme-design.md` (approved as written, including permanent note delete per A1)

## Global Constraints

- Flutter is at `C:\Users\MIKE\dev\flutter\bin`; prepend to PATH. Work on branch `feat/clipps-v4` (created from `main` in Task 1). Commit per task. Do not merge to `main`.
- Only commit the task's own files. Leave `windows/flutter/generated_plugin*` alone. Run `dart format` only on files you change.
- `kSchemaVersion` becomes `4`. Migration uses `CREATE … IF NOT EXISTS` only and adds nothing that drops or rewrites rows.
- Permanent deletes: the 15-day Trash purge of clips (which cascades to notes), and deleting a single note after a confirm (approved A1). Nothing else is permanent.
- Copy (exact): `Notes`, `No notes for this clip yet`, `Write a note`, `Add note`, `Created `, ` · edited `, `Delete this note?`, `This can't be undone.`, `Cancel`, `Delete`, `Delete note`, `Notes (N)` (N = count, tooltip on the row button), `No notes yet`, `Notes are limited to 20,000 characters`, `Save`, `System`, `Light`, `Dark`.
- Keys: `notesButton-<id>`, `noteInput`, `addNote`, `editNote-<id>`, `saveNote-<id>`, `deleteNote-<id>`, `view-notes`. Existing keys stay.
- `kMaxNoteLength = 20000` (in `lib/models/note.dart`). Length is counted in UTF-16 code units; blank means empty after trim.
- Theme: `ColorScheme.fromSeed(seedColor: Color(0xFF5B5BD6), brightness: …)`; default `ThemeMode.system`.

## Review Focus

1. **Upgrading the live v3 database (311 clips, tags, groups, pins) to v4** → every row survives, and `backups/clipps-pre-v4.db` is written before the migration runs. Pinned in Task 1 (`upgrade v3 keeps every row and writes the pre-v4 copy`).
2. **Purging a clip, and notes of trashed clips** → purge removes the clip's notes; trashed clips' notes never appear in the Notes view or the notes dialog; restoring the clip brings them back. Pinned in Task 1 (`purge removes notes`, `notesView excludes trashed clips`) and Task 2.
3. **Blank, whitespace, newline, emoji and over-limit notes** → blank is refused, over-limit is refused with the copy, newlines are kept, and an emoji is never split at the limit. Pinned in Task 2 (`addNote refuses blank`, `…over 20,000`, `keeps newlines and emoji`).
4. **Editing a note whose clip was purged meanwhile, or saving the same text twice** → no crash; `edited` only when text actually changed. Pinned in Task 1 (`updateNote on a missing id returns false`, `updateNote with same text keeps updated_at`).
5. **Unknown or missing theme value, and light-theme text contrast** → missing or unknown is `system`; text on surfaces reaches 4.5:1 in both themes. Pinned in Task 2 (`themeFromSetting defaults to system`) and Task 3 (`text contrast is at least 4.5 in both themes`).

---

### Task 1: Notes and settings in the database (DB v4)

**Files:**
- Create: `lib/models/note.dart`
- Modify: `lib/database/db_helper.dart`, `lib/models/clipboard_model.dart`
- Test: `test/database/db_helper_test.dart`, `test/models/clipboard_model_test.dart`, `test/models/note_test.dart`

**Interfaces:**
- Consumes: existing `DbHelper` (`open`, `getClips`, `purgeTrashedBefore`, `_select`), `ClipboardModel`.
- Produces:
  - `const kMaxNoteLength = 20000;`
  - `class Note { const Note({required this.id, required this.clipId, required this.body, required this.createdAt, required this.updatedAt}); final int id; final int clipId; final String body; final DateTime createdAt; final DateTime updatedAt; bool get edited; factory Note.fromMap(Map<String, Object?> map); }` (value equality)
  - `class NoteEntry { const NoteEntry({required this.note, required this.clip}); final Note note; final ClipboardModel clip; }`
  - `ClipboardModel` gains `final int noteCount;` (default 0), read from `note_count` in `fromMap` (absent → 0).
  - `kSchemaVersion = 4`. `DbHelper`: `Future<String?> getSetting(String key)`, `Future<void> setSetting(String key, String value)`, `Future<Note> addNote(int clipId, String body, DateTime now)`, `Future<bool> updateNote(int id, String body, DateTime now)` (true when a row changed; returns true without touching `updated_at` when the text is identical), `Future<int> deleteNote(int id)`, `Future<List<Note>> notesForClip(int clipId)` (newest first: `created_at DESC, id DESC`), `Future<List<NoteEntry>> notesView()` (live clips only, `updated_at DESC, id DESC`).

- [ ] **Step 1: Create branch.** `git switch -c feat/clipps-v4`

- [ ] **Step 2: Write failing model tests** in `test/models/note_test.dart`:
  - `Note.fromMap reads every column` (`created_at`/`updated_at` as ms).
  - `edited is false when updatedAt equals createdAt, true otherwise`.
  - `NoteEntry and Note compare by value`.
  - In `clipboard_model_test.dart`: `fromMap reads note_count and defaults to 0`.

- [ ] **Step 3: Write failing DB tests** in `test/database/db_helper_test.dart` (in-memory unless noted):
  - `addNote and notesForClip newest first`.
  - `updateNote changes body and updated_at`; `updateNote with same text keeps updated_at`; `updateNote on a missing id returns false`.
  - `deleteNote removes one note and returns 1`.
  - `notesView excludes trashed clips and shows the clip fields`.
  - `getClips carries note_count`.
  - `purge removes notes of purged clips` (file-backed or in-memory with `foreign_keys` on; assert `notes` table is empty for that clip).
  - `getSetting is null when absent; setSetting then getSetting round-trips; setSetting overwrites`.
  - `upgrade v3 keeps every row and writes the pre-v4 copy` (file-backed, temp dir): open with `DbHelper`, insert clips, a pinned clip, a tag and a group; then with raw `databaseFactoryFfi` drop `notes` and `settings` and set `PRAGMA user_version = 3`; call `DbHelper.backupBeforeUpgrade`; assert `backups/clipps-pre-v4.db` exists with `user_version` 3 and the same row count; reopen with `DbHelper.open`; assert all clips, pin, tag, group and `user_version == 4`.

- [ ] **Step 4: Run** `flutter test test/models test/database` — expect FAIL (missing members).

- [ ] **Step 5: Implement.**
  - `note.dart` as above; `Note.fromMap` reads `id`, `clip_id`, `body`, `created_at`, `updated_at`.
  - `_onCreate` and `onUpgrade` (`oldVersion < 4`): `CREATE TABLE IF NOT EXISTS notes(…)`, `CREATE INDEX IF NOT EXISTS idx_notes_clip ON notes(clip_id)`, `CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)`. Bump `kSchemaVersion` to 4.
  - Add `note_count` to the `_select` column list: `(SELECT COUNT(*) FROM notes WHERE notes.clip_id = clips.id) AS note_count`.
  - `notesView` joins `notes` to `clips` with `clips.deleted_at IS NULL`, and builds `ClipboardModel` from the clip columns (tags may be empty).
  - `updateNote` reads the current body first; identical text returns true without writing.

- [ ] **Step 6: Run** `flutter test` — expect PASS.

- [ ] **Step 7: Commit** — `git add` the task files only; `git commit -m "feat: notes and settings tables (DB v4) with pre-upgrade copy"`

---

### Task 2: Provider — theme mode, notes state and actions

**Files:**
- Modify: `lib/providers/clipboard_provider.dart`, `lib/models/clip_view.dart`
- Test: `test/providers/clipboard_provider_test.dart`

**Interfaces:**
- Consumes: Task 1 `Note`, `NoteEntry`, `kMaxNoteLength`, `DbHelper` note and setting methods.
- Produces:
  - `enum ClipView { all, tasks, trash, notes }`.
  - `enum NoteResult { saved, blank, tooLong }` (top-level in the provider file).
  - `ThemeMode themeFromSetting(String? value)` (top-level): `light` → light, `dark` → dark, otherwise system.
  - `ThemeMode get themeMode`; `Future<void> setThemeMode(ThemeMode mode)` (saves `light` / `dark` / `system`, notifies). `load()` reads the `theme` setting.
  - `List<NoteEntry> get notes`; `Future<List<Note>> notesFor(int clipId)` (no notify).
  - `Future<NoteResult> addNote(int clipId, String body)`, `Future<NoteResult> editNote(int id, String body)`, `Future<void> deleteNote(int id)`. Each refreshes clips (for `noteCount`) and notes, then notifies.
  - `setView(ClipView.notes)` clears selection and the group; `load()` fills `notes` when the view is notes and leaves `clips` empty.

Validation: trim before checking blank; length check uses the untrimmed body's `length` against `kMaxNoteLength`; text is stored as the user typed it (trimmed only for the blank check).

- [ ] **Step 1: Write failing tests:**
  - `themeFromSetting defaults to system` (`null`, `''`, `'blue'` → system; `light`, `dark`).
  - `setThemeMode saves and notifies; a new provider reads it back on load`.
  - `addNote refuses blank and whitespace-only` (returns `blank`, no row).
  - `addNote refuses over 20,000 characters` (`'a' * 20001` → `tooLong`; `'a' * 20000` → `saved`).
  - `addNote keeps newlines and emoji intact` (body `'line 1\n👍🏽 line 2'` round-trips exactly).
  - `editNote changes text; same text does not change edited`.
  - `deleteNote removes it and notifies`.
  - `notes list excludes notes of trashed clips`; `setView(notes) clears selection and group`.

- [ ] **Step 2: Run** `flutter test test/providers` — expect FAIL.

- [ ] **Step 3: Implement** the members above.

- [ ] **Step 4: Run** `flutter test` and `flutter analyze` — expect PASS. Existing `switch` statements over `ClipView` may need a `notes` case; add it.

- [ ] **Step 5: Commit** — `git commit -m "feat: provider support for notes and theme mode"`

---

### Task 3: Light theme, theme control and contrast

**Files:**
- Modify: `lib/main.dart`, `lib/screens/sidebar.dart`
- Create: `lib/theme/app_theme.dart` (`ThemeData appTheme(Brightness b)` with the seed and component defaults used today)
- Test: `test/theme/app_theme_test.dart`, `test/screens/sidebar_test.dart`

**Interfaces:**
- Consumes: Task 2 `themeMode`, `setThemeMode`.
- Produces: `ThemeData appTheme(Brightness b)`; the sidebar theme control is a `SegmentedButton<ThemeMode>` with three `ButtonSegment`s (icons `Icons.brightness_auto`, `Icons.light_mode`, `Icons.dark_mode`; tooltips `System`, `Light`, `Dark`), placed at the bottom of the sidebar.

- [ ] **Step 1: Write failing tests:**
  - `text contrast is at least 4.5 in both themes` — for `Brightness.light` and `Brightness.dark`: contrast of `onSurface` on `surface`, `onSurfaceVariant` on `surface`, and `onSurface` on `surfaceContainerHighest` are each ≥ 4.5 (WCAG relative luminance formula, written in the test).
  - `ClippsApp uses light theme when Light is chosen` (pump the app with a provider in Light; `MaterialApp.themeMode == ThemeMode.light`).
  - `sidebar theme control changes the mode and saves it` (tap the `Light` tooltip; provider's `themeMode` is light; setting saved).

- [ ] **Step 2: Run** `flutter test test/theme test/screens/sidebar_test.dart` — expect FAIL.

- [ ] **Step 3: Implement.** `main.dart`: `themeMode: context.watch<ClipboardProvider>().themeMode`, `theme: appTheme(Brightness.light)`, `darkTheme: appTheme(Brightness.dark)`. Sidebar: the segmented control at the bottom, bound to `p.themeMode`.

- [ ] **Step 4: Run** `flutter test` — expect PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat: light, dark and system theme with a saved sidebar control"`

---

### Task 4: Notes UI — row button, per-clip scratchpad and Notes view

**Files:**
- Create: `lib/screens/notes_dialog.dart`
- Modify: `lib/screens/clip_row.dart`, `lib/screens/sidebar.dart`, `lib/screens/home_screen.dart`
- Test: `test/screens/notes_dialog_test.dart`, `test/screens/home_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 provider note API, `ClipView.notes`; Task 1 `Note`, `NoteEntry`.
- Produces: `Future<void> showNotesDialog(BuildContext context, ClipboardModel clip)`.

UI rules:
- **Row:** `notesButton-<id>` before the pin button. Tooltip `Notes` when there are no notes, `Notes (N)` otherwise; the icon is `Icons.sticky_note_2` when `noteCount > 0`, otherwise `Icons.sticky_note_2_outlined`. Not shown on Trash rows.
- **Dialog:** title `Notes`; the full clip text in a selectable, scrollable box; then the notes (newest first) with `Created …` and `· edited …` when changed; `noteInput` with hint `Write a note` (multi-line, `minLines: 1`, `maxLines: 6`) and `addNote` (`Add note`, disabled when blank). Edit (`editNote-<id>`) swaps the note text for a field with `saveNote-<id>` (`Save`) and `Cancel`. Delete (`deleteNote-<id>`, tooltip `Delete note`) asks `Delete this note?` / `This can't be undone.` / `Cancel` / `Delete`. A refused save shows the length copy in a SnackBar.
- **Notes view:** sidebar item `view-notes` (label `Notes`, icon `Icons.sticky_note_2_outlined`) between Tasks and Trash. Home body shows note cards: text (up to 3 lines), then the clip preview (2 lines), source label and time. Tap opens `showNotesDialog`. Empty state `No notes yet`. The manual input, search, tag row and selection controls are hidden in this view; app bar title `Notes`.

- [ ] **Step 1: Write failing widget tests:**
  - Row: `notes button shows count and opens the dialog`.
  - Dialog: `add, edit and delete a note; delete asks first` (confirm dialog text, then gone from the list and the DB).
  - Dialog: `blank note cannot be added; over-limit shows the copy`.
  - Dialog: `dialog shows the full clip text`.
  - Notes view: `Notes view lists notes with their clip; empty state; tapping opens the dialog`.
  - `notes button is absent on Trash rows`.

- [ ] **Step 2: Run** `flutter test test/screens` — expect FAIL.

- [ ] **Step 3: Implement** the dialog file, the row button, the sidebar item and the Notes view.

- [ ] **Step 4: Run** `flutter test` and `flutter analyze` — expect PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat: per-clip notes dialog and Notes view"`

---

### Task 5: Release check — build, installer 3.2.0, in-place upgrade

**Files:**
- Modify: `installer/clipps.iss` (`AppVersion` → `3.2.0`; the comment already names the build step)

- [ ] **Step 1: Full checks.** `flutter analyze` (no issues), `flutter test` (all pass).

- [ ] **Step 2: Snapshot the live data** with the SQLite backup API while Clipps keeps running, into `C:\Users\MIKE\Documents\Clipps-backup-<date>\pre-upgrade-3.1.0-snapshot.db`. Record integrity, `user_version`, clip count, pinned and trashed counts.

- [ ] **Step 3: Build.** `flutter build windows --no-tree-shake-icons`; `git checkout -- windows/flutter/`. Check the icon font contains every icon used (the same check as 3.1.0).

- [ ] **Step 4: Compile** the installer with ISCC.

- [ ] **Step 5: Upgrade in place** over the running 3.1.0 (silent Setup). Expect exit 0, the old process stopped, the new exe installed, the startup entry and shortcut kept.

- [ ] **Step 6: Verify data.** Start with `--hidden`. Expect `user_version = 4`; clip, tag, group and pinned counts ≥ the snapshot; `backups\clipps-pre-v4.db` exists with `user_version = 3` and the snapshot's counts.

- [ ] **Step 7: Visual check.** Screenshot the window in System (dark here). Click the Light segment (a display setting only) and screenshot; click System to restore. Do not create notes in the real history. Notes behaviour is covered by the widget tests.

- [ ] **Step 8: Commit** the installer version — `git commit -m "build: installer version 3.2.0"`.

Do not merge to `main`; report the branch and wait for approval.
