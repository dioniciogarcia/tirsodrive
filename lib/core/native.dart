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

  static Future<void> showInFolder(String path) async {
    if (Platform.isWindows) await Process.start('explorer.exe', ['/select,', path]);
  }

  static Future<void> releaseUri(String uri) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('releaseUri', {'uri': uri});
    } catch (_) {}
  }

  static Future<void> keepAwake(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('keepAwake', {'on': on});
    } catch (_) {}
  }
}
