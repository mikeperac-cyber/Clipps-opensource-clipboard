import 'dart:io';

import 'package:clipps/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('text copied to the OS clipboard appears in history', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('clipps_it');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // DB file may still be locked on Windows.
      }
    });
    await startApp(p.join(dir.path, 'clips.db'));
    final marker = 'clipps-it-${DateTime.now().microsecondsSinceEpoch}';
    // Goes through the real OS clipboard and WM_CLIPBOARDUPDATE.
    await Clipboard.setData(ClipboardData(text: marker));
    for (var i = 0; i < 50 && find.text(marker).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(marker), findsOneWidget);
    // A copy made by the app itself is owned by Clipps.
    expect(find.textContaining('· Clipps'), findsOneWidget);
  });
}
