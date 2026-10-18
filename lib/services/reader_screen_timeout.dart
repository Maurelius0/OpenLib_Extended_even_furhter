import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native interaction tracking also sees touches inside the EPUB platform view.
abstract final class ReaderScreenTimeout {
  static const channel = MethodChannel('openlib/reader_screen_timeout');

  static Future<void> setReading(bool reading) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod<void>('setReading', reading);
    } on PlatformException catch (error) {
      debugPrint('Could not update reader screen timeout: $error');
    } on MissingPluginException catch (error) {
      debugPrint('Reader screen timeout unavailable: $error');
    }
  }
}
