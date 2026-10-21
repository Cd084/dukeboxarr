import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../browse.dart';
import '../library.dart';
import '../models.dart';
import 'actions.dart';
import 'theme.dart';

/// Selection-code entry shared by the pop-up keypad and the on-screen strip:
/// 4-digit album number + 2-digit track (e.g. 012305).
class CodeEntry extends ChangeNotifier {
  final Library library;
  CodeEntry(this.library, [this.digits = '']);

  String digits;

  Entry? get entry => digits.length >= 4 ? library.byNumber(int.parse(digits.substring(0, 4))) : null;

  Song? get song {
    final e = entry;
    if (e == null || digits.length < 6) return null;
    final t = int.parse(digits.substring(4, 6));
    return (t >= 1 && t <= e.songs.length) ? e.songs[t - 1] : null;
  }

  String get display {
    String slot(int i) => i < digits.length ? digits[i] : '_';
    return '${[for (var i = 0; i < 4; i++) slot(i)].join()} - ${slot(4)}${slot(5)}';
  }

  /// Human-readable status of what has been typed, and whether it's an error.
  (String, bool) get preview {
    final e = entry, s = song;
    if (digits.length < 4) return ('Enter album number, then track', false);
    if (e == null) return ('No album ${digits.substring(0, 4)}', true);
    if (digits.length < 6) return ('${e.artist} — ${e.title}  (${e.songs.length} tracks)', false);
    if (s == null) return ('Track ${digits.substring(4)} not on ${e.title}', true);
    return ('${s.title} — ${s.artist}', false);
  }

  void press(String d) {
    if (digits.length < 6) {
      digits += d;
      notifyListeners();
    }
  }

  void back() {
    if (digits.isNotEmpty) {
      digits = digits.substring(0, digits.length - 1);
      notifyListeners();
    }
  }

  void clear() {
    digits = '';
    notifyListeners();
  }

  /// Queues the entered song. Returns true if something was queued.
  bool select(BuildContext context) {
    final s = song;
    if (s == null) return false;
    requestSong(context, s);
    clear();
    return true;
  }

  /// Handles a physical-keyboard key. [onGoTo] is called on Enter with only
  /// an album number typed.
  KeyEventResult handleKey(KeyEvent ev, BuildContext context, {VoidCallback? onGoTo}) {
    if (ev is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = ev.character;
    if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      press(ch);
    } else if (ev.logicalKey == LogicalKeyboardKey.backspace) {
      back();
    } else if (ev.logicalKey == LogicalKeyboardKey.escape) {
      clear();
    } else if (ev.logicalKey == LogicalKeyboardKey.enter || ev.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (digits.length == 6) {
        select(context);
      } else {
        onGoTo?.call();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }
}

/// A chrome jukebox key.
class PadKey extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final double height;
  final double fontSize;
  const PadKey(this.label, this.onTap, {super.key, this.color = Jb.neon, this.height = 68, this.fontSize = 30});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: height,
            alignment: Alignment.center,
            decoration: Jb.chromeButton(),
            child: Text(label,
                style: TextStyle(
                    fontSize: fontSize, fontWeight: FontWeight.bold, color: onTap == null ? Colors.white24 : color)),
          ),
        ),
      );
}

/// Black LED-style readout.
class CodeDisplay extends StatelessWidget {
  final String text;
  final double fontSize;
  const CodeDisplay(this.text, {super.key, this.fontSize = 44});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(vertical: fontSize * 0.3, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Jb.neonDim),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamilyFallback: Jb.mono,
              fontSize: fontSize,
              letterSpacing: fontSize / 7,
              color: Jb.neon,
              shadows: const [Shadow(color: Jb.neon, blurRadius: 12)],
            )),
      );
}

/// Opens the selection keypad. [initial] pre-fills digits typed on a
/// physical keyboard before the pad opened.
Future<void> showKeypad(BuildContext context, {String initial = ''}) => showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Keypad(initial: initial),
    );

class Keypad extends StatefulWidget {
  final String initial;
  const Keypad({super.key, this.initial = ''});

  @override
  State<Keypad> createState() => _KeypadState();
}

class _KeypadState extends State<Keypad> {
  late final CodeEntry _code = CodeEntry(AppScope.of(context).library, widget.initial);
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    _code.dispose();
    super.dispose();
  }

  void _goTo() {
    final e = _code.entry;
    if (e == null) return;
    AppScope.of(context).browse.jumpTo(e);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, ev) => _code.handleKey(ev, context, onGoTo: _goTo),
      child: Dialog(
        backgroundColor: Jb.cabinetHi,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Jb.chrome, width: 2)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ListenableBuilder(
              listenable: _code,
              builder: (context, _) {
                final (preview, isError) = _code.preview;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CodeDisplay(_code.display),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      child: Center(
                        child: Text(preview,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: isError ? Colors.redAccent : _code.song != null ? Jb.neon : Jb.chrome,
                                fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
                      Row(children: [for (final d in row) Expanded(child: PadKey(d, () => _code.press(d)))]),
                    Row(children: [
                      Expanded(child: PadKey('⌫', _code.back, color: Jb.chrome)),
                      Expanded(child: PadKey('0', () => _code.press('0'))),
                      Expanded(child: PadKey('CLR', _code.clear, color: Jb.chrome)),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 64)),
                          onPressed: _code.entry == null ? null : _goTo,
                          icon: const Icon(Icons.visibility),
                          label: const Text('SHOW ALBUM', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 64)),
                          onPressed: _code.song == null ? null : () => _code.select(context),
                          icon: const Icon(Icons.playlist_add),
                          label: const Text('SELECT'),
                        ),
                      ),
                    ]),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The always-visible keypad strip under the A–Z bar.
class InlineKeypad extends StatelessWidget {
  final CodeEntry code;
  const InlineKeypad({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: code,
      builder: (context, _) {
        final (preview, isError) = code.preview;
        final e = code.entry;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 360,
              child: Row(children: [
                CodeDisplay(code.display, fontSize: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isError ? Colors.redAccent : code.song != null ? Jb.neon : Jb.chrome, fontSize: 14)),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            for (final d in const ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'])
              Expanded(child: PadKey(d, () => code.press(d), height: 60, fontSize: 26)),
            SizedBox(width: 70, child: PadKey('⌫', code.back, color: Jb.chrome, height: 60, fontSize: 24)),
            SizedBox(
              width: 70,
              // Show the album for the 4-digit number typed so far.
              child: PadKey('GO', e == null ? null : () => AppScope.of(context).browse.jumpTo(e),
                  color: Jb.chrome, height: 60, fontSize: 20),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 150,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: FilledButton(
                  onPressed: code.song == null ? null : () => code.select(context),
                  child: const Text('SELECT'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
