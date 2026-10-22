import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'browse.dart';
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
  PlexClient.appVersion = (await PackageInfo.fromPlatform()).version;

  final settings = await Settings.load();
  final library = Library(settings);
  final jukebox = Jukebox(library, settings, LocalOutput());
  final browse = Browse(library);
  if (settings.isConfigured) library.init();
  library.startAutoSync();
  if (settings.outputId.isNotEmpty) jukebox.applyOutputSetting();

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
