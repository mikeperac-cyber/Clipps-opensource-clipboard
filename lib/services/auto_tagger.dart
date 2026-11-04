const kAutoTags = ['Link', 'Email', 'Phone', 'Number', 'Code', 'Secret'];

final _link = RegExp(r'https?://\S');
final _email = RegExp(r'[\w.+-]{1,64}@[\w-]{1,63}(\.[\w-]{1,63})+');
final _phone = RegExp(r'^\+?[\d\s().-]+$');
final _number = RegExp(r'^[+-]?[\d.,\s]+$');
final _codeLine = RegExp(
  r'^\s*(def |function |class |import |#include|const |let |var |public |private )',
);
final _keyPrefix = RegExp(
  r'(?<![\w-])(sk-|sk_live_|ghp_|gho_|github_pat_|xoxb-|xoxp-)\S'
  r'|(?<![\w-])AKIA[A-Z0-9]{16}'
  r'|(?<![\w-])AIza[\w-]{35}'
  r'|(?<![\w-])eyJ[\w-]+\.eyJ[\w-]+\.',
);
final _token = RegExp(r'^[A-Za-z0-9_+/=-]{32,}$');

int _digits(String s) => RegExp(r'\d').allMatches(s).length;

/// Local, offline tags for a clip, in [kAutoTags] order.
List<String> detectTags(String text) {
  final t = text.trim();
  final link = _link.hasMatch(t);
  final phone = _phone.hasMatch(t) && _digits(t) >= 7 && _digits(t) <= 15;
  final lines = t.split('\n');
  final code =
      lines.length >= 2 &&
      (lines.where((l) => RegExp(r'[;{})]$').hasMatch(l.trimRight())).length >=
              2 ||
          lines.any(_codeLine.hasMatch));
  final secret =
      _keyPrefix.hasMatch(t) ||
      (!link &&
          _token.hasMatch(t) &&
          t.contains(RegExp(r'[A-Z]')) &&
          t.contains(RegExp(r'[a-z]')) &&
          t.contains(RegExp(r'\d')));
  return [
    if (link) 'Link',
    if (t.contains('@') && _email.hasMatch(t)) 'Email',
    if (phone) 'Phone',
    if (!phone && _number.hasMatch(t) && _digits(t) > 0) 'Number',
    if (code) 'Code',
    if (secret) 'Secret',
  ];
}
