// Windows "T:" drive: a WebDAV server on this PC only (127.0.0.1), mapped to a drive letter.
// Root = your TirsoDrive channels as folders. Copying a file in uploads it; opening one streams it from Telegram;
// deleting moves it to the Trash. New folder at the root = new channel.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'desktop.dart';
import 'drive.dart';
import 'strings.dart';

class WebDavDrive {
  final Drive d;
  HttpServer? _server;
  String? letter; // mapped drive letter, e.g. "T:"
  String status = '';
  int hits = 0; // requests Windows has sent us (0 after a failed mapping = Windows never reached the server)
  final Map<String, (int, DateTime)> _pending = {}; // "/Channel/name" → being uploaded (size, time)

  WebDavDrive(this.d);

  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  // ---------------- start / stop

  Future<void> start() async {
    if (!Platform.isWindows || _server != null) return;
    for (var p = 8765; p < 8775; p++) {
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, p);
        break;
      } catch (_) {}
    }
    if (_server == null) {
      status = t('drive_err_port');
      d.notifyListeners();
      return;
    }
    _server!.listen((r) {
      hits++;
      DesktopHost.log('webdav ${r.method} ${r.uri} [${r.headers.value('user-agent') ?? ''}]');
      _handle(r).catchError((e) {
        DesktopHost.log('webdav handler error: $e');
      });
    });
    await DesktopHost.log('webdav server on 127.0.0.1:$port');
    await _selfTest();
    await _map();
  }

  Future<void> stop() async {
    if (letter != null) {
      await Process.run('net', ['use', letter!, '/delete', '/y']);
      letter = null;
    }
    await _server?.close(force: true);
    _server = null;
    status = '';
    d.notifyListeners();
  }

  /// Asks our own server the way Windows will, to prove it answers (and to write the answer to the log).
  Future<void> _selfTest() async {
    try {
      final c = HttpClient()..findProxy = (_) => 'DIRECT';
      final rq = await c.openUrl('PROPFIND', Uri.parse('http://127.0.0.1:$port/'));
      rq.headers.set('Depth', '0');
      final rs = await rq.close();
      final body = await utf8.decodeStream(rs);
      await DesktopHost.log('webdav self-test PROPFIND / -> ${rs.statusCode}, ${body.length} bytes');
      c.close(force: true);
      hits = 0;
    } catch (e) {
      await DesktopHost.log('webdav self-test failed: $e');
    }
    try {
      final r = await Process.run('netsh', ['winhttp', 'show', 'proxy']);
      await DesktopHost.log('winhttp proxy: ${'${r.stdout}'.replaceAll(RegExp(r'\s+'), ' ').trim()}');
      final w = await Process.run('sc', ['qc', 'WebClient']);
      await DesktopHost.log('WebClient config: ${'${w.stdout}'.replaceAll(RegExp(r'\s+'), ' ').trim()}');
    } catch (_) {}
  }

  /// 'running', 'stopped' or 'missing' (asks Windows itself; the old message guessed).
  Future<String> _webClientState() async {
    try {
      final o = '${(await Process.run('sc', ['query', 'WebClient'])).stdout}';
      if (o.contains('RUNNING')) return 'running';
      if (o.contains('STOPPED') || o.contains('START_PENDING')) return 'stopped';
    } catch (_) {}
    return 'missing';
  }

  /// Removes T: style mappings left over from a previous run that didn't close cleanly.
  Future<void> _dropStale() async {
    try {
      final o = '${(await Process.run('net', ['use'])).stdout}';
      for (final m in RegExp(r'([A-Z]):\s+\\\\127\.0\.0\.1@\d+|([A-Z]):\s+http://127\.0\.0\.1', caseSensitive: false).allMatches(o)) {
        final l = (m.group(1) ?? m.group(2))!.toUpperCase();
        await Process.run('net', ['use', '$l:', '/delete', '/y']);
      }
    } catch (_) {}
  }

  Future<void> _map() async {
    await _dropStale();
    var detail = '';
    var tries = 0;
    while (tries < 2) {
      tries++;
      for (final l in ['T:', 'U:', 'V:', 'W:', 'X:', 'Y:']) {
        if (Directory('$l\\').existsSync()) continue; // letter already used
        // two address forms: Windows accepts one or the other depending on its WebClient version
        for (final target in ['http://127.0.0.1:$port/', '\\\\127.0.0.1@$port\\DavWWWRoot', 'http://localhost:$port/', '\\\\localhost@$port\\DavWWWRoot']) {
          final r = await Process.run('net', ['use', l, target, '/persistent:no']);
          if (r.exitCode == 0) {
            letter = l;
            status = t('drive_on', {'l': l});
            d.notifyListeners();
            return;
          }
          detail = '${r.stderr}${r.stdout}'.replaceAll(RegExp(r'\s+'), ' ').trim();
          await DesktopHost.log('net use $l $target -> ${r.exitCode} $detail (server saw $hits requests)');
        }
        break; // the first free letter is the one we want; its failure isn't about the letter
      }
      if (tries == 1) {
        // The service starts on demand and may need a moment; if it is truly stopped, try starting it.
        if (await _webClientState() != 'running') {
          await Process.run('sc', ['start', 'WebClient']);
        }
        await Future.delayed(const Duration(seconds: 3));
      }
    }
    final state = await _webClientState();
    status = state == 'running'
        ? t('drive_err_map', {'e': '${detail.length > 140 ? detail.substring(0, 140) : detail} [requests: $hits]'})
        : t('drive_err_service');
    d.notifyListeners();
  }

  /// Windows limits WebDAV files to 50 MB unless this is raised (asks for admin permission once).
  static Future<void> allowBigFiles() async {
    const cmd = r'reg add HKLM\SYSTEM\CurrentControlSet\Services\WebClient\Parameters /v FileSizeLimitInBytes /t REG_DWORD /d 4294967295 /f; Restart-Service WebClient';
    await Process.run('powershell', ['-NoProfile', '-Command', "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-Command','$cmd'"]);
  }

  // ---------------- paths

  String _folderName(DriveChannel c) => c.display.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  List<DriveChannel> get _folders => d.channels.where((c) => c.title.toLowerCase() != Drive.trashTitle.toLowerCase()).toList();

  DriveChannel? _channel(String name) {
    for (final c in _folders) {
      if (_folderName(c).toLowerCase() == name.toLowerCase()) return c;
    }
    return null;
  }

  /// Unique file names inside a channel (two files with the same name get " [id]" added).
  Map<String, DriveFile> _filesOf(DriveChannel c) {
    final out = <String, DriveFile>{};
    for (final f in d.filesByChat[c.chatId] ?? <DriveFile>[]) {
      if (f.encrypted) continue; // encrypted files only open inside the app
      var name = f.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      if (out.containsKey(name.toLowerCase())) {
        final dot = name.lastIndexOf('.');
        name = dot > 0 ? '${name.substring(0, dot)} [${f.messageId}]${name.substring(dot)}' : '$name [${f.messageId}]';
      }
      out[name.toLowerCase()] = f;
    }
    return out;
  }

  List<String> _segments(Uri uri) => uri.pathSegments.where((s) => s.isNotEmpty).toList();

  // ---------------- requests

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.set('MS-Author-Via', 'DAV');
    final seg = _segments(req.uri);
    switch (req.method) {
      case 'OPTIONS':
        res.headers
          ..set('DAV', '1, 2')
          ..set('Allow', 'OPTIONS, GET, HEAD, PUT, DELETE, PROPFIND, PROPPATCH, MKCOL, MOVE, COPY, LOCK, UNLOCK');
        await res.close();
        return;
      case 'PROPFIND':
        await _propfind(req, seg);
        return;
      case 'PROPPATCH':
        res.statusCode = 207;
        res.headers.contentType = ContentType('application', 'xml', charset: 'utf-8');
        res.write('<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:"><D:response><D:href>${_href(seg, false)}</D:href>'
            '<D:propstat><D:prop/><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>');
        await res.close();
        return;
      case 'LOCK':
        final token = 'opaquelocktoken:${DateTime.now().microsecondsSinceEpoch}';
        res.statusCode = 200;
        res.headers.set('Lock-Token', '<$token>');
        res.headers.contentType = ContentType('application', 'xml', charset: 'utf-8');
        res.write('<?xml version="1.0" encoding="utf-8"?><D:prop xmlns:D="DAV:"><D:lockdiscovery><D:activelock>'
            '<D:locktype><D:write/></D:locktype><D:lockscope><D:exclusive/></D:lockscope><D:depth>0</D:depth>'
            '<D:timeout>Second-3600</D:timeout><D:locktoken><D:href>$token</D:href></D:locktoken></D:activelock></D:lockdiscovery></D:prop>');
        await res.close();
        return;
      case 'UNLOCK':
        res.statusCode = 204;
        await res.close();
        return;
      case 'GET':
      case 'HEAD':
        if (seg.length == 2) {
          final c = _channel(seg[0]);
          if (c != null) {
            await d.loadFiles(c.chatId);
            final f = _filesOf(c)[seg[1].toLowerCase()];
            if (f != null) {
              await d.streamer.serveFile(req, f);
              return;
            }
          }
          res.statusCode = HttpStatus.notFound;
        }
        await res.close();
        return;
      case 'PUT':
        await _put(req, seg);
        return;
      case 'DELETE':
        if (seg.length == 2) {
          final c = _channel(seg[0]);
          final f = c == null ? null : _filesOf(c)[seg[1].toLowerCase()];
          if (f != null) {
            await d.deleteFiles([f], quiet: true); // to the Trash
            res.statusCode = 204;
          } else {
            res.statusCode = _pending.remove('/${seg.join('/')}'.toLowerCase()) != null ? 204 : 404;
          }
        } else {
          res.statusCode = 403; // channels can't be deleted from Explorer
        }
        await res.close();
        return;
      case 'MKCOL':
        if (seg.length == 1) {
          final err = await d.createCustomChannel(seg[0]);
          res.statusCode = err == null ? 201 : 405;
        } else {
          res.statusCode = 403;
        }
        await res.close();
        return;
      case 'MOVE':
      case 'COPY':
        await _moveCopy(req, seg, req.method == 'MOVE');
        return;
    }
    res.statusCode = HttpStatus.methodNotAllowed;
    await res.close();
  }

  String _href(List<String> seg, bool folder) {
    final p = seg.map(Uri.encodeComponent).join('/');
    return '/$p${folder && p.isNotEmpty ? '/' : ''}';
  }

  String _entry(List<String> seg, {required bool folder, int size = 0, DateTime? time, String? mime}) {
    final when = HttpDate.format(time ?? DateTime.now());
    final name = seg.isEmpty ? 'TirsoDrive' : seg.last;
    return '<D:response><D:href>${_esc(_href(seg, folder))}</D:href><D:propstat><D:prop>'
        '<D:displayname>${_esc(name)}</D:displayname>'
        '<D:resourcetype>${folder ? '<D:collection/>' : ''}</D:resourcetype>'
        '${folder ? '' : '<D:getcontentlength>$size</D:getcontentlength><D:getcontenttype>${_esc(mime ?? 'application/octet-stream')}</D:getcontenttype>'}'
        '<D:getlastmodified>$when</D:getlastmodified><D:creationdate>${(time ?? DateTime.now()).toUtc().toIso8601String()}</D:creationdate>'
        '</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>';
  }

  static String _esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);

  Future<void> _propfind(HttpRequest req, List<String> seg) async {
    final res = req.response;
    await req.drain<void>();
    final depth = req.headers.value('Depth') ?? '1';
    final b = StringBuffer('<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:">');
    if (seg.isEmpty) {
      b.write(_entry(const [], folder: true));
      if (depth != '0') {
        for (final c in _folders) {
          b.write(_entry([_folderName(c)], folder: true));
        }
      }
    } else {
      final c = _channel(seg[0]);
      if (c == null) {
        res.statusCode = 404;
        await res.close();
        return;
      }
      await d.loadFiles(c.chatId);
      final files = _filesOf(c);
      if (seg.length == 1) {
        b.write(_entry([seg[0]], folder: true));
        if (depth != '0') {
          files.forEach((_, f) {
            b.write(_entry([seg[0], _displayName(files, f)], folder: false, size: f.size, time: DateTime.fromMillisecondsSinceEpoch(f.date * 1000), mime: f.mime));
          });
          _pending.forEach((k, v) {
            final parts = k.split('/').where((x) => x.isNotEmpty).toList();
            if (parts.length == 2 && parts[0] == seg[0].toLowerCase() && !files.containsKey(parts[1])) {
              b.write(_entry([seg[0], parts[1]], folder: false, size: v.$1, time: v.$2));
            }
          });
        }
      } else {
        final f = files[seg[1].toLowerCase()];
        final p = _pending['/${seg.join('/')}'.toLowerCase()];
        if (f != null) {
          b.write(_entry(seg, folder: false, size: f.size, time: DateTime.fromMillisecondsSinceEpoch(f.date * 1000), mime: f.mime));
        } else if (p != null) {
          b.write(_entry(seg, folder: false, size: p.$1, time: p.$2));
        } else {
          res.statusCode = 404;
          await res.close();
          return;
        }
      }
    }
    b.write('</D:multistatus>');
    res.statusCode = 207;
    res.headers.contentType = ContentType('application', 'xml', charset: 'utf-8');
    res.write(b.toString());
    await res.close();
  }

  String _displayName(Map<String, DriveFile> files, DriveFile f) {
    for (final e in files.entries) {
      if (identical(e.value, f)) {
        // keep the original capitalization when possible
        return e.key == f.name.toLowerCase() ? f.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_') : e.key;
      }
    }
    return f.name;
  }

  Future<void> _put(HttpRequest req, List<String> seg) async {
    final res = req.response;
    final c = seg.length == 2 ? _channel(seg[0]) : null;
    if (c == null) {
      await req.drain<void>();
      res.statusCode = 403; // files go inside a channel folder
      await res.close();
      return;
    }
    final dir = Directory('${(await getApplicationSupportDirectory()).path}\\webdav-in\\${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    final tmp = File('${dir.path}\\${seg[1]}');
    final sink = tmp.openWrite();
    await req.cast<List<int>>().pipe(sink);
    final size = tmp.lengthSync();
    final key = '/${seg.join('/')}'.toLowerCase();
    if (size == 0) {
      _pending[key] = (0, DateTime.now()); // Explorer creates an empty file first, then writes it
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    } else if (size > d.maxBytes) {
      res.statusCode = 507; // too large for Telegram
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
      await res.close();
      return;
    } else {
      _pending[key] = (size, DateTime.now());
      final tr = Transfer.upload(name: seg[1], size: size, sourcePath: tmp.path, modifiedMs: DateTime.now().millisecondsSinceEpoch, destChatId: c.chatId);
      tr.tempPath = tmp.path; // removed after the upload
      tr.onSent = (_) => _pending.remove(key);
      d.enqueueUploads([tr], quiet: true);
    }
    res.statusCode = 201;
    await res.close();
  }

  Future<void> _moveCopy(HttpRequest req, List<String> seg, bool move) async {
    final res = req.response;
    final destHeader = req.headers.value('Destination');
    final dest = destHeader == null ? null : _segments(Uri.parse(destHeader));
    if (seg.length != 2 || dest == null || dest.length != 2) {
      res.statusCode = 403; // only files can be moved/copied
      await res.close();
      return;
    }
    final from = _channel(seg[0]);
    final to = _channel(dest[0]);
    final f = from == null ? null : _filesOf(from)[seg[1].toLowerCase()];
    if (f == null || to == null) {
      res.statusCode = 404;
      await res.close();
      return;
    }
    if (from!.chatId == to.chatId) {
      if (move) await d.renameFile(f, dest[1]);
    } else {
      await d.copyFiles([f], toChatId: to.chatId, move: move);
    }
    res.statusCode = 201;
    await res.close();
  }
}
