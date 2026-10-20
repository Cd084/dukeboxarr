import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../browse.dart';
import '../models.dart';
import 'actions.dart';
import 'theme.dart';

/// Opens the selection keypad. [initial] pre-fills digits typed on a
/// physical keyboard before the pad opened.
Future<void> showKeypad(BuildContext context, {String initial = ''}) => showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Keypad(initial: initial),
    );

/// Jukebox selector: 4-digit album number + 2-digit track (e.g. 012305).
class Keypad extends StatefulWidget {
  final String initial;
  const Keypad({super.key, this.initial = ''});

  @override
  State<Keypad> createState() => _KeypadState();
}

class _KeypadState extends State<Keypad> {
  late String digits = widget.initial;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Entry? get _entry => digits.length >= 4
      ? AppScope.of(context).library.byNumber(int.parse(digits.substring(0, 4)))
      : null;

  Song? get _song {
    final e = _entry;
    if (e == null || digits.length < 6) return null;
    final t = int.parse(digits.substring(4, 6));
    return (t >= 1 && t <= e.songs.length) ? e.songs[t - 1] : null;
  }

  void _press(String d) {
    if (digits.length < 6) setState(() => digits += d);
  }

  void _back() {
    if (digits.isNotEmpty) setState(() => digits = digits.substring(0, digits.length - 1));
  }

  void _select() {
    final s = _song;
    if (s == null) return;
    requestSong(context, s);
    setState(() => digits = '');
  }

  void _goTo() {
    final e = _entry;
    if (e == null) return;
    AppScope.of(context).browse.jumpTo(e);
    Navigator.pop(context);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent ev) {
    if (ev is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = ev.character;
    if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      _press(ch);
    } else if (ev.logicalKey == LogicalKeyboardKey.backspace) {
      _back();
    } else if (ev.logicalKey == LogicalKeyboardKey.enter ||
        ev.logicalKey == LogicalKeyboardKey.numpadEnter) {
      digits.length == 6 ? _select() : _goTo();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final e = _entry, s = _song;
    String preview;
    Color previewColor = Jb.chrome;
    if (digits.length < 4) {
      preview = 'Enter album number, then track';
    } else if (e == null) {
      preview = 'No album ${digits.substring(0, 4)}';
      previewColor = Colors.redAccent;
    } else if (digits.length < 6) {
      preview = '${e.artist} — ${e.title}  (${e.songs.length} tracks)';
    } else if (s == null) {
      preview = 'Track ${digits.substring(4)} not on ${e.title}';
      previewColor = Colors.redAccent;
    } else {
      preview = '${s.title} — ${s.artist}';
      previewColor = Jb.neon;
    }

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Dialog(
        backgroundColor: Jb.cabinetHi,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Jb.chrome, width: 2)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _display(),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: Center(
                    child: Text(preview,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: previewColor, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 8),
                for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
                  Row(children: [for (final d in row) _key(d, () => _press(d))]),
                Row(children: [
                  _key('⌫', _back, color: Jb.chrome),
                  _key('0', () => _press('0')),
                  _key('CLR', () => setState(() => digits = ''), color: Jb.chrome),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 64)),
                      onPressed: e == null ? null : _goTo,
                      icon: const Icon(Icons.visibility),
                      label: const Text('SHOW ALBUM', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 64)),
                      onPressed: s == null ? null : _select,
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('SELECT'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _display() {
    String slot(int i) => i < digits.length ? digits[i] : '_';
    final text = '${[for (var i = 0; i < 4; i++) slot(i)].join()} - ${slot(4)}${slot(5)}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Jb.neonDim),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamilyFallback: Jb.mono,
            fontSize: 44,
            letterSpacing: 6,
            color: Jb.neon,
            shadows: [Shadow(color: Jb.neon, blurRadius: 12)],
          )),
    );
  }

  Widget _key(String label, VoidCallback onTap, {Color color = Jb.neon}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 68,
              alignment: Alignment.center,
              decoration: Jb.chromeButton(),
              child: Text(label, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: color)),
            ),
          ),
        ),
      );
}
