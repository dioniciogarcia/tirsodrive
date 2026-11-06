// In-app video/audio player (streams while it downloads) and photo viewer.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/drive.dart';
import '../core/native.dart';
import '../core/strings.dart';

/// Plays a video/audio file. Android: inside the app. Windows: in VLC if installed, else the browser.
Future<void> playMedia(BuildContext context, Drive d, DriveFile f) async {
  final url = await d.streamer.urlFor(f);
  if (!Platform.isAndroid) {
    d.markTemp([f.fileId]); // partial download is cleaned the next time the app opens
    await NativeBridge.openStreamUrl(url);
    return;
  }
  if (!context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => _VideoScreen(drive: d, file: f, url: url)));
  await d.streamer.release(f);
}

Future<void> viewImage(BuildContext context, Drive d, DriveFile f) async {
  await Navigator.push(context, MaterialPageRoute(builder: (_) => _ImageScreen(drive: d, file: f)));
}

class _VideoScreen extends StatefulWidget {
  final Drive drive;
  final DriveFile file;
  final String url;
  const _VideoScreen({required this.drive, required this.file, required this.url});
  @override
  State<_VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<_VideoScreen> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _ready = false;
  String? _error;
  bool _controls = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    NativeBridge.keepAwake(true);
    _c.addListener(() {
      if (mounted) setState(() {});
    });
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c.play();
      _autoHide();
    }).catchError((e) {
      if (mounted) setState(() => _error = t('play_failed'));
    });
  }

  void _autoHide() {
    _hide?.cancel();
    _hide = Timer(Duration(seconds: 3), () {
      if (mounted && _c.value.isPlaying) setState(() => _controls = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c.dispose();
    NativeBridge.keepAwake(false);
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}' : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  void _seek(int seconds) {
    final p = _c.value.position + Duration(seconds: seconds);
    _c.seekTo(p < Duration.zero ? Duration.zero : p);
    _autoHide();
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    final buffered = v.buffered.isEmpty ? Duration.zero : v.buffered.last.end;
    final total = v.duration.inMilliseconds == 0 ? 1 : v.duration.inMilliseconds;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _controls = !_controls);
          if (_controls) _autoHide();
        },
        onDoubleTapDown: (det) => _seek(det.localPosition.dx < MediaQuery.of(context).size.width / 2 ? -10 : 10),
        child: Stack(children: [
          Center(
            child: _error != null
                ? Padding(padding: EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white)))
                : !_ready
                    ? Column(mainAxisSize: MainAxisSize.min, children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 14),
                        Text(t('streaming'), style: TextStyle(color: Colors.white70)),
                      ])
                    : AspectRatio(aspectRatio: v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio, child: VideoPlayer(_c)),
          ),
          if (_ready && v.isBuffering) Center(child: CircularProgressIndicator()),
          if (_controls || !_ready || _error != null) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Row(children: [
                  IconButton(tooltip: t('close'), onPressed: () => Navigator.pop(context), icon: Icon(Icons.arrow_back, color: Colors.white)),
                  Expanded(child: Text(widget.file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                  IconButton(
                    tooltip: t('rotate'),
                    onPressed: () {
                      final landscape = MediaQuery.of(context).orientation == Orientation.landscape;
                      SystemChrome.setPreferredOrientations(landscape
                          ? [DeviceOrientation.portraitUp]
                          : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
                      SystemChrome.setEnabledSystemUIMode(landscape ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
                    },
                    icon: Icon(Icons.screen_rotation, color: Colors.white),
                  ),
                ]),
              ),
            ),
            if (_ready)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: Container(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
                    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Stack(alignment: Alignment.centerLeft, children: [
                        FractionallySizedBox(
                          widthFactor: (buffered.inMilliseconds / total).clamp(0.0, 1.0),
                          child: Container(height: 3, margin: EdgeInsets.symmetric(horizontal: 24), color: Colors.white24),
                        ),
                        Slider(
                          value: v.position.inMilliseconds.clamp(0, total).toDouble(),
                          max: total.toDouble(),
                          onChanged: (x) {
                            _c.seekTo(Duration(milliseconds: x.round()));
                            _autoHide();
                          },
                        ),
                      ]),
                      Row(children: [
                        Text('${_fmt(v.position)} / ${_fmt(v.duration)}', style: TextStyle(color: Colors.white, fontSize: 12)),
                        Spacer(),
                        IconButton(tooltip: '-10 s', onPressed: () => _seek(-10), icon: Icon(Icons.replay_10, color: Colors.white)),
                        IconButton(
                          tooltip: v.isPlaying ? t('pause') : t('play'),
                          iconSize: 40,
                          onPressed: () {
                            v.isPlaying ? _c.pause() : _c.play();
                            _autoHide();
                          },
                          icon: Icon(v.isPlaying ? Icons.pause_circle : Icons.play_circle, color: Colors.white),
                        ),
                        IconButton(tooltip: '+10 s', onPressed: () => _seek(10), icon: Icon(Icons.forward_10, color: Colors.white)),
                        Spacer(),
                        SizedBox(width: 60),
                      ]),
                    ]),
                  ),
                ),
              ),
          ],
        ]),
      ),
    );
  }
}

class _ImageScreen extends StatefulWidget {
  final Drive drive;
  final DriveFile file;
  const _ImageScreen({required this.drive, required this.file});
  @override
  State<_ImageScreen> createState() => _ImageScreenState();
}

class _ImageScreenState extends State<_ImageScreen> {
  String? _path;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    widget.drive.fetch(widget.file).then((p) {
      if (!mounted) return;
      setState(() {
        _path = p;
        _failed = p == null;
      });
    });
  }

  @override
  void dispose() {
    widget.drive.markTemp([widget.file.fileId]); // removed from the device later; the photo stays in Telegram
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.file.name, style: TextStyle(fontSize: 15)),
      ),
      body: Center(
        child: _failed
            ? Text(t('open_failed'), style: TextStyle(color: Colors.white))
            : _path == null
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(t('loading_files'), style: TextStyle(color: Colors.white70)),
                  ])
                : InteractiveViewer(
                    minScale: 1,
                    maxScale: 8,
                    child: Image.file(
                      File(_path!),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Text(t('open_failed'), style: TextStyle(color: Colors.white)),
                    ),
                  ),
      ),
    );
  }
}

