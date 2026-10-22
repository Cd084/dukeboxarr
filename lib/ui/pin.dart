import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../browse.dart';
import 'keypad.dart';
import 'theme.dart';

Future<T?> _show<T>(BuildContext context, Widget dialog) =>
    showDialog<T>(context: context, barrierColor: Colors.black87, builder: (_) => dialog);

/// True if settings may be opened (no PIN set, or the right PIN entered).
Future<bool> unlockSettings(BuildContext context) async {
  final pin = AppScope.of(context).settings.adminPin;
  if (pin.isEmpty) return true;
  return await _show<bool>(
          context, _PinDialog(title: 'Enter settings PIN', check: (p) => p == pin, returnPin: false)) ??
      false;
}

/// Asks for a PIN once (e.g. a Plex Home user's PIN). Null if cancelled.
Future<String?> askPin(BuildContext context, String title) => _show<String>(context, _PinDialog(title: title));

/// Prompts for a new PIN (entered twice). Returns null if cancelled.
Future<String?> chooseNewPin(BuildContext context) async {
  final first = await _show<String>(context, const _PinDialog(title: 'New PIN (4–8 digits)'));
  if (first == null || !context.mounted) return null;
  final again = await _show<String>(context, _PinDialog(title: 'Repeat the new PIN', check: (p) => p == first));
  return again == null ? null : first;
}

class _PinDialog extends StatefulWidget {
  final String title;

  /// If set, the PIN must pass this check (wrong entries are cleared).
  final bool Function(String)? check;

  /// Pop the entered PIN (true), or just `true` once verified (false).
  final bool returnPin;
  const _PinDialog({required this.title, this.check, this.returnPin = true});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  String _pin = '';
  bool _wrong = false;

  void _press(String d) {
    if (_pin.length < 8) {
      setState(() {
        _pin += d;
        _wrong = false;
      });
    }
  }

  void _ok() {
    if (_pin.length < 4) return;
    if (widget.check?.call(_pin) ?? true) {
      Navigator.pop(context, widget.returnPin ? _pin : true);
    } else {
      setState(() {
        _pin = '';
        _wrong = true;
      });
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent ev) {
    if (ev is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = ev.character;
    if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      _press(ch);
    } else if (ev.logicalKey == LogicalKeyboardKey.backspace) {
      if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
    } else if (ev.logicalKey == LogicalKeyboardKey.enter || ev.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _ok();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Dialog(
        backgroundColor: Jb.cabinetHi,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Jb.chrome, width: 2)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.title,
                    textAlign: TextAlign.center, style: const TextStyle(color: Jb.neon, fontSize: 22)),
                const SizedBox(height: 12),
                CodeDisplay(_pin.isEmpty ? ' ' : '•' * _pin.length, fontSize: 40),
                SizedBox(
                  height: 32,
                  child: Center(
                    child: Text(_wrong ? 'Wrong PIN' : '',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 16)),
                  ),
                ),
                for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
                  Row(children: [for (final d in row) Expanded(child: PadKey(d, () => _press(d)))]),
                Row(children: [
                  Expanded(child: PadKey('✕', () => Navigator.pop(context), color: Colors.redAccent)),
                  Expanded(child: PadKey('0', () => _press('0'))),
                  Expanded(child: PadKey('OK', _pin.length >= 4 ? _ok : null)),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
