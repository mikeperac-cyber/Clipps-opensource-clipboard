import '../providers/clipboard_provider.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
String dayString(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';

String relativeTime(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'just now'; // includes future times
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  final today = DateTime(now.year, now.month, now.day);
  if (!t.isBefore(today)) return '${d.inHours} h ago';
  if (!t.isBefore(DateTime(now.year, now.month, now.day - 1))) {
    return 'yesterday ${_hm(t)}';
  }
  return '${dayString(t)} ${_hm(t)}';
}

String maskSecret(String text) =>
    '${text.length <= 4 ? '' : text.substring(0, 4)}••••••••';

int trashDaysLeft(DateTime deletedAt, DateTime now) {
  final left = deletedAt.add(kTrashRetention).difference(now);
  final days = (left.inMinutes / Duration.minutesPerDay).ceil();
  return days < 1 ? 1 : days;
}
