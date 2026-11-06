// App lock: PIN, plus fingerprint/face (Android) or Windows Hello when turned on.
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../core/drive.dart';
import '../core/strings.dart';
import 'theme.dart';

class LockScreen extends StatefulWidget {
  final Drive drive;
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.drive, required this.onUnlocked});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  String? _err;

  @override
  void initState() {
    super.initState();
    if (widget.drive.lockBio) WidgetsBinding.instance.addPostFrameCallback((_) => _bio());
  }

  Future<void> _bio() async {
    try {
      final ok = await LocalAuthentication().authenticate(localizedReason: t('lock_reason'));
      if (ok) widget.onUnlocked();
    } catch (_) {}
  }

  void _key(String k) {
    setState(() {
      _err = null;
      if (k == '<') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 8) {
        _pin += k;
      }
    });
    if (_pin.length >= 4 && Drive.hashPin(_pin) == widget.drive.lockHash) {
      widget.onUnlocked();
    } else if (_pin.length == 8) {
      setState(() {
        _err = t('lock_wrong');
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget btn(String k) => Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(
            width: 72,
            height: 72,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(shape: CircleBorder(), padding: EdgeInsets.zero),
              onPressed: () => _key(k),
              child: k == '<' ? Icon(Icons.backspace_outlined) : Text(k, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            ),
          ),
        );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TdLogo(size: 56),
              SizedBox(height: 16),
              Text(t('lock_title'), style: TextStyle(fontFamily: displayFont, fontSize: 22, fontWeight: FontWeight.w600)),
              SizedBox(height: 18),
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < 4 || i < _pin.length; i++)
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 6),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: i < _pin.length ? C.accent : C.border2),
                  ),
              ]),
              SizedBox(height: 10),
              SizedBox(height: 20, child: _err == null ? null : Text(_err!, style: TextStyle(color: C.red))),
              SizedBox(height: 8),
              for (final row in [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                Row(mainAxisSize: MainAxisSize.min, children: row.map(btn).toList()),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: widget.drive.lockBio ? IconButton(tooltip: t('lock_bio'), onPressed: _bio, icon: Icon(Icons.fingerprint, size: 34, color: C.accentSoft)) : null,
                  ),
                ),
                btn('0'),
                btn('<'),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Settings dialog to turn the lock on (PIN + optional fingerprint) or off.
Future<void> lockSettingsDialog(BuildContext context, Drive d) async {
  if (d.lockEnabled) {
    d.setLock(null);
    return;
  }
  final a = TextEditingController();
  final b = TextEditingController();
  var bio = false;
  var canBio = false;
  try {
    canBio = await LocalAuthentication().isDeviceSupported();
  } catch (_) {}
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        return AlertDialog(
          title: Text(t('lock_set'), style: TextStyle(fontFamily: displayFont)),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: a, obscureText: true, keyboardType: TextInputType.number, maxLength: 8, decoration: InputDecoration(labelText: t('lock_pin'))),
              TextField(controller: b, obscureText: true, keyboardType: TextInputType.number, maxLength: 8, decoration: InputDecoration(labelText: t('lock_pin2'))),
              if (canBio)
                SwitchListTile(contentPadding: EdgeInsets.zero, value: bio, onChanged: (v) => set(() => bio = v), title: Text(t('lock_bio'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: Size(96, 44)),
              onPressed: () {
                if (!RegExp(r'^\d{4,8}$').hasMatch(a.text) || a.text != b.text) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('lock_pin_bad'))));
                  return;
                }
                d.setLock(a.text, bio: bio);
                Navigator.pop(ctx);
              },
              child: Text(t('verify')),
            ),
          ],
        );
      },
    ),
  );
}
