# Clipps v4: Notes on Clips and a Theme Setting (Spec)

> Builds on the v1–v3 specs in this folder (implemented on `main`, installed as 3.1.0).

## Goal

1. Let the user write notes about a clip, kept with that clip.
2. Make the light theme usable: a setting that chooses Light, Dark or System,
   so light mode doesn't depend on the Windows setting.

## Decisions (from the user, 2026-11-09)

- **Theme:** Light / Dark / System, chosen in the sidebar and saved.
- **Notes:** many notes per clip, each with its own timestamps. A Notes view
  lists all notes.

## Assumptions (made by the planner; confirm or change)

- **A1 Deleting one note is permanent (needs approval).** The v3 spec allowed
  only one permanent delete, the 15-day Trash purge. Deleting a single note
  here is a second permanent delete. Chosen: a note delete asks first ("This
  can't be undone.") and is then final. Alternative: notes also go to Trash
  and follow the 15-day rule. Say which you want.
- **A2 Notes follow their clip.** Notes of a trashed clip are hidden with it
  and come back when the clip is restored. When the 15-day purge removes a
  clip, its notes are removed too (cascade).
- **A3 Notes are plain text.** No formatting, no attachments. Newlines are kept.
  Limit: 20,000 characters per note.
- **A4 Theme choice is per PC.** It is stored in the database, not synced.

## 1. Data model (DB v3 → v4, adds only)

- `notes(id INTEGER PRIMARY KEY AUTOINCREMENT, clip_id INTEGER NOT NULL REFERENCES
  clips(id) ON DELETE CASCADE, body TEXT NOT NULL, created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL)` plus `idx_notes_clip ON notes(clip_id)`.
- `settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)`. Theme key: `theme`,
  values `system` (default when absent), `light`, `dark`.
- `kSchemaVersion` becomes 4. Migration uses `CREATE … IF NOT EXISTS` only,
  so it is safe to repeat. `onCreate` builds the same tables.
- Because the schema version changes, the pre-upgrade copy runs and writes
  `backups/clipps-pre-v4.db` before the migration.

## 2. Notes behaviour

- **Row:** a notes button before the pin, `notesButton-<id>`, tooltip `Notes`.
  When the clip has notes, the icon is filled and shows the count
  (`Notes (N)` in the tooltip). Hidden on Trash rows.
- **Per-clip scratchpad (dialog):** title `Notes`. Shows the full clip text
  (selectable, scrolls) above the notes. Then the notes, newest first. Each note
  shows its text and `Created YYYY-MM-DD HH:mm`, with `· edited HH:mm` when
  changed. Empty state: `No notes for this clip yet`.
  - Add: field `noteInput` (hint `Write a note`, multi-line), button `addNote`
    (label `Add note`, disabled when the text is blank).
  - Edit: `editNote-<id>` turns the note into a field with `saveNote-<id>` and
    `Cancel`.
  - Delete: `deleteNote-<id>` (tooltip `Delete note`) asks
    `Delete this note?` / `This can't be undone.` / `Cancel` / `Delete`.
- **Notes view:** sidebar item `Notes` (key `view-notes`) between Tasks and
  Trash. Lists notes of live clips, newest update first. Each card: note text,
  then the clip preview (2 lines) with its source label and time. Tapping a card
  opens that clip's scratchpad. Empty state: `No notes yet`.
- Notes are not searched by the search box in this version.

## 3. Theme

- **Sidebar control:** a `SegmentedButton` with three icon segments (system,
  light, dark), tooltips `System`, `Light`, `Dark`, at the bottom of the sidebar.
- **Behaviour:** the choice applies at once and is saved. Default `System`.
- **Light theme:** `ColorScheme.fromSeed(seedColor: Color(0xFF5B5BD6),
  brightness: Brightness.light)`, with the same component themes as dark. Text,
  icons, tag chips and the masked secret text must reach at least 4.5:1 contrast
  on the light surface.
- The app still wraps `MaterialApp` with `themeMode` from the provider.

## 4. Errors and edge cases

| Case | Behaviour |
|---|---|
| Blank or over-limit note | Add/save disabled; over-limit text is refused with `Notes are limited to 20,000 characters` |
| Clip purged while dialog open | Dialog closes; notes were removed by the cascade |
| Settings row missing or unknown value | Treated as `system` |
| Migration fails | Startup error screen as today; the pre-v4 copy is kept |

## Testing

- **Database (file-backed, temp dir):** a v3 file upgrades to v4 with every row
  intact, the new tables present, and `clipps-pre-v4.db` written. Notes CRUD;
  note counts per clip; purge removes a clip's notes; notes of a trashed clip
  are excluded from the Notes view; theme setting round-trips and defaults to
  `system`.
- **Provider:** `setThemeMode` saves and notifies; add/edit/delete note reloads;
  `noteCount` on rows.
- **Widgets:** notes icon shows the count; dialog adds, edits and deletes a note
  (delete asks first); Notes view lists and empties; segmented control switches
  `ThemeMode`; the light theme is applied when `Light` is chosen.
- **Manual (Release build, installed over 3.1.0):** light and dark screenshots,
  contrast check, and an upgrade test that confirms the copy and data.

## Out of scope

Searching notes, formatting, attachments, syncing the theme, notes on several
clips, and exporting notes.
