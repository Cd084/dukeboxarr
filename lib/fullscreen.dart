import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Must run before runApp on desktop.
Future<void> initWindow() async {
  if (_desktop) await windowManager.ensureInitialized();
}

/// Full screen: a borderless full-screen window on desktop; immersive mode
/// (system bars hidden) on Android/iOS.
Future<void> applyFullScreen(bool on) async {
  if (_desktop) {
    await windowManager.setFullScreen(on);
  } else {
    await SystemChrome.setEnabledSystemUIMode(on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }
}
