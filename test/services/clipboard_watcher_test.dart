import 'package:clipps/models/clip_source.dart';
import 'package:clipps/services/clipboard_watcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _native(String method, [Object? args]) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'clipps/clipboard',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (_) {},
        );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> received;
  late List<ClipSource> sources;
  late ClipboardWatcher watcher;

  ClipboardWatcher make(Future<String?> Function() readText) =>
      ClipboardWatcher(
        onText: (t, s) async {
          received.add(t);
          sources.add(s);
        },
        readText: readText,
      )..start();

  setUp(() {
    received = [];
    sources = [];
  });
  tearDown(() => watcher.stop());

  test('clipboardChanged reads text and passes it to onText', () async {
    watcher = make(() async => 'hello');
    await _native('clipboardChanged');
    expect(received, ['hello']);
  });

  test('clipboardChanged passes the source map through', () async {
    watcher = make(() async => 'hello');
    await _native('clipboardChanged', {'sourceApp': 'A', 'sourceTitle': 'T'});
    expect(received, ['hello']);
    expect(sources, [const ClipSource(app: 'A', title: 'T')]);
  });

  test('missing or null argument means no source', () async {
    watcher = make(() async => 'hello');
    await _native('clipboardChanged');
    expect(sources, [const ClipSource()]);
  });

  test('empty strings become null', () async {
    watcher = make(() async => 'hello');
    await _native('clipboardChanged', {'sourceApp': '', 'sourceTitle': ''});
    expect(sources, [const ClipSource()]);
  });

  test('null clipboard text (image/files) is ignored', () async {
    watcher = make(() async => null);
    await _native('clipboardChanged');
    expect(received, isEmpty);
  });

  test(
    'readText throwing PlatformException is ignored and later events work',
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
    },
  );

  test('onText throwing is reported and later events still work', () async {
    final reported = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = old);
    var first = true;
    watcher = ClipboardWatcher(
      onText: (t, _) async {
        if (first) {
          first = false;
          throw StateError('db down');
        }
        received.add(t);
      },
      readText: () async => 'x',
    )..start();
    await _native('clipboardChanged');
    expect(reported, hasLength(1));
    expect(received, isEmpty);
    await _native('clipboardChanged');
    expect(received, ['x']);
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

  test('focusSearch calls onFocusSearch', () async {
    var n = 0;
    watcher = ClipboardWatcher(
      onText: (t, s) async {},
      onFocusSearch: () => n++,
    )..start();
    await _native('focusSearch');
    expect(n, 1);
  });

  test('hotkeyUnavailable calls onHotkeyUnavailable', () async {
    var n = 0;
    watcher = ClipboardWatcher(
      onText: (t, s) async {},
      onHotkeyUnavailable: () => n++,
    )..start();
    await _native('hotkeyUnavailable');
    expect(n, 1);
  });

  test('focusSearch without a callback is ignored', () async {
    watcher = make(() async => 'x');
    await _native('focusSearch');
    expect(received, isEmpty);
  });
}
