import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tirsodrive/core/updater.dart';

void main() {
  test('version comparison is numeric (0.10 is newer than 0.9)', () {
    expect(compareVersions('0.10.0', '0.9.9') > 0, true);
    expect(compareVersions('v1.2.3', '1.2.3'), 0);
    expect(compareVersions('1.2', '1.2.0'), 0);
    expect(compareVersions('0.13.1+1301', '0.13.1'), 0);
    expect(compareVersions('0.12.9', '0.13.0') < 0, true);
    expect(compareVersions('2.0.0', '1.99.99') > 0, true);
  });

  group('with a fake GitHub release on a local server', () {
    late HttpServer server;
    late Directory tmp;
    String exeBody = 'MZ${'x' * 1000}';
    String tag = 'v9.9.9';
    int sizeLie = 0;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = Directory.systemTemp.createTempSync('upd');
      server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) async {
        final base = 'http://127.0.0.1:${server.port}';
        if (req.uri.path == '/release') {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({
            'tag_name': tag,
            'body': 'Version 9.9.9 → new things — ok',
            'assets': [
              {'name': 'TirsoDrive-Setup.exe', 'browser_download_url': '$base/dl/TirsoDrive-Setup.exe', 'size': exeBody.length + sizeLie},
              {'name': 'TirsoDrive.apk', 'browser_download_url': '$base/dl/TirsoDrive.apk', 'size': 10},
            ],
          }));
        } else if (req.uri.path == '/dl/TirsoDrive-Setup.exe') {
          req.response.add(utf8.encode(exeBody));
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      tmp.deleteSync(recursive: true);
    });

    Updater make(String installed, {void Function(String)? ran}) {
      final u = Updater(installed: installed, transfersRunning: () => false, exitApp: () async {}, onChange: () {});
      u.apiOverride = 'http://127.0.0.1:${server.port}/release';
      u.skipHostCheck = true;
      u.platformOverride = 'windows';
      u.workDir = tmp;
      u.runInstaller = (p) async => ran?.call(p);
      return u;
    }

    test('finds a newer release and its notes (UTF-8 intact)', () async {
      final u = make('0.13.1');
      await u.init();
      await u.check();
      expect(u.state, UpdState.available);
      expect(u.latest, '9.9.9');
      expect(u.notes.contains('→'), true);
    });

    test('same or older version = up to date', () async {
      tag = 'v0.13.1';
      final u = make('0.13.1');
      await u.init();
      await u.check();
      expect(u.state, UpdState.upToDate);
      tag = 'v9.9.9';
    });

    test('downloads, verifies size and "MZ", then runs the installer', () async {
      String? ranWith;
      final u = make('0.13.1', ran: (p) => ranWith = p);
      await u.init();
      await u.check();
      await u.install();
      expect(ranWith, isNotNull);
      expect(File(ranWith!).readAsStringSync().startsWith('MZ'), true);
      expect(u.state, UpdState.available);
    });

    test('a file that is not a program is refused and nothing is run', () async {
      exeBody = 'NOTANEXE${'x' * 500}';
      String? ranWith;
      final u = make('0.13.1', ran: (p) => ranWith = p);
      await u.init();
      await u.check();
      await u.install();
      expect(ranWith, isNull);
      expect(u.state, UpdState.error);
      exeBody = 'MZ${'x' * 1000}';
    });

    test('a truncated download (wrong size) is refused', () async {
      sizeLie = 50;
      String? ranWith;
      final u = make('0.13.1', ran: (p) => ranWith = p);
      await u.init();
      await u.check();
      await u.install();
      expect(ranWith, isNull);
      expect(u.state, UpdState.error);
      expect(File('${tmp.path}/updates/TirsoDrive-Setup.exe.part').existsSync(), false);
      sizeLie = 0;
    });

    test('downloads from any other address are refused when the host check is on', () async {
      final u = make('0.13.1');
      u.skipHostCheck = false;
      await u.init();
      await u.check();
      expect(u.state, UpdState.error);
    });

    test('no internet: a silent check shows no error', () async {
      final u = make('0.13.1');
      u.apiOverride = 'http://127.0.0.1:1/none';
      await u.init();
      await u.check(silent: true);
      expect(u.state, UpdState.idle);
    });
  });
}
