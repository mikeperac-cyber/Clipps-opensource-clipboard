import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database/db_helper.dart';
import 'providers/clipboard_provider.dart';
import 'screens/home_screen.dart';
import 'services/clipboard_watcher.dart';

class ClippsApp extends StatelessWidget {
  const ClippsApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(title: 'Clipps', home: HomeScreen());
}

Widget _errorApp(Object error, StackTrace stack) {
  debugPrint('Clipps startup failed: $error\n$stack');
  return MaterialApp(
    title: 'Clipps',
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          'Clipps could not open its clip history.\n$error',
        ),
      ),
    ),
  );
}

/// The app wired to the database at [dbPath], or an error screen if that fails.
Future<Widget> buildApp(String dbPath) async {
  try {
    sqfliteFfiInit();
    final db = await DbHelper.open(databaseFactoryFfi, dbPath);
    final provider = ClipboardProvider(db);
    await provider.load();
    ClipboardWatcher(onText: (t, s) async {
      await provider.addClip(t, source: s);
    }).start();
    return ChangeNotifierProvider.value(
      value: provider,
      child: const ClippsApp(),
    );
  } catch (e, s) {
    return _errorApp(e, s);
  }
}

Future<void> startApp(String dbPath) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await buildApp(dbPath));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final dir = await getApplicationSupportDirectory();
    await startApp(p.join(dir.path, 'clipps.db'));
  } catch (e, s) {
    runApp(_errorApp(e, s));
  }
}
