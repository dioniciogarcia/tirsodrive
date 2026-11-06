import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/drive.dart';
import '../core/strings.dart';
import 'theme.dart';

/// Shared frame for the setup and sign-in screens.
class _AuthFrame extends StatelessWidget {
  final Drive drive;
  final List<Widget> children;
  const _AuthFrame({required this.drive, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: EdgeInsets.fromLTRB(22, 24, 22, 26),
              children: [
                Row(children: [
                  TdLogo(),
                  SizedBox(width: 10),
                  Text('TirsoDrive', style: TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w700, fontSize: 20)),
                  Spacer(),
                  LangSwitch(lang: drive.lang, onChanged: drive.setLang),
                ]),
                SizedBox(height: 26),
                ...children,
                SizedBox(height: 26),
                Panel(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    Icon(Icons.lock_outline, size: 18, color: C.green),
                    SizedBox(width: 10),
                    Expanded(child: Text(t('secure_note'), style: TextStyle(fontSize: 12, color: C.muted, height: 1.4))),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _title(String s) =>
    Text(s, style: TextStyle(fontFamily: displayFont, fontSize: 28, fontWeight: FontWeight.w600, height: 1.15));
Widget _body(String s) => Padding(
      padding: EdgeInsets.only(top: 8),
      child: Text(s, style: TextStyle(fontSize: 14, color: C.muted, height: 1.5)),
    );
Widget _error(String? e) => e == null
    ? SizedBox.shrink()
    : Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(e, style: TextStyle(color: C.red, fontSize: 13, height: 1.4)),
      );

// ------------------------------------------------------------------ API setup

class ApiSetupScreen extends StatefulWidget {
  final Drive drive;
  const ApiSetupScreen({super.key, required this.drive});
  @override
  State<ApiSetupScreen> createState() => _ApiSetupScreenState();
}

class _ApiSetupScreenState extends State<ApiSetupScreen> {
  final _id = TextEditingController();
  final _hash = TextEditingController();
  String? _err;

  void _save() {
    final id = int.tryParse(_id.text.trim());
    final hash = _hash.text.trim();
    if (id == null || id <= 0 || !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hash)) {
      setState(() => _err = t('setup_invalid'));
      return;
    }
    widget.drive.saveApi(id, hash);
  }

  @override
  Widget build(BuildContext context) {
    return _AuthFrame(drive: widget.drive, children: [
      _title(t('setup_title')),
      _body(t('setup_body')),
      SizedBox(height: 22),
      TextField(controller: _id, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('setup_id'))),
      SizedBox(height: 12),
      TextField(controller: _hash, autocorrect: false, decoration: InputDecoration(labelText: t('setup_hash'))),
      _error(_err),
      SizedBox(height: 18),
      FilledButton(onPressed: _save, child: Text(t('setup_save'))),
    ]);
  }
}

// ------------------------------------------------------------------ Sign in

class LoginScreen extends StatefulWidget {
  final Drive drive;
  const LoginScreen({super.key, required this.drive});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _pw = TextEditingController();
  final _email = TextEditingController();
  bool _qrTab = false;
  bool _hidePw = true;

  Drive get d => widget.drive;

  Widget _busyButton(String label, VoidCallback onTap) => FilledButton(
        onPressed: d.authBusy ? null : onTap,
        child: d.authBusy
            ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: C.text))
            : Text(label),
      );

  Widget _tabs() {
    Widget tab(String label, bool qr) => Expanded(
          child: Material(
            color: _qrTab == qr ? C.raised : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () {
                if (_qrTab == qr) return;
                setState(() => _qrTab = qr);
                if (qr) {
                  d.requestQr();
                } else {
                  d.wantQr = false;
                  if (d.step == AuthStep.qr) d.startOver();
                }
              },
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(label,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _qrTab == qr ? C.strong : C.muted)),
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: EdgeInsets.all(4),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
      child: Row(children: [tab(t('tab_phone'), false), tab(t('tab_qr'), true)]),
    );
  }

  List<Widget> _phoneOrQr() {
    final out = <Widget>[
      _title(t('login_title')),
      _body(t('login_sub')),
      SizedBox(height: 22),
      _tabs(),
      SizedBox(height: 22),
    ];
    if (_qrTab) {
      final link = d.qrLink;
      out.add(Center(
        child: Container(
          width: 240,
          height: 240,
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: link == null
              ? Center(child: Text(t('qr_loading'), style: TextStyle(color: C.onAccent)))
              : QrImageView(data: link, padding: EdgeInsets.zero, backgroundColor: Colors.white),
        ),
      ));
      out.add(SizedBox(height: 18));
      for (final (i, s) in [t('qr_step1'), t('qr_step2'), t('qr_step3')].indexed) {
        out.add(Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('${i + 1}.  $s', style: TextStyle(fontSize: 14, color: C.soft, height: 1.45)),
        ));
      }
      out.add(Text(t('qr_note'), style: TextStyle(fontSize: 12, color: C.label, height: 1.4)));
    } else {
      out.addAll([
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          style: TextStyle(fontSize: 17),
          decoration: InputDecoration(labelText: t('phone_label'), hintText: '+1 809 555 0123'),
          onSubmitted: (_) => d.submitPhone(_phone.text),
        ),
        SizedBox(height: 10),
        Text(t('phone_hint'), style: TextStyle(fontSize: 13, color: C.muted, height: 1.5)),
        SizedBox(height: 16),
        _busyButton(t('send_code'), () => d.submitPhone(_phone.text)),
      ]);
    }
    out.add(_error(d.authError));
    return out;
  }

  List<Widget> _codeStep() {
    final key = d.codeKind.contains('TelegramMessage')
        ? 'code_sent_app'
        : d.codeKind.contains('Sms')
            ? 'code_sent_sms'
            : 'code_sent_other';
    return [
      _title(t('code_title')),
      _body(t(key, {'p': d.codeTarget.isEmpty ? '' : '+${d.codeTarget}'})),
      SizedBox(height: 22),
      TextField(
        controller: _code,
        keyboardType: TextInputType.number,
        autofocus: true,
        style: TextStyle(fontSize: 22, letterSpacing: 6),
        decoration: InputDecoration(labelText: t('code_label')),
        onSubmitted: (_) => d.submitCode(_code.text),
      ),
      _error(d.authError),
      SizedBox(height: 16),
      _busyButton(t('verify'), () => d.submitCode(_code.text)),
      SizedBox(height: 8),
      Row(children: [
        TextButton(onPressed: d.resendCode, child: Text(t('resend'))),
        Spacer(),
        TextButton(onPressed: () => d.startOver(), child: Text(t('start_over'))),
      ]),
    ];
  }

  List<Widget> _passwordStep() => [
        _title(t('pw_title')),
        _body(t('pw_body')),
        if (d.passwordHint.isNotEmpty) _body(t('pw_hint', {'h': d.passwordHint})),
        SizedBox(height: 22),
        TextField(
          controller: _pw,
          obscureText: _hidePw,
          autofocus: true,
          decoration: InputDecoration(
            labelText: t('pw_label'),
            suffixIcon: IconButton(
              tooltip: t('pw_label'),
              icon: Icon(_hidePw ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _hidePw = !_hidePw),
            ),
          ),
          onSubmitted: (_) => d.submitPassword(_pw.text),
        ),
        _error(d.authError),
        SizedBox(height: 16),
        _busyButton(t('verify'), () => d.submitPassword(_pw.text)),
        SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => d.startOver(), child: Text(t('start_over')))),
      ];

  List<Widget> _emailStep(bool code) => [
        _title(t('email_title')),
        _body(code ? t('email_code_body', {'e': d.emailPattern}) : t('email_body')),
        SizedBox(height: 22),
        TextField(
          controller: code ? _code : _email,
          keyboardType: code ? TextInputType.number : TextInputType.emailAddress,
          decoration: InputDecoration(labelText: code ? t('code_label') : t('email_label')),
        ),
        _error(d.authError),
        SizedBox(height: 16),
        _busyButton(t('verify'), () => code ? d.submitEmailCode(_code.text) : d.submitEmail(_email.text)),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => d.startOver(), child: Text(t('start_over')))),
      ];

  List<Widget> _messageStep(String msg) => [
        _title(t('login_title')),
        _body(msg),
        SizedBox(height: 20),
        FilledButton(onPressed: () => d.startOver(qr: true), child: Text(t('start_over'))),
      ];

  @override
  Widget build(BuildContext context) {
    if (d.step == AuthStep.qr) _qrTab = true;
    List<Widget> body;
    switch (d.step) {
      case AuthStep.phone:
      case AuthStep.qr:
        body = _phoneOrQr();
        break;
      case AuthStep.code:
        body = _codeStep();
        break;
      case AuthStep.password:
        body = _passwordStep();
        break;
      case AuthStep.email:
        body = _emailStep(false);
        break;
      case AuthStep.emailCode:
        body = _emailStep(true);
        break;
      case AuthStep.registration:
        body = _messageStep(t('reg_body'));
        break;
      case AuthStep.unsupported:
        body = _messageStep(t('premium_body'));
        break;
      default:
        body = [
          SizedBox(height: 80),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 18),
          Center(child: Text(t('connecting'), style: TextStyle(color: C.muted))),
          _error(d.authError),
        ];
    }
    return _AuthFrame(drive: d, children: body);
  }
}
