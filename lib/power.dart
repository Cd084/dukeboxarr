import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android power handling for playback with the screen off
/// (see PlaybackLocks in MainActivity.kt). No-ops on other platforms.
abstract final class Power {
  static const _channel = MethodChannel('ca.dukebox/power');

  static bool get supported => Platform.isAndroid;

  /// Hold a wake lock + Wi-Fi lock while music is playing, release otherwise.
  static Future<void> holdForPlayback(bool on) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('hold', on);
    } catch (e) {
      debugPrint('playback locks unavailable: $e');
    }
  }

  /// Whether Android exempts DukeBoxarr from battery optimization
  /// ("Unrestricted"). Null if unknown.
  static Future<bool?> unrestricted() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
    } catch (_) {
      return null;
    }
  }

  /// Opens Android's prompt to stop restricting DukeBoxarr's battery use.
  static Future<void> askUnrestricted() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      debugPrint('battery prompt unavailable: $e');
    }
  }
}
