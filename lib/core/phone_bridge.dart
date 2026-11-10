// Android: everything the watch app and the "TirsoDrive in the file picker" storage location need from this app.
//  - keeps a small index file (td_index.json) up to date: categories, files, favorite contacts
//  - uploads files that other apps saved into TirsoDrive (the inbox)
//  - sends files to the watch's favorite contacts when the watch asks
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'categories.dart';
import 'drive.dart';
import 'strings.dart';

class PhoneBridge {
  final Drive d;
  PhoneBridge(this.d);

  Timer? _debounce;
  String _lastIndex = '';
  final Set<String> _queued = {};
  bool _started = false;

  Future<Directory> get _dir => getApplicationSupportDirectory();

  void start() {
    if (_started || !Platform.isAndroid) return;
    _started = true;
    d.addListener(_changed);
    _changed();
    scanInbox();
    handleWearShares();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), writeIndex);
  }

  // ---------------------------------------------------------------- index

  DateTime? _contactsAt;
  List<ShareTarget> _contacts = [];

  Future<void> writeIndex() async {
    if (d.step != AuthStep.ready) return;
    final hidden = d.isolatedChats;
    final groups = <Map<String, dynamic>>[];
    var hasApk = false, hasRom = false;
    Map<String, dynamic> g(DriveChannel c) {
      final cat = c.category;
      return {
        'key': cat?.key ?? 'chat',
        'title': c.display,
        'chatId': c.chatId,
        'parent': cat == null ? null : (cat.isApk ? 'apks' : (cat.isRom ? 'roms' : null)),
        'logo': cat?.logo,
        'count': d.filesByChat[c.chatId]?.length ?? 0,
      };
    }

    final chans = d.channels.where((c) => c.title.toLowerCase() != Drive.trashTitle.toLowerCase() && !hidden.contains(c.chatId)).toList();
    int rank(DriveChannel c) {
      final cat = c.category;
      if (cat == null) return 900;
      if (cat.isApk) return 300;
      if (cat.isRom) return 400;
      final i = libraryCategories.indexWhere((x) => x.key == cat.key);
      return i < 0 ? 800 : i * 10;
    }

    chans.sort((a, b) => rank(a).compareTo(rank(b)));
    for (final c in chans) {
      final m = g(c);
      if (m['parent'] == 'apks') hasApk = true;
      if (m['parent'] == 'roms') hasRom = true;
      groups.add(m);
    }
    // virtual parents (Games APKs by console / ROMs by console)
    int at(String parentFirst) => groups.indexWhere((x) => x['parent'] == parentFirst);
    if (hasRom) groups.insert(at('roms'), {'key': 'roms', 'title': t('roms'), 'chatId': 0, 'parent': null, 'kids': true});
    if (hasApk) groups.insert(at('apks'), {'key': 'apks', 'title': t('apks'), 'chatId': 0, 'parent': null, 'kids': true});

    final files = <Map<String, dynamic>>[];
    for (final f in d.allFiles) {
      if (files.length >= 6000) break;
      files.add({'i': f.messageId, 'c': f.chatId, 'n': f.name, 's': f.size, 'd': f.date, 'm': f.mime});
    }
    // contacts for the watch: recent chats (same list as the phone's share picker) + everyone, for searching
    final chats = d.shareChats();
    final recent = chats.take(25).map((e) => {'id': e.chatId, 'name': e.title}).toList();
    if (_contactsAt == null || DateTime.now().difference(_contactsAt!).inMinutes > 60) {
      _contactsAt = DateTime.now();
      _contacts = await d.shareContacts(chats.map((e) => e.chatId).toSet());
    }
    final all = <Map<String, dynamic>>[
      for (final c in [...chats, ..._contacts].take(1500)) {'id': c.chatId, 'name': c.title}
    ];
    final body = jsonEncode({'v': 1, 'lang': appLang, 'groups': groups, 'files': files, 'recent': recent, 'all': all});
    if (body == _lastIndex) return;
    _lastIndex = body;
    final out = File('${(await _dir).path}${Platform.pathSeparator}td_index.json');
    await out.writeAsString(jsonEncode({...jsonDecode(body) as Map<String, dynamic>, 'updated': DateTime.now().millisecondsSinceEpoch}));
  }

  // ---------------------------------------------------------------- inbox (files saved into TirsoDrive by other apps)

  Future<void> scanInbox() async {
    try {
      final inbox = Directory('${(await _dir).path}${Platform.pathSeparator}inbox');
      if (!inbox.existsSync()) return;
      var again = false;
      for (final cd in inbox.listSync().whereType<Directory>()) {
        final chat = int.tryParse(cd.path.split(Platform.pathSeparator).last);
        if (chat == null || d.channelById(chat) == null) continue;
        for (final f in cd.listSync().whereType<File>()) {
          if (_queued.contains(f.path)) continue;
          final st = f.statSync();
          if (st.size == 0 || DateTime.now().difference(st.modified).inSeconds < 4) {
            again = true; // still being written
            continue;
          }
          _queued.add(f.path);
          final name = f.path.split(Platform.pathSeparator).last;
          final tr = Transfer.upload(name: name, size: st.size, sourcePath: f.path, modifiedMs: st.modified.millisecondsSinceEpoch, destChatId: chat);
          tr.tempPath = f.path; // removed once uploaded
          tr.onSent = (_) => _queued.remove(f.path);
          d.enqueueUploads([tr], quiet: true);
        }
      }
      if (again) Timer(const Duration(seconds: 6), scanInbox);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- watch → share a file to a favorite contact

  Future<void> handleWearShares() async {
    try {
      final f = File('${(await _dir).path}${Platform.pathSeparator}wear_share.json');
      if (!f.existsSync()) return;
      final list = jsonDecode(await f.readAsString()) as List;
      await f.delete();
      for (final r in list) {
        final m = r as Map<String, dynamic>;
        final to = (m['to'] as num).toInt();
        final file = d.allFiles.where((x) => x.chatId == (m['c'] as num).toInt() && x.messageId == (m['i'] as num).toInt()).firstOrNull;
        if (file == null) continue;
        final known = d.shareChats().where((e) => e.chatId == to).firstOrNull ?? _contacts.where((e) => e.chatId == to).firstOrNull;
        if (known == null) continue; // only people/chats from the phone's own lists
        await d.sendToChat(known, [file]);
      }
    } catch (_) {}
  }
}
