import 'dart:convert';

import 'package:clipps/services/auto_tagger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = <String, List<String>>{
    'see https://example.com/a?b=1': ['Link'],
    'mail me at jane.doe@example.co.uk': ['Email'],
    '+1 (555) 010-2345': ['Phone'],
    '1,234.56': ['Number'],
    '-42': ['Number'],
    'const a = 1;\nconst b = 2;': ['Code'],
    'def run():\n    pass': ['Code'],
    'sk-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789': ['Secret'], // fake
    'ghp_16C7e42F292c6912E7710c838347Ae178B4a': ['Secret'],
    'AKIAIOSFODNN7EXAMPLE': ['Secret'],
    'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig': ['Secret'],
    'aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY': ['Secret'],
    'https://chromewebstore.google.com/detail/ldnheaepmnmbjjjahokphckbpgciiaed?utm_source=item-share-cb':
        ['Link'],
    'e83c5163316f89bfbde7d9ab23ca2e25604af290': [],
    'If I were paying for a lot of AI software, I would not try.': [],
    '': [],
    // extra: order and edge rules
    'a@b.co https://x.io': ['Link', 'Email'],
    '1234567': ['Phone'],
    'foo();\nbar()': ['Code'],
    'one line;': [],
  };
  cases.forEach(
    (input, want) => test(
      'detectTags(${jsonEncode(input)})',
      () => expect(detectTags(input), want),
    ),
  );

  group('long inputs stay linear', () {
    final inputs = {
      'a x 1M': 'a' * 1000000,
      'a x 500k @ b x 500k': '${'a' * 500000}@${'b' * 500000}',
      'digits x 1M': '1' * 1000000,
      'ones x 5M': '1' * 5000000,
      'dashes x 5M': '-' * 5000000,
      '1 x 5M': '1 ' * 2500000,
      'eyJ + a x 5M': 'eyJ${'a' * 5000000}',
    };
    inputs.forEach((name, text) {
      test(name, () {
        final sw = Stopwatch()..start();
        final tags = detectTags(text);
        sw.stop();
        expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
        if (name == 'a x 1M') expect(tags, isNot(contains('Email')));
      });
    });
  });
}
