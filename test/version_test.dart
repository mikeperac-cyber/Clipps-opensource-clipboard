import 'dart:io';

import 'package:clipps/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kAppVersion matches pubspec and installer', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    final iss = File('installer/clipps.iss').readAsStringSync();
    expect(pub, contains('version: $kAppVersion+'));
    expect(iss, contains('#define AppVersion "$kAppVersion"'));
  });
}
