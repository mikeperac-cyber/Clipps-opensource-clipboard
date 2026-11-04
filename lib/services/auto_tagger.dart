const kAutoTags = ['Link', 'Email', 'Phone', 'Number', 'Code', 'Secret'];

// Email and Code look only at this prefix, to keep MB-sized clips fast.
const _scanLimit = 65536;

final _link = RegExp(r'https?://\S');
final _email = RegExp(r'[\w.+-]{1,64}@[\w-]{1,63}(\.[\w-]{1,63})+');
// Negated classes, searched: `+` loops overflow the regex stack on MB-sized text.
final _notPhone = RegExp(r'[^\d\s().-]');
final _notNumber = RegExp(r'[^\d.,\s]');
final _codeLine = RegExp(
  r'^\s*(def |function |class |import |#include|const |let |var |public |private )',
);
// Cheap literal pre-check: the regex alone costs ~300ms on a 4 MB clip.
const _keyHints = [
  'sk-',
  'sk_live_',
  'ghp_',
  'gho_',
  'github_pat_',
  'xoxb-',
  'xoxp-',
  'AKIA',
  'AIza',
  'eyJ',
];

final _keyPrefix = RegExp(
  r'(?<![\w-])(sk-|sk_live_|ghp_|gho_|github_pat_|xoxb-|xoxp-)\S'
  r'|(?<![\w-])AKIA[A-Z0-9]{16}'
  r'|(?<![\w-])AIza[\w-]{35}'
  r'|(?<![\w-])eyJ[\w-]{1,4096}\.eyJ[\w-]{1,4096}\.',
);
// Negated class, searched: a quantified loop overflows the regex stack on MB-sized text.
final _notToken = RegExp(r'[^A-Za-z0-9_+/=-]');

int _digits(String s) => RegExp(r'\d').allMatches(s).length;

/// Local, offline tags for a clip, in [kAutoTags] order. Tags are best-effort:
/// any failure (even a regex stack overflow) yields no tags, never an error.
List<String> detectTags(String text) {
  try {
    return _detect(text);
  } catch (_) {
    return const [];
  }
}

List<String> _detect(String text) {
  final t = text.trim();
  final link = _link.hasMatch(t);
  final phone =
      t.length <= 40 &&
      t.isNotEmpty &&
      !_notPhone.hasMatch(t.startsWith('+') ? t.substring(1) : t) &&
      _digits(t) >= 7 &&
      _digits(t) <= 15;
  final numBody = t.startsWith('+') || t.startsWith('-') ? t.substring(1) : t;
  final number =
      numBody.isNotEmpty && !_notNumber.hasMatch(numBody) && _digits(t) > 0;
  final head = t.length > _scanLimit ? t.substring(0, _scanLimit) : t;
  final lines = head.split('\n');
  final code =
      lines.length >= 2 &&
      (lines.where((l) => RegExp(r'[;{})]$').hasMatch(l.trimRight())).length >=
              2 ||
          lines.any(_codeLine.hasMatch));
  final secret =
      (_keyHints.any(t.contains) && _keyPrefix.hasMatch(t)) ||
      (!link &&
          t.length >= 32 &&
          !_notToken.hasMatch(t) &&
          t.contains(RegExp(r'[A-Z]')) &&
          t.contains(RegExp(r'[a-z]')) &&
          t.contains(RegExp(r'\d')));
  return [
    if (link) 'Link',
    if (head.contains('@') && _email.hasMatch(head)) 'Email',
    if (phone) 'Phone',
    if (!phone && number) 'Number',
    if (code) 'Code',
    if (secret) 'Secret',
  ];
}
