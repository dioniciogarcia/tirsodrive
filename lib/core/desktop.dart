// Windows only: system tray icon, upload status card, close-to-tray, and "Start with Windows".
// The window closes to the tray (the app keeps running, so uploads and folder sync continue);
// "Quit" in the tray menu really exits. Clicking the tray icon opens a small OneDrive-style status card.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'drive.dart';
import 'strings.dart';

class DesktopHost with TrayListener, WindowListener {
  final Drive d;
  DesktopHost(this.d);

  /// true while the small status card is showing instead of the full window
  final ValueNotifier<bool> card = ValueNotifier<bool>(false);
  bool _quitting = false;
  bool _ready = false;

  static bool get supported => Platform.isWindows;

  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _runName = 'TirsoDrive';

  // ---------------- Start with Windows (per user, no admin needed)

  static Future<bool> autostartEnabled() async {
    if (!Platform.isWindows) return false;
    final r = await Process.run('reg', ['query', _runKey, '/v', _runName]);
    return r.exitCode == 0;
  }

  static Future<void> setAutostart(bool on) async {
    if (!Platform.isWindows) return;
    if (on) {
      await Process.run('reg', ['add', _runKey, '/v', _runName, '/t', 'REG_SZ', '/d', '"${Platform.resolvedExecutable}" --minimized', '/f']);
    } else {
      await Process.run('reg', ['delete', _runKey, '/v', _runName, '/f']);
    }
  }

  // ---------------- setup

  Future<void> init({required bool startHidden}) async {
    if (!supported) return;
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    trayManager.addListener(this);
    try {
      await trayManager.setIcon('assets/tray_icon.ico');
      await trayManager.setToolTip('TirsoDrive');
      await _menu();
    } catch (_) {}
    d.addListener(_refresh);
    _ready = true;
    if (startHidden) {
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
    }
  }

  String _lastTip = '';

  void _refresh() {
    if (!_ready) return;
    final active = d.transfers.where((x) => !x.finished).length;
    final tip = active == 0 ? 'TirsoDrive' : 'TirsoDrive · ${t('tray_active', {'n': active})}';
    if (tip != _lastTip) {
      _lastTip = tip;
      trayManager.setToolTip(tip).catchError((_) {});
    }
  }

  Future<void> _menu() async {
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'open', label: t('tray_open')),
      MenuItem(key: 'pause', label: d.paused ? t('tray_resume') : t('tray_pause')),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: t('tray_quit')),
    ]));
  }

  // ---------------- window modes

  Future<void> showMain() async {
    card.value = false;
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setSize(const Size(1360, 860));
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> showCard() async {
    card.value = true;
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    await windowManager.setSize(const Size(380, 520));
    await windowManager.setAlignment(Alignment.bottomRight);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hideAll() async {
    card.value = false;
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  Future<void> quit() async {
    _quitting = true;
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  // ---------------- events

  @override
  void onWindowClose() async {
    if (_quitting) return;
    if (d.keepInTray) {
      await hideAll(); // keep running: uploads and folder sync go on in the background
    } else {
      await quit();
    }
  }

  @override
  void onWindowBlur() async {
    if (card.value) await hideAll(); // the card closes when you click elsewhere, like OneDrive's
  }

  @override
  void onTrayIconMouseDown() {
    if (card.value) {
      hideAll();
    } else {
      showCard();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    _menu().then((_) => trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        showMain();
        break;
      case 'pause':
        d.togglePause();
        break;
      case 'quit':
        quit();
        break;
    }
  }
}
