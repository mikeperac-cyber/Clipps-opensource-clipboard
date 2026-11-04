# Clipps v3: Trash, Tags, Tasks, Groups, Backups, UI Polish (Spec)

> Builds on the v1 and v2 specs in this folder (implemented on `main`).

## Source request (verbatim)

"polish the UI for a better taste. make sure the data is persistent and always
available. (clipboard history can only be deleted on 15 days- add this rule)
build automatic labeling and tagging build a button to turn any line into a
task or enable grouping"

## Decisions (from the user, 2026-11-04)

- **15-day rule = 15-day Trash.** Deleting a clip moves it to Trash. It can be
  restored there for 15 days, then it is removed for good. Nothing is ever
  removed permanently sooner, and there is no "Empty Trash".
- **Per-line button = both.** Each clip can be made a task and can be put in a
  group.
- **Tags = local rules + manual tags.** Automatic tags are detected on this PC
  from the clip text. The user can add and remove their own tags.

## Assumptions (made by the planner; the user may change them)

- **A1 "Persistent and always available"** means: history is never lost.
  Clipps keeps a daily backup copy of the database (newest 7 kept) and turns on
  SQLite write-ahead logging for crash safety. Trade-off: purged and private
  text can survive in backups for up to 7 days.
- **A2 Secrets are hidden, not blocked.** A clip tagged `Secret` shows a masked
  preview until the user reveals it. Copy-back still copies the full text.
- **A3 One group per clip.** Groups are user-named collections. A clip belongs
  to at most one group. Deleting a group keeps its clips (they become ungrouped).
- **A4 UI direction.** Material 3 with a left sidebar for views, quieter rows,
  relative times, tag chips, and a dark theme that follows Windows.

## 1. Trash and the 15-day rule

- `clips.deleted_at INTEGER NULL` (ms since epoch). `NULL` = live.
- Delete (row button or Delete selected) sets `deleted_at = now` for unpinned
  clips. Pinned clips still cannot be deleted.
- Confirm dialog: title `Move N clip(s) to Trash?`, body
  `You can restore them for 15 days.`, buttons `Cancel` / `Move to Trash`.
- **Trash view** lists trashed clips, newest deletion first. Each row shows
  `Deleted 2026-11-04 · removed in N days` (N = whole days left, minimum 1)
  and a `Restore` button. Restore clears `deleted_at`.
- **Purge:** rows with `deleted_at` older than 15 days are deleted (the only
  hard delete in the app). It runs at startup and every hour while running.
  `secure_delete` stays on.
- Trashed clips are excluded from All, Tasks, groups, search and tag filters,
  and from the "same as newest clip" dedupe check.

## 2. Automatic and manual tags

- Table `clip_tags(clip_id INTEGER NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
  tag TEXT NOT NULL COLLATE NOCASE, auto INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (clip_id, tag))`, plus an index on `tag`.
- **Automatic tags**, detected when a clip is saved (and once for existing
  clips during the upgrade), fixed display order:
  - `Link`: contains `http://` or `https://` followed by a non-space.
  - `Email`: contains an address like `name@example.com`.
  - `Phone`: the whole trimmed text is a phone number: optional `+`, digits,
    spaces, `( ) . -`, with 7 to 15 digits.
  - `Number`: the whole trimmed text is digits with optional sign, `.`, `,` or
    spaces, and it is not a `Phone`.
  - `Code`: at least 2 lines, and either 2 or more lines end in `;`, `{`, `}` or
    `)`, or some line starts with `def `, `function `, `class `, `import `,
    `#include`, `const `, `let `, `var `, `public ` or `private `.
  - `Secret`: a known key prefix (`sk-`, `sk_live_`, `ghp_`, `gho_`,
    `github_pat_`, `xoxb-`, `xoxp-`, `AKIA` + 16 caps/digits, `AIza` + 35
    chars, or a JWT `eyJ….eyJ….`), or a single token of 32 or more characters
    from `A-Z a-z 0-9 _ - + / =` with at least one upper, one lower and one
    digit, and no `Link` tag.
- **Manual tags:** add and remove on any clip (auto or manual tags can be
  removed). Names are trimmed, 1 to 30 characters, case-insensitive unique per
  clip, shown as typed.
- **Filter:** a chip row lists every tag used by live clips; choosing one
  filters the current view to clips with that tag. One tag filter at a time.
- **Masking:** a clip with a `Secret` tag shows its first 4 characters then
  `••••••••` until the user clicks its eye button (per row, this session only).

## 3. Tasks

- `clips.task_state INTEGER NULL`: `NULL` not a task, `0` open, `1` done.
- Row button `Make task` (tooltip) turns a clip into an open task; on a task the
  same button reads `Remove task`.
- **Tasks view** lists live task clips: open first, then done; each group newest
  first. A checkbox toggles done; done tasks show struck-through text.

## 4. Groups

- Table `groups(id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE COLLATE NOCASE)`;
  `clips.group_id INTEGER NULL REFERENCES groups(id) ON DELETE SET NULL`.
- Row button `Add to group` opens a menu: existing groups, `New group…`, and
  `Remove from group` when grouped.
- The sidebar lists groups under the views, with `New group` (name 1 to 40
  characters, unique ignoring case). A group's menu offers `Rename` and
  `Delete group` (clips are kept).
- Selecting a group shows its live clips.

## 5. Persistence and backups

- `PRAGMA journal_mode = WAL` and `PRAGMA foreign_keys = ON` on open.
- **Daily backup:** at startup and every 6 hours, if no backup exists for today,
  write `backups/clipps-YYYY-MM-DD.db` next to `clipps.db` with
  `VACUUM INTO`. Keep the newest 7 backup files; delete older ones. Failures are
  reported to the debug log and never block the app.
- DB version 2 → 3 adds columns and tables only; existing clips get automatic
  tags during the upgrade. Nothing is dropped.

## 6. UI polish

- **Theme:** Material 3, `ColorScheme.fromSeed(seedColor: Color(0xFF5B5BD6))`,
  light and dark, `ThemeMode.system`.
- **Layout:** left sidebar (220 px) with views `All clips`, `Tasks`, `Trash`,
  then a `Groups` header, the groups, and `New group`. Main area: manual save
  row, search row (search icon, date button), tag chip row, then the list.
  List content width is capped at 1100 px and centred.
- **Rows:** preview at most 2 lines (`Code` clips in `Consolas`); meta line with
  relative time (`just now`, `N min ago`, `N h ago`, `yesterday HH:mm`, else
  `YYYY-MM-DD HH:mm`; full timestamp in a tooltip), source label, and tag chips.
  Actions are compact, muted icons: pin, task, group, tags, delete.
- **Selection:** when clips are selected the app bar shows `N selected`, a
  `Move to Trash` action and a clear button.
- **Empty states:** icon plus text: `No clips yet`, `No clips match`,
  `No tasks yet`, `Trash is empty`, `No clips in this group`.
- Existing behaviour stays: tap to copy (`Copied`), manual save
  (`Nothing new to save`), pins, hotkey focus and warning line, source labels.

## Out of scope

AI tagging, multiple groups per clip, sync between PCs, restoring from a
backup inside the app (backups are restored by copying the file back),
editing clip text.
