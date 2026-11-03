import 'package:clipps/services/clipboard_watcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _native(String method) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'clipps/clipboard',
      const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
      (_) {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> received;
  late ClipboardWatcher watcher;

  ClipboardWatcher make(Future<String?> Function() readText) =>
      ClipboardWatcher(
        onText: (t) async => received.add(t),
        readText: readText,
      )..start();

  setUp(() => received = []);
  tearDown(() => watcher.stop());

  test('clipboardChanged reads text and passes it to onText', () async {
    watcher = make(() async => 'hello');
    await _native('clipboardChanged');
    expect(received, ['hello']);
  });

  test('null clipboard text (image/files) is ignored', () async {
    watcher = make(() async => null);
    await _native('clipboardChanged');
    expect(received, isEmpty);
  });

  test('readText throwing PlatformException is ignored and later events work',
      () async {
    var fail = true;
    watcher = make(() async {
      if (fail) throw PlatformException(code: 'busy');
      return 'ok';
    });
    await _native('clipboardChanged');
    expect(received, isEmpty);
    fail = false;
    await _native('clipboardChanged');
    expect(received, ['ok']);
  });

  test('a transiently locked clipboard is retried', () async {
    var calls = 0;
    watcher = make(() async {
      if (calls++ < 2) throw PlatformException(code: 'busy');
      return 'ok';
    });
    await _native('clipboardChanged');
    expect(received, ['ok']);
  });

  test('unknown method names are ignored', () async {
    watcher = make(() async => 'x');
    await _native('somethingElse');
    expect(received, isEmpty);
  });

  test('no callbacks after stop()', () async {
    watcher = make(() async => 'x');
    watcher.stop();
    await _native('clipboardChanged');
    expect(received, isEmpty);
  });
}
