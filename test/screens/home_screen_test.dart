import 'package:clipps/database/db_helper.dart';
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
    await t.tap(find.text('Delete'));
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
    await t.tap(find.byKey(Key('clip-${p.clips.first.id}')));
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

  testWidgets('select two clips, confirm Delete: both gone from list and DB', (
    t,
  ) async {
    await show(t, clips: ['a', 'b', 'c']);
    final ids = p.clips.map((c) => c.id).toList(); // c, b, a
    await t.tap(find.byKey(Key('select-${ids[0]}')));
    await t.tap(find.byKey(Key('select-${ids[1]}')));
    await t.pump();
    await t.tap(find.byKey(const Key('deleteSelected')));
    await t.pumpAndSettle();
    expect(find.text('Delete 2 clip(s)?'), findsOneWidget);
    expect(find.text('This permanently removes them.'), findsOneWidget);
    await confirmDelete(t);
    expect(find.byKey(Key('clip-${ids[0]}')), findsNothing);
    expect(find.byKey(Key('clip-${ids[1]}')), findsNothing);
    expect(find.byKey(Key('clip-${ids[2]}')), findsOneWidget);
    final left = await t.runAsync(db.getClips);
    expect(left!.map((c) => c.content), ['a']);
  });

  testWidgets('deleteSelected is disabled with nothing selected', (t) async {
    await show(t, clips: ['a']);
    expect(
      t.widget<IconButton>(find.byKey(const Key('deleteSelected'))).onPressed,
      isNull,
    );
  });

  testWidgets('Cancel in delete dialog keeps clips', (t) async {
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
    expect(find.text('Delete 1 clip(s)?'), findsOneWidget);
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
}
