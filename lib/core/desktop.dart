// Windows only: system tray icon, upload status card, close-to-tray, and "Start with Windows".
// The window closes to the tray (the app keeps running, so uploads and folder sync continue);
// "Quit" in the tray menu really exits. Clicking the tray icon opens a small OneDrive-style status card.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
    return r.exitCode == 0 && '${r.stdout}'.contains('--minimized');
  }

  /// Returns null when it worked, otherwise Windows' error text.
  static Future<String?> setAutostart(bool on) async {
    if (!Platform.isWindows) return null;
    final exe = Platform.resolvedExecutable.replaceAll("'", "''");
    final ps = on
        ? "Set-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' -Name '$_runName' -Value '\"$exe\" --minimized'"
        : "Remove-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' -Name '$_runName' -ErrorAction SilentlyContinue";
    final r = await Process.run('powershell', ['-NoProfile', '-NonInteractive', '-Command', ps]);
    final ok = (await autostartEnabled()) == on;
    await log('autostart ${on ? 'on' : 'off'}: exit ${r.exitCode} ${r.stderr} -> ${ok ? 'ok' : 'FAILED'}');
    return ok ? null : '${r.stderr}'.trim();
  }

  // ---------------- log (so a failure can be diagnosed from a file instead of guessing)

  static Future<void> log(String line) async {
    try {
      final dir = await getApplicationSupportDirectory();
      await File(p.join(dir.path, 'desktop.log')).writeAsString('${DateTime.now().toIso8601String()} $line\n', mode: FileMode.append);
    } catch (_) {}
  }

  bool trayOk = false;

  static File get _flag => File(p.join(Directory.systemTemp.path, 'tirsodrive-tray.flag'));

  /// The native runner reads this file: present = the Close button only hides the window.
  void _syncFlag() {
    try {
      final want = trayOk && d.keepInTray && !_quitting;
      if (want && !_flag.existsSync()) _flag.writeAsStringSync('1');
      if (!want && _flag.existsSync()) _flag.deleteSync();
    } catch (_) {}
  }

  // ---------------- setup

  /// Called a moment after the first frame, when the native window and its plugins are fully ready.
  Future<void> init({required bool startHidden}) async {
    if (!supported) return;
    await log('init (hidden start: $startHidden)');
    try {
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);
      windowManager.addListener(this);
    } catch (e) {
      await log('window manager failed: $e');
    }
    trayManager.addListener(this);
    final icon = p.join(p.dirname(Platform.resolvedExecutable), 'data', 'flutter_assets', 'assets', 'tray_icon.ico');
    await log('tray icon file exists: ${File(icon).existsSync()} ($icon)');
    for (var attempt = 1; attempt <= 4 && !trayOk; attempt++) {
      try {
        await trayManager.setIcon('assets/tray_icon.ico');
        await trayManager.setToolTip('TirsoDrive');
        await _menu();
        trayOk = true;
        await log('tray icon created (attempt $attempt)');
      } catch (e) {
        await log('tray attempt $attempt failed: $e');
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    d.addListener(_refresh);
    _ready = true;
    _syncFlag();
    await log('keep in tray: ${d.keepInTray}, flag: ${_flag.existsSync()}');
    if (startHidden) {
      if (trayOk) {
        await windowManager.hide();
        await windowManager.setSkipTaskbar(true);
      } else {
        await showMain(); // never leave the app invisible without a tray icon to bring it back
      }
    }
  }

  String _lastTip = '';

  void _refresh() {
    if (!_ready) return;
    _syncFlag();
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
    _syncFlag();
    await log('quit');
    try { await trayManager.destroy(); } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  // ---------------- events

  @override
  void onWindowClose() async {
    await log('close event (keepInTray ${d.keepInTray}, trayOk $trayOk)');
    if (_quitting) return;
    if (d.keepInTray && trayOk) {
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
