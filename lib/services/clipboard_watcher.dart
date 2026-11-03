import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Forwards OS clipboard text changes (signalled by the native runner) to [onText].
class ClipboardWatcher {
  ClipboardWatcher({
    required this.onText,
    Future<String?> Function()? readText,
    this.channel = const MethodChannel('clipps/clipboard'),
  }) : _readText = readText ?? _readPlainText;

  final Future<void> Function(String text) onText;
  final Future<String?> Function() _readText;
  final MethodChannel channel;

  static const _maxReadAttempts = 5;

  static Future<String?> _readPlainText() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  void start() => channel.setMethodCallHandler(_onCall);

  void stop() => channel.setMethodCallHandler(null);

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'clipboardChanged') return;
    // The writing app often still holds the clipboard lock when the change
    // notification arrives, so retry briefly before giving up.
    for (var attempt = 1; attempt <= _maxReadAttempts; attempt++) {
      try {
        final text = await _readText();
        if (text != null) await onText(text);
        return;
      } on PlatformException catch (e) {
        debugPrint('Clipboard read failed (attempt $attempt): $e');
        if (attempt < _maxReadAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    }
  }
}
