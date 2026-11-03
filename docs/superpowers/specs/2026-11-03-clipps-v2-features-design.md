# Clipps v2 — Source App, Global Hotkey, Pinning, Start at Login (Spec)

> Builds on `docs/superpowers/specs/2026-11-03-clipboard-manager-design.md`
> (v1, implemented on `main`). Four independent features, one spec.

## Goal

Make Clipps more useful day to day: know where each clip came from, open it
from anywhere with a shortcut, keep important clips pinned and safe from
deletion, and never miss copies after a reboot.

## Constraints carried from v1

- Windows desktop, Flutter/Dart, SQLite via `sqflite_common_ffi`, `provider`.
- Clips kept indefinitely; removed only by explicit user delete.
- Text clips only. Copies flagged private (`ExcludeClipboardContentFromMonitorProcessing`,
  `Clipboard Viewer Ignore`, `CanIncludeInClipboardHistory = 0`) are never stored —
  and so no source is recorded for them.
- Layer files stay where they are (`lib/models`, `lib/database`, `lib/providers`,
  `lib/services`, `lib/screens`, `lib/main.dart`, `windows/runner`).
- Existing history must survive the upgrade.

## 1. Source app and window title

**What is recorded:** for each automatically captured clip —
- `sourceApp`: the app's friendly name, i.e. the `FileDescription` from the owning
  exe's version resource (e.g. `Google Chrome`); if absent, the exe file name
  (e.g. `notepad.exe`); `null` if it cannot be determined.
- `sourceTitle`: the foreground window's title at copy time, **only if** the
  foreground window belongs to the same process as the clipboard owner; otherwise
  `null`. Empty titles are stored as `null`.

Manually saved clips (Save Clip) have no source (`null`, `null`). Clips from
before the upgrade have no source.

**How (native, `windows/runner/flutter_window.cpp`):** on `WM_CLIPBOARDUPDATE`,
before starting the existing 50 ms privacy timer, capture the source:
`GetClipboardOwner()` → `GetWindowThreadProcessId` →
`OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` → `QueryFullProcessImageNameW` →
`GetFileVersionInfoW` / `VerQueryValueW` (`\StringFileInfo\<lang><codepage>\FileDescription`,
using the first entry of `\VarFileInfo\Translation`). Title: `GetForegroundWindow()`
+ `GetWindowTextW` when its process id equals the owner's. Any failure yields
`null` for that field; capture never blocks or fails because of source lookup.
Link `version.lib` in `windows/runner/CMakeLists.txt`.

If several updates arrive before the timer fires, the source from the latest
update is used.

**Channel:** `clipboardChanged` now carries a map argument
`{"sourceApp": String?, "sourceTitle": String?}`. Dart must also accept a
`null`/missing argument (treated as no source).

**Dart:** `ClipboardWatcher.onText` becomes
`Future<void> Function(String text, ClipSource source)`, where
`ClipSource { final String? app; final String? title; }` (const, value equality).
`ClipboardProvider.addClip(String content, {ClipSource source = const ClipSource()})`.
Dedupe is unchanged: content equal to the most recent clip is skipped regardless
of source.

**Display only:** no search or filter by source. Row subtitle:
- `2026-11-03 14:02:11 · Google Chrome — Inbox - Gmail` (app and title)
- `2026-11-03 14:02:11 · Google Chrome` (app only)
- `2026-11-03 14:02:11` (no source)

Single line, ellipsized.

## 2. Global hotkey

**Shortcut:** Ctrl + AltGr + `.` — registered as
`RegisterHotKey(hwnd, 1, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_OEM_PERIOD)`
in `OnCreate`; `UnregisterHotKey` on `WM_DESTROY`. Windows cannot distinguish
left/right Alt for hotkeys, so Ctrl+Alt+`.` also triggers it; on layouts where
AltGr+`.` types a character, Clipps takes it over. Not configurable.

**Behaviour on `WM_HOTKEY`:**
- Window visible **and** foreground → hide it (same as closing to tray).
- Otherwise → show, restore, bring to front, then invoke `focusSearch` on the
  `clipps/clipboard` channel. Dart focuses the search field and selects its text.

**Shortcut taken:** if `RegisterHotKey` fails, the runner invokes
`hotkeyUnavailable` once, from the first-frame callback (which fires whether or
not the window is shown). Dart records it and shows a persistent warning line
directly under the app bar: `Shortcut Ctrl+Alt+. is already used by another app`.
(A SnackBar would expire unseen after a hidden start at login.) Everything else
works.

## 3. Pin favorites

- **Storage:** `pinned INTEGER NOT NULL DEFAULT 0`.
  `DbHelper.setPinned(int id, bool pinned)`.
- **Order:** list order `pinned DESC, created_at DESC, id DESC`. Pinned clips
  still obey search text and date range. `latestClip()` (used for dedupe) keeps
  `created_at DESC, id DESC` — it ignores pins.
- **Delete protection:** `deleteClips` deletes only rows with `pinned = 0`
  (SQL guard), so pinned rows are never deleted. In the UI a pinned row's
  checkbox and delete button are disabled; the delete button tooltip is
  `Unpin to delete`. `ClipboardProvider.togglePin(int id)` also removes the id
  from the selection.
- **Row UI:** a pin `IconButton` before the delete button — filled pin, tooltip
  `Unpin` when pinned; outlined pin, tooltip `Pin` when not. Pinned rows get a
  subtle tinted background (theme `secondaryContainer` at low opacity).
  Tap-to-copy works on pinned rows.

## 4. Start at login (always on)

- **Registration:** on every launch of a **Release** build (`#ifdef NDEBUG`),
  write `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, value name
  `Clipps`, `REG_SZ` data `"<full path of the running exe>" --hidden`.
  Rewriting each launch keeps the path correct if the folder moves. Debug builds
  never write it. No in-app switch. Failure to write is ignored.
- **Hidden launch:** `main.cpp` detects `--hidden` on the command line. The window
  is created but not shown on the first frame; it lives in the tray and captures
  as usual. Tray click or the hotkey shows it.
- **Single instance:** a second instance started **with** `--hidden` exits
  without showing the first one; without `--hidden` it shows the first one
  (unchanged v1 behaviour).
- **Removal:** deleting the app leaves a dangling Run value, which Windows
  ignores. (A future installer's uninstaller should remove it.)

## Database migration

DB version 1 → 2. `onUpgrade` from 1 runs:
```sql
ALTER TABLE clips ADD COLUMN source_app TEXT;
ALTER TABLE clips ADD COLUMN source_title TEXT;
ALTER TABLE clips ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;
```
`onCreate` creates the v2 table directly. `ClipboardModel` gains
`String? sourceApp`, `String? sourceTitle`, `bool pinned`. An upgrade failure
shows the existing startup error window; nothing is deleted.

## Error handling summary

| Failure | Behaviour |
|---|---|
| Source lookup fails (any step) | Field is `null`; clip still saved |
| Hotkey already registered elsewhere | Persistent warning line under the app bar; app otherwise normal |
| Run-key write fails | Ignored; no start at login |
| DB upgrade fails | Startup error window; data untouched |

## Testing

- **Dart unit/widget (TDD):** v1→v2 upgrade on a real v1 DB file keeps every row
  and defaults (`pinned = 0`, sources `null`); pinned sort first and obey
  filters; `deleteClips` never removes pinned rows; dedupe ignores pins; watcher
  forwards the source map (and tolerates a null argument); subtitle formats for
  the three cases; pin toggle and disabled checkbox/delete on pinned rows;
  `focusSearch` focuses and selects the search text; `hotkeyUnavailable` shows
  the warning line.
- **Integration:** the existing capture test also asserts a non-null `sourceApp`
  is stored for a copy made by the test app.
- **Scripted Win32 checks (Release build):** hotkey toggles show/hide (via
  `SendInput` or posting `WM_HOTKEY`); `--hidden` launch stays hidden with the
  process running; Run value written with the exe path and `--hidden`; second
  `--hidden` instance exits without showing the first.
- **Left for the user:** pressing the physical AltGr key on their keyboard.

## Out of scope

Search/filter by source, configurable hotkey, autostart toggle, installer,
per-app exclusion lists.
