import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/clip_view.dart';
import '../providers/clipboard_provider.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  static const width = 220.0;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ClipboardProvider>();
    Widget item(String key, IconData icon, String label, ClipView v) =>
        ListTile(
          key: Key(key),
          dense: true,
          leading: Icon(icon),
          title: Text(label),
          selected: p.view == v && p.groupId == null,
          selectedTileColor: Theme.of(context).colorScheme.secondaryContainer
              .withValues(alpha: 0.5),
          shape: const StadiumBorder(),
          onTap: () => p.setView(v),
        );
    return SizedBox(
      width: width,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          item('view-all', Icons.inbox_outlined, 'All clips', ClipView.all),
          item('view-tasks', Icons.checklist, 'Tasks', ClipView.tasks),
          item('view-trash', Icons.delete_outline, 'Trash', ClipView.trash),
          // Task 7 adds the Groups header, group list and New group here.
        ],
      ),
    );
  }
}
