import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One discrete pulse per page, never continuous vibration during scrolling.
class ReaderHaptics {
  static const channel = MethodChannel('forum.iqro.app/reader_haptics');

  static Future<void> pageChanged({required bool enabled}) async {
    if (!enabled) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await channel.invokeMethod<String>('pageTick');
        return;
      } on MissingPluginException {
        // Older native shells and test hosts have no custom channel.
      } on PlatformException {
        // A denied or unavailable motor must not interrupt reading.
      }
    }
    try {
      await HapticFeedback.lightImpact();
    } on PlatformException {
      // Haptics are best effort; page navigation remains functional.
    }
  }
}
