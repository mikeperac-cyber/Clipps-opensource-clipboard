import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/clip_view.dart';
import '../providers/clipboard_provider.dart';
import 'clip_row.dart';
import 'format.dart';
import 'notes_dialog.dart';
import 'sidebar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Right-hand column shared by the save row and the search row, so their
/// fields end at the same edge and the controls line up.
const _trailingWidth = 240.0;

/// Names the place the user is looking at, so bulk actions read in context.
String _viewTitle(ClipboardProvider p) {
  final groupId = p.groupId;
  if (groupId != null) {
    for (final g in p.groups) {
      if (g.id == groupId) return g.name;
    }
  }
  return switch (p.view) {
    ClipView.all => 'All clips',
    ClipView.tasks => 'Tasks',
    ClipView.trash => 'Trash',
    ClipView.notes => 'Notes',
  };
}

/// Hides the window via the native runner; a no-op where there is none (tests).
Future<void> _hideWindow() async {
  try {
    await const MethodChannel('clipps/clipboard')
        .invokeMethod<void>('hideWindow');
  } on MissingPluginException {
    // No native side.
  } on PlatformException {
    // Nothing more to do.
  }
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Showing the window from the tray doesn't notify Dart; keep times fresh.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ClipboardProvider>();
    final range = p.dateRange;
    final filtered =
        p.searchText.isNotEmpty || range != null || p.tagFilter != null;
    final selected = p.selectedIds;
    final trash = p.view == ClipView.trash;
    final notesView = p.view == ClipView.notes;
    final canSelectAll = p.clips.any((c) => !c.pinned);

    // Focus sits inside the shortcuts so Esc bubbles up to them.
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _hideWindow},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              selected.isEmpty ? _viewTitle(p) : '${selected.length} selected',
            ),
            actions: notesView
                ? null
                : [
                    if (selected.isNotEmpty)
                      IconButton(
                        key: const Key('clearSelection'),
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear selection',
                        onPressed: p.clearSelection,
                      ),
                    IconButton(
                      key: const Key('selectAll'),
                      icon: const Icon(Icons.select_all),
                      tooltip: 'Select all',
                      onPressed: canSelectAll ? p.selectAllVisible : null,
                    ),
                    if (trash)
                      IconButton(
                        key: const Key('restoreSelected'),
                        icon: const Icon(Icons.restore),
                        tooltip: 'Restore selected',
                        onPressed: selected.isEmpty ? null : p.restoreSelected,
                      )
                    else
                      IconButton(
                        key: const Key('deleteSelected'),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Move to Trash',
                        onPressed: selected.isEmpty
                            ? null
                            : () => confirmTrash(
                                context,
                                selected.length,
                              ).then((ok) => ok ? p.trashSelected() : null),
                      ),
                  ],
          ),
          body: Row(
            children: [
              const Sidebar(),
              const VerticalDivider(width: 1),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      children: [
                        if (p.hotkeyUnavailable)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                            child: Text(
                              'Shortcut Ctrl+Alt+. is already used by another app',
                              key: const Key('hotkeyWarning'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (p.capturePaused)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                            child: Text(
                              'Capture is paused. New copies are not saved.',
                              key: const Key('pausedBanner'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                            ),
                          ),
                        if (!trash && !notesView) const _ManualInput(),
                        if (!notesView) _searchRow(context, p, range),
                        if (!notesView && p.tagsInUse.isNotEmpty) _tagRow(p),
                        Expanded(
                          child: notesView ? _notesList(p) : _list(p, filtered),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchRow(
    BuildContext context,
    ClipboardProvider p,
    DateTimeRange? range,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        Expanded(
          child: _SearchField(
            initialText: p.searchText,
            focusRequests: p.searchFocusRequests,
            onChanged: p.setSearchText,
            onSubmitted: (_) {
              if (p.view == ClipView.trash || p.clips.isEmpty) return;
              Clipboard.setData(ClipboardData(text: p.clips.first.content));
              _hideWindow();
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: _trailingWidth,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                key: const Key('dateRange'),
                icon: const Icon(Icons.date_range),
                label: Text(
                  range == null
                      ? 'Any date'
                      : '${dayString(range.start)} - ${dayString(range.end)}',
                ),
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: p.now().add(const Duration(days: 1)),
                    initialDateRange: range,
                  );
                  if (picked != null) await p.setDateRange(picked);
                },
              ),
              if (range != null)
                IconButton(
                  key: const Key('clearDateRange'),
                  tooltip: 'Clear date range',
                  icon: const Icon(Icons.clear),
                  onPressed: () => p.setDateRange(null),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _tagRow(ClipboardProvider p) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final t in p.tagsInUse)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  key: Key('tagFilter-$t'),
                  label: Text(t),
                  selected: p.tagFilter?.toLowerCase() == t.toLowerCase(),
                  onSelected: (on) => p.setTagFilter(on ? t : null),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _notesList(ClipboardProvider p) {
    if (p.notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notes,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            const Text('No notes yet'),
          ],
        ),
      );
    }
    final now = p.now();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView.builder(
      itemCount: p.notes.length,
      itemBuilder: (context, i) {
        final e = p.notes[i];
        final label = e.clip.sourceLabel;
        return Card(
          key: Key('noteCard-${e.note.id}'),
          margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: ListTile(
            onTap: () => showNotesDialog(context, e.clip),
            title: Text(
              e.note.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.clip.isSecret ? maskSecret(e.clip.preview) : e.clip.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${relativeTime(e.note.updatedAt, now)}'
                  '${label == null ? '' : ' · $label'}',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _list(ClipboardProvider p, bool filtered) {
    if (p.clips.isEmpty) {
      final (icon, text) = filtered
          ? (Icons.search_off, 'No clips match')
          : switch (p.view) {
              ClipView.tasks => (Icons.checklist, 'No tasks yet'),
              ClipView.trash => (Icons.delete_outline, 'Trash is empty'),
              ClipView.notes => (Icons.notes, 'No notes yet'),
              ClipView.all =>
                p.groupId != null
                    ? (Icons.folder_open, 'No clips in this group')
                    : (Icons.content_paste, 'No clips yet'),
            };
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(text),
            if (!filtered && p.view == ClipView.all && p.groupId == null) ...[
              const SizedBox(height: 4),
              Text(
                p.hotkeyUnavailable
                    ? 'Copy any text and it appears here.'
                    : 'Copy any text and it appears here. '
                          'Press Ctrl+Alt+. to open Clipps from anywhere.',
                key: const Key('emptyHint'),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    }
    final now = p.now();
    return ListView.builder(
      itemCount: p.clips.length,
      itemBuilder: (context, i) {
        final clip = p.clips[i];
        return ClipRow(
          key: ValueKey(clip.id),
          clip: clip,
          view: p.view,
          selected: p.selectedIds.contains(clip.id),
          now: now,
        );
      },
    );
  }
}

class _ManualInput extends StatefulWidget {
  const _ManualInput();

  @override
  State<_ManualInput> createState() => _ManualInputState();
}

class _ManualInputState extends State<_ManualInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Only clear when saved, so a skipped duplicate doesn't eat the user's text.
    final saved = await context.read<ClipboardProvider>().addClip(
      _controller.text,
    );
    if (!mounted) return;
    if (saved) {
      _controller.clear();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nothing new to save')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              key: const Key('manualInput'),
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Paste or type text to save',
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: _trailingWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('saveClip'),
                onPressed: _save,
                child: const Text('Save Clip'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.initialText,
    required this.focusRequests,
    required this.onChanged,
    required this.onSubmitted,
  });

  final String initialText;
  final int focusRequests;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final _controller = TextEditingController(text: widget.initialText);
  final _focus = FocusNode();

  @override
  void didUpdateWidget(_SearchField old) {
    super.didUpdateWidget(old);
    if (widget.focusRequests != old.focusRequests) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focus.requestFocus();
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('search'),
      controller: _controller,
      focusNode: _focus,
      decoration: const InputDecoration(
        hintText: 'Search clips',
        prefixIcon: Icon(Icons.search),
      ),
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
  }
}
