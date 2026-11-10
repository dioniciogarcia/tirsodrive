import 'dart:async';

import 'package:flutter/material.dart';

import 'core/desktop.dart';
import 'core/drive.dart';
import 'core/strings.dart';
import 'ui/desktop_shell.dart';
import 'ui/tray_card.dart';
import 'ui/library_screen.dart';
import 'ui/lock_screen.dart';
import 'ui/login_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/theme.dart';
import 'ui/transfers_screen.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final drive = Drive();
  await drive.loadTheme(); // before the first frame, so there is no flash of the wrong theme
  if (DesktopHost.supported) {
    drive.desktop = DesktopHost(drive);
    await drive.desktop!.init(startHidden: args.contains('--minimized'));
  }
  runApp(TirsoDriveApp(drive: drive));
  await drive.init();
}

class TirsoDriveApp extends StatelessWidget {
  final Drive drive;
  const TirsoDriveApp({super.key, required this.drive});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: drive.themeTick,
      builder: (context, tick, _) {
        // Rebuild every screen with the new colors WITHOUT recreating the app, so you stay where you were.
        WidgetsBinding.instance.addPostFrameCallback((_) => _repaintAll());
        return MaterialApp(
        title: 'TirsoDrive',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: drive.desktop == null
            ? _home()
            : ValueListenableBuilder<bool>(
                valueListenable: drive.desktop!.card,
                // the full app stays alive (hidden) behind the card, so you return to the same screen
                builder: (context, card, _) => Stack(children: [
                  Positioned.fill(child: Offstage(offstage: card, child: TickerMode(enabled: !card, child: _home()))),
                  if (card) Positioned.fill(child: TrayCard(drive: drive)),
                ]),
              ),
      );
      },
    );
  }

  Widget _home() {
    return _LockGate(
          drive: drive,
          child: ListenableBuilder(
            listenable: drive,
            builder: (context, _) {
              switch (drive.step) {
                case AuthStep.needApi:
                  return ApiSetupScreen(drive: drive);
                case AuthStep.ready:
                  return LayoutBuilder(
                    builder: (context, box) =>
                        box.maxWidth >= 1000 || drive.isTv
                        ? DesktopShell(drive: drive)
                        : MainShell(drive: drive),
                  );
                default:
                  return LoginScreen(drive: drive);
              }
            },
          ),
        );
  }
}

void _repaintAll() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }
  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}

class MainShell extends StatefulWidget {
  final Drive drive;
  const MainShell({super.key, required this.drive});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.drive.messages.listen((m) {
      if (mounted) snack(context, m);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.drive;
    final active = d.transfers.where((x) => !x.finished).length;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          LibraryScreen(drive: d),
          TransfersScreen(drive: d),
          SettingsScreen(drive: d),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: C.panel,
        indicatorColor: C.raised,
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: t('nav_library'),
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: active > 0,
              label: Text('$active'),
              child: Icon(Icons.swap_vert),
            ),
            label: t('nav_transfers'),
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: t('nav_settings'),
          ),
        ],
      ),
    );
  }
}

/// Shows the PIN screen when the app opens, and again after it was in the background for over a minute.
class _LockGate extends StatefulWidget {
  final Drive drive;
  final Widget child;
  const _LockGate({required this.drive, required this.child});
  @override
  State<_LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<_LockGate> with WidgetsBindingObserver {
  late bool _locked = widget.drive.lockEnabled;
  DateTime? _away;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.drive.isTv) {
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _away ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_away != null &&
          widget.drive.lockEnabled &&
          DateTime.now().difference(_away!).inSeconds > 60) {
        setState(() => _locked = true);
      }
      _away = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_locked && widget.drive.lockEnabled) {
      return LockScreen(
        drive: widget.drive,
        onUnlocked: () => setState(() => _locked = false),
      );
    }
    return widget.child;
  }
}
