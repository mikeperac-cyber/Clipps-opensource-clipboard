import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/clipboard_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ClipboardProvider>();
    final range = p.dateRange;
    final filtered = p.searchText.isNotEmpty || range != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clipps'),
        actions: [
          IconButton(
            key: const Key('deleteSelected'),
            icon: const Icon(Icons.delete),
            tooltip: 'Delete selected',
            onPressed: p.selectedIds.isEmpty
                ? null
                : () => _confirmDelete(
                    context,
                    p.selectedIds.length,
                  ).then((ok) => ok ? p.deleteSelected() : null),
          ),
        ],
      ),
      body: Column(
        children: [
          const _ManualInput(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('search'),
                    decoration: const InputDecoration(hintText: 'Search clips'),
                    onChanged: p.setSearchText,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  key: const Key('dateRange'),
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    range == null
                        ? 'Any date'
                        : '${_day(range.start)} - ${_day(range.end)}',
                  ),
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
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
          Expanded(
            child: p.clips.isEmpty
                ? Center(
                    child: Text(filtered ? 'No clips match' : 'No clips yet'),
                  )
                : ListView.builder(
                    itemCount: p.clips.length,
                    itemBuilder: (context, i) {
                      final clip = p.clips[i];
                      return ListTile(
                        key: Key('clip-${clip.id}'),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: clip.content));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied')),
                          );
                        },
                        leading: Checkbox(
                          key: Key('select-${clip.id}'),
                          value: p.selectedIds.contains(clip.id),
                          onChanged: (_) => p.toggleSelected(clip.id),
                        ),
                        title: Text(
                          clip.preview,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          clip.createdAt.toLocal().toString().substring(0, 19),
                        ),
                        trailing: IconButton(
                          key: Key('delete-${clip.id}'),
                          tooltip: 'Delete clip',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(
                            context,
                            1,
                          ).then((ok) => ok ? p.deleteClip(clip.id) : null),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

String _day(DateTime d) => d.toString().substring(0, 10);

Future<bool> _confirmDelete(BuildContext context, int count) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete $count clip(s)?'),
      content: const Text('This permanently removes them.'),
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
  return ok ?? false;
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
          FilledButton(
            key: const Key('saveClip'),
            onPressed: _save,
            child: const Text('Save Clip'),
          ),
        ],
      ),
    );
  }
}
