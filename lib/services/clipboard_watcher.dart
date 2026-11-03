import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/clip_source.dart';

/// Forwards OS clipboard text changes (signalled by the native runner) to [onText].
class ClipboardWatcher {
  ClipboardWatcher({
    required this.onText,
    this.onFocusSearch,
    this.onHotkeyUnavailable,
    Future<String?> Function()? readText,
    this.channel = const MethodChannel('clipps/clipboard'),
  }) : _readText = readText ?? _readPlainText;

  final Future<void> Function(String text, ClipSource source) onText;
  final VoidCallback? onFocusSearch;
  final VoidCallback? onHotkeyUnavailable;
  final Future<String?> Function() _readText;
  final MethodChannel channel;

  static const _maxReadAttempts = 5;

  static Future<String?> _readPlainText() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  static String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

  static ClipSource _sourceOf(Object? args) => args is Map
      ? ClipSource(
          app: _str(args['sourceApp']),
          title: _str(args['sourceTitle']),
        )
      : const ClipSource();

  void start() => channel.setMethodCallHandler(_onCall);

  void stop() => channel.setMethodCallHandler(null);

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'focusSearch':
        onFocusSearch?.call();
        return;
      case 'hotkeyUnavailable':
        onHotkeyUnavailable?.call();
        return;
      case 'clipboardChanged':
        break;
      default:
        return;
    }
    // The writing app often still holds the clipboard lock when the change
    // notification arrives, so retry briefly before giving up.
    try {
      for (var attempt = 1; attempt <= _maxReadAttempts; attempt++) {
        String? text;
        try {
          text = await _readText();
        } on PlatformException catch (e) {
          debugPrint('Clipboard read failed (attempt $attempt): $e');
          if (attempt < _maxReadAttempts) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          continue;
        }
        if (text != null) await onText(text, _sourceOf(call.arguments));
        return;
      }
    } catch (e, s) {
      // Native drops error replies, so surface failures here instead.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: s,
          library: 'clipps',
          context: ErrorDescription('while capturing a clipboard change'),
        ),
      );
    }
  }
}
