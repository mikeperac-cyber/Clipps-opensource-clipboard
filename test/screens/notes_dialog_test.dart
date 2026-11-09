import 'package:clipps/database/db_helper.dart';
import 'package:clipps/providers/clipboard_provider.dart';
import 'package:clipps/screens/notes_dialog.dart';
import 'package:flutter/material.dart';
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

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> open(WidgetTester t, String clipText) async {
    await t.runAsync(() async {
      await p.addClip(clipText);
      await p.load();
    });
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: p,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                key: const Key('open'),
                onPressed: () => showNotesDialog(c, p.clips.first),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byKey(const Key('open')));
    await settle(t);
  }

  testWidgets('add, edit and delete a note; delete asks first', (t) async {
    await open(t, 'clip');
    await t.enterText(find.byKey(const Key('noteInput')), 'first');
    await t.pump();
    await t.tap(find.byKey(const Key('addNote')));
    await settle(t);
    expect(find.text('first'), findsOneWidget);
    final id = (await t.runAsync(() => p.notesFor(p.clips.first.id)))!
        .single
        .id;

    await t.tap(find.byKey(Key('editNote-$id')));
    await t.pump();
    await t.enterText(find.byKey(Key('noteEdit-$id')), 'second');
    await t.tap(find.byKey(Key('saveNote-$id')));
    await settle(t);
    expect(find.text('second'), findsOneWidget);
    expect(find.textContaining('edited'), findsOneWidget);

    await t.tap(find.byKey(Key('deleteNote-$id')));
    await t.pumpAndSettle();
    expect(find.text('Delete this note?'), findsOneWidget);
    expect(find.text("This can't be undone."), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);

    await t.tap(find.byKey(Key('deleteNote-$id')));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await settle(t);
    expect(find.text('second'), findsNothing);
    expect(await t.runAsync(() => p.notesFor(p.clips.first.id)), isEmpty);
  });

  testWidgets('blank note cannot be added; over-limit shows the copy', (
    t,
  ) async {
    await open(t, 'clip');
    expect(
      t.widget<FilledButton>(find.byKey(const Key('addNote'))).onPressed,
      isNull,
    );
    await t.enterText(find.byKey(const Key('noteInput')), 'x' * 20001);
    await t.pump();
    await t.tap(find.byKey(const Key('addNote')));
    await settle(t);
    expect(find.text('Notes are limited to 20,000 characters'), findsOneWidget);
    expect(find.textContaining('xxxx'), findsOneWidget); // text kept
  });

  testWidgets('dialog shows the full clip text', (t) async {
    final long = List.generate(50, (i) => 'line $i').join('\n');
    await open(t, long);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(t.widget<SelectableText>(find.byType(SelectableText)).data, long);
  });
}
