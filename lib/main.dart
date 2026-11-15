import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'browse.dart';
import 'fullscreen.dart';
import 'jukebox.dart';
import 'library.dart';
import 'media_session.dart';
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
  } else if (Platform.isIOS) {
    // iOS 16+ reports a generic name like "iPad" unless the app has a special entitlement.
    final i = await DeviceInfoPlugin().iosInfo;
    PlexClient.deviceLabel = i.name.isNotEmpty ? i.name : i.model;
  }

  final settings = await Settings.load();
  final library = Library(settings);
  final jukebox = Jukebox(library, settings, LocalOutput());
  final browse = Browse(library);
  if (settings.isConfigured) library.init();
  library.startAutoSync();
  if (settings.outputId.isNotEmpty) jukebox.applyOutputSetting();

  // Phones/tablets: a media session keeps playback going with the screen
  // locked (Android media service) and adds lock-screen controls.
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await AudioService.init(
        builder: () => JukeboxAudioHandler(jukebox, settings),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'ca.dukebox.dukebox.playback',
          androidNotificationChannelName: 'DukeBoxarr playback',
          // Stay a foreground service while paused too, so Android never cuts the
          // network mid-queue. (Ongoing notifications require stop-on-pause.)
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
        ),
      );
    } catch (e) {
      debugPrint('media session unavailable: $e');
    }
  }

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
