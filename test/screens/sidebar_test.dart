import 'package:clipps/database/db_helper.dart';
import 'package:clipps/providers/clipboard_provider.dart';
import 'package:clipps/screens/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('sidebar theme control changes the mode and saves it', (t) async {
    final db = await DbHelper.open(
      databaseFactoryFfiNoIsolate,
      inMemoryDatabasePath,
    );
    addTearDown(db.close);
    final p = ClipboardProvider(db);
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: p,
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(height: 700, child: Sidebar())),
        ),
      ),
    );
    await t.tap(find.byTooltip('Light'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump();
    expect(p.themeMode, ThemeMode.light);
    expect(await t.runAsync(() => db.getSetting('theme')), 'light');
  });

  testWidgets('About Clipps shows version, privacy and licenses', (t) async {
    final db = await DbHelper.open(
      databaseFactoryFfiNoIsolate,
      inMemoryDatabasePath,
    );
    addTearDown(db.close);
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: ClipboardProvider(db),
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(height: 700, child: Sidebar())),
        ),
      ),
    );
    await t.tap(find.byKey(const Key('aboutClipps')));
    await t.pumpAndSettle();
    expect(find.text('Clipps'), findsWidgets);
    expect(find.text('3.3.0'), findsOneWidget);
    expect(find.textContaining('never sent anywhere'), findsOneWidget);
    expect(find.byKey(const Key('openDataFolder')), findsOneWidget);
    expect(find.text('View licenses'), findsOneWidget);
  });
}
