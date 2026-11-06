// Folder sync: pairs a folder (PC or phone) with a TirsoDrive channel.
// Safety rules: nothing is ever deleted automatically on either side; files already in the channel are not re-uploaded.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'drive.dart';
import 'native.dart';
import 'strings.dart';

class SyncPair {
  final String id;
  final String folder; // Windows path, or Android tree URI
  final String label; // folder name shown in the app
  String? key; // destination category…
  int? chatId; // …or channel
  bool twoWay;
  int lastRun = 0; // unix seconds
  String status = '';
  bool running = false;
  /// relative path → [size, modifiedMs] as last seen locally after a successful sync.
  final Map<String, List<int>> state;

  SyncPair({required this.id, required this.folder, required this.label, this.key, this.chatId, this.twoWay = false, Map<String, List<int>>? state})
      : state = state ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'folder': folder,
        'label': label,
        'key': key,
        'chat': chatId,
        'twoWay': twoWay,
        'last': lastRun,
        'state': state,
      };

  static SyncPair fromJson(Map<String, dynamic> m) {
    final st = <String, List<int>>{};
    (m['state'] as Map<String, dynamic>? ?? {}).forEach((k, v) => st[k] = (v as List).map((e) => (e as num).toInt()).toList());
    return SyncPair(
      id: m['id'] as String,
      folder: m['folder'] as String,
      label: (m['label'] ?? '') as String,
      key: m['key'] as String?,
      chatId: (m['chat'] as num?)?.toInt(),
      twoWay: m['twoWay'] == true,
      state: st,
    )..lastRun = (m['last'] as num?)?.toInt() ?? 0;
  }
}

class _LocalFile {
  final String rel;
  final int size;
  final int modifiedMs;
  final String? path; // Windows
  final String? uri; // Android
  _LocalFile(this.rel, this.size, this.modifiedMs, {this.path, this.uri});
}

class SyncManager {
  final Drive d;
  final List<SyncPair> pairs = [];
  Timer? _timer;
  static const _ch = MethodChannel('tirsodrive/native');

  SyncManager(this.d);

  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}sync_v1.json');

  Future<void> load() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return;
      final list = jsonDecode(await f.readAsString()) as List<dynamic>;
      pairs
        ..clear()
        ..addAll(list.map((e) => SyncPair.fromJson(e as Map<String, dynamic>)));
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(pairs.map((p) => p.toJson()).toList()));
    } catch (_) {}
  }

  /// Runs every pair now and then every 15 minutes while the app is open.
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => runAll());
    Future.delayed(const Duration(seconds: 8), runAll);
  }

  Future<void> runAll() async {
    for (final p in List<SyncPair>.from(pairs)) {
      await run(p);
    }
  }

  // ---------------- choosing a folder

  /// Windows: a folder path. Android: a folder the user grants access to.
  Future<(String, String)?> pickFolder() async {
    if (Platform.isAndroid) {
      final r = await _ch.invokeMethod<Map<dynamic, dynamic>>('pickTree');
      if (r == null) return null;
      return (r['uri'] as String, (r['name'] ?? 'Folder') as String);
    }
    final dir = await NativeBridge.pickFolderPath();
    if (dir == null) return null;
    return (dir, dir.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last);
  }

  Future<void> add(SyncPair p) async {
    pairs.add(p);
    await save();
    d.notifyListeners();
    unawaited(run(p));
  }

  Future<void> remove(SyncPair p) async {
    pairs.remove(p);
    await save();
    d.notifyListeners();
  }

  // ---------------- scanning

  Future<List<_LocalFile>> _listLocal(SyncPair p) async {
    if (Platform.isAndroid) {
      final res = await _ch.invokeMethod<List<dynamic>>('listTree', {'uri': p.folder});
      return (res ?? []).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return _LocalFile(m['path'] as String, (m['size'] as num).toInt(), (m['modified'] as num).toInt(), uri: m['uri'] as String);
      }).toList();
    }
    final root = Directory(p.folder);
    if (!root.existsSync()) throw Exception(t('sync_missing_folder'));
    final out = <_LocalFile>[];
    final base = root.absolute.path;
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = e.path.substring(base.length).replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
      final name = rel.split('/').last;
      if (name.startsWith('.') || name.toLowerCase() == 'desktop.ini' || name.toLowerCase() == 'thumbs.db' || name.endsWith('.tmp')) continue;
      try {
        final st = e.statSync();
        out.add(_LocalFile(rel, st.size, st.modified.millisecondsSinceEpoch, path: e.path));
      } catch (_) {}
    }
    return out;
  }

  Future<void> run(SyncPair p) async {
    if (p.running || d.step != AuthStep.ready) return;
    p.running = true;
    p.status = t('sync_scanning');
    d.notifyListeners();
    try {
      // 1. The channel (created if needed) and what is already in it
      final chatId = p.chatId ?? await d.ensureChannel(p.key!);
      if (p.chatId == null) {
        p.chatId = chatId;
        await save();
      }
      await d.loadFiles(chatId, refresh: true);
      final remote = <String, DriveFile>{};
      for (final f in d.filesByChat[chatId] ?? <DriveFile>[]) {
        remote.putIfAbsent(f.relPath, () => f);
      }

      // 2. Local files
      final local = await _listLocal(p);
      final localByRel = {for (final l in local) l.rel: l};
      var queued = 0, tooBig = 0, alreadyThere = 0;
      final busy = d.transfers.where((x) => x.upload && !x.finished && x.captionExtra.contains('sync=${p.id}')).map((x) => x.captionExtra).toSet();

      for (final l in local) {
        final st = p.state[l.rel];
        if (st != null && st[0] == l.size && st[1] == l.modifiedMs) continue; // unchanged
        final r = remote[l.rel];
        if (st == null && r != null && r.size == l.size) {
          p.state[l.rel] = [l.size, l.modifiedMs]; // already uploaded earlier (e.g. by hand) — don't upload twice
          alreadyThere++;
          continue;
        }
        if (l.size > d.maxBytes) {
          tooBig++;
          continue;
        }
        final extra = 'sync=${p.id} path=${Uri.encodeComponent(l.rel)}';
        if (busy.contains(extra)) continue;
        final replace = (st != null && r != null) ? r : null; // changed file: newer version replaces the old one
        final tr = Transfer.upload(
          name: l.rel.split('/').last,
          size: l.size,
          uri: l.uri,
          sourcePath: l.path,
          modifiedMs: l.modifiedMs,
          destChatId: chatId,
        )..captionExtra = extra;
        tr.onSent = (sent) {
          p.state[l.rel] = [l.size, l.modifiedMs];
          unawaited(save());
          if (replace != null && sent != null && replace.messageId != sent.messageId) {
            unawaited(d.deleteFiles([replace], quiet: true));
          }
        };
        d.enqueueUploads([tr], quiet: true);
        queued++;
      }

      // 3. Two-way: bring down files that are only in the channel (never ones you deleted from the folder)
      var downloaded = 0;
      if (p.twoWay) {
        for (final entry in remote.entries) {
          if (localByRel.containsKey(entry.key) || p.state.containsKey(entry.key)) continue;
          final path = await d.fetch(entry.value);
          if (path == null) continue;
          try {
            List<int> st;
            if (Platform.isAndroid) {
              final r = await _ch.invokeMethod<Map<dynamic, dynamic>>('writeToTree', {'tree': p.folder, 'rel': entry.key, 'src': path});
              st = [(r!['size'] as num).toInt(), (r['modified'] as num).toInt()];
              unawaited(d.dropLocal([entry.value.fileId])); // the folder copy is enough
            } else {
              final target = File('${p.folder}${Platform.pathSeparator}${entry.key.replaceAll('/', Platform.pathSeparator)}');
              target.parent.createSync(recursive: true);
              await File(path).copy(target.path);
              unawaited(d.dropLocal([entry.value.fileId]));
              final s = target.statSync();
              st = [s.size, s.modified.millisecondsSinceEpoch];
            }
            p.state[entry.key] = st;
            downloaded++;
            await save();
          } catch (_) {}
        }
      }

      final keptInCloud = p.state.keys.where((k) => !localByRel.containsKey(k) && remote.containsKey(k)).length;
      p.lastRun = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final parts = <String>[
        if (queued > 0) t('sync_up', {'n': queued}),
        if (downloaded > 0) t('sync_down', {'n': downloaded}),
        if (alreadyThere > 0) t('sync_already', {'n': alreadyThere}),
        if (tooBig > 0) t('sync_toobig', {'n': tooBig}),
        if (keptInCloud > 0) t('sync_kept', {'n': keptInCloud}),
      ];
      p.status = parts.isEmpty ? t('sync_uptodate', {'n': local.length}) : parts.join(' · ');
      await save();
    } catch (e) {
      p.status = t('err_generic', {'e': e is PlatformException ? (e.message ?? e.code) : e});
    }
    p.running = false;
    d.notifyListeners();
  }
}
