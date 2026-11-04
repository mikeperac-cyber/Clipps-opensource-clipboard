import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/clipboard_provider.dart';

/// Name dialog; stays open with an error until [submit] returns true.
Future<void> showGroupNameDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  required Future<bool> Function(String name) submit,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _GroupNameDialog(title: title, initial: initial, submit: submit),
);

class _GroupNameDialog extends StatefulWidget {
  const _GroupNameDialog({
    required this.title,
    required this.initial,
    required this.submit,
  });
  final String title;
  final String initial;
  final Future<bool> Function(String) submit;

  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  late final _c = TextEditingController(text: widget.initial);
  bool _bad = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _ok() async {
    final ok = await widget.submit(_c.text);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _bad = true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const Key('groupNameInput'),
      controller: _c,
      autofocus: true,
      decoration: InputDecoration(
        hintText: 'Group name',
        errorText: _bad ? 'Name already used or invalid' : null,
      ),
      onSubmitted: (_) => _ok(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: const Key('groupNameOk'),
        onPressed: _ok,
        child: const Text('OK'),
      ),
    ],
  );
}

Future<void> showTagEditor(BuildContext context, int clipId) =>
    showDialog<void>(context: context, builder: (_) => _TagEditor(clipId));

class _TagEditor extends StatefulWidget {
  const _TagEditor(this.clipId);
  final int clipId;

  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  final _c = TextEditingController();
  bool _bad = false;
  // Last tags seen: the clip may leave p.clips (e.g. filtered out) while open.
  List<String> _tags = const [];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _c.text.trim();
    final ok = await context.read<ClipboardProvider>().addTag(
      widget.clipId,
      _c.text,
    );
    if (!mounted) return;
    setState(() {
      _bad = !ok;
      if (ok && !_tags.any((x) => x.toLowerCase() == text.toLowerCase())) {
        _tags = [..._tags, text];
      }
    });
    if (ok) _c.clear();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ClipboardProvider>();
    final clip = p.clips.where((c) => c.id == widget.clipId).firstOrNull;
    if (clip != null) _tags = clip.tags;
    final tags = _tags;
    return AlertDialog(
      title: const Text('Edit tags'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              children: [
                for (final t in tags)
                  InputChip(
                    key: Key('removeTag-$t'),
                    label: Text(t),
                    onDeleted: () async {
                      await p.removeTag(widget.clipId, t);
                      if (mounted) {
                        setState(
                          () => _tags = [
                            for (final x in _tags)
                              if (x != t) x,
                          ],
                        );
                      }
                    },
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('tagInput'),
                    controller: _c,
                    decoration: InputDecoration(
                      hintText: 'Add a tag',
                      errorText: _bad ? 'Invalid tag' : null,
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                TextButton(
                  key: const Key('addTag'),
                  onPressed: _add,
                  child: const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
