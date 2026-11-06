// Streams Telegram files to a video player without downloading them first.
// A tiny web server on this device only (127.0.0.1) answers the player's byte-range requests
// by downloading just those parts from Telegram.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'drive.dart';

class StreamServer {
  final Drive d;
  HttpServer? _server;
  final Map<String, DriveFile> _files = {};
  final _rnd = Random.secure();

  StreamServer(this.d);

  /// Returns a local link a player can open, e.g. `http://127.0.0.1:51234/s/TOKEN/movie.mp4`
  Future<String> urlFor(DriveFile f) async {
    _server ??= await _start();
    final token = List.generate(16, (_) => _rnd.nextInt(16).toRadixString(16)).join();
    _files[token] = f;
    return 'http://127.0.0.1:${_server!.port}/s/$token/${Uri.encodeComponent(f.name)}';
  }

  /// Stops serving a file and removes its partial download from the device.
  Future<void> release(DriveFile f) async {
    _files.removeWhere((_, v) => v.fileId == f.fileId);
    try {
      await d.td.call({'@type': 'cancelDownloadFile', 'file_id': f.fileId, 'only_if_pending': false});
    } catch (_) {}
    await d.dropLocal([f.fileId]);
  }

  Future<HttpServer> _start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0); // this device only
    s.listen((req) => _handle(req).catchError((_) {}));
    return s;
  }

  Future<void> _handle(HttpRequest req) async {
    final parts = req.uri.pathSegments;
    final f = parts.length >= 2 && parts[0] == 's' ? _files[parts[1]] : null;
    if (f == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    await serveFile(req, f, keepServing: () => _files.containsValue(f));
  }

  /// Answers a GET/HEAD (with byte ranges) for [f] by reading the needed parts from Telegram.
  Future<void> serveFile(HttpRequest req, DriveFile f, {bool Function()? keepServing}) async {
    final res = req.response;
    final total = f.size;
    var start = 0;
    var end = total - 1;
    final range = req.headers.value(HttpHeaders.rangeHeader);
    final m = range == null ? null : RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
    if (m != null) {
      if (m.group(1)!.isNotEmpty) start = int.parse(m.group(1)!);
      if (m.group(2)!.isNotEmpty) end = int.parse(m.group(2)!);
      if (m.group(1)!.isEmpty && m.group(2)!.isNotEmpty) {
        start = total - int.parse(m.group(2)!); // "last N bytes"
        end = total - 1;
      }
    }
    if (start >= total || start < 0) {
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
      await res.close();
      return;
    }
    end = min(end, total - 1);
    res.statusCode = m != null ? HttpStatus.partialContent : HttpStatus.ok;
    res.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..contentType = ContentType.parse(f.mime.isEmpty ? 'application/octet-stream' : f.mime)
      ..contentLength = end - start + 1;
    if (m != null) res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }

    // Ask Telegram for the file from this point on (high priority), then send it as it arrives.
    try {
      await d.td.call({'@type': 'downloadFile', 'file_id': f.fileId, 'priority': 32, 'offset': start, 'limit': 0, 'synchronous': false});
    } catch (_) {}
    var pos = start;
    const chunk = 512 * 1024;
    var idle = 0;
    try {
      while (pos <= end && (keepServing?.call() ?? true)) {
        final want = min(chunk, end - pos + 1);
        final pre = await d.td.call({'@type': 'getFileDownloadedPrefixSize', 'file_id': f.fileId, 'offset': pos});
        final ready = (pre['size'] as num?)?.toInt() ?? 0;
        if (ready <= 0) {
          if (++idle > 600) break; // ~60 s without data: give up on this request
          if (idle % 50 == 0) {
            // nudge the download again (another request may have moved it)
            try {
              await d.td.call({'@type': 'downloadFile', 'file_id': f.fileId, 'priority': 32, 'offset': pos, 'limit': 0, 'synchronous': false});
            } catch (_) {}
          }
          await Future.delayed(const Duration(milliseconds: 100));
          continue;
        }
        idle = 0;
        final n = min(want, ready);
        final data = await d.td.call({'@type': 'readFilePart', 'file_id': f.fileId, 'offset': pos, 'count': n});
        final bytes = base64Decode((data['data'] ?? '') as String);
        if (bytes.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 100));
          continue;
        }
        res.add(bytes);
        await res.flush();
        pos += bytes.length;
      }
    } catch (_) {
      // the player closed the connection (seek or close) — normal
    }
    try {
      await res.close();
    } catch (_) {}
  }
}

const _videoExt = {'mp4', 'mkv', 'webm', 'mov', 'm4v', '3gp', 'avi', 'ts', 'mpg', 'mpeg', 'wmv', 'flv'};
const _audioExt = {'mp3', 'm4a', 'aac', 'flac', 'ogg', 'opus', 'wav'};
const _imageExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif'};

bool isPlayable(DriveFile f) => _videoExt.contains(f.ext.toLowerCase()) || _audioExt.contains(f.ext.toLowerCase()) || f.mime.startsWith('video/') || f.mime.startsWith('audio/');
bool isImage(DriveFile f) => _imageExt.contains(f.ext.toLowerCase()) || f.mime.startsWith('image/');
