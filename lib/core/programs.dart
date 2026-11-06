// "Connected programs" (option B): each program, like Tirso Compiler, gets its own Telegram bot
// that can only post in its own channels. TirsoDrive creates the bot through @BotFather for you.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'drive.dart';
import 'native.dart';
import 'strings.dart';
import '../td/td_client.dart';

const tirsoConsoles = ['N64', 'DS', 'PSP', 'PS2', 'GameCube', 'Wii'];

class ConnectedProgram {
  final String name;
  final String botUsername;
  final int botId;
  final String token;
  final Map<String, int> channels; // console → chat id
  ConnectedProgram(this.name, this.botUsername, this.botId, this.token, this.channels);

  Map<String, dynamic> toJson() => {'name': name, 'bot': botUsername, 'botId': botId, 'token': token, 'channels': channels};
  static ConnectedProgram fromJson(Map<String, dynamic> m) => ConnectedProgram(
        m['name'] as String,
        m['bot'] as String,
        (m['botId'] as num).toInt(),
        m['token'] as String,
        (m['channels'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toInt())),
      );
}

class Programs {
  final Drive d;
  final List<ConnectedProgram> list = [];
  String progress = '';
  bool busy = false;
  Programs(this.d);

  void load(String? raw) {
    list.clear();
    if (raw == null) return;
    try {
      list.addAll((jsonDecode(raw) as List).map((e) => ConnectedProgram.fromJson(e as Map<String, dynamic>)));
    } catch (_) {}
  }

  String get json => jsonEncode(list.map((p) => p.toJson()).toList());

  void _step(String s) {
    progress = s;
    d.notifyListeners();
  }

  // ---- talking to @BotFather

  Future<String> _ask(int chatId, String text) async {
    final c = Completer<String>();
    late StreamSubscription<Map<String, dynamic>> sub;
    sub = d.td.updates.listen((u) {
      if (u['@type'] != 'updateNewMessage') return;
      final m = u['message'] as Map<String, dynamic>;
      if ((m['chat_id'] as num).toInt() != chatId || m['is_outgoing'] == true) return;
      final txt = (m['content']?['text']?['text'] ?? '').toString();
      if (!c.isCompleted) c.complete(txt);
    });
    await d.td.call({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': text, 'entities': <dynamic>[]},
      },
    });
    try {
      return await c.future.timeout(const Duration(seconds: 40));
    } on TimeoutException {
      throw Exception(t('prog_err_timeout'));
    } finally {
      await sub.cancel();
    }
  }

  /// Creates the bot, the channels, gives the bot access to only those channels, and saves the setup file.
  Future<String?> connectTirso() async {
    if (busy) return null;
    busy = true;
    try {
      _step(t('prog_step_bot'));
      final bf = await d.td.call({'@type': 'searchPublicChat', 'username': 'BotFather'});
      final bfId = (bf['id'] as num).toInt();
      await d.td.call({'@type': 'openChat', 'chat_id': bfId});
      var reply = await _ask(bfId, '/newbot');
      if (!reply.toLowerCase().contains('name')) throw Exception(reply);
      reply = await _ask(bfId, 'Tirso Compiler (TirsoDrive)');
      String? token;
      String username = '';
      final rnd = Random.secure();
      for (var attempt = 0; attempt < 4 && token == null; attempt++) {
        username = 'tirso_${List.generate(6, (_) => 'abcdefghijkmnpqrstuvwxyz23456789'[rnd.nextInt(32)]).join()}_bot';
        reply = await _ask(bfId, username);
        token = RegExp(r'(\d{6,}:[A-Za-z0-9_-]{30,})').firstMatch(reply)?.group(1);
        if (token == null && !reply.toLowerCase().contains('taken') && !reply.toLowerCase().contains('invalid')) throw Exception(reply);
      }
      if (token == null) throw Exception(reply);
      final botId = int.parse(token.split(':').first);
      await d.td.call({'@type': 'searchPublicChat', 'username': username}); // so Telegram knows the bot

      final channels = <String, int>{};
      for (final console in tirsoConsoles) {
        _step(t('prog_step_channel', {'c': console}));
        final title = 'TD - $console APKs';
        var existing = d.channels.where((c) => c.title.toLowerCase() == title.toLowerCase());
        if (existing.isEmpty) {
          final err = await d.createCustomChannel('$console APKs');
          if (err != null) throw Exception(err);
          existing = d.channels.where((c) => c.title.toLowerCase() == title.toLowerCase());
        }
        final chatId = existing.first.chatId;
        await d.td.call({
          '@type': 'setChatMemberStatus',
          'chat_id': chatId,
          'member_id': {'@type': 'messageSenderUser', 'user_id': botId},
          'status': {
            '@type': 'chatMemberStatusAdministrator',
            'can_be_edited': true,
            'rights': {
              '@type': 'chatAdministratorRights',
              'can_manage_chat': true,
              'can_post_messages': true,
              'can_edit_messages': true,
              'can_delete_messages': true,
            },
          },
        });
        channels[console] = chatId;
      }
      final p = ConnectedProgram('Tirso Compiler', username, botId, token, channels);
      list.removeWhere((x) => x.name == p.name);
      list.add(p);
      _step(t('prog_step_file'));
      final where = await exportConfig(p);
      d.savePrograms();
      return where;
    } on TdError catch (e) {
      throw Exception(e.retryAfter != null ? t('err_flood', {'s': e.retryAfter}) : e.message);
    } finally {
      busy = false;
      progress = '';
      d.notifyListeners();
    }
  }

  /// Writes the setup file Tirso Compiler reads (bot token + one channel per console).
  Future<String> exportConfig(ConnectedProgram p) async {
    final cfg = const JsonEncoder.withIndent('  ').convert({
      'program': p.name,
      'api_id': d.apiId,
      'api_hash': d.apiHash,
      'bot_username': p.botUsername,
      'bot_token': p.token,
      'channels': p.channels, // console → Telegram chat id
      'naming': 'TV builds: add " TV" to the APK file name only, e.g. "Super Mario 64 TV.apk"; never to the app name.',
      'max_file_bytes': d.maxBytes,
    });
    final tmp = File('${Directory.systemTemp.path}${Platform.pathSeparator}tirso-compiler-telegram.json');
    await tmp.writeAsString(cfg);
    return NativeBridge.saveToDownloads(tmp.path, 'tirso-compiler-telegram.json', 'application/json');
  }

  /// Ends the program's access immediately: the bot is removed from all its channels. Files stay.
  Future<void> disconnect(ConnectedProgram p) async {
    for (final chatId in p.channels.values) {
      try {
        await d.td.call({
          '@type': 'setChatMemberStatus',
          'chat_id': chatId,
          'member_id': {'@type': 'messageSenderUser', 'user_id': p.botId},
          'status': {'@type': 'chatMemberStatusBanned', 'banned_until_date': 0},
        });
      } catch (_) {}
    }
    list.remove(p);
    d.savePrograms();
    d.notifyListeners();
  }
}
