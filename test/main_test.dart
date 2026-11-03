import 'dart:io';

import 'package:clipps/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows an error screen when the database cannot be opened', (
    t,
  ) async {
    final dir = Directory.systemTemp.createTempSync('clipps_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    // A directory is not a valid database file, so open fails.
    final app = await t.runAsync(() => buildApp(dir.path));
    await t.pumpWidget(app!);

    expect(
      find.textContaining('Clipps could not open its clip history.\n'),
      findsOneWidget,
    );
  });
}
