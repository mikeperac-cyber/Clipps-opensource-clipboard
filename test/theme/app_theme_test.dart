import 'dart:math';

import 'package:clipps/database/db_helper.dart';
import 'package:clipps/main.dart';
import 'package:clipps/providers/clipboard_provider.dart';
import 'package:clipps/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// WCAG 2.x relative luminance and contrast ratio.
double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final l1 = _lum(a), l2 = _lum(b);
  return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05);
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('text contrast is at least 4.5 in both themes', () {
    for (final b in Brightness.values) {
      final s = appTheme(b).colorScheme;
      final pairs = {
        'onSurface/surface': contrast(s.onSurface, s.surface),
        'onSurfaceVariant/surface': contrast(s.onSurfaceVariant, s.surface),
        'onSurface/surfaceContainerHighest': contrast(
          s.onSurface,
          s.surfaceContainerHighest,
        ),
      };
      pairs.forEach((name, ratio) {
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '$b $name');
      });
    }
  });

  testWidgets('ClippsApp uses light theme when Light is chosen', (t) async {
    final db = await DbHelper.open(
      databaseFactoryFfiNoIsolate,
      inMemoryDatabasePath,
    );
    addTearDown(db.close);
    final p = ClipboardProvider(db);
    await t.runAsync(() => p.setThemeMode(ThemeMode.light));
    await t.pumpWidget(
      ChangeNotifierProvider.value(value: p, child: const ClippsApp()),
    );
    expect(
      t.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
  });
}
