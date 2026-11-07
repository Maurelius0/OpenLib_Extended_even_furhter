import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Synchronizes the real Android status bar with the reader's controls.
///
/// This uses native WindowInsetsController on modern Android, since Flutter's
/// legacy fullscreen SystemUiModes are ignored under enforced edge-to-edge.
abstract final class ReaderSystemBars {
  static const channel = MethodChannel('openlib/reader_system_bars');

  static Future<void> setReaderActive(bool active) =>
      _invoke('setReaderActive', active);

  static Future<void> setControlsVisible(bool visible) =>
      _invoke('setControlsVisible', visible);

  static Future<void> _invoke(String method, bool value) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod<void>(method, value);
    } on PlatformException catch (error) {
      debugPrint('Could not update reader status bar: $error');
    } on MissingPluginException catch (error) {
      debugPrint('Reader status bar control unavailable: $error');
    }
  }
}
