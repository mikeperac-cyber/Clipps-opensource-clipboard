import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/clip_view.dart';
import '../models/clipboard_model.dart';
import '../providers/clipboard_provider.dart';
import 'dialogs.dart';
import 'format.dart';
import 'notes_dialog.dart';

Future<bool> confirmTrash(BuildContext context, int count) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Move $count clip(s) to Trash?'),
      content: const Text('You can restore them for 15 days.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Move to Trash'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

const _newGroup = -1;
const _noGroup = -2;

String _days(int n) => n == 1 ? '1 day' : '$n days';

class ClipRow extends StatefulWidget {
  const ClipRow({
    super.key,
    required this.clip,
    required this.view,
    required this.selected,
    required this.now,
  });

  final ClipboardModel clip;
  final ClipView view;
  final bool selected;
  final DateTime now;

  @override
  State<ClipRow> createState() => _ClipRowState();
}

class _ClipRowState extends State<ClipRow> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final p = context.read<ClipboardProvider>();
    final clip = widget.clip;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final pinned = clip.pinned;
    final trash = widget.view == ClipView.trash;
    final done = clip.taskState == TaskState.done;
    final hidden = clip.isSecret && !_revealed;
    final isCode = clip.tags.contains('Code');
    final label = clip.sourceLabel;
    final metaStyle = TextStyle(fontSize: 12, color: muted);

    Widget? leading;
    if (!trash) {
      leading = widget.view == ClipView.tasks
          ? Checkbox(
              key: Key('taskDone-${clip.id}'),
              value: done,
              onChanged: (v) => p.setTaskDone(clip.id, v ?? false),
            )
          : Checkbox(
              key: Key('select-${clip.id}'),
              value: widget.selected,
              onChanged: pinned ? null : (_) => p.toggleSelected(clip.id),
            );
    }

    final meta = trash
        ? Text(
            'Deleted ${dayString(clip.deletedAt!.toLocal())} · removed in '
            '${_days(trashDaysLeft(clip.deletedAt!, widget.now))}',
            style: metaStyle,
          )
        : Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 2,
            children: [
              Tooltip(
                message: clip.createdAt.toLocal().toString().substring(0, 19),
                child: Text(
                  label == null
                      ? relativeTime(clip.createdAt.toLocal(), widget.now)
                      : '${relativeTime(clip.createdAt.toLocal(), widget.now)}'
                            ' · $label',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metaStyle,
                ),
              ),
              for (final tag in clip.tags)
                Chip(
                  label: Text(tag),
                  labelStyle: const TextStyle(fontSize: 11),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              if (p.isDuplicate(clip.id))
                Tooltip(
                  message: 'This text is saved more than once',
                  child: Chip(
                    key: Key('dupBadge-${clip.id}'),
                    avatar: Icon(
                      Icons.content_copy,
                      size: 14,
                      color: scheme.tertiary,
                    ),
                    label: Text(
                      'Duplicate',
                      style: TextStyle(fontSize: 11, color: scheme.tertiary),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          );

    return ListTile(
      key: Key('clip-${clip.id}'),
      tileColor: pinned
          ? scheme.secondaryContainer.withValues(alpha: 0.35)
          : null,
      onTap: () {
        Clipboard.setData(ClipboardData(text: clip.content));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Copied')));
      },
      leading: leading,
      title: Text(
        hidden ? maskSecret(clip.preview) : clip.preview,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: isCode ? 'Consolas' : null,
          decoration: done ? TextDecoration.lineThrough : null,
          color: done ? muted : null,
        ),
      ),
      subtitle: meta,
      trailing: trash
          ? TextButton(
              key: Key('restore-${clip.id}'),
              onPressed: () => p.restoreClip(clip.id),
              child: const Text('Restore'),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (clip.isSecret)
                  IconButton(
                    key: Key('reveal-${clip.id}'),
                    tooltip: _revealed ? 'Hide' : 'Reveal',
                    color: muted,
                    icon: Icon(
                      _revealed ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _revealed = !_revealed),
                  ),
                IconButton(
                  key: Key('notesButton-${clip.id}'),
                  tooltip: clip.noteCount > 0
                      ? 'Notes (${clip.noteCount})'
                      : 'Notes',
                  color: muted,
                  icon: Icon(
                    clip.noteCount > 0
                        ? Icons.sticky_note_2
                        : Icons.sticky_note_2_outlined,
                  ),
                  onPressed: () => showNotesDialog(context, clip),
                ),
                IconButton(
                  key: Key('pin-${clip.id}'),
                  tooltip: pinned ? 'Unpin' : 'Pin',
                  color: muted,
                  icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
                  onPressed: () => p.togglePin(clip.id),
                ),
                IconButton(
                  key: Key('task-${clip.id}'),
                  tooltip: clip.taskState == TaskState.none
                      ? 'Make task'
                      : 'Remove task',
                  color: muted,
                  icon: Icon(
                    clip.taskState == TaskState.none
                        ? Icons.add_task
                        : Icons.task_alt,
                  ),
                  onPressed: () => clip.taskState == TaskState.none
                      ? p.makeTask(clip.id)
                      : p.removeTask(clip.id),
                ),
                PopupMenuButton<int>(
                  key: Key('group-${clip.id}'),
                  tooltip: 'Group',
                  icon: Icon(Icons.folder_outlined, color: muted),
                  onSelected: (v) {
                    if (v == _newGroup) {
                      showGroupNameDialog(
                        context,
                        title: 'New group',
                        submit: (n) async {
                          if (!await p.createGroup(n)) return false;
                          final g = p.groups.where((g) => g.name == n.trim());
                          if (g.isNotEmpty) {
                            await p.setClipGroup(clip.id, g.first.id);
                          }
                          return true;
                        },
                      );
                    } else {
                      p.setClipGroup(clip.id, v == _noGroup ? null : v);
                    }
                  },
                  itemBuilder: (_) => [
                    for (final g in p.groups)
                      PopupMenuItem(
                        key: Key('groupOption-${g.id}'),
                        value: g.id,
                        child: Text(g.name),
                      ),
                    const PopupMenuItem(
                      key: Key('newGroupOption'),
                      value: _newGroup,
                      child: Text('New group…'),
                    ),
                    if (clip.groupId != null)
                      const PopupMenuItem(
                        key: Key('removeFromGroup'),
                        value: _noGroup,
                        child: Text('Remove from group'),
                      ),
                  ],
                ),
                IconButton(
                  key: Key('tags-${clip.id}'),
                  tooltip: 'Edit tags',
                  color: muted,
                  icon: const Icon(Icons.sell_outlined),
                  onPressed: () => showTagEditor(context, clip.id),
                ),
                IconButton(
                  key: Key('delete-${clip.id}'),
                  tooltip: pinned ? 'Unpin to delete' : 'Delete clip',
                  color: muted,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: pinned
                      ? null
                      : () => confirmTrash(
                          context,
                          1,
                        ).then((ok) => ok ? p.trashClip(clip.id) : null),
                ),
              ],
            ),
    );
  }
}
