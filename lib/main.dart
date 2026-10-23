import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'browse.dart';
import 'fullscreen.dart';
import 'jukebox.dart';
import 'library.dart';
import 'output.dart';
import 'plex_client.dart';
import 'settings.dart';
import 'ui/home.dart';
import 'ui/settings_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await initWindow();
  PlexClient.appVersion = (await PackageInfo.fromPlatform()).version;
  if (Platform.isAndroid) {
    final a = await DeviceInfoPlugin().androidInfo;
    PlexClient.deviceLabel = a.model.toLowerCase().startsWith(a.manufacturer.toLowerCase())
        ? a.model
        : '${a.manufacturer} ${a.model}';
  }

  final settings = await Settings.load();
  final library = Library(settings);
  final jukebox = Jukebox(library, settings, LocalOutput());
  final browse = Browse(library);
  if (settings.isConfigured) library.init();
  library.startAutoSync();
  if (settings.outputId.isNotEmpty) jukebox.applyOutputSetting();

  // Full screen from the start if set, and whenever the setting changes.
  var fullScreen = settings.fullScreen;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (fullScreen) applyFullScreen(true);
  });
  settings.addListener(() {
    if (settings.fullScreen != fullScreen) applyFullScreen(fullScreen = settings.fullScreen);
  });

  // Keep the screen awake while the jukebox is open (setting, default on).
  var keepOn = settings.keepScreenOn;
  WakelockPlus.toggle(enable: keepOn);
  settings.addListener(() {
    if (settings.keepScreenOn != keepOn) WakelockPlus.toggle(enable: keepOn = settings.keepScreenOn);
  });

  runApp(AppScope(
    settings: settings,
    library: library,
    jukebox: jukebox,
    browse: browse,
    child: const DukeBoxarrApp(),
  ));
}

class DukeBoxarrApp extends StatelessWidget {
  const DukeBoxarrApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return MaterialApp(
      title: 'DukeBoxarr',
      debugShowCheckedModeBanner: false,
      theme: Jb.theme(),
      home: ListenableBuilder(
        listenable: app.settings,
        builder: (context, _) =>
            app.settings.isConfigured ? const HomeScreen() : const SettingsScreen(setup: true),
      ),
    );
  }
}
