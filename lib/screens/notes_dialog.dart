import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/clipboard_model.dart';
import '../models/note.dart';
import '../providers/clipboard_provider.dart';
import 'format.dart';

Future<void> showNotesDialog(BuildContext context, ClipboardModel clip) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NotesDialog(clip: clip),
    );

const _saveFailedCopy = 'Could not save this note. Your text is still here.';
const _tooLongCopy = 'Notes are limited to 20,000 characters';

/// Local `YYYY-MM-DD HH:mm`.
String _stamp(DateTime t) => t.toLocal().toString().substring(0, 16);

/// Local `HH:mm`.
String _time(DateTime t) => t.toLocal().toString().substring(11, 16);

class _NotesDialog extends StatefulWidget {
  const _NotesDialog({required this.clip});

  final ClipboardModel clip;

  @override
  State<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<_NotesDialog> {
  final _input = TextEditingController();
  final _edit = TextEditingController();
  List<Note> _notes = [];
  bool _loaded = false;
  bool _revealed = false;
  int? _editing;
  String? _inputError;
  String? _editError;

  ClipboardProvider get _p => context.read<ClipboardProvider>();

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() => _inputError = null));
    _edit.addListener(() => setState(() => _editError = null));
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
    if (mounted) {
      setState(() {
        _notes = notes;
        _loaded = true;
      });
    }
  }

  /// True when the save went through. `missing` (clip or note purged) closes
  /// the dialog quietly; `tooLong` keeps the typed text and flags the field.
  Future<bool> _finish(NoteResult r, {required bool edit}) async {
    if (!mounted) return false;
    switch (r) {
      case NoteResult.saved:
        await _reload();
        return true;
      case NoteResult.missing:
        Navigator.pop(context);
      case NoteResult.tooLong:
        setState(() {
          if (edit) {
            _editError = _tooLongCopy;
          } else {
            _inputError = _tooLongCopy;
          }
        });
      case NoteResult.blank:
        break;
    }
    return false;
  }

  Future<void> _add() async {
    try {
      final r = await _p.addNote(widget.clip.id, _input.text);
      if (await _finish(r, edit: false)) _input.clear();
    } catch (_) {
      if (mounted) setState(() => _inputError = _saveFailedCopy);
    }
  }

  Future<void> _save(int id) async {
    try {
      final r = await _p.editNote(id, _edit.text);
      if (await _finish(r, edit: true) && mounted) {
        setState(() => _editing = null);
      }
    } catch (_) {
      if (mounted) setState(() => _editError = _saveFailedCopy);
    }
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
    if (mounted) await _reload();
  }

  Widget _noteTile(Note n) {
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
            decoration: InputDecoration(errorText: _editError),
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
                onPressed: _edit.text.trim().isEmpty ? null : () => _save(n.id),
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
        'Created ${_stamp(n.createdAt)}'
        '${n.edited ? ' · edited ${_time(n.updatedAt)}' : ''}',
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
              _editError = null;
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        widget.clip.isSecret && !_revealed
                            ? maskSecret(widget.clip.content)
                            : widget.clip.content,
                      ),
                    ),
                  ),
                  if (widget.clip.isSecret)
                    IconButton(
                      key: const Key('revealClip'),
                      tooltip: _revealed ? 'Hide' : 'Reveal',
                      icon: Icon(
                        _revealed ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _revealed = !_revealed),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_loaded && _notes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No notes for this clip yet'),
              ),
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
              decoration: InputDecoration(
                hintText: 'Write a note',
                errorText: _inputError,
              ),
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
