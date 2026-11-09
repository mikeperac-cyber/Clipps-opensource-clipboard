import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/clipboard_model.dart';
import '../models/note.dart';
import '../providers/clipboard_provider.dart';
import 'format.dart';

Future<void> showNotesDialog(BuildContext context, ClipboardModel clip) {
  // The dialog has no Scaffold of its own, so messages go to the page's.
  final messenger = ScaffoldMessenger.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) => _NotesDialog(clip: clip, messenger: messenger),
  );
}

class _NotesDialog extends StatefulWidget {
  const _NotesDialog({required this.clip, required this.messenger});

  final ClipboardModel clip;
  final ScaffoldMessengerState messenger;

  @override
  State<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<_NotesDialog> {
  final _input = TextEditingController();
  final _edit = TextEditingController();
  List<Note> _notes = [];
  int? _editing;

  ClipboardProvider get _p => context.read<ClipboardProvider>();

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _reload();
  }

  @override
  void dispose() {
    _input.dispose();
    _edit.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final notes = await _p.notesFor(widget.clip.id);
    if (mounted) setState(() => _notes = notes);
  }

  /// True when the save went through. `missing` (clip or note purged) closes
  /// the dialog quietly; `tooLong` keeps the typed text.
  Future<bool> _finish(NoteResult r) async {
    if (!mounted) return false;
    switch (r) {
      case NoteResult.saved:
        await _reload();
        return true;
      case NoteResult.missing:
        Navigator.pop(context);
      case NoteResult.tooLong:
        widget.messenger.showSnackBar(
          const SnackBar(
            content: Text('Notes are limited to 20,000 characters'),
          ),
        );
      case NoteResult.blank:
        break;
    }
    return false;
  }

  Future<void> _add() async {
    final r = await _p.addNote(widget.clip.id, _input.text);
    if (await _finish(r)) _input.clear();
  }

  Future<void> _save(int id) async {
    final r = await _p.editNote(id, _edit.text);
    if (await _finish(r) && mounted) setState(() => _editing = null);
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this note?'),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _p.deleteNote(id);
    await _reload();
  }

  Widget _noteTile(Note n) {
    final now = DateTime.now();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (_editing == n.id) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            key: Key('noteEdit-${n.id}'),
            controller: _edit,
            autofocus: true,
            minLines: 1,
            maxLines: 6,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _editing = null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: Key('saveNote-${n.id}'),
                onPressed: () => _save(n.id),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(n.body),
      subtitle: Text(
        'Created ${relativeTime(n.createdAt, now)}'
        '${n.edited ? ' · edited ${relativeTime(n.updatedAt, now)}' : ''}',
        style: TextStyle(fontSize: 12, color: muted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('editNote-${n.id}'),
            tooltip: 'Edit note',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => setState(() {
              _editing = n.id;
              _edit.text = n.body;
            }),
          ),
          IconButton(
            key: Key('deleteNote-${n.id}'),
            tooltip: 'Delete note',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(n.id),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Notes'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(widget.clip.content),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [for (final n in _notes) _noteTile(n)],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('noteInput'),
              controller: _input,
              minLines: 1,
              maxLines: 6,
              decoration: const InputDecoration(hintText: 'Write a note'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('addNote'),
                onPressed: _input.text.trim().isEmpty ? null : _add,
                child: const Text('Add note'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
