import 'dart:async';

import 'package:flutter/material.dart';

import '../browse.dart';
import '../plex_client.dart';
import 'theme.dart';

class SettingsScreen extends StatefulWidget {
  /// First-run mode: only the Plex connection, and no back button until done.
  final bool setup;
  const SettingsScreen({super.key, this.setup = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url, _token, _lib;
  String? _connMsg;
  bool _busy = false;
  String? _pinCode;
  Timer? _pinTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context).settings;
    _url = TextEditingController(text: s.plexUrl.isEmpty ? 'http://' : s.plexUrl);
    _token = TextEditingController(text: s.plexToken);
    _lib = TextEditingController(text: s.musicLibrary);
  }

  @override
  void dispose() {
    _pinTimer?.cancel();
    _url.dispose();
    _token.dispose();
    _lib.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final id = AppScope.of(context).settings.clientId;
    try {
      final pin = await PlexClient.createPin(id);
      setState(() => _pinCode = pin.code);
      _pinTimer?.cancel();
      var tries = 0;
      _pinTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
        if (++tries > 150) {
          t.cancel();
          setState(() => _pinCode = null);
          return;
        }
        final token = await PlexClient.checkPin(id, pin.id);
        if (token != null && mounted) {
          t.cancel();
          setState(() {
            _token.text = token;
            _pinCode = null;
            _connMsg = 'Signed in to Plex.';
          });
        }
      });
    } catch (e) {
      setState(() => _connMsg = '$e');
    }
  }

  Future<void> _connect() async {
    final app = AppScope.of(context);
    setState(() {
      _busy = true;
      _connMsg = 'Testing connection…';
    });
    try {
      final sections = await PlexClient(_url.text.trim(), _token.text.trim(), app.settings.clientId).musicSections();
      if (sections.isEmpty) throw PlexException('Connected, but no music libraries found');
      if (!sections.containsKey(_lib.text.trim())) {
        _lib.text = sections.keys.first;
      }
      await app.settings.setPlex(_url.text, _token.text, _lib.text);
      app.library.resetClient();
      setState(() => _connMsg = 'Connected. Libraries: ${sections.keys.join(', ')}');
      if (widget.setup) {
        unawaited(app.library.sync());
      }
    } catch (e) {
      setState(() => _connMsg = 'Could not connect: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Jb.cabinetHi,
        toolbarHeight: 72,
        automaticallyImplyLeading: !widget.setup,
        title: Text(widget.setup ? 'Welcome to Dukebox — connect to Plex' : 'Settings',
            style: const TextStyle(color: Jb.neon, fontSize: 26)),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([s, app.library]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _section('PLEX SERVER'),
            Row(children: [
              Expanded(flex: 3, child: _field(_url, 'Server URL', 'http://192.168.1.10:32400')),
              const SizedBox(width: 12),
              Expanded(child: _field(_lib, 'Music library', 'Music')),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _field(_token, 'Plex token', '', obscure: true)),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
                onPressed: _signIn,
                icon: const Icon(Icons.login),
                label: const Text('Sign in with Plex'),
              ),
            ]),
            if (_pinCode != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'On any device, go to  '),
                  const TextSpan(text: 'plex.tv/link', style: TextStyle(color: Jb.neon, fontWeight: FontWeight.bold)),
                  const TextSpan(text: '  and enter  '),
                  TextSpan(
                      text: _pinCode,
                      style: const TextStyle(
                          color: Jb.neon, fontSize: 28, letterSpacing: 4, fontFamilyFallback: Jb.mono)),
                ]), style: const TextStyle(fontSize: 18)),
              ),
            const SizedBox(height: 12),
            Row(children: [
              FilledButton(onPressed: _busy ? null : _connect, child: const Text('SAVE & CONNECT')),
              const SizedBox(width: 16),
              if (_connMsg != null) Expanded(child: Text(_connMsg!, style: const TextStyle(color: Jb.chrome))),
            ]),
            if (!widget.setup || app.library.loading || app.library.entries.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
                  onPressed: app.library.loading ? null : app.library.sync,
                  icon: const Icon(Icons.sync),
                  label: const Text('Re-sync library'),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    app.library.loading
                        ? app.library.status
                        : app.library.error ??
                            '${app.library.songs.length} songs · ${app.library.entries.length} selections'
                                '${app.library.syncedAt == null ? '' : ' · synced ${app.library.syncedAt.toString().substring(0, 16)}'}',
                    style: TextStyle(color: app.library.error != null ? Colors.redAccent : Jb.chrome),
                  ),
                ),
              ]),
            ],
            if (!widget.setup) ...[
              _section('QUEUE'),
              _switch('Allow removing songs from the queue', s.allowDelete, (v) => s.allowDelete = v),
              _switch('Allow skipping the current song', s.allowSkip, (v) => s.allowSkip = v),
              _switch('Random play when the queue is empty', s.randomWhenEmpty, (v) => s.randomWhenEmpty = v,
                  sub: 'Picks songs matching the genres of recently played tracks'),
              _section('DISPLAY'),
              _stepper('Album cards per screen', s.cardsPerPage, 2, 6, (v) => s.cardsPerPage = v),
              _section('CATALOGUE NUMBERING'),
              _stepper('Releases with fewer tracks than this count as singles', s.albumMinTracks, 2, 8,
                  (v) => s.albumMinTracks = v, rebuild: true),
              _stepper('Artists with this many singles get their own card', s.artistSinglesMin, 1, 10,
                  (v) => s.artistSinglesMin = v, rebuild: true),
              _stepper('Songs per shared "Singles" card', s.mixedSinglesSize, 10, 40,
                  (v) => s.mixedSinglesSize = v, step: 5, rebuild: true),
              const SizedBox(height: 8),
              Row(children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
                  onPressed: () => _confirmRenumber(context),
                  child: const Text('Renumber all albums'),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                      'Numbers normally stay fixed as your library grows. Renumbering puts them back in A–Z order.',
                      style: TextStyle(color: Jb.chrome)),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRenumber(BuildContext context) async {
    final app = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Renumber all albums?'),
        content: const Text('Every album gets a new number, so any printed or remembered codes will change.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Renumber')),
        ],
      ),
    );
    if (ok == true) await app.library.rebuildCatalog(renumber: true);
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 8),
        child: Text(t, style: const TextStyle(color: Jb.neon, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 3)),
      );

  Widget _field(TextEditingController c, String label, String hint, {bool obscure = false}) => TextField(
        controller: c,
        obscureText: obscure,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
      );

  Widget _switch(String title, bool v, ValueChanged<bool> on, {String? sub}) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontSize: 18)),
        subtitle: sub == null ? null : Text(sub, style: const TextStyle(color: Jb.chrome)),
        value: v,
        onChanged: on,
      );

  Widget _stepper(String title, int v, int min, int max, ValueChanged<int> on,
      {int step = 1, bool rebuild = false}) {
    void set(int n) {
      on(n);
      if (rebuild) AppScope.of(context).library.rebuildCatalog();
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontSize: 18)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(iconSize: 32, onPressed: v - step >= min ? () => set(v - step) : null, icon: const Icon(Icons.remove_circle_outline)),
        SizedBox(width: 44, child: Text('$v', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22))),
        IconButton(iconSize: 32, onPressed: v + step <= max ? () => set(v + step) : null, icon: const Icon(Icons.add_circle_outline)),
      ]),
    );
  }
}
