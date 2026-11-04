import 'package:clipps/screens/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 4, 12, 0);

  test('relativeTime', () {
    expect(
      relativeTime(now.subtract(const Duration(seconds: 20)), now),
      'just now',
    );
    expect(relativeTime(now.add(const Duration(minutes: 5)), now), 'just now');
    expect(
      relativeTime(now.subtract(const Duration(minutes: 5)), now),
      '5 min ago',
    );
    expect(relativeTime(DateTime(2026, 11, 4, 9, 0), now), '3 h ago');
    expect(relativeTime(DateTime(2026, 11, 3, 14, 2), now), 'yesterday 14:02');
    expect(relativeTime(DateTime(2026, 10, 30, 8, 5), now), '2026-10-30 08:05');
  });

  test('maskSecret', () {
    expect(maskSecret('sk-AbCdEfGhIj'), 'sk-A••••••••');
    expect(maskSecret('abcd'), '••••••••');
    expect(maskSecret(''), '••••••••');
  });

  test('trashDaysLeft', () {
    expect(
      trashDaysLeft(now.subtract(const Duration(days: 14, hours: 23)), now),
      1,
    );
    expect(trashDaysLeft(now, now), 15);
    expect(trashDaysLeft(now.subtract(const Duration(days: 40)), now), 1);
    expect(trashDaysLeft(now.subtract(const Duration(days: 10)), now), 5);
  });
}
