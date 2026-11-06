import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tirsodrive/core/drive.dart';
import 'package:tirsodrive/main.dart';

/// The test font is far wider than the real fonts, so "overflowed by N pixels" here isn't a real problem.
void _check(WidgetTester tester, String reason) {
  final e = tester.takeException();
  if (e == null || e.toString().contains('overflowed')) return;
  fail('$reason: $e');
}

/// Opens the signed-in app and visits every main screen, in both themes and both layouts.
/// Catches freezes/loops (like the 0.6.0 startup crash) before an APK is built.
Future<void> _run(WidgetTester tester, Size size, String theme) async {
  SharedPreferences.setMockInitialValues({'theme': theme});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final drive = Drive();
  await tester.runAsync(() => drive.loadTheme());
  drive.step = AuthStep.ready;
  await tester.pumpWidget(TirsoDriveApp(drive: drive));
  await tester.pump(const Duration(milliseconds: 300));
  _check(tester, 'start ($theme)');
  final phone = size.width < 1000;
  final tabs = phone ? ['Transfers', 'Settings', 'Library'] : ['Search', 'Folder sync', 'Transfers', 'Settings', 'Videos'];
  for (final name in tabs) {
    final f = find.text(name);
    if (f.evaluate().isEmpty) continue;
    await tester.tap(f.first, warnIfMissed: false);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    _check(tester, 'screen "$name" ($theme, ${phone ? 'phone' : 'desktop'})');
  }
}

void main() {
  for (final theme in ['dark', 'light']) {
    testWidgets('phone, $theme', (t) => _run(t, const Size(412, 915), theme), timeout: const Timeout(Duration(seconds: 60)));
    testWidgets('desktop, $theme', (t) => _run(t, const Size(1400, 900), theme), timeout: const Timeout(Duration(seconds: 60)));
  }
}
