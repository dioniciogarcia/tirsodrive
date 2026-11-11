// ===================================================================================================
//  UPDATE KIT — "Check for updates / Update now" from GitHub Releases.
//  Self-contained: to reuse it in another project copy this file, set the three constants below,
//  and provide NativeBridge.apkInfo / canInstall / openInstallSettings / installApk on Android
//  (see MainActivity.kt) plus the strings in strings.dart (keys starting with "upd_").
//  Windows: downloads the Inno Setup installer and runs it silently (it closes and restarts the app).
//  Android: downloads the APK to private storage, checks it, and opens Android's installer.
//  Only files from https://github.com/<repo>/releases/download/ are ever downloaded.
// ===================================================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native.dart';

enum UpdState { idle, checking, upToDate, available, downloading, installing, needsPermission, error }

/// Compares "0.10.2" style versions number by number (so 0.10 is newer than 0.9). Ignores "+build" and "-tag".
int compareVersions(String a, String b) {
  List<int> parts(String v) {
    final core = v.trim().replaceFirst(RegExp(r'^[vV]'), '').split(RegExp(r'[+\-]')).first;
    return core.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  }

  final x = parts(a), y = parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final u = i < x.length ? x[i] : 0, v = i < y.length ? y[i] : 0;
    if (u != v) return u.compareTo(v);
  }
  return 0;
}

class Updater extends ChangeNotifier {
  // ---- set these three for another project
  static const repo = 'dioniciogarcia/tirsodrive';
  static const windowsAsset = 'TirsoDrive-Setup.exe';
  static const androidAsset = 'TirsoDrive.apk';
  static const androidPackage = 'com.tirso.tirsodrive';

  static String get _prefix => 'https://github.com/$repo/releases/download/';
  static String get releasesPage => 'https://github.com/$repo/releases/latest';

  final String installed;
  final bool Function() transfersRunning;
  final Future<void> Function() exitApp;
  final void Function() onChange;
  Updater({required this.installed, required this.transfersRunning, required this.exitApp, required this.onChange});

  UpdState state = UpdState.idle;
  String latest = '';
  String notes = '';
  String error = '';
  double progress = 0;
  bool autoCheck = true;
  String? _url;
  int _size = 0;
  String? _readyApk; // downloaded and verified, waiting for the "allow installs" permission
  SharedPreferences? _prefs;

  /// Test hook: point the kit at a local server instead of api.github.com.
  @visibleForTesting
  String? apiOverride;
  @visibleForTesting
  bool skipHostCheck = false;
  @visibleForTesting
  String? platformOverride; // 'windows' | 'android'
  @visibleForTesting
  Future<void> Function(String path)? runInstaller;
  @visibleForTesting
  Directory? workDir;

  String get _platform => platformOverride ?? (Platform.isWindows ? 'windows' : (Platform.isAndroid ? 'android' : ''));
  bool get _win => _platform == 'windows';

  bool get available => state == UpdState.available || state == UpdState.needsPermission || (state == UpdState.downloading) || (state == UpdState.installing);
  bool get supported => _platform == 'windows' || _platform == 'android';
  bool get busy => state == UpdState.checking || state == UpdState.downloading || state == UpdState.installing;

  void _set(UpdState s, {String? err}) {
    state = s;
    if (err != null) error = err;
    notifyListeners();
    onChange();
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    autoCheck = _prefs!.getBool('upd_auto') ?? true;
    unawaited(_cleanup());
  }

  Future<void> setAuto(bool v) async {
    autoCheck = v;
    await _prefs?.setBool('upd_auto', v);
    notifyListeners();
  }

  /// Leftover installers/APKs from a previous update.
  Future<void> _cleanup() async {
    try {
      final dir = Directory(p.join((await getTemporaryDirectory()).path, 'updates'));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  /// Silent check shortly after start. Android: at most once every 6 hours. Never shows errors.
  Future<void> autoCheckNow() async {
    if (!supported || !autoCheck) return;
    final last = _prefs?.getInt('upd_last') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_platform == 'android' && now - last < 6 * 3600 * 1000) return;
    await check(silent: true);
  }

  Future<void> check({bool silent = false}) async {
    if (!supported || busy) return;
    if (!silent) _set(UpdState.checking);
    try {
      final j = await _getJson(apiOverride ?? 'https://api.github.com/repos/$repo/releases/latest');
      final tag = (j['tag_name'] ?? '').toString().replaceFirst(RegExp(r'^[vV]'), '');
      final want = _win ? windowsAsset : androidAsset;
      Map<String, dynamic>? asset;
      for (final a in (j['assets'] as List? ?? const [])) {
        if (a is Map<String, dynamic> && a['name'] == want) asset = a;
      }
      await _prefs?.setInt('upd_last', DateTime.now().millisecondsSinceEpoch);
      latest = tag;
      notes = (j['body'] ?? '').toString().trim();
      if (asset == null || tag.isEmpty) {
        if (!silent) _set(UpdState.upToDate); // a release without our file yet: nothing to install
        return;
      }
      final url = (asset['browser_download_url'] ?? '').toString();
      if (!skipHostCheck && !url.startsWith(_prefix)) throw 'unexpected download address';
      _url = url;
      _size = (asset['size'] as num?)?.toInt() ?? 0;
      _readyApk = null;
      _set(compareVersions(tag, installed) > 0 ? UpdState.available : UpdState.upToDate);
    } catch (e) {
      if (!silent) _set(UpdState.error, err: '$e');
    }
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final r = await (await c.getUrl(Uri.parse(url))
            ..headers.set('Accept', 'application/vnd.github+json')
            ..headers.set('User-Agent', 'TirsoDrive-updater'))
          .close()
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw 'GitHub answered ${r.statusCode}';
      return jsonDecode(await utf8.decodeStream(r)) as Map<String, dynamic>;
    } finally {
      c.close(force: true);
    }
  }

  /// Download, verify, install. The caller must already have checked that no transfer is running (or got a yes).
  Future<void> install() async {
    if (_url == null || state == UpdState.downloading || state == UpdState.installing) return;
    try {
      var path = _readyApk;
      if (path == null) {
        _set(UpdState.downloading);
        progress = 0;
        final dir = Directory(p.join((workDir ?? await getTemporaryDirectory()).path, 'updates'))..createSync(recursive: true);
        path = p.join(dir.path, _win ? windowsAsset : androidAsset);
        await _download(_url!, path, _size);
        await _verify(path);
        if (!_win) _readyApk = path;
      }
      _set(UpdState.installing);
      if (_win) {
        // The installer closes TirsoDrive, replaces the files and starts the new version. Nothing is touched before this point,
        // so a failed download leaves the installed program exactly as it was.
        if (runInstaller != null) {
          await runInstaller!(path);
          _set(UpdState.available);
          return;
        }
        await Process.start(path, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'], mode: ProcessStartMode.detached);
        await Future.delayed(const Duration(seconds: 2));
        await exitApp();
      } else {
        if (!await NativeBridge.canInstallApks()) {
          _set(UpdState.needsPermission);
          await NativeBridge.openInstallSettings();
          return;
        }
        await NativeBridge.installApk(path);
        _set(UpdState.available); // the Android installer takes over; if the user cancels they can tap again
      }
    } catch (e) {
      _readyApk = null;
      _set(UpdState.error, err: '$e');
    }
  }

  Future<void> _download(String url, String dest, int expected) async {
    if (!skipHostCheck && !url.startsWith(_prefix)) throw 'unexpected download address';
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final part = File('$dest.part');
    try {
      final r = await (await c.getUrl(Uri.parse(url))..headers.set('User-Agent', 'TirsoDrive-updater')).close();
      if (r.statusCode != 200) throw 'download failed (${r.statusCode})';
      final total = r.contentLength > 0 ? r.contentLength : expected;
      final sink = part.openWrite();
      var got = 0;
      var tick = DateTime.now();
      await for (final chunk in r.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        got += chunk.length;
        if (DateTime.now().difference(tick).inMilliseconds > 150) {
          tick = DateTime.now();
          progress = total > 0 ? got / total : 0;
          notifyListeners();
        }
      }
      await sink.close();
      if (expected > 0 && got != expected) throw 'incomplete download ($got of $expected bytes)';
      if (File(dest).existsSync()) File(dest).deleteSync();
      part.renameSync(dest);
      progress = 1;
      notifyListeners();
    } catch (_) {
      try {
        if (part.existsSync()) part.deleteSync();
      } catch (_) {}
      rethrow;
    } finally {
      c.close(force: true);
    }
  }

  /// Windows: must be a real program ("MZ"). Android: must be a valid APK of our app, with the version we expect and a higher version code.
  Future<void> _verify(String path) async {
    final f = File(path);
    if (_win) {
      final raf = await f.open();
      final head = await raf.read(2);
      await raf.close();
      if (head.length < 2 || head[0] != 0x4D || head[1] != 0x5A) throw 'the downloaded file is not a Windows program';
    } else {
      final info = await NativeBridge.apkInfo(path);
      if (info == null) throw 'the downloaded file is not a valid APK';
      if (info['package'] != androidPackage) throw 'the APK is for a different app (${info['package']})';
      final code = (info['versionCode'] as num).toInt();
      final mine = (info['installedVersionCode'] as num).toInt();
      if (code <= mine) throw 'the APK is not newer than the installed app';
    }
  }

  Future<void> openReleases() => NativeBridge.openUrl(releasesPage);
}
