// Low-level bridge to TDLib (Telegram's official client library) through its JSON interface.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

typedef _CreateC = Int32 Function();
typedef _CreateD = int Function();
typedef _SendC = Void Function(Int32, Pointer<Utf8>);
typedef _SendD = void Function(int, Pointer<Utf8>);
typedef _RecvC = Pointer<Utf8> Function(Double);
typedef _RecvD = Pointer<Utf8> Function(double);
typedef _ExecC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ExecD = Pointer<Utf8> Function(Pointer<Utf8>);

DynamicLibrary _openLib() {
  if (Platform.isAndroid) return DynamicLibrary.open('libtdjson.so');
  if (Platform.isWindows) return DynamicLibrary.open('tdjson.dll');
  if (Platform.isMacOS) return DynamicLibrary.open('libtdjson.dylib');
  return DynamicLibrary.open('libtdjson.so');
}

/// An error returned by Telegram (for example PHONE_CODE_INVALID).
class TdError implements Exception {
  final int code;
  final String message;
  TdError(this.code, this.message);

  /// Seconds Telegram asks us to wait (FLOOD_WAIT / "retry after N"), or null.
  int? get retryAfter {
    final m = RegExp(r'retry after (\d+)', caseSensitive: false).firstMatch(message) ??
        RegExp(r'FLOOD_WAIT_(\d+)').firstMatch(message);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  @override
  String toString() => message;
}

/// Runs in a background isolate: waits for TDLib events and passes them to the app.
void _receiveLoop(SendPort port) {
  final lib = _openLib();
  final recv = lib.lookupFunction<_RecvC, _RecvD>('td_receive');
  while (true) {
    final p = recv(1.0);
    if (p != nullptr) port.send(p.toDartString());
  }
}

class TdClient {
  late final DynamicLibrary _lib;
  late final _SendD _send;
  late final _ExecD _exec;
  late final _CreateD _create;

  int clientId = 0;
  int _seq = 0;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  final StreamController<Map<String, dynamic>> _updates = StreamController.broadcast();

  Stream<Map<String, dynamic>> get updates => _updates.stream;

  bool _started = false;

  Future<void> start() async {
    if (_started) {
      newClient();
      return;
    }
    _started = true;
    _lib = _openLib();
    _create = _lib.lookupFunction<_CreateC, _CreateD>('td_create_client_id');
    _send = _lib.lookupFunction<_SendC, _SendD>('td_send');
    _exec = _lib.lookupFunction<_ExecC, _ExecD>('td_execute');
    execute({'@type': 'setLogVerbosityLevel', 'new_verbosity_level': 1});
    final rp = ReceivePort();
    rp.listen(_onMessage);
    await Isolate.spawn(_receiveLoop, rp.sendPort);
    newClient();
  }

  /// Creates a fresh TDLib instance (used at start and after logging out / resetting login).
  void newClient() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(TdError(0, 'Client restarted'));
    }
    _pending.clear();
    clientId = _create();
    // Any request wakes the instance up; TDLib then reports its authorization state.
    send({'@type': 'getOption', 'name': 'version'});
  }

  void _onMessage(dynamic raw) {
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final cid = m['@client_id'];
    if (cid is int && cid != clientId) return; // message from an old, closed instance
    final extra = m['@extra'];
    if (extra is String && _pending.containsKey(extra)) {
      final c = _pending.remove(extra)!;
      if (m['@type'] == 'error') {
        c.completeError(TdError((m['code'] as num?)?.toInt() ?? 0, (m['message'] ?? '').toString()));
      } else {
        c.complete(m);
      }
      return;
    }
    _updates.add(m);
  }

  void send(Map<String, dynamic> request) {
    final s = jsonEncode(request).toNativeUtf8();
    _send(clientId, s);
    malloc.free(s);
  }

  /// Sends a request and waits for Telegram's answer.
  Future<Map<String, dynamic>> call(Map<String, dynamic> request) {
    final id = 'r${++_seq}';
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    send({...request, '@extra': id});
    return c.future;
  }

  Map<String, dynamic>? execute(Map<String, dynamic> request) {
    final s = jsonEncode(request).toNativeUtf8();
    final r = _exec(s);
    malloc.free(s);
    if (r == nullptr) return null;
    return jsonDecode(r.toDartString()) as Map<String, dynamic>;
  }
}
