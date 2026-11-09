import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../models/clip_view.dart';
import '../providers/clipboard_provider.dart';
import 'dialogs.dart';

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
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                item(
                  'view-all',
                  Icons.inbox_outlined,
                  'All clips',
                  ClipView.all,
                ),
                item('view-tasks', Icons.checklist, 'Tasks', ClipView.tasks),
                item(
                  'view-notes',
                  Icons.sticky_note_2_outlined,
                  'Notes',
                  ClipView.notes,
                ),
                item(
                  'view-trash',
                  Icons.delete_outline,
                  'Trash',
                  ClipView.trash,
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Groups',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                for (final g in p.groups)
                  ListTile(
                    key: Key('group-item-${g.id}'),
                    dense: true,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(
                      g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: p.groupId == g.id,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .secondaryContainer
                        .withValues(alpha: 0.5),
                    shape: const StadiumBorder(),
                    onTap: () => p.selectGroup(g.id),
                    trailing: PopupMenuButton<String>(
                      key: Key('groupMenu-${g.id}'),
                      icon: const Icon(Icons.more_vert, size: 18),
                      onSelected: (v) => v == 'rename'
                          ? showGroupNameDialog(
                              context,
                              title: 'Rename group',
                              initial: g.name,
                              submit: (n) => p.renameGroup(g.id, n),
                            )
                          : p.deleteGroup(g.id),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete group'),
                        ),
                      ],
                    ),
                  ),
                ListTile(
                  key: const Key('newGroup'),
                  dense: true,
                  leading: const Icon(Icons.add),
                  title: const Text('New group'),
                  shape: const StadiumBorder(),
                  onTap: () => showGroupNameDialog(
                    context,
                    title: 'New group',
                    submit: p.createGroup,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            key: const Key('aboutClipps'),
            dense: true,
            leading: const Icon(Icons.info_outline),
            title: const Text('About Clipps'),
            shape: const StadiumBorder(),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Clipps',
              applicationVersion: kAppVersion,
              applicationLegalese: '© 2026 Clipps',
              children: [
                const Text(
                  'Clipps works offline. Your clips are stored only on this PC '
                  'and are never sent anywhere.',
                ),
                SelectableText(p.dataDir),
                TextButton(
                  key: const Key('openDataFolder'),
                  child: const Text('Open data folder'),
                  onPressed: () async {
                    try {
                      // explorer exits non-zero even on success; ignore result
                      await Process.run('explorer.exe', [p.dataDir]);
                    } catch (_) {}
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto),
                  tooltip: 'System',
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode),
                  tooltip: 'Light',
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode),
                  tooltip: 'Dark',
                ),
              ],
              selected: {p.themeMode},
              onSelectionChanged: (s) => p.setThemeMode(s.first),
            ),
          ),
        ],
      ),
    );
  }
}
