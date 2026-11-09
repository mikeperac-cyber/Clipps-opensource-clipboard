import 'package:clipps/database/db_helper.dart';
import 'package:clipps/models/clip_view.dart';
import 'package:clipps/models/clip_source.dart';
import 'package:clipps/models/clipboard_model.dart';
import 'package:clipps/providers/clipboard_provider.dart';
import 'package:clipps/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper db;
  late ClipboardProvider p;
  setUp(() async {
    db = await DbHelper.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    p = ClipboardProvider(db);
  });
  tearDown(() => db.close());

  // Real DB I/O needs the real event loop, not the fake-async test zone.
  Future<void> settle(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump();
  }

  Future<void> show(WidgetTester t, {List<String> clips = const []}) async {
    await t.runAsync(() async {
      for (final c in clips) {
        await p.addClip(c);
      }
      await p.load();
    });
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: p,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.tap(find.byKey(Key(key)));
    await settle(t);
  }

  Future<void> confirmDelete(WidgetTester t) async {
    await t.tap(find.text('Move to Trash').last);
    await settle(t);
    await t.pumpAndSettle();
  }

  testWidgets('shows "No clips yet" when history is empty', (t) async {
    await show(t);
    expect(find.text('No clips yet'), findsOneWidget);
  });

  testWidgets(
    'Save Clip stores manual text, lists it first, clears the field',
    (t) async {
      await show(t, clips: ['old']);
      await t.enterText(find.byKey(const Key('manualInput')), 'new text');
      await tapKey(t, 'saveClip');
      expect(p.clips.first.content, 'new text');
      expect(find.text('new text'), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('manualInput')))
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  testWidgets('Save Clip with a duplicate shows "Nothing new to save"', (
    t,
  ) async {
    await show(t, clips: ['a']);
    await t.enterText(find.byKey(const Key('manualInput')), 'a');
    await tapKey(t, 'saveClip');
    expect(find.text('Nothing new to save'), findsOneWidget);
    expect(p.clips.length, 1);
    expect(
      t
          .widget<TextField>(find.byKey(const Key('manualInput')))
          .controller!
          .text,
      'a',
    );
  });

  testWidgets('tapping a row copies its full content and shows Copied', (
    t,
  ) async {
    final long = 'x' * 600;
    final copied = <String?>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String?);
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await show(t, clips: [long]);
    // Tap the title area; the centre now lands on the wider button row.
    final row = find.byKey(Key('clip-${p.clips.first.id}'));
    await t.tapAt(t.getTopLeft(row) + const Offset(120, 20));
    await t.pump();
    expect(copied, [long]);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('Save Clip with blank text saves nothing', (t) async {
    await show(t);
    await t.enterText(find.byKey(const Key('manualInput')), '   ');
    await tapKey(t, 'saveClip');
    expect(p.clips, isEmpty);
    expect(find.text('No clips yet'), findsOneWidget);
  });

  testWidgets(
    'typing in search filters the list; no hits shows "No clips match"',
    (t) async {
      await show(t, clips: ['apple', 'banana']);
      await t.enterText(find.byKey(const Key('search')), 'app');
      await settle(t);
      expect(find.text('apple'), findsOneWidget);
      expect(find.text('banana'), findsNothing);
      await t.enterText(find.byKey(const Key('search')), 'zzz');
      await settle(t);
      expect(find.text('No clips match'), findsOneWidget);
    },
  );

  testWidgets('search text survives Notes -> All and still filters', (t) async {
    await show(t, clips: ['apple', 'banana']);
    await t.enterText(find.byKey(const Key('search')), 'apple');
    await settle(t);
    await tapKey(t, 'view-notes');
    await tapKey(t, 'view-all');
    expect(
      t.widget<TextField>(find.byKey(const Key('search'))).controller!.text,
      'apple',
    );
    expect(find.byKey(Key('clip-${p.clips.single.id}')), findsOneWidget);
    expect(p.clips.map((c) => c.content), ['apple']);
    expect(find.text('banana'), findsNothing);
  });

  testWidgets(
    'select two clips, confirm Move to Trash: both gone from list and DB',
    (t) async {
      await show(t, clips: ['a', 'b', 'c']);
      final ids = p.clips.map((c) => c.id).toList(); // c, b, a
      await t.tap(find.byKey(Key('select-${ids[0]}')));
      await t.tap(find.byKey(Key('select-${ids[1]}')));
      await t.pump();
      await t.tap(find.byKey(const Key('deleteSelected')));
      await t.pumpAndSettle();
      expect(find.text('Move 2 clip(s) to Trash?'), findsOneWidget);
      expect(find.text('You can restore them for 15 days.'), findsOneWidget);
      await confirmDelete(t);
      expect(find.byKey(Key('clip-${ids[0]}')), findsNothing);
      expect(find.byKey(Key('clip-${ids[1]}')), findsNothing);
      expect(find.byKey(Key('clip-${ids[2]}')), findsOneWidget);
      final left = await t.runAsync(db.getClips);
      expect(left!.map((c) => c.content), ['a']);
      final trash = await t.runAsync(() => db.getClips(view: ClipView.trash));
      expect(trash!.length, 2);
    },
  );

  testWidgets('app bar names the current view', (t) async {
    await show(t, clips: ['a']);
    String title() =>
        (t.widget<AppBar>(find.byType(AppBar)).title! as Text).data!;
    expect(title(), 'All clips');
    await t.runAsync(() => p.setView(ClipView.trash));
    await t.pump();
    expect(title(), 'Trash');
  });

  testWidgets('select all then Move to Trash trashes every unpinned clip', (
    t,
  ) async {
    await show(t, clips: ['a', 'b', 'c']);
    await t.tap(find.byKey(const Key('selectAll')));
    await t.pump();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('3 selected'),
      ),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('deleteSelected')));
    await t.pumpAndSettle();
    expect(find.text('Move 3 clip(s) to Trash?'), findsOneWidget);
    await confirmDelete(t);
    expect((await t.runAsync(db.getClips))!, isEmpty);
    final trash = await t.runAsync(() => db.getClips(view: ClipView.trash));
    expect(trash!.length, 3);
  });

  testWidgets('select all leaves pinned clips out', (t) async {
    await show(t, clips: ['a', 'b']);
    final pinned = p.clips.first.id;
    await t.runAsync(() => p.togglePin(pinned));
    await t.pump();
    await t.tap(find.byKey(const Key('selectAll')));
    await t.pump();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('1 selected'),
      ),
      findsOneWidget,
    );
    expect(p.selectedIds, isNot(contains(pinned)));
  });

  testWidgets('in Trash, Restore selected brings the clips back', (t) async {
    await show(t, clips: ['a', 'b']);
    await t.tap(find.byKey(const Key('selectAll')));
    await t.pump();
    await t.tap(find.byKey(const Key('deleteSelected')));
    await t.pumpAndSettle();
    await confirmDelete(t);
    await t.runAsync(() => p.setView(ClipView.trash));
    await t.pump();
    await t.tap(find.byKey(const Key('selectAll')));
    await t.pump();
    await t.tap(find.byKey(const Key('restoreSelected')));
    await settle(t);
    expect((await t.runAsync(db.getClips))!.length, 2);
  });

  testWidgets('deleteSelected is disabled with nothing selected', (t) async {
    await show(t, clips: ['a']);
    expect(
      t.widget<IconButton>(find.byKey(const Key('deleteSelected'))).onPressed,
      isNull,
    );
  });

  testWidgets('Cancel in Trash dialog keeps clips', (t) async {
    await show(t, clips: ['a']);
    await t.tap(find.byKey(Key('select-${p.clips.first.id}')));
    await t.pump();
    await t.tap(find.byKey(const Key('deleteSelected')));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
    expect((await t.runAsync(db.getClips))!.length, 1);
  });

  testWidgets('row delete button removes just that clip after confirm', (
    t,
  ) async {
    await show(t, clips: ['a', 'b']);
    final bId = p.clips.first.id;
    await t.tap(find.byKey(Key('delete-$bId')));
    await t.pumpAndSettle();
    expect(find.text('Move 1 clip(s) to Trash?'), findsOneWidget);
    await confirmDelete(t);
    expect(find.text('b'), findsNothing);
    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('a 2 MB clip renders as a 500-character preview', (t) async {
    await show(t, clips: ['y' * 2 * 1024 * 1024]);
    final id = p.clips.first.id;
    final title = t.widget<Text>(
      find
          .descendant(
            of: find.byKey(Key('clip-$id')),
            matching: find.byType(Text),
          )
          .first,
    );
    expect(title.data!.length, 500);
  });

  Future<int> seed(WidgetTester t, String c, {ClipSource? source}) async {
    final m = await t.runAsync(
      () => db.insertClip(
        c,
        DateTime.now(),
        source: source ?? const ClipSource(),
      ),
    );
    return m!.id;
  }

  testWidgets('subtitle shows app and title', (t) async {
    await seed(
      t,
      'a',
      source: const ClipSource(app: 'Google Chrome', title: 'Inbox'),
    );
    await show(t);
    expect(find.textContaining('Google Chrome — Inbox'), findsOneWidget);
  });

  testWidgets('meta shows relative time without source', (t) async {
    await show(t, clips: ['a']);
    final row = find.byKey(Key('clip-${p.clips.first.id}'));
    expect(
      find.descendant(of: row, matching: find.text('just now')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.textContaining('·')),
      findsNothing,
    );
  });

  testWidgets('pin moves row to top and disables checkbox and delete', (
    t,
  ) async {
    await show(t, clips: ['a', 'b']);
    final aId = p.clips.last.id;
    expect(find.byTooltip('Pin'), findsNWidgets(2));
    await tapKey(t, 'pin-$aId');
    expect(p.clips.first.id, aId);
    expect(find.byTooltip('Unpin'), findsOneWidget);
    expect(
      t.widget<Checkbox>(find.byKey(Key('select-$aId'))).onChanged,
      isNull,
    );
    expect(
      t.widget<IconButton>(find.byKey(Key('delete-$aId'))).onPressed,
      isNull,
    );
  });

  testWidgets('pinned delete button tooltip is "Unpin to delete"', (t) async {
    await show(t, clips: ['a']);
    await tapKey(t, 'pin-${p.clips.first.id}');
    expect(find.byTooltip('Unpin to delete'), findsOneWidget);
  });

  testWidgets('requestSearchFocus focuses the search field and selects text', (
    t,
  ) async {
    await show(t);
    await t.enterText(find.byKey(const Key('search')), 'hello');
    await t.tap(find.byKey(const Key('manualInput')));
    await t.pump();
    p.requestSearchFocus();
    await t.pump();
    await t.pump();
    final tf = t.widget<TextField>(find.byKey(const Key('search')));
    expect(tf.focusNode!.hasFocus, isTrue);
    expect(
      tf.controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
  });

  testWidgets('hotkeyUnavailable shows the warning line', (t) async {
    await show(t);
    expect(find.byKey(const Key('hotkeyWarning')), findsNothing);
    p.markHotkeyUnavailable();
    await t.pump();
    expect(
      find.text('Shortcut Ctrl+Alt+. is already used by another app'),
      findsOneWidget,
    );
  });

  testWidgets('paused shows the banner', (t) async {
    await t.runAsync(() => p.setCapturePaused(true));
    await show(t);
    expect(find.byKey(const Key('pausedBanner')), findsOneWidget);
    expect(
      find.text('Capture is paused. New copies are not saved.'),
      findsOneWidget,
    );
  });

  Future<void> openView(WidgetTester t, String key) async {
    await t.tap(find.byKey(Key(key)));
    await settle(t);
  }

  testWidgets('delete moves clip to Trash, shown with days left', (t) async {
    await show(t, clips: ['a']);
    final id = p.clips.first.id;
    await t.tap(find.byKey(Key('delete-$id')));
    await t.pumpAndSettle();
    await confirmDelete(t);
    expect(find.text('No clips yet'), findsOneWidget);
    await openView(t, 'view-trash');
    expect(find.text('a'), findsOneWidget);
    expect(find.textContaining('removed in 15 days'), findsOneWidget);
    expect(find.byKey(Key('select-$id')), findsNothing);
    expect(find.byKey(Key('pin-$id')), findsNothing);
    expect(find.byKey(Key('delete-$id')), findsNothing);
  });

  testWidgets('restore returns the clip to All clips', (t) async {
    await show(t, clips: ['a']);
    final id = p.clips.first.id;
    await t.runAsync(() => p.trashClip(id));
    await t.pump();
    await openView(t, 'view-trash');
    await tapKey(t, 'restore-$id');
    expect(find.text('Trash is empty'), findsOneWidget);
    await openView(t, 'view-all');
    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('secret clip is masked until revealed', (t) async {
    const key = 'sk-AbCdEfGhIjKlMnOpQrStUvWxYz123456';
    await show(t, clips: [key]);
    final id = p.clips.first.id;
    expect(p.clips.first.isSecret, isTrue);
    expect(find.textContaining(key), findsNothing);
    expect(find.text('sk-A••••••••'), findsOneWidget);
    await t.tap(find.byKey(Key('reveal-$id')));
    await t.pump();
    expect(find.text(key), findsOneWidget);
  });

  testWidgets('selection shows "N selected" and clearSelection clears it', (
    t,
  ) async {
    await show(t, clips: ['a', 'b']);
    expect(find.byKey(const Key('clearSelection')), findsNothing);
    await t.tap(find.byKey(Key('select-${p.clips.first.id}')));
    await t.pump();
    expect(find.text('1 selected'), findsOneWidget);
    await t.tap(find.byKey(const Key('clearSelection')));
    await t.pump();
    expect(find.text('1 selected'), findsNothing);
    expect(p.selectedIds, isEmpty);
  });

  testWidgets('empty states per view', (t) async {
    await show(t);
    expect(find.text('No clips yet'), findsOneWidget);
    await openView(t, 'view-tasks');
    expect(find.text('No tasks yet'), findsOneWidget);
    await openView(t, 'view-trash');
    expect(find.text('Trash is empty'), findsOneWidget);
  });

  testWidgets('tasks view checkbox marks done and strikes through', (t) async {
    await show(t, clips: ['a']);
    final id = p.clips.first.id;
    await t.runAsync(() => p.makeTask(id));
    await t.pump();
    await openView(t, 'view-tasks');
    await tapKey(t, 'taskDone-$id');
    expect(p.clips.first.taskState, TaskState.done);
    expect(
      t.widget<Text>(find.text('a')).style?.decoration,
      TextDecoration.lineThrough,
    );
  });

  testWidgets('make task then it shows in Tasks view', (t) async {
    await show(t, clips: ['a']);
    final id = p.clips.first.id;
    await tapKey(t, 'task-$id');
    expect(p.clips.first.taskState, TaskState.open);
    expect(find.byTooltip('Remove task'), findsOneWidget);
    await openView(t, 'view-tasks');
    expect(find.byKey(Key('clip-$id')), findsOneWidget);
  });

  testWidgets('add clip to a new group from the row menu, sidebar shows it', (
    t,
  ) async {
    await show(t, clips: ['a', 'b']);
    final id = p.clips.last.id;
    await tapKey(t, 'group-$id');
    await t.pumpAndSettle();
    expect(find.text('New group…'), findsOneWidget);
    await tapKey(t, 'newGroupOption');
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('groupNameInput')), 'Work');
    await tapKey(t, 'groupNameOk');
    await t.pumpAndSettle();
    final g = p.groups.single;
    expect(p.clips.firstWhere((c) => c.id == id).groupId, g.id);
    await tapKey(t, 'group-item-${g.id}');
    expect(p.clips.map((c) => c.id), [id]);
  });

  testWidgets('duplicate group name shows error', (t) async {
    await show(t);
    await t.runAsync(() => p.createGroup('Work'));
    await t.pump();
    await tapKey(t, 'newGroup');
    await t.enterText(find.byKey(const Key('groupNameInput')), 'work');
    await tapKey(t, 'groupNameOk');
    expect(find.text('Name already used or invalid'), findsOneWidget);
  });

  testWidgets('delete group from sidebar keeps the clip in All clips', (
    t,
  ) async {
    await show(t, clips: ['a']);
    final id = p.clips.first.id;
    await t.runAsync(() async {
      await p.createGroup('Work');
      await p.setClipGroup(id, p.groups.single.id);
    });
    await t.pump();
    await tapKey(t, 'groupMenu-${p.groups.single.id}');
    await t.pumpAndSettle();
    await t.tap(find.text('Delete group'));
    await settle(t);
    await t.pumpAndSettle();
    expect(p.groups, isEmpty);
    expect(find.byKey(Key('clip-$id')), findsOneWidget);
  });

  testWidgets('edit tags: add Work, filter by chip, remove tag', (t) async {
    await show(t, clips: ['a', 'b']);
    final id = p.clips.last.id;
    await tapKey(t, 'tags-$id');
    await t.enterText(find.byKey(const Key('tagInput')), 'Work');
    await tapKey(t, 'addTag');
    expect(find.byKey(const Key('removeTag-Work')), findsOneWidget);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    await tapKey(t, 'tagFilter-Work');
    expect(p.clips.map((c) => c.id), [id]);
    await tapKey(t, 'tagFilter-Work');
    expect(p.clips.length, 2);
    await tapKey(t, 'tags-$id');
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('removeTag-Work')),
        matching: find.byIcon(Icons.clear),
      ),
    );
    await settle(t);
    expect(find.byKey(const Key('removeTag-Work')), findsNothing);
  });

  testWidgets('auto tags appear as chips on the row and in the filter bar', (
    t,
  ) async {
    await show(t, clips: ['https://example.com']);
    expect(find.byKey(const Key('tagFilter-Link')), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Link'), findsOneWidget);
  });

  testWidgets('many tags at narrow width do not overflow', (t) async {
    t.view.physicalSize = const Size(700, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await show(t, clips: ['a']);
    final id = p.clips.first.id;
    await t.runAsync(() async {
      for (final x in ['One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven']) {
        await p.addTag(id, x);
      }
    });
    await t.pump();
    expect(find.byKey(Key('clip-$id')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('trash rows hide task, group and tag buttons', (t) async {
    await show(t, clips: ['a']);
    final id = p.clips.first.id;
    await t.runAsync(() => p.trashClip(id));
    await openView(t, 'view-trash');
    expect(find.byKey(Key('task-$id')), findsNothing);
    expect(find.byKey(Key('group-$id')), findsNothing);
    expect(find.byKey(Key('tags-$id')), findsNothing);
    expect(find.byKey(Key('restore-$id')), findsOneWidget);
  });

  testWidgets('empty selected group shows empty state', (t) async {
    await show(t);
    await t.runAsync(() => p.createGroup('Work'));
    await t.pump();
    await tapKey(t, 'group-item-${p.groups.single.id}');
    expect(find.text('No clips in this group'), findsOneWidget);
  });

  testWidgets('removing the filtered tag clears the filter', (t) async {
    await show(t, clips: ['a']);
    final id = p.clips.first.id;
    await t.runAsync(() => p.addTag(id, 'Work'));
    await t.pump();
    await tapKey(t, 'tagFilter-Work');
    await tapKey(t, 'tags-$id');
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('removeTag-Work')),
        matching: find.byIcon(Icons.clear),
      ),
    );
    await settle(t);
    expect(p.tagFilter, isNull);
    expect(p.clips.map((c) => c.id), [id]);
  });

  testWidgets('relative times refresh every minute', (t) async {
    var now = DateTime(2026, 1, 1, 10);
    p = ClipboardProvider(db, clock: () => now);
    await show(t, clips: ['a']);
    expect(find.text('just now'), findsOneWidget);
    now = now.add(const Duration(minutes: 5));
    await t.pump(const Duration(minutes: 1));
    expect(find.text('5 min ago'), findsOneWidget);
  });

  testWidgets('tag filter with no results says "No clips match"', (t) async {
    await show(t, clips: ['a']);
    final id = p.clips.first.id;
    await t.runAsync(() => p.addTag(id, 'Work'));
    await t.pump();
    await tapKey(t, 'tagFilter-Work');
    await openView(t, 'view-trash');
    expect(find.text('No clips match'), findsOneWidget);
  });

  testWidgets('filter chip highlights regardless of case', (t) async {
    await show(t, clips: ['a']);
    final id = p.clips.first.id;
    await t.runAsync(() async {
      await p.addTag(id, 'Work');
      await p.setTagFilter('work');
    });
    await t.pump();
    final chip = t.widget<FilterChip>(find.byKey(const Key('tagFilter-Work')));
    expect(chip.selected, isTrue);
  });

  testWidgets('tag editor keeps showing tags after clip is filtered out', (
    t,
  ) async {
    await show(t, clips: ['a', 'b']);
    final a = p.clips.firstWhere((c) => c.content == 'a').id;
    final b = p.clips.firstWhere((c) => c.content == 'b').id;
    await t.runAsync(() async {
      for (final id in [a, b]) {
        await p.addTag(id, 'Work');
      }
      await p.addTag(a, 'Extra');
    });
    await t.pump();
    await tapKey(t, 'tagFilter-Work');
    await tapKey(t, 'tags-$a');
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('removeTag-Work')),
        matching: find.byIcon(Icons.clear),
      ),
    );
    await settle(t);
    expect(p.clips.map((c) => c.id), [b]);
    expect(find.byKey(const Key('removeTag-Extra')), findsOneWidget);
    expect(find.byKey(const Key('removeTag-Work')), findsNothing);
  });

  testWidgets('search field has a search icon', (t) async {
    await show(t);
    expect(
      find.descendant(
        of: find.byKey(const Key('search')),
        matching: find.byIcon(Icons.search),
      ),
      findsOneWidget,
    );
  });

  testWidgets('200 tags in use do not overflow the chip row', (t) async {
    t.view.physicalSize = const Size(800, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await show(t, clips: ['a']);
    final id = p.clips.first.id;
    await t.runAsync(() async {
      for (var i = 0; i < 200; i++) {
        await p.addTag(id, 'tag-number-$i');
      }
      await p.load();
    });
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('notes button shows count and opens the dialog', (t) async {
    await show(t, clips: ['a', 'b']);
    final a = p.clips.firstWhere((c) => c.content == 'a').id;
    final b = p.clips.firstWhere((c) => c.content == 'b').id;
    await t.runAsync(() async {
      await p.addNote(a, 'n1');
      await p.addNote(a, 'n2');
      await p.load();
    });
    await t.pump();
    expect(find.byTooltip('Notes (2)'), findsOneWidget);
    expect(find.byTooltip('Notes'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(Key('notesButton-$a')),
        matching: find.byIcon(Icons.sticky_note_2),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(Key('notesButton-$b')),
        matching: find.byIcon(Icons.sticky_note_2_outlined),
      ),
      findsOneWidget,
    );
    await t.tap(find.byKey(Key('notesButton-$a')));
    await settle(t);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('noteInput')), findsOneWidget);
    expect(find.text('n1'), findsOneWidget);
  });

  testWidgets(
    'Notes view lists notes with their clip; empty state; tap opens',
    (t) async {
      await show(t, clips: ['a clip']);
      final clipId = p.clips.first.id;
      await tapKey(t, 'view-notes');
      expect(find.text('No notes yet'), findsOneWidget);
      expect(find.byKey(const Key('manualInput')), findsNothing);
      expect(find.byKey(const Key('search')), findsNothing);
      expect(find.byKey(const Key('selectAll')), findsNothing);
      expect(find.byKey(const Key('deleteSelected')), findsNothing);
      await t.runAsync(() => p.addNote(clipId, 'my note'));
      await tapKey(t, 'view-all');
      await tapKey(t, 'view-notes');
      expect(find.text('Notes'), findsWidgets);
      expect(find.text('my note'), findsOneWidget);
      expect(find.text('a clip'), findsOneWidget);
      await t.tap(find.text('my note'));
      await settle(t);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('noteInput')), findsOneWidget);
    },
  );

  testWidgets('notes button is absent on Trash rows', (t) async {
    await show(t, clips: ['a']);
    final id = p.clips.first.id;
    await t.runAsync(() => p.trashClip(id));
    await tapKey(t, 'view-trash');
    expect(find.byKey(Key('restore-$id')), findsOneWidget);
    expect(find.byKey(Key('notesButton-$id')), findsNothing);
  });

  testWidgets('Notes view masks the preview of a secret clip', (t) async {
    await show(t, clips: ['password123']);
    final id = p.clips.first.id;
    await t.runAsync(() async {
      await p.addTag(id, 'Secret');
      await p.addNote(id, 'my note');
    });
    await tapKey(t, 'view-notes');
    expect(find.text('my note'), findsOneWidget);
    expect(find.text('password123'), findsNothing);
    expect(find.textContaining('\u2022'), findsOneWidget);
  });

  group('quick copy and first-run hint', () {
    String? copied;
    late List<String> nativeCalls;

    void mockChannels(WidgetTester t, {bool native = true}) {
      copied = null;
      nativeCalls = [];
      final m = t.binding.defaultBinaryMessenger;
      m.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      if (native) {
        m.setMockMethodCallHandler(const MethodChannel('clipps/clipboard'), (
          call,
        ) async {
          nativeCalls.add(call.method);
          return null;
        });
      }
      addTearDown(() {
        m.setMockMethodCallHandler(SystemChannels.platform, null);
        m.setMockMethodCallHandler(
          const MethodChannel('clipps/clipboard'),
          null,
        );
      });
    }

    testWidgets('enter copies the top clip and hides the window', (t) async {
      mockChannels(t);
      await show(t, clips: ['older', 'newest full text']);
      await t.enterText(find.byKey(const Key('search')), '');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settle(t);
      expect(copied, 'newest full text');
      expect(nativeCalls, ['hideWindow']);
    });

    testWidgets('enter with no results does nothing', (t) async {
      mockChannels(t);
      await show(t, clips: ['abc']);
      await t.enterText(find.byKey(const Key('search')), 'zzz');
      await settle(t);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settle(t);
      expect(copied, isNull);
      expect(nativeCalls, isEmpty);
    });

    testWidgets('enter copies even without a native hide handler', (t) async {
      mockChannels(t, native: false);
      await show(t, clips: ['x']);
      await t.enterText(find.byKey(const Key('search')), '');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settle(t);
      expect(t.takeException(), isNull);
      expect(copied, 'x');
    });

    testWidgets('enter right after typing copies the new top match', (t) async {
      mockChannels(t);
      await show(t, clips: ['older apple', 'newest banana']);
      await t.enterText(find.byKey(const Key('search')), 'apple');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settle(t);
      expect(copied, 'older apple');
      expect(nativeCalls, ['hideWindow']);
    });

    testWidgets('enter in Trash neither copies nor hides', (t) async {
      mockChannels(t);
      await show(t, clips: ['a']);
      await t.runAsync(() => p.trashClip(p.clips.first.id));
      await openView(t, 'view-trash');
      await t.tap(find.byKey(const Key('search')));
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settle(t);
      expect(copied, isNull);
      expect(nativeCalls, isEmpty);
    });

    testWidgets('escape still hides after the search box loses focus', (
      t,
    ) async {
      mockChannels(t);
      await show(t);
      await t.pump();
      await t.tap(find.byKey(const Key('search')));
      await t.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(t);
      expect(nativeCalls, ['hideWindow']);
    });

    testWidgets('escape hides the window', (t) async {
      mockChannels(t);
      await show(t);
      await t.pump(); // autofocus lands after the first frame
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(t);
      expect(nativeCalls, ['hideWindow']);
    });

    testWidgets('empty history explains how to start', (t) async {
      await show(t);
      expect(find.text('No clips yet'), findsOneWidget);
      expect(
        find.text(
          'Copy any text and it appears here. '
          'Press Ctrl+Alt+. to open Clipps from anywhere.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('hint drops the shortcut when it is unavailable', (t) async {
      p.markHotkeyUnavailable();
      await show(t);
      expect(find.text('Copy any text and it appears here.'), findsOneWidget);
    });
  });

  testWidgets('rows with repeated text show Duplicate', (t) async {
    await show(t, clips: ['same', 'x', 'same']);
    expect(find.text('Duplicate'), findsNWidgets(2));
  });
}
