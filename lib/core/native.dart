// Platform helpers: the small Android helper in MainActivity.kt, and plain Dart on Windows.
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

class PickedFile {
  final String? uri; // Android content link
  final String? path; // real path (desktop)
  final String name;
  final int size;
  final int modifiedMs;
  PickedFile({this.uri, this.path, required this.name, required this.size, required this.modifiedMs});

  /// A file that already exists on disk (Windows picker, drag and drop, folder scan).
  static PickedFile? fromPath(String path) {
    try {
      final f = File(path);
      final st = f.statSync();
      if (st.type != FileSystemEntityType.file) return null;
      return PickedFile(
        path: path,
        name: path.split(RegExp(r'[\\/]')).last,
        size: st.size,
        modifiedMs: st.modified.millisecondsSinceEpoch,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Expands dropped/picked paths: files stay, folders are scanned with all subfolders.
Future<List<PickedFile>> expandPaths(Iterable<String> paths) async {
  final out = <PickedFile>[];
  for (final p in paths) {
    final type = FileSystemEntity.typeSync(p);
    if (type == FileSystemEntityType.directory) {
      try {
        await for (final e in Directory(p).list(recursive: true, followLinks: false)) {
          if (e is File) {
            final name = e.path.split(RegExp(r'[\\/]')).last;
            if (name.startsWith('.') || name.toLowerCase() == 'desktop.ini' || name.toLowerCase() == 'thumbs.db') continue;
            final f = PickedFile.fromPath(e.path);
            if (f != null) out.add(f);
          }
        }
      } catch (_) {}
    } else {
      final f = PickedFile.fromPath(p);
      if (f != null) out.add(f);
    }
  }
  return out;
}

class NativeBridge {
  static const _ch = MethodChannel('tirsodrive/native');

  static Future<List<PickedFile>> pickFiles() async {
    if (!Platform.isAndroid) {
      final files = await openFiles();
      return expandPaths(files.map((x) => x.path));
    }
    final res = await _ch.invokeMethod<List<dynamic>>('pickFiles');
    return (res ?? []).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return PickedFile(
        uri: m['uri'] as String?,
        name: (m['name'] ?? 'file') as String,
        size: (m['size'] as num?)?.toInt() ?? -1,
        modifiedMs: (m['modified'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  static Future<String?> pickFolderPath() => getDirectoryPath();

  /// Windows: pick a whole folder (all subfolders are included).
  static Future<List<PickedFile>> pickFolder() async {
    final dir = await getDirectoryPath();
    if (dir == null) return [];
    return expandPaths([dir]);
  }

  /// Copies one picked file into private temporary storage and returns its path.
  static Future<String> copyToCache(String uri, String name) async {
    final p = await _ch.invokeMethod<String>('copyToCache', {'uri': uri, 'name': name});
    return p!;
  }

  static String _windowsDownloads() {
    final home = Platform.environment['USERPROFILE'] ?? Directory.current.path;
    return '$home\\Downloads\\TirsoDrive';
  }

  /// Copies a file into [dirPath] (created if needed) without overwriting; returns the new path.
  static Future<String> copyInto(String path, String name, String dirPath) async {
    final dir = Directory(dirPath);
    dir.createSync(recursive: true);
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final dot = safe.lastIndexOf('.');
    final base = dot > 0 ? safe.substring(0, dot) : safe;
    final ext = dot > 0 ? safe.substring(dot) : '';
    final sep = Platform.pathSeparator;
    var target = File('${dir.path}$sep$safe');
    var i = 1;
    while (target.existsSync()) {
      target = File('${dir.path}$sep$base ($i)$ext');
      i++;
    }
    await File(path).copy(target.path);
    return target.path;
  }

  /// Windows cloud folders that sync automatically (Google Drive for desktop, OneDrive, Dropbox).
  static List<(String, String)> cloudFolders() {
    if (!Platform.isWindows) return [];
    final out = <(String, String)>[];
    final env = Platform.environment;
    final od = env['OneDrive'] ?? env['OneDriveConsumer'];
    if (od != null && Directory(od).existsSync()) out.add(('OneDrive', od));
    for (var c = 'D'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
      for (final sub in ['My Drive', 'Mi unidad']) {
        final p = '${String.fromCharCode(c)}:\\$sub';
        if (Directory(p).existsSync()) out.add(('Google Drive', p));
      }
    }
    final home = env['USERPROFILE'];
    if (home != null) {
      for (final (label, sub) in [('Google Drive', 'Google Drive'), ('Dropbox', 'Dropbox')]) {
        final p = '$home\\$sub';
        if (Directory(p).existsSync() && !out.any((o) => o.$2 == p)) out.add((label, p));
      }
    }
    return out;
  }

  /// Android share menu for one or more downloaded files.
  static Future<void> shareFiles(List<String> paths, List<String> names, List<String> mimes) async {
    if (!Platform.isAndroid) return;
    await _ch.invokeMethod('shareFiles', {'paths': paths, 'names': names, 'mimes': mimes});
  }

  static Future<String> saveToDownloads(String path, String name, String mime) async {
    if (!Platform.isAndroid) {
      final dir = Directory(_windowsDownloads());
      dir.createSync(recursive: true);
      final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final dot = safe.lastIndexOf('.');
      final base = dot > 0 ? safe.substring(0, dot) : safe;
      final ext = dot > 0 ? safe.substring(dot) : '';
      var target = File('${dir.path}\\$safe');
      var i = 1;
      while (target.existsSync()) {
        target = File('${dir.path}\\$base ($i)$ext');
        i++;
      }
      await File(path).copy(target.path);
      return target.path;
    }
    final p = await _ch.invokeMethod<String>('saveToDownloads', {'path': path, 'name': name, 'mime': mime});
    return p ?? '';
  }

  static Future<void> openFile(String path, String mime) async {
    if (Platform.isWindows) {
      // Opens the file with its default Windows app.
      await Process.start('explorer.exe', [path], runInShell: false);
      return;
    }
    await _ch.invokeMethod('openFile', {'path': path, 'mime': mime});
  }

  /// Windows: plays a stream link in VLC when installed (plays everything), otherwise in the default browser.
  static Future<void> openStreamUrl(String url) async {
    final pf = [Platform.environment['ProgramFiles'], Platform.environment['ProgramFiles(x86)']];
    for (final dir in pf) {
      if (dir == null) continue;
      final vlc = File('$dir\\VideoLAN\\VLC\\vlc.exe');
      if (vlc.existsSync()) {
        await Process.start(vlc.path, [url]);
        return;
      }
    }
    await Process.start('explorer.exe', [url]);
  }

  static Future<void> showInFolder(String path) async {
    if (Platform.isWindows) await Process.start('explorer.exe', ['/select,', path]);
  }

  static Future<void> releaseUri(String uri) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('releaseUri', {'uri': uri});
    } catch (_) {}
  }

  /// Shows/updates the "TirsoDrive · Uploading…" notification that keeps transfers running in the background.
  static Future<void> serviceUpdate({required String title, required String text, required int progress, required bool paused, required String button}) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('serviceUpdate', {'title': title, 'text': text, 'progress': progress, 'paused': paused, 'button': button});
    } catch (_) {}
  }

  static Future<void> serviceStop() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('serviceStop');
    } catch (_) {}
  }

  static Future<void> askNotifications() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('askNotifications');
    } catch (_) {}
  }

  /// Calls [onTogglePause] when the notification's Pause/Resume button is tapped.
  static void listen({required void Function() onTogglePause}) {
    if (!Platform.isAndroid) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'togglePause') onTogglePause();
      return null;
    });
  }

  /// (on Wi-Fi?, charging?) — null when unknown (Windows counts as both).
  static Future<(bool?, bool?)> deviceState() async {
    if (!Platform.isAndroid) return (true, true);
    try {
      final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('deviceState');
      return (m?['wifi'] as bool?, m?['charging'] as bool?);
    } catch (_) {
      return (null, null);
    }
  }

  static Future<bool> isTv() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('isTv') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> keepAwake(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('keepAwake', {'on': on});
    } catch (_) {}
  }
}
