import 'dart:async';

import 'package:flutter/material.dart';

import 'core/drive.dart';
import 'core/strings.dart';
import 'ui/desktop_shell.dart';
import 'ui/library_screen.dart';
import 'ui/login_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/theme.dart';
import 'ui/transfers_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final drive = Drive();
  runApp(TirsoDriveApp(drive: drive));
  await drive.init();
}

class TirsoDriveApp extends StatelessWidget {
  final Drive drive;
  const TirsoDriveApp({super.key, required this.drive});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TirsoDrive',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ListenableBuilder(
        listenable: drive,
        builder: (context, _) {
          switch (drive.step) {
            case AuthStep.needApi:
              return ApiSetupScreen(drive: drive);
            case AuthStep.ready:
              return LayoutBuilder(
                builder: (context, box) => box.maxWidth >= 1000 ? DesktopShell(drive: drive) : MainShell(drive: drive),
              );
            default:
              return LoginScreen(drive: drive);
          }
        },
      ),
    );
  }
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
      body: IndexedStack(index: _tab, children: [
        LibraryScreen(drive: d),
        TransfersScreen(drive: d),
        SettingsScreen(drive: d),
      ]),
      bottomNavigationBar: NavigationBar(
        backgroundColor: C.panel,
        indicatorColor: C.raised,
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.folder_outlined), selectedIcon: const Icon(Icons.folder), label: t('nav_library')),
          NavigationDestination(
            icon: Badge(isLabelVisible: active > 0, label: Text('$active'), child: const Icon(Icons.swap_vert)),
            label: t('nav_transfers'),
          ),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: t('nav_settings')),
        ],
      ),
    );
  }
}
