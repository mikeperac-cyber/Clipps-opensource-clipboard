import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database/db_helper.dart';
import 'providers/clipboard_provider.dart';
import 'screens/home_screen.dart';

class ClippsApp extends StatelessWidget {
  const ClippsApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(title: 'Clipps', home: HomeScreen());
}

Future<void> startApp(String dbPath) async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final db = await DbHelper.open(databaseFactoryFfi, dbPath);
  final provider = ClipboardProvider(db);
  await provider.load();
  runApp(
    ChangeNotifierProvider.value(value: provider, child: const ClippsApp()),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  await startApp(p.join(dir.path, 'clipps.db'));
}
