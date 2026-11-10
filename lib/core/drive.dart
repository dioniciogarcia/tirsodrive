// The heart of TirsoDrive: sign-in, channels, files and the transfer queue.
import 'package:image/image.dart' as img;
import 'desktop.dart';
import 'phone_bridge.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' hide Category;

import '../ui/theme.dart' show C;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../td/td_client.dart';
import 'categories.dart';
import 'native.dart';
import 'programs.dart';
import 'stream_server.dart';
import 'sync.dart';
import 'vault.dart';
import 'webdav.dart';
import 'strings.dart';

/// Fill these in to build the API ID/hash into the app. Left empty, the app asks once on first launch.
const int builtInApiId = 38798734;
const String builtInApiHash = 'dee69532c862a3a3975eda119ba52223';
const String appVersion = '0.11.2';

class DriveChannel {
  final int chatId;
  String title;
  DriveChannel(this.chatId, this.title);
  Category? get category => categoryByTitle(title);
  String get display {
    final c = category;
    if (c != null) return c.label(appLang);
    return title.startsWith(channelPrefix) ? title.substring(channelPrefix.length) : title;
  }
}

class DriveFile {
  final int chatId;
  final int messageId;
  final String name;
  final int size;
  final int date;
  final String mime;
  final int fileId;
  final int? originalMs;
  final String caption; // TirsoDrive's own caption (mtime=, name=, path=, ...)
  final int? thumbId; // Telegram's preview image for this file, when it has one
  List<String> get _words => caption.split(RegExp(r'\s+'));
  bool get fav => _words.contains('fav');
  List<String> get collections => [
        for (final w in _words)
          if (w.startsWith('col=')) Uri.decodeComponent(w.substring(4))
      ];
  int? get trashedAt => _tagInt('trashed');
  int? get trashedFrom => _tagInt('from');
  bool get encrypted => _words.contains('enc=1');
  int? _tagInt(String k) {
    for (final w in _words) {
      if (w.startsWith('$k=')) return int.tryParse(w.substring(k.length + 1));
    }
    return null;
  }

  /// Folder-relative path for synced files ("Pokemon/Emerald.gba"), else just the name.
  String get relPath {
    final m = RegExp(r'(?:^|\s)path=(\S+)').firstMatch(caption);
    if (m != null) {
      try {
        return Uri.decodeComponent(m.group(1)!);
      } catch (_) {}
    }
    return name;
  }
  DriveFile({
    required this.chatId,
    required this.messageId,
    required this.name,
    required this.size,
    required this.date,
    required this.mime,
    required this.fileId,
    this.originalMs,
    this.caption = '',
    this.thumbId,
  });
  bool get previewable => !encrypted && (mime.startsWith('image/') || mime.startsWith('video/'));
  String get ext => extensionOf(name).toUpperCase();
}

class ShareTarget {
  final int chatId;
  final String title;
  final bool group;
  final int? userId; // contacts without a chat yet
  const ShareTarget({required this.chatId, required this.title, this.group = false, this.userId});
}

enum TStatus { queued, preparing, creating, waiting, active, done, failed, cancelled }

class Transfer {
  static int _ids = 0;
  final int id = ++_ids;
  final bool upload;
  final String name;
  final int size;
  // upload source
  final String? uri;
  final String? sourcePath;
  final int? modifiedMs;
  // upload destination
  String? destKey;
  int? destChatId;
  // download
  final DriveFile? file;
  final String? action; // 'open' or 'save'
  // sync: extra caption words (e.g. "path=..."), and a hook called with the uploaded file
  String captionExtra = '';
  bool verified = false;
  bool encrypt = false; // encrypt before uploading (Settings › Encryption)
  int? remoteSize; // size Telegram should report (encrypted files are slightly bigger)
  void Function(DriveFile? sent)? onSent;

  TStatus status = TStatus.queued;
  int bytes = 0;
  int waitSeconds = 0;
  String? error;
  int? chatId;
  int? tempMessageId;
  int? fileId;
  String? tempPath;
  double speed = 0;
  int _lastBytes = 0;
  DateTime _lastTime = DateTime.now();
  Completer<void>? _done;
  /// Downloads: completes with the local file path (or null if it failed/was cancelled).
  final Completer<String?> result = Completer<String?>();

  Transfer.upload({required this.name, required this.size, this.uri, this.sourcePath, this.modifiedMs, this.destKey, this.destChatId})
      : upload = true,
        file = null,
        action = null;

  Transfer.download(DriveFile f, this.action)
      : upload = false,
        name = f.name,
        size = f.size,
        uri = null,
        sourcePath = null,
        modifiedMs = null,
        file = f;

  double get fraction => size <= 0 ? 0 : (bytes / size).clamp(0.0, 1.0);
  bool get finished => status == TStatus.done || status == TStatus.failed || status == TStatus.cancelled;
  bool get running => !finished && status != TStatus.queued;

  void _progress(int b) {
    final now = DateTime.now();
    final dt = now.difference(_lastTime).inMilliseconds;
    if (dt >= 700) {
      final inst = (b - _lastBytes) * 1000 / dt;
      speed = speed == 0 ? inst : speed * 0.6 + inst * 0.4;
      _lastBytes = b;
      _lastTime = now;
    }
    bytes = b;
  }

  int? get secondsLeft => speed <= 1 ? null : ((size - bytes) / speed).round();
}

enum AuthStep { starting, needApi, params, phone, qr, code, password, email, emailCode, registration, unsupported, ready, closing }

class Drive extends ChangeNotifier {
  final TdClient td = TdClient();
  late final SyncManager sync = SyncManager(this);
  late final StreamServer streamer = StreamServer(this);
  late final WebDavDrive webdav = WebDavDrive(this);
  Drive() {
    current = this;
  }
  late final Programs programs = Programs(this);
  bool driveLetter = false; // Windows: show TirsoDrive as a drive letter
  late SharedPreferences _prefs;

  // settings
  String lang = 'en';
  int maxBytes = 2000 * 1024 * 1024; // Telegram's free limit (≈2 GB)
  String sortMode = 'new'; // new | old | az | za | big | small
  String themeMode = 'dark'; // dark | light | system
  // upload rules
  bool ruleWifi = false;
  bool keepInTray = true; // Windows: closing the window keeps TirsoDrive running in the tray
  DesktopHost? desktop;
  PhoneBridge? phone; // Android: watch + file-picker storage support
  List<(int, String)> watchFavorites = []; // contacts the watch may send files to (chosen on the phone)
  bool watchSupport = true;
  bool ruleCharging = false;
  int quietFrom = -1; // hour 0-23, -1 = off
  int quietTo = -1;
  String? uploadsBlocked; // why uploads are waiting, or null
  // app lock
  String lockHash = '';
  bool lockBio = false;
  bool isTv = false;
  List<int>? vaultKey; // encryption key on this device (from your password)
  final ValueNotifier<int> themeTick = ValueNotifier<int>(0);
  int apiId = builtInApiId;
  String apiHash = builtInApiHash;

  // auth
  AuthStep step = AuthStep.starting;
  String? qrLink;
  String codeTarget = '';
  String codeKind = '';
  String passwordHint = '';
  String emailPattern = '';
  String? authError;
  bool authBusy = false;
  bool wantQr = false;

  // account
  String myName = '';
  String myPhone = '';
  int myId = 0;
  String connection = 'connectionStateConnecting';

  // chats & channels
  final Map<int, Map<String, dynamic>> _chats = {};
  final Map<int, Map<String, dynamic>> _supergroups = {};
  bool channelsLoaded = false;
  final Map<int, List<DriveFile>> filesByChat = {};
  final Set<int> loadingChats = {};

  // transfers
  final List<Transfer> transfers = [];
  bool paused = false;
  bool _upBusy = false;
  bool _downBusy = false;
  final Map<int, Transfer> _byFileId = {};
  final StreamController<String> _messages = StreamController.broadcast();
  Stream<String> get messages => _messages.stream;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final sys = PlatformDispatcher.instance.locale.languageCode;
    lang = _prefs.getString('lang') ?? (sys == 'es' ? 'es' : 'en');
    appLang = lang;
    maxBytes = _prefs.getInt('maxBytes') ?? maxBytes;
    sortMode = _prefs.getString('sortMode') ?? sortMode;
    ruleWifi = _prefs.getBool('ruleWifi') ?? false;
    keepInTray = _prefs.getBool('keepInTray') ?? true;
    watchSupport = _prefs.getBool('watchSupport') ?? true;
    try {
      watchFavorites = [for (final e in jsonDecode(_prefs.getString('watchFavs') ?? '[]') as List) ((e['id'] as num).toInt(), e['name'] as String)];
    } catch (_) {}
    ruleCharging = _prefs.getBool('ruleCharging') ?? false;
    quietFrom = _prefs.getInt('quietFrom') ?? -1;
    quietTo = _prefs.getInt('quietTo') ?? -1;
    lockHash = _prefs.getString('lockHash') ?? '';
    lockBio = _prefs.getBool('lockBio') ?? false;
    Timer.periodic(const Duration(seconds: 20), (_) => _checkRules());
    if (builtInApiId == 0) {
      apiId = _prefs.getInt('apiId') ?? 0;
      apiHash = _prefs.getString('apiHash') ?? '';
    }
    td.updates.listen(_onUpdate);
    NativeBridge.listen(onTogglePause: togglePause, onInbox: () => phone?.scanInbox(), onWearShare: () => phone?.handleWearShares());
    NativeBridge.serviceStop(); // clear any leftover notification from a previous run
    if (apiId == 0 || apiHash.isEmpty) {
      step = AuthStep.needApi;
      notifyListeners();
      return;
    }
    await td.start();
  }

  bool get usesBuiltInApi => builtInApiId != 0;

  Future<void> saveApi(int id, String hash) async {
    apiId = id;
    apiHash = hash;
    await _prefs.setInt('apiId', id);
    await _prefs.setString('apiHash', hash);
    step = AuthStep.starting;
    notifyListeners();
    await td.start();
  }

  void setLang(String l) {
    lang = l;
    appLang = l;
    _prefs.setString('lang', l);
    notifyListeners();
  }

  Future<void> loadTheme() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    themeMode = p.getString('theme') ?? 'dark';
    lockHash = p.getString('lockHash') ?? '';
    lockBio = p.getBool('lockBio') ?? false;
    final vk = p.getString('vaultKey');
    vaultKey = vk == null ? null : base64Decode(vk);
    isTv = await NativeBridge.isTv();
    _applyTheme();
    PlatformDispatcher.instance.onPlatformBrightnessChanged = () {
      if (themeMode == 'system') {
        _applyTheme();
        themeTick.value++;
      }
    };
  }

  void _applyTheme() {
    C.dark = themeMode == 'dark' || (themeMode == 'system' && PlatformDispatcher.instance.platformBrightness == Brightness.dark);
  }

  void setTheme(String m) {
    themeMode = m;
    _prefs.setString('theme', m);
    _applyTheme();
    themeTick.value++;
  }

  void setWatchSupport(bool v) {
    _prefs.setBool('watchSupport', watchSupport = v);
    notifyListeners();
  }

  void setWatchFavorites(List<(int, String)> v) {
    watchFavorites = v;
    _prefs.setString('watchFavs', jsonEncode([for (final e in v) {'id': e.$1, 'name': e.$2}]));
    notifyListeners();
    phone?.writeIndex();
  }

  void setKeepInTray(bool v) {
    _prefs.setBool('keepInTray', keepInTray = v);
    notifyListeners();
  }

  void setRules({bool? wifi, bool? charging, int? from, int? to}) {
    if (wifi != null) _prefs.setBool('ruleWifi', ruleWifi = wifi);
    if (charging != null) _prefs.setBool('ruleCharging', ruleCharging = charging);
    if (from != null) _prefs.setInt('quietFrom', quietFrom = from);
    if (to != null) _prefs.setInt('quietTo', quietTo = to);
    notifyListeners(); // the switches only move when the screen is told (this was the "toggle doesn't work" bug)
    _checkRules();
  }

  Future<void> _checkRules() async {
    String? why;
    final h = DateTime.now().hour;
    if (quietFrom >= 0 && quietTo >= 0 && quietFrom != quietTo) {
      final inQuiet = quietFrom < quietTo ? (h >= quietFrom && h < quietTo) : (h >= quietFrom || h < quietTo);
      if (inQuiet) why = t('rule_wait_quiet', {'a': '$quietFrom:00', 'b': '$quietTo:00'});
    }
    if (why == null && (ruleWifi || ruleCharging)) {
      final st = await NativeBridge.deviceState();
      if (ruleWifi && st.$1 == false) why = t('rule_wait_wifi');
      if (why == null && ruleCharging && st.$2 == false) why = t('rule_wait_charging');
    }
    if (why != uploadsBlocked) {
      uploadsBlocked = why;
      notifyListeners();
      _pump();
    }
  }

  // app lock (PIN, optionally fingerprint/face)
  static String hashPin(String pin) {
    var h = 0x811c9dc5;
    for (final c in 'tirsodrive:$pin'.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    // a few extra rounds so it isn't trivially reversible
    for (var i = 0; i < 20000; i++) {
      h = ((h ^ (h >> 13)) * 0x5bd1e995 + i) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  bool get lockEnabled => lockHash.isNotEmpty;

  Future<void> setVaultPassword(String? password) async {
    if (password == null) {
      vaultKey = null;
      await _prefs.remove('vaultKey');
    } else {
      vaultKey = await deriveVaultKey(password, myId);
      await _prefs.setString('vaultKey', base64Encode(vaultKey!));
    }
    notifyListeners();
  }
  void setLock(String? pin, {bool bio = false}) {
    lockHash = pin == null ? '' : hashPin(pin);
    lockBio = pin != null && bio;
    _prefs.setString('lockHash', lockHash);
    _prefs.setBool('lockBio', lockBio);
    notifyListeners();
  }

  void savePrograms() => _prefs.setString('programs', programs.json);

  Future<void> setDriveLetter(bool on) async {
    driveLetter = on;
    await _prefs.setBool('driveLetter', on);
    if (on) {
      await webdav.start();
    } else {
      await webdav.stop();
    }
    notifyListeners();
  }

  void setSort(String m) {
    sortMode = m;
    _prefs.setString('sortMode', m);
    notifyListeners();
  }

  List<DriveFile> sorted(List<DriveFile> files) {
    final out = List<DriveFile>.from(files);
    int byName(DriveFile a, DriveFile b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    switch (sortMode) {
      case 'old':
        out.sort((a, b) => a.date != b.date ? a.date.compareTo(b.date) : a.messageId.compareTo(b.messageId));
        break;
      case 'az':
        out.sort(byName);
        break;
      case 'za':
        out.sort((a, b) => byName(b, a));
        break;
      case 'big':
        out.sort((a, b) => b.size.compareTo(a.size));
        break;
      case 'small':
        out.sort((a, b) => a.size.compareTo(b.size));
        break;
      default:
        out.sort((a, b) => a.date != b.date ? b.date.compareTo(a.date) : b.messageId.compareTo(a.messageId));
    }
    return out;
  }

  void setMaxBytes(int b) {
    maxBytes = b;
    _prefs.setInt('maxBytes', b);
    notifyListeners();
  }

  void _say(String s) => _messages.add(s);

  // ---------------------------------------------------------------- updates

  void _onUpdate(Map<String, dynamic> u) {
    switch (u['@type']) {
      case 'updateAuthorizationState':
        _onAuth(u['authorization_state'] as Map<String, dynamic>);
        break;
      case 'updateConnectionState':
        connection = (u['state']?['@type'] ?? '') as String;
        notifyListeners();
        break;
      case 'updateNewChat':
        final c = u['chat'] as Map<String, dynamic>;
        _chats[(c['id'] as num).toInt()] = c;
        if (channelsLoaded) notifyListeners();
        break;
      case 'updateChatTitle':
        final id = (u['chat_id'] as num).toInt();
        _chats[id]?['title'] = u['title'];
        if (channelsLoaded) notifyListeners();
        break;
      case 'updateChatPosition':
        final id = (u['chat_id'] as num).toInt();
        final pos = u['position'] as Map<String, dynamic>;
        final chat = _chats[id];
        if (chat != null) {
          final list = List<dynamic>.from((chat['positions'] as List?) ?? []);
          list.removeWhere((p) => jsonEncode((p as Map)['list']) == jsonEncode(pos['list']));
          if ('${pos['order']}' != '0') list.add(pos);
          chat['positions'] = list;
        }
        break;
      case 'updateSupergroup':
        final s = u['supergroup'] as Map<String, dynamic>;
        _supergroups[(s['id'] as num).toInt()] = s;
        break;
      case 'updateFile':
        _onFile(u['file'] as Map<String, dynamic>);
        break;
      case 'updateMessageSendSucceeded':
        _onSent(u['message'] as Map<String, dynamic>, (u['old_message_id'] as num).toInt());
        break;
      case 'updateMessageSendFailed':
        _onSendFailed(u['message'] as Map<String, dynamic>, (u['old_message_id'] as num).toInt(), (u['error']?['message'] ?? u['error_message'] ?? 'failed').toString());
        break;
      case 'updateNewMessage':
        final m = u['message'] as Map<String, dynamic>;
        if (m['sending_state'] == null) _addMessage(m);
        break;
      case 'updateMessageContent':
        _refreshMessage((u['chat_id'] as num).toInt(), (u['message_id'] as num).toInt());
        break;
      case 'updateDeleteMessages':
        if (u['is_permanent'] == true) {
          final chatId = (u['chat_id'] as num).toInt();
          final ids = (u['message_ids'] as List).map((e) => (e as num).toInt()).toSet();
          filesByChat[chatId]?.removeWhere((f) => ids.contains(f.messageId));
          notifyListeners();
        }
        break;
    }
  }

  // ---------------------------------------------------------------- sign-in

  Future<void> _onAuth(Map<String, dynamic> s) async {
    authBusy = false;
    switch (s['@type']) {
      case 'authorizationStateWaitTdlibParameters':
        step = AuthStep.params;
        final base = await getApplicationSupportDirectory();
        try {
          await td.call({
            '@type': 'setTdlibParameters',
            'use_test_dc': false,
            'database_directory': '${base.path}/td_db',
            'files_directory': '${base.path}/td_files',
            'database_encryption_key': '',
            'use_file_database': true,
            'use_chat_info_database': true,
            'use_message_database': true,
            'use_secret_chats': false,
            'api_id': apiId,
            'api_hash': apiHash,
            'system_language_code': lang,
            'device_model': Platform.isAndroid ? 'TirsoDrive (Android)' : 'TirsoDrive (PC)',
            'system_version': Platform.operatingSystemVersion.split(' ').first,
            'application_version': appVersion,
          });
        } on TdError catch (e) {
          authError = t('err_generic', {'e': e.message});
        }
        break;
      case 'authorizationStateWaitPhoneNumber':
        qrLink = null;
        step = AuthStep.phone;
        if (wantQr) requestQr();
        break;
      case 'authorizationStateWaitOtherDeviceConfirmation':
        qrLink = s['link'] as String?;
        step = AuthStep.qr;
        break;
      case 'authorizationStateWaitCode':
        final info = s['code_info'] as Map<String, dynamic>? ?? {};
        codeTarget = (info['phone_number'] ?? '').toString();
        codeKind = (info['type']?['@type'] ?? '').toString();
        step = AuthStep.code;
        break;
      case 'authorizationStateWaitPassword':
        passwordHint = (s['password_hint'] ?? '').toString();
        step = AuthStep.password;
        break;
      case 'authorizationStateWaitEmailAddress':
        step = AuthStep.email;
        break;
      case 'authorizationStateWaitEmailCode':
        emailPattern = (s['code_info']?['email_address_pattern'] ?? '').toString();
        step = AuthStep.emailCode;
        break;
      case 'authorizationStateWaitRegistration':
        step = AuthStep.registration;
        break;
      case 'authorizationStateReady':
        step = AuthStep.ready;
        authError = null;
        _afterLogin();
        break;
      case 'authorizationStateLoggingOut':
      case 'authorizationStateClosing':
        step = AuthStep.closing;
        break;
      case 'authorizationStateClosed':
        step = AuthStep.starting;
        _chats.clear();
        _supergroups.clear();
        filesByChat.clear();
        channelsLoaded = false;
        if (apiId == 0 || apiHash.isEmpty) {
          step = AuthStep.needApi;
        } else {
          td.newClient();
        }
        break;
      default:
        step = AuthStep.unsupported;
    }
    notifyListeners();
  }

  String _authMessage(TdError e) {
    final m = e.message.toUpperCase();
    if (e.retryAfter != null) return t('err_flood', {'s': e.retryAfter});
    if (m.contains('PHONE_NUMBER')) return t('err_phone');
    if (m.contains('CODE_EXPIRED')) return t('err_code_expired');
    if (m.contains('CODE_INVALID') || m.contains('CODE_EMPTY')) return t('err_code');
    if (m.contains('PASSWORD')) return t('err_password');
    if (m.contains('API_ID')) return t('err_api');
    return t('err_generic', {'e': e.message});
  }

  Future<void> _authCall(Map<String, dynamic> req) async {
    authError = null;
    authBusy = true;
    notifyListeners();
    try {
      await td.call(req);
    } on TdError catch (e) {
      authError = _authMessage(e);
      authBusy = false;
      notifyListeners();
    }
  }

  void requestQr() {
    wantQr = true;
    if (step == AuthStep.phone) {
      _authCall({'@type': 'requestQrCodeAuthentication', 'other_user_ids': <int>[]});
    }
  }

  void submitPhone(String phone) {
    wantQr = false;
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    _authCall({'@type': 'setAuthenticationPhoneNumber', 'phone_number': clean});
  }

  void submitCode(String code) => _authCall({'@type': 'checkAuthenticationCode', 'code': code.trim()});
  void resendCode() => _authCall({'@type': 'resendAuthenticationCode', 'reason': {'@type': 'resendCodeReasonUserRequest'}});
  void submitPassword(String pw) => _authCall({'@type': 'checkAuthenticationPassword', 'password': pw});
  void submitEmail(String e) => _authCall({'@type': 'setAuthenticationEmailAddress', 'email_address': e.trim()});
  void submitEmailCode(String c) => _authCall({
        '@type': 'checkAuthenticationEmailCode',
        'code': {'@type': 'emailAddressAuthenticationCode', 'code': c.trim()}
      });

  /// Goes back to the first sign-in screen (closes this TDLib instance and opens a fresh one).
  void startOver({bool qr = false}) {
    wantQr = qr;
    authError = null;
    td.send({'@type': 'close'});
  }

  Future<void> logOut() async {
    wantQr = false;
    try {
      await td.call({'@type': 'logOut'});
    } catch (_) {}
  }

  Future<void> changeApi() async {
    await _prefs.remove('apiId');
    await _prefs.remove('apiHash');
    apiId = 0;
    apiHash = '';
    await logOut();
  }

  // ---------------------------------------------------------------- channels

  Future<void> _afterLogin() async {
    try {
      final me = await td.call({'@type': 'getMe'});
      myName = [me['first_name'], me['last_name']].where((e) => e != null && '$e'.isNotEmpty).join(' ');
      myPhone = (me['phone_number'] ?? '').toString();
      myId = (me['id'] as num?)?.toInt() ?? 0;
    } catch (_) {}
    await loadChannels();
    await _restoreQueue();
    unawaited(_cleanTemp()); // remove files left from sharing/opening last time
    try {
      final dec = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}dec');
      if (dec.existsSync()) dec.deleteSync(recursive: true); // decrypted copies from last time
    } catch (_) {}
    await sync.load();
    sync.start();
    unawaited(purgeTrash());
    driveLetter = _prefs.getBool('driveLetter') ?? false;
    programs.load(_prefs.getString('programs'));
    if (driveLetter) unawaited(webdav.start());
    if (Platform.isAndroid && !isTv) {
      phone ??= PhoneBridge(this);
      phone!.start();
      if (watchSupport) unawaited(loadAllChannels()); // so the watch can browse and search everything
    }
  }

  Future<void> loadChannels() async {
    for (final list in [
      {'@type': 'chatListMain'},
      {'@type': 'chatListArchive'}
    ]) {
      for (var i = 0; i < 100; i++) {
        try {
          await td.call({'@type': 'loadChats', 'chat_list': list, 'limit': 200});
        } on TdError catch (e) {
          if (e.code != 404) debugPrint('loadChats: ${e.message}');
          break;
        }
      }
    }
    channelsLoaded = true;
    notifyListeners();
  }

  bool _isMyChannel(Map<String, dynamic> chat) {
    final type = chat['type'] as Map<String, dynamic>? ?? {};
    if (type['@type'] != 'chatTypeSupergroup' || type['is_channel'] != true) return false;
    final title = (chat['title'] ?? '').toString();
    if (!title.startsWith(channelPrefix)) return false;
    final sg = _supergroups[(type['supergroup_id'] as num?)?.toInt() ?? 0];
    if (sg == null) return true;
    return sg['status']?['@type'] == 'chatMemberStatusCreator';
  }

  List<DriveChannel> get channels {
    final out = <DriveChannel>[];
    _chats.forEach((id, c) {
      if (_isMyChannel(c)) out.add(DriveChannel(id, (c['title'] ?? '').toString()));
    });
    out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return out;
  }

  /// Chats that belong to a connected program kept apart from your personal files (work profile).
  Set<int> get isolatedChats => {for (final p in programs.list) if (p.isolated) ...p.channels.values};

  List<DriveChannel> get customChannels => channels.where((c) => c.category == null && c.title.toLowerCase() != trashTitle.toLowerCase() && !isolatedChats.contains(c.chatId)).toList();

  DriveChannel? channelForKey(String key) {
    final cat = categoryByKey(key);
    if (cat == null) return null;
    for (final c in channels) {
      if (c.title.toLowerCase() == cat.channelTitle.toLowerCase()) return c;
    }
    return null;
  }

  DriveChannel? channelById(int chatId) {
    final c = _chats[chatId];
    if (c == null || !_isMyChannel(c)) return null;
    return DriveChannel(chatId, (c['title'] ?? '').toString());
  }

  Future<int> _createChannel(String title, {Transfer? forTransfer}) async {
    while (true) {
      try {
        final chat = await td.call({
          '@type': 'createNewSupergroupChat',
          'title': title,
          'is_forum': false,
          'is_channel': true,
          'description': 'TirsoDrive storage channel. Files here are managed by the TirsoDrive app.',
          'message_auto_delete_time': 0,
          'for_import': false,
        });
        final id = (chat['id'] as num).toInt();
        _chats[id] = chat;
        // Keep Telegram's main chat list tidy: TirsoDrive channels live in the Archive.
        try {
          await td.call({'@type': 'addChatToList', 'chat_id': id, 'chat_list': {'@type': 'chatListArchive'}});
        } catch (_) {}
        notifyListeners();
        return id;
      } on TdError catch (e) {
        final wait = e.retryAfter;
        if (wait == null || wait > 3600) rethrow;
        if (forTransfer != null) {
          forTransfer.status = TStatus.waiting;
          forTransfer.waitSeconds = wait;
          notifyListeners();
        }
        await Future.delayed(Duration(seconds: wait + 1));
      }
    }
  }

  Future<int> ensureChannel(String key, {Transfer? forTransfer}) async {
    final existing = channelForKey(key);
    if (existing != null) return existing.chatId;
    return _createChannel(categoryByKey(key)!.channelTitle, forTransfer: forTransfer);
  }

  Future<String?> createCustomChannel(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return null;
    final title = '$channelPrefix$clean';
    if (channels.any((c) => c.title.toLowerCase() == title.toLowerCase())) return t('new_channel_exists');
    try {
      await _createChannel(title);
      return null;
    } on TdError catch (e) {
      return e.retryAfter != null ? t('err_flood', {'s': e.retryAfter}) : t('err_generic', {'e': e.message});
    }
  }

  // ---------------------------------------------------------------- files

  DriveFile? _fileFromMessage(Map<String, dynamic> m) {
    final c = m['content'] as Map<String, dynamic>? ?? {};
    final id = (m['id'] as num).toInt();
    Map<String, dynamic>? file;
    Map<String, dynamic>? thumb;
    String name = '';
    String mime = '';
    switch (c['@type']) {
      case 'messageDocument':
        final d = c['document'] as Map<String, dynamic>;
        file = d['document'] as Map<String, dynamic>?;
        thumb = d['thumbnail']?['file'] as Map<String, dynamic>?;
        name = (d['file_name'] ?? '').toString();
        mime = (d['mime_type'] ?? '').toString();
        break;
      case 'messageVideo':
        final v = c['video'] as Map<String, dynamic>;
        file = v['video'] as Map<String, dynamic>?;
        thumb = v['thumbnail']?['file'] as Map<String, dynamic>?;
        name = (v['file_name'] ?? '').toString();
        mime = (v['mime_type'] ?? 'video/mp4').toString();
        if (name.isEmpty) name = 'video_$id.mp4';
        break;
      case 'messageAudio':
        final a = c['audio'] as Map<String, dynamic>;
        file = a['audio'] as Map<String, dynamic>?;
        name = (a['file_name'] ?? '').toString();
        mime = (a['mime_type'] ?? '').toString();
        break;
      case 'messageAnimation':
        final a = c['animation'] as Map<String, dynamic>;
        file = a['animation'] as Map<String, dynamic>?;
        name = (a['file_name'] ?? '').toString();
        mime = (a['mime_type'] ?? '').toString();
        break;
      case 'messagePhoto':
        final sizes = (c['photo']?['sizes'] as List?) ?? [];
        if (sizes.isNotEmpty) file = (sizes.last as Map<String, dynamic>)['photo'] as Map<String, dynamic>?;
        if (sizes.length > 1) thumb = (sizes.first as Map<String, dynamic>)['photo'] as Map<String, dynamic>?;
        name = 'photo_$id.jpg';
        mime = 'image/jpeg';
        break;
      default:
        return null;
    }
    if (file == null) return null;
    if (name.isEmpty) name = 'file_$id';
    final caption = (c['caption']?['text'] ?? '').toString();
    final mt = RegExp(r'mtime=(\d+)').firstMatch(caption);
    final rn = RegExp(r'(?:^|\s)name=(\S+)').firstMatch(caption);
    if (rn != null) {
      try {
        name = Uri.decodeComponent(rn.group(1)!);
      } catch (_) {}
    }
    final size = (file['size'] as num?)?.toInt() ?? 0;
    return DriveFile(
      chatId: (m['chat_id'] as num).toInt(),
      messageId: id,
      name: name,
      size: size > 0 ? size : ((file['expected_size'] as num?)?.toInt() ?? 0),
      date: (m['date'] as num?)?.toInt() ?? 0,
      mime: mime.isEmpty ? mimeFor(name) : mime,
      fileId: (file['id'] as num).toInt(),
      originalMs: mt == null ? null : int.tryParse(mt.group(1)!),
      caption: caption,
      thumbId: (thumb?['id'] as num?)?.toInt(),
    );
  }

  void _addMessage(Map<String, dynamic> m) {
    final chatId = (m['chat_id'] as num).toInt();
    final list = filesByChat[chatId];
    if (list == null) return; // not opened yet; it will load fresh
    final f = _fileFromMessage(m);
    if (f == null || list.any((x) => x.messageId == f.messageId)) return;
    list.insert(0, f);
    notifyListeners();
  }

  Future<void> loadFiles(int chatId, {bool refresh = false}) async {
    if (loadingChats.contains(chatId)) return;
    if (!refresh && filesByChat.containsKey(chatId)) return;
    loadingChats.add(chatId);
    notifyListeners();
    final out = <DriveFile>[];
    try {
      var from = 0;
      var emptyRounds = 0;
      for (var i = 0; i < 300; i++) {
        final res = await td.call({
          '@type': 'getChatHistory',
          'chat_id': chatId,
          'from_message_id': from,
          'offset': 0,
          'limit': 100,
          'only_local': false,
        });
        final msgs = (res['messages'] as List?) ?? [];
        if (msgs.isEmpty) {
          if (++emptyRounds >= 2 || from == 0) break;
          continue;
        }
        emptyRounds = 0;
        for (final m in msgs) {
          final f = _fileFromMessage(m as Map<String, dynamic>);
          if (f != null && !out.any((x) => x.messageId == f.messageId)) out.add(f);
        }
        from = ((msgs.last as Map)['id'] as num).toInt();
      }
    } catch (e) {
      debugPrint('loadFiles: $e');
    }
    filesByChat[chatId] = out;
    loadingChats.remove(chatId);
    notifyListeners();
  }

  Future<void> _refreshMessage(int chatId, int messageId) async {
    final list = filesByChat[chatId];
    if (list == null) return;
    final i = list.indexWhere((x) => x.messageId == messageId);
    if (i < 0) return;
    try {
      final m = await td.call({'@type': 'getMessage', 'chat_id': chatId, 'message_id': messageId});
      final f = _fileFromMessage(m);
      if (f != null) {
        list[i] = f;
        notifyListeners();
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------- copy / move / rename / search

  final Map<String, Completer<Map<String, dynamic>?>> _copyWaiters = {};

  /// Copies messages to [dest] (Telegram re-uses the stored files) and waits until each copy is confirmed.
  /// Returns, for each original, the confirmed new message (or null if that copy failed).
  Future<List<(DriveFile, Map<String, dynamic>?)>> _forwardAndWait(int dest, List<DriveFile> files, {bool removeCaption = false}) async {
    final out = <(DriveFile, Map<String, dynamic>?)>[];
    final bySource = <int, List<DriveFile>>{};
    for (final f in files) {
      bySource.putIfAbsent(f.chatId, () => []).add(f);
    }
    for (final entry in bySource.entries) {
      for (var i = 0; i < entry.value.length; i += 50) {
        final chunk = entry.value.sublist(i, (i + 50).clamp(0, entry.value.length));
        try {
          final res = await td.call({
            '@type': 'forwardMessages',
            'chat_id': dest,
            'from_chat_id': entry.key,
            'message_ids': chunk.map((f) => f.messageId).toList(),
            'send_copy': true, // a clean copy: no "Forwarded from"
            'remove_caption': removeCaption,
          });
          final sent = (res['messages'] as List?) ?? [];
          final pending = <(DriveFile, Future<Map<String, dynamic>?>)>[];
          for (var k = 0; k < chunk.length; k++) {
            final m = k < sent.length ? sent[k] as Map<String, dynamic>? : null;
            if (m == null) {
              pending.add((chunk[k], Future.value(null)));
            } else if (m['sending_state'] == null) {
              pending.add((chunk[k], Future.value(m)));
            } else {
              final c = Completer<Map<String, dynamic>?>();
              _copyWaiters['$dest:${m['id']}'] = c;
              pending.add((chunk[k], c.future.timeout(const Duration(minutes: 3), onTimeout: () => null)));
            }
          }
          for (final p in pending) {
            out.add((p.$1, await p.$2));
          }
        } on TdError catch (e) {
          final wait = e.retryAfter;
          if (wait != null && wait < 300) {
            await Future.delayed(Duration(seconds: wait + 1));
            i -= 50; // try this chunk again
            continue;
          }
          _say(t('err_generic', {'e': e.message}));
          for (final f in chunk) {
            out.add((f, null));
          }
        }
      }
    }
    return out;
  }

  /// Copies files to another channel instantly (nothing is re-uploaded).
  /// With [move], each original is deleted only after its copy is confirmed.
  Future<void> copyFiles(List<DriveFile> files, {String? toKey, int? toChatId, bool move = false}) async {
    if (files.isEmpty) return;
    int dest;
    try {
      dest = toChatId ?? await ensureChannel(toKey!);
    } on TdError catch (e) {
      _say(t('err_generic', {'e': e.message}));
      return;
    }
    final results = await _forwardAndWait(dest, files.where((f) => f.chatId != dest).toList());
    var ok = 0;
    for (final (orig, sent) in results) {
      if (sent == null) continue;
      ok++;
      if (move) await _removeMessages([orig]);
    }
    notifyListeners();
    _say(t(move ? 'moved_n' : 'copied_n', {'n': ok, 'c': channelName(dest)}));
  }

  // ---- caption tags: TirsoDrive keeps its own info (name, favorite, collections, trash…) in each file's caption,
  // so every device sees the same thing and nothing has to be backed up separately.

  static String _withTags(String caption, Map<String, String?> set) {
    final words = caption.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    for (final key in set.keys) {
      words.removeWhere((w) => w == key || w.startsWith('$key='));
    }
    if (!words.any((w) => w.startsWith('tirsodrive'))) words.insert(0, 'tirsodrive v1');
    set.forEach((k, v) {
      if (v == null) return;
      words.add(v.isEmpty ? k : '$k=$v');
    });
    return words.join(' ');
  }

  Future<bool> _setCaption(int chatId, int messageId, String caption) async {
    try {
      await td.call({
        '@type': 'editMessageCaption',
        'chat_id': chatId,
        'message_id': messageId,
        'caption': {'@type': 'formattedText', 'text': caption, 'entities': <dynamic>[]},
      });
      await _refreshMessage(chatId, messageId);
      return true;
    } on TdError catch (e) {
      _say(t('err_generic', {'e': e.message}));
      return false;
    }
  }

  /// Renames a file for TirsoDrive (every device sees it, and downloads use it).
  Future<void> renameFile(DriveFile f, String newName) async {
    final clean = newName.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (clean.isEmpty || clean == f.name) return;
    if (await _setCaption(f.chatId, f.messageId, _withTags(f.caption, {'name': Uri.encodeComponent(clean)}))) _say(t('renamed'));
  }

  Future<void> setFavorite(List<DriveFile> files, bool fav) async {
    for (final f in files) {
      if (f.fav == fav) continue;
      await _setCaption(f.chatId, f.messageId, _withTags(f.caption, {'fav': fav ? '' : null}));
    }
    _say(t(fav ? 'fav_added' : 'fav_removed', {'n': files.length}));
  }

  Future<void> addToCollection(List<DriveFile> files, String name, {bool remove = false}) async {
    final enc = Uri.encodeComponent(name.trim());
    if (enc.isEmpty) return;
    for (final f in files) {
      final words = f.caption.split(RegExp(r'\s+')).where((w) => w.isNotEmpty && w != 'col=$enc').toList();
      if (!remove) words.add('col=$enc');
      await _setCaption(f.chatId, f.messageId, _withTags(words.join(' '), {}));
    }
    _say(t(remove ? 'col_removed' : 'col_added', {'n': files.length, 'c': name}));
  }

  List<String> get collections {
    final set = <String>{};
    for (final f in allFiles) {
      set.addAll(f.collections);
    }
    return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  // ---- trash bin (30 days)

  static const trashTitle = 'TD - Trash';
  DriveChannel? get trashChannel {
    for (final c in channels) {
      if (c.title.toLowerCase() == trashTitle.toLowerCase()) return c;
    }
    return null;
  }

  Future<void> _removeMessages(List<DriveFile> files) async {
    final byChat = <int, List<DriveFile>>{};
    for (final f in files) {
      byChat.putIfAbsent(f.chatId, () => []).add(f);
    }
    for (final e in byChat.entries) {
      try {
        await td.call({'@type': 'deleteMessages', 'chat_id': e.key, 'message_ids': e.value.map((f) => f.messageId).toList(), 'revoke': true});
        final ids = e.value.map((f) => f.messageId).toSet();
        filesByChat[e.key]?.removeWhere((x) => ids.contains(x.messageId));
      } on TdError catch (err) {
        _say(t('err_generic', {'e': err.message}));
      }
    }
  }

  /// "Delete" moves files to the TD - Trash channel for 30 days (files already in the trash are deleted for good).
  Future<void> deleteFiles(List<DriveFile> files, {bool quiet = false}) async {
    final trash = trashChannel;
    final inTrash = files.where((f) => trash != null && f.chatId == trash.chatId).toList();
    final toTrash = files.where((f) => !inTrash.contains(f)).toList();
    if (inTrash.isNotEmpty) await deleteForever(inTrash, quiet: true);
    var n = inTrash.length;
    if (toTrash.isNotEmpty) {
      int trashId;
      try {
        trashId = trash?.chatId ?? await _createChannel(trashTitle);
      } on TdError catch (e) {
        _say(t('err_generic', {'e': e.message}));
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final results = await _forwardAndWait(trashId, toTrash);
      final done = <DriveFile>[];
      for (final (orig, sent) in results) {
        if (sent == null) continue;
        final cap = (sent['content']?['caption']?['text'] ?? orig.caption).toString();
        await _setCaption(trashId, (sent['id'] as num).toInt(), _withTags(cap, {'trashed': '$now', 'from': '${orig.chatId}'}));
        done.add(orig);
      }
      await _removeMessages(done);
      n += done.length;
    }
    notifyListeners();
    if (n > 0 && !quiet) _say(t('trashed_n', {'n': n}));
  }

  Future<void> deleteForever(List<DriveFile> files, {bool quiet = false}) async {
    await _removeMessages(files);
    for (final f in files) {
      try {
        await td.call({'@type': 'deleteFile', 'file_id': f.fileId});
      } catch (_) {}
    }
    notifyListeners();
    if (!quiet) _say(t('deleted_n', {'n': files.length}));
  }

  Future<void> restoreFiles(List<DriveFile> files) async {
    var n = 0;
    final byDest = <int, List<DriveFile>>{};
    for (final f in files) {
      var dest = f.trashedFrom;
      if (dest == null || channelById(dest) == null) dest = await ensureChannel('other');
      byDest.putIfAbsent(dest, () => []).add(f);
    }
    for (final e in byDest.entries) {
      final results = await _forwardAndWait(e.key, e.value);
      final done = <DriveFile>[];
      for (final (orig, sent) in results) {
        if (sent == null) continue;
        final cap = (sent['content']?['caption']?['text'] ?? orig.caption).toString();
        await _setCaption(e.key, (sent['id'] as num).toInt(), _withTags(cap, {'trashed': null, 'from': null}));
        done.add(orig);
      }
      await _removeMessages(done);
      n += done.length;
    }
    notifyListeners();
    _say(t('restored_n', {'n': n}));
  }

  /// Deletes trash items older than 30 days (runs when the app starts).
  Future<void> purgeTrash({bool all = false}) async {
    final trash = trashChannel;
    if (trash == null) return;
    await loadFiles(trash.chatId, refresh: true);
    final limit = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 30 * 86400;
    final old = (filesByChat[trash.chatId] ?? <DriveFile>[]).where((f) => all || (f.trashedAt ?? f.date) < limit).toList();
    if (old.isNotEmpty) await deleteForever(old, quiet: !all);
  }

  /// Search index: loads every TirsoDrive channel once (later loads come from Telegram's local cache).
  bool indexing = false;
  int indexDone = 0;
  Future<void> loadAllChannels({bool refresh = false}) async {
    if (indexing) return;
    indexing = true;
    final chs = channels;
    indexDone = 0;
    notifyListeners();
    for (final c in chs) {
      await loadFiles(c.chatId, refresh: refresh);
      indexDone++;
      notifyListeners();
    }
    indexing = false;
    notifyListeners();
  }

  /// Your personal files (everything except the Trash and programs kept separate, such as work).
  List<DriveFile> get allFiles {
    final hidden = isolatedChats;
    return [for (final c in channels) if (c.title.toLowerCase() != trashTitle.toLowerCase() && !hidden.contains(c.chatId)) ...?filesByChat[c.chatId]];
  }

  /// Files of one separate program (searched only when you choose that program).
  List<DriveFile> programFiles(String name) {
    final ids = programs.list.where((p) => p.name == name).expand((p) => p.channels.values).toSet();
    return [for (final id in ids) ...?filesByChat[id]];
  }

  // ---------------------------------------------------------------- sharing

  /// Removes TirsoDrive's downloaded copy of these files from this device (the files stay in Telegram).
  Future<void> dropLocal(List<int> fileIds) async {
    for (final id in fileIds) {
      if (transfers.any((x) => !x.finished && (x.fileId == id || x.file?.fileId == id))) continue; // still in use
      try {
        await td.call({'@type': 'deleteFile', 'file_id': id});
      } catch (_) {}
    }
  }

  void markTemp(List<int> ids) => _markTemp(ids);

  void _markTemp(List<int> ids) {
    final cur = (_prefs.getStringList('temp_files') ?? <String>[]).toSet()..addAll(ids.map((e) => '$e'));
    _prefs.setStringList('temp_files', cur.toList());
  }

  Future<void> _cleanTemp({List<int>? only}) async {
    final cur = (_prefs.getStringList('temp_files') ?? <String>[]).toSet();
    final go = only == null ? cur.map(int.parse).toList() : only.where((i) => cur.contains('$i')).toList();
    await dropLocal(go);
    cur.removeAll(go.map((e) => '$e'));
    await _prefs.setStringList('temp_files', cur.toList());
  }

  // ---------------------------------------------------------------- previews (thumbnails)

  static Drive? current; // the running app's Drive, so small widgets can ask for previews
  final Map<int, Uint8List?> _thumbCache = {}; // fileId → image bytes (null = none available)
  final Map<int, Future<Uint8List?>> _thumbLoading = {};
  int _thumbBusy = 0;

  Uint8List? cachedThumb(DriveFile f) => _thumbCache[f.fileId];

  /// A small preview for an image or video. Uses Telegram's thumbnail; for older photos that have none,
  /// downloads the photo itself (only when it is small) and shrinks it. Nothing stays on the device.
  Future<Uint8List?> thumbBytes(DriveFile f) {
    if (_thumbCache.containsKey(f.fileId)) return Future.value(_thumbCache[f.fileId]);
    return _thumbLoading.putIfAbsent(f.fileId, () => _loadThumb(f));
  }

  Future<Uint8List?> _loadThumb(DriveFile f) async {
    while (_thumbBusy >= 4) {
      await Future.delayed(const Duration(milliseconds: 120));
    }
    _thumbBusy++;
    Uint8List? out;
    try {
      final id = f.thumbId ?? (f.mime.startsWith('image/') && f.size > 0 && f.size <= 4 * 1024 * 1024 ? f.fileId : null);
      if (id != null) {
        final r = await td.call({'@type': 'downloadFile', 'file_id': id, 'priority': 1, 'offset': 0, 'limit': 0, 'synchronous': true});
        final path = r['local']?['path'] as String?;
        if (path != null && path.isNotEmpty && r['local']?['is_downloading_completed'] == true) {
          out = await File(path).readAsBytes();
          if (id == f.fileId) await dropLocal([id]); // the full photo was only fetched to make a preview
        }
      }
    } catch (_) {}
    _thumbBusy--;
    if (_thumbCache.length > 300) _thumbCache.remove(_thumbCache.keys.first);
    _thumbCache[f.fileId] = out;
    _thumbLoading.remove(f.fileId);
    return out;
  }

  /// Makes a small JPEG preview to upload with a file (Telegram shows it as the file's thumbnail).
  /// Returns null when the file isn't an image/video we can make one for.
  Future<({String path, int w, int h})?> _makeUploadThumb(String srcPath, String name) async {
    final ext = extensionOf(name);
    final tmp = (await getTemporaryDirectory()).path;
    final out = '$tmp${Platform.pathSeparator}thumb_${DateTime.now().microsecondsSinceEpoch}.jpg';
    try {
      if (const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}.contains(ext)) {
        final r = await compute(_imageThumb, [srcPath, out]);
        if (r == null) return null;
        return (path: out, w: r[0], h: r[1]);
      }
      if (Platform.isAndroid && const {'mp4', 'mkv', 'mov', 'avi', 'webm', 'm4v', '3gp', 'ts', 'mpg', 'mpeg', 'wmv', 'flv'}.contains(ext)) {
        final r = await NativeBridge.videoThumb(srcPath, out);
        if (r == null) return null;
        return (path: out, w: r.$1, h: r.$2);
      }
    } catch (_) {}
    return null;
  }

  /// Downloads a file (through the normal queue, with progress) and returns where it is on this device.
  Future<String?> fetch(DriveFile f) {
    final tr = Transfer.download(f, 'keep');
    transfers.add(tr);
    notifyListeners();
    _pump();
    return tr.result.future;
  }

  String _orderInMain(Map<String, dynamic> chat) {
    for (final p in (chat['positions'] as List?) ?? const []) {
      if ((p as Map)['list']?['@type'] == 'chatListMain') return '${p['order']}';
    }
    return '0';
  }

  /// Chats you can send files to: Saved Messages, your recent chats and groups (not TirsoDrive channels).
  List<ShareTarget> shareChats() {
    final out = <(BigInt, ShareTarget)>[];
    _chats.forEach((id, c) {
      if (_isMyChannel(c)) return;
      final type = c['type'] as Map<String, dynamic>? ?? {};
      final kind = type['@type'];
      final isChannel = kind == 'chatTypeSupergroup' && type['is_channel'] == true;
      if (kind == 'chatTypeSecret' || isChannel) return;
      final order = BigInt.tryParse(_orderInMain(c)) ?? BigInt.zero;
      if (order == BigInt.zero && id != myId) return; // not in your chat list
      final title = id == myId ? t('saved_messages') : (c['title'] ?? '').toString();
      final group = kind == 'chatTypeBasicGroup' || kind == 'chatTypeSupergroup';
      out.add((id == myId ? BigInt.parse('9' * 30) : order, ShareTarget(chatId: id, title: title, group: group)));
    });
    out.sort((a, b) => b.$1.compareTo(a.$1));
    return out.map((e) => e.$2).toList();
  }

  /// Your Telegram contacts that don't already appear in [shareChats].
  Future<List<ShareTarget>> shareContacts(Set<int> already) async {
    try {
      final res = await td.call({'@type': 'getContacts'});
      final ids = ((res['user_ids'] as List?) ?? []).map((e) => (e as num).toInt()).where((id) => !already.contains(id)).toList();
      final users = await Future.wait(ids.take(400).map((id) => td.call({'@type': 'getUser', 'user_id': id}).then<Map<String, dynamic>?>((u) => u, onError: (_) => null)));
      final out = <ShareTarget>[];
      for (final u in users) {
        if (u == null) continue;
        final name = [u['first_name'], u['last_name']].where((e) => e != null && '$e'.isNotEmpty).join(' ');
        out.add(ShareTarget(chatId: (u['id'] as num).toInt(), title: name.isEmpty ? '?' : name, userId: (u['id'] as num).toInt()));
      }
      out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Sends files to a chat as a clean copy (no "Forwarded from", no TirsoDrive caption). Nothing is re-uploaded.
  Future<void> sendToChat(ShareTarget target, List<DriveFile> files) async {
    try {
      if (target.userId != null) await td.call({'@type': 'createPrivateChat', 'user_id': target.userId, 'force': false});
      final bySource = <int, List<DriveFile>>{};
      for (final f in files) {
        bySource.putIfAbsent(f.chatId, () => []).add(f);
      }
      for (final e in bySource.entries) {
        await td.call({
          '@type': 'forwardMessages',
          'chat_id': target.chatId,
          'from_chat_id': e.key,
          'message_ids': e.value.map((f) => f.messageId).toList(),
          'send_copy': true,
          'remove_caption': true,
        });
      }
      _say(t('sent_to', {'n': files.length, 'c': target.title}));
    } on TdError catch (e) {
      _say(e.retryAfter != null ? t('err_flood', {'s': e.retryAfter}) : t('err_generic', {'e': e.message}));
    }
  }

  /// Downloads the files, then hands them to the Android share menu (WhatsApp, Instagram, Drive…).
  Future<void> shareToApps(List<DriveFile> files) async {
    final paths = <String>[];
    final names = <String>[];
    final mimes = <String>[];
    for (final f in files) {
      final p = await fetch(f);
      if (p == null) continue;
      paths.add(p);
      names.add(f.name);
      mimes.add(f.mime);
    }
    if (paths.isEmpty) return;
    final ids = files.map((f) => f.fileId).toList();
    _markTemp(ids);
    // The other app reads the file directly (no copy). Give it time, then remove it from the phone.
    Timer(const Duration(minutes: 10), () => _cleanTemp(only: ids));
    try {
      await NativeBridge.shareFiles(paths, names, mimes);
    } catch (e) {
      _say(t('err_generic', {'e': e}));
    }
  }

  /// Windows: downloads the files and copies them into a cloud folder (Google Drive, OneDrive…).
  Future<void> sendToFolder(List<DriveFile> files, String folder, String label) async {
    var n = 0;
    for (final f in files) {
      final p = await fetch(f);
      if (p == null) continue;
      try {
        await NativeBridge.copyInto(p, f.name, '$folder${Platform.pathSeparator}TirsoDrive');
        n++;
        unawaited(dropLocal([f.fileId]));
      } catch (e) {
        _say(t('err_generic', {'e': e}));
      }
    }
    if (n > 0) _say(t('sent_to', {'n': n, 'c': label}));
  }

  Future<void> deleteFile(DriveFile f) => deleteFiles([f]);


  String channelName(int chatId) => channelById(chatId)?.display ?? (_chats[chatId]?['title'] ?? '').toString();

  // ---------------------------------------------------------------- picking

  Future<List<PickedFile>> pick() => NativeBridge.pickFiles();
  Future<List<PickedFile>> pickFolder() => NativeBridge.pickFolder();

  void enqueueUploads(List<Transfer> items, {bool quiet = false}) {
    if (!transfers.any((x) => x.upload && !x.finished)) {
      _batchTotal = 0;
      _batchDone = 0;
    }
    _batchTotal += items.length;
    transfers.addAll(items);
    if (!_askedNotifications) {
      _askedNotifications = true;
      NativeBridge.askNotifications();
    }
    if (!quiet) _say(t('queued_msg', {'n': items.length}));
    notifyListeners();
    _pump();
  }

  void download(DriveFile f, String action) {
    final existing = transfers.where((x) => !x.upload && !x.finished && x.file?.fileId == f.fileId);
    if (existing.isNotEmpty) return;
    transfers.add(Transfer.download(f, action));
    notifyListeners();
    _pump();
  }

  void togglePause() {
    paused = !paused;
    notifyListeners();
    _pump();
  }

  void retry(Transfer tr) {
    if (tr.upload) {
      if (!transfers.any((x) => x.upload && !x.finished)) {
        _batchTotal = 0;
        _batchDone = 0;
      }
      _batchTotal++;
      tr.tempMessageId = null;
      tr.chatId = null;
      tr.fileId = null;
    }
    tr.status = TStatus.queued;
    tr.error = null;
    tr.bytes = 0;
    tr.speed = 0;
    notifyListeners();
    _pump();
  }

  void clearFinished() {
    transfers.removeWhere((x) => x.finished);
    notifyListeners();
  }

  Future<void> cancel(Transfer tr) async {
    if (tr.finished) return;
    final wasRunning = tr.running;
    if (!tr.upload && !wasRunning && !tr.result.isCompleted) tr.result.complete(null);
    if (tr.upload && !wasRunning) _batchDone++; // a queued one never runs, so count it here
    tr.status = TStatus.cancelled;
    if (tr.upload && tr.tempMessageId != null && tr.chatId != null) {
      try {
        await td.call({'@type': 'deleteMessages', 'chat_id': tr.chatId, 'message_ids': [tr.tempMessageId], 'revoke': true});
      } catch (_) {}
    }
    if (!tr.upload && tr.fileId != null) {
      try {
        await td.call({'@type': 'cancelDownloadFile', 'file_id': tr.fileId, 'only_if_pending': false});
      } catch (_) {}
    }
    if (wasRunning && !(tr._done?.isCompleted ?? true)) tr._done!.complete();
    notifyListeners();
  }

  // ---------------------------------------------------------------- queue engine

  void _pump() {
    if (paused || step != AuthStep.ready) return;
    if (!_upBusy && uploadsBlocked == null) {
      final next = transfers.where((x) => x.upload && x.status == TStatus.queued);
      if (next.isNotEmpty) _runUpload(next.first);
    }
    if (!_downBusy) {
      final next = transfers.where((x) => !x.upload && x.status == TStatus.queued);
      if (next.isNotEmpty) _runDownload(next.first);
    }
  }

  // ---------------------------------------------------------------- background + remembered queue

  @override
  void notifyListeners() {
    super.notifyListeners();
    _bgTimer ??= Timer(const Duration(milliseconds: 900), () {
      _bgTimer = null;
      _syncBackground();
    });
  }

  Timer? _bgTimer;
  bool _serviceOn = false;
  bool _askedNotifications = false;
  String _lastSaved = '';

  void _syncBackground() {
    // 1. Notification + background service (Android)
    final pending = transfers.where((x) => !x.finished).toList();
    if (pending.isEmpty || step != AuthStep.ready) {
      if (_serviceOn) {
        _serviceOn = false;
        NativeBridge.serviceStop();
      }
    } else {
      final cur = pending.where((x) => x.running).toList();
      final tr = cur.isNotEmpty ? cur.first : null;
      String title;
      String text;
      var progress = -1;
      if (paused) {
        title = t('tr_paused');
        text = t('notif_waiting', {'n': pending.length});
      } else if (tr == null) {
        title = 'TirsoDrive';
        text = t('notif_waiting', {'n': pending.length});
      } else {
        title = tr.upload
            ? t('tr_uploading', {'i': (uploadsDone + 1).clamp(1, uploadsTotal < 1 ? 1 : uploadsTotal), 'n': uploadsTotal < 1 ? 1 : uploadsTotal})
            : t('tr_downloading');
        final finishing = tr.upload && tr.size > 0 && tr.bytes >= tr.size;
        if (tr.status == TStatus.active && !finishing) progress = (tr.fraction * 100).round();
        text = '${tr.name} · ${finishing ? t('tr_finishing') : (tr.status == TStatus.active ? '$progress%' : t('tr_preparing'))}';
      }
      _serviceOn = true;
      NativeBridge.serviceUpdate(
        title: title,
        text: text,
        progress: progress,
        paused: paused,
        button: paused ? t('tr_resume') : t('notif_pause'),
      );
    }
    // 2. Remember unfinished uploads so they continue after the app or phone restarts
    final list = transfers
        .where((x) => x.upload && !x.finished)
        .map((x) => {
              'name': x.name,
              'size': x.size,
              'uri': x.uri,
              'path': x.sourcePath,
              'mtime': x.modifiedMs,
              'key': x.destKey,
              'chat': x.destChatId,
              'tmpChat': x.chatId,
              'tmpMsg': x.tempMessageId,
              'extra': x.captionExtra,
              'enc': x.encrypt,
            })
        .toList();
    final json = jsonEncode(list);
    if (json != _lastSaved && step == AuthStep.ready) {
      _lastSaved = json;
      _prefs.setString('queue_v1', json);
    }
  }

  Future<void> _restoreQueue() async {
    final raw = _prefs.getString('queue_v1');
    if (raw == null || raw == '[]' || transfers.isNotEmpty) return;
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return;
    }
    final items = <Transfer>[];
    for (final e in list) {
      final m = e as Map<String, dynamic>;
      // An upload that was half-sent when the app closed: cancel Telegram's leftover copy, then send it again.
      final tmpChat = (m['tmpChat'] as num?)?.toInt();
      final tmpMsg = (m['tmpMsg'] as num?)?.toInt();
      if (tmpChat != null && tmpMsg != null) {
        try {
          final msg = await td.call({'@type': 'getMessage', 'chat_id': tmpChat, 'message_id': tmpMsg});
          if (msg['sending_state'] != null) {
            await td.call({'@type': 'deleteMessages', 'chat_id': tmpChat, 'message_ids': [tmpMsg], 'revoke': true});
          } else {
            continue; // it actually finished sending — nothing to redo
          }
        } catch (_) {}
      }
      final restored = Transfer.upload(
        name: (m['name'] ?? 'file') as String,
        size: (m['size'] as num?)?.toInt() ?? 0,
        uri: m['uri'] as String?,
        sourcePath: m['path'] as String?,
        modifiedMs: (m['mtime'] as num?)?.toInt(),
        destKey: m['key'] as String?,
        destChatId: (m['chat'] as num?)?.toInt(),
      );
      restored.captionExtra = (m['extra'] ?? '') as String;
      restored.encrypt = m['enc'] == true;
      items.add(restored);
    }
    if (items.isEmpty) return;
    _batchTotal = items.length;
    _batchDone = 0;
    transfers.addAll(items);
    _say(t('resumed', {'n': items.length}));
    notifyListeners();
    _pump();
  }

  Future<void> _runUpload(Transfer tr) async {
    _upBusy = true;
    tr._done = Completer<void>();
    try {
      // 1. Make sure the destination channel exists
      int chatId;
      if (tr.destChatId != null) {
        chatId = tr.destChatId!;
      } else {
        tr.status = TStatus.creating;
        notifyListeners();
        chatId = await ensureChannel(tr.destKey!, forTransfer: tr);
      }
      if (tr.status == TStatus.cancelled) throw _Cancelled();
      tr.chatId = chatId;

      // 2. Get a real file path (Android copies the one file it is about to upload)
      tr.status = TStatus.preparing;
      notifyListeners();
      String path;
      if (tr.uri != null) {
        path = await NativeBridge.copyToCache(tr.uri!, tr.name);
        tr.tempPath = path;
      } else {
        path = tr.sourcePath!;
      }
      if (tr.status == TStatus.cancelled) throw _Cancelled();
      String extra = tr.captionExtra;
      String? encPath;
      if (tr.encrypt) {
        final key = vaultKey;
        if (key == null) throw Exception(t('vault_need'));
        final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}enc')..createSync(recursive: true);
        encPath = '${dir.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}.tde';
        await encryptFile(path, encPath, key);
        path = encPath;
        tr.remoteSize = encryptedSize(tr.size);
        extra = '$extra enc=1 name=${Uri.encodeComponent(tr.name)}'.trim();
      }
      if (tr.status == TStatus.cancelled) throw _Cancelled();

      // 3. Send it as a document so Telegram keeps the original file untouched
      final mtimeSec = (tr.modifiedMs ?? 0) ~/ 1000;
      final caption = 'tirsodrive v1${mtimeSec > 0 ? ' mtime=$mtimeSec' : ''} src=${Platform.isAndroid ? 'android' : 'pc'}${extra.isEmpty ? '' : ' $extra'}';
      tr.status = TStatus.active;
      tr._lastTime = DateTime.now();
      notifyListeners();
      final th = tr.encrypt ? null : await _makeUploadThumb(path, tr.name);
      final msg = await td.call({
        '@type': 'sendMessage',
        'chat_id': chatId,
        'input_message_content': {
          '@type': 'inputMessageDocument',
          // TDLib 1.8.6x wraps the file in an inputDocument object
          'document': {
            '@type': 'inputDocument',
            'document': {'@type': 'inputFileLocal', 'path': path},
            if (th != null)
              'thumbnail': {'@type': 'inputThumbnail', 'thumbnail': {'@type': 'inputFileLocal', 'path': th.path}, 'width': th.w, 'height': th.h},
            'disable_content_type_detection': true,
          },
          'caption': {'@type': 'formattedText', 'text': caption, 'entities': <dynamic>[]},
        },
      });
      tr.tempMessageId = (msg['id'] as num).toInt();
      final doc = msg['content']?['document']?['document'] as Map<String, dynamic>?;
      if (doc != null) {
        tr.fileId = (doc['id'] as num).toInt();
        _byFileId[tr.fileId!] = tr;
      }
      await tr._done!.future;
      if (encPath != null) {
        try {
          File(encPath).deleteSync();
        } catch (_) {}
      }
    } on _Cancelled {
      tr.status = TStatus.cancelled;
    } on TdError catch (e) {
      tr.status = TStatus.failed;
      tr.error = e.message;
    } catch (e) {
      tr.status = TStatus.failed;
      tr.error = e.toString();
    }
    if (tr.fileId != null) _byFileId.remove(tr.fileId);
    if (tr.tempPath != null) {
      try {
        File(tr.tempPath!).deleteSync();
      } catch (_) {}
    }
    if (tr.uri != null && tr.status == TStatus.done) NativeBridge.releaseUri(tr.uri!);
    _batchDone++;
    _upBusy = false;
    notifyListeners();
    _pump();
  }

  Future<void> _runDownload(Transfer tr) async {
    _downBusy = true;
    tr._done = Completer<void>();
    final f = tr.file!;
    tr.fileId = f.fileId;
    _byFileId[f.fileId] = tr;
    tr.status = TStatus.active;
    tr._lastTime = DateTime.now();
    notifyListeners();
    String? path;
    try {
      final res = await td.call({
        '@type': 'downloadFile',
        'file_id': f.fileId,
        'priority': 16,
        'offset': 0,
        'limit': 0,
        'synchronous': false,
      });
      if (res['local']?['is_downloading_completed'] == true) {
        tr.bytes = tr.size;
        tr._done!.complete();
      }
      await tr._done!.future;
      if (tr.status != TStatus.cancelled) {
        final file = await td.call({'@type': 'getFile', 'file_id': f.fileId});
        path = file['local']?['path'] as String?;
        if (path == null || path.isEmpty) throw Exception('Download did not finish');
        if (f.encrypted) {
          final key = vaultKey;
          if (key == null) throw Exception(t('vault_need'));
          final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}dec${Platform.pathSeparator}${f.fileId}')..createSync(recursive: true);
          final out = '${dir.path}${Platform.pathSeparator}${f.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}';
          try {
            await decryptFile(path, out, key);
          } on VaultError {
            throw Exception(t('vault_wrong'));
          }
          unawaited(dropLocal([f.fileId])); // keep only the readable copy, and only for now
          path = out;
        }
        tr.status = TStatus.done;
        tr.bytes = tr.size;
      }
    } on TdError catch (e) {
      tr.status = TStatus.failed;
      tr.error = e.message;
    } catch (e) {
      tr.status = TStatus.failed;
      tr.error = e.toString();
    }
    _byFileId.remove(f.fileId);
    _downBusy = false;
    notifyListeners();
    _pump();
    if (!tr.result.isCompleted) tr.result.complete(tr.status == TStatus.done ? path : null);
    if (path != null && tr.status == TStatus.done && tr.action != 'keep') {
      try {
        if (tr.action == 'save') {
          final where = await NativeBridge.saveToDownloads(path, f.name, f.mime);
          _say(t('saved_to', {'p': where}));
          unawaited(dropLocal([f.fileId])); // the copy in Downloads is enough
        } else {
          await NativeBridge.openFile(path, f.mime);
          _markTemp([f.fileId]); // the viewer may still be reading it; cleaned the next time the app opens
        }
      } catch (e) {
        _say(tr.action == 'save' ? t('err_generic', {'e': e}) : t('open_failed'));
      }
    }
  }

  void _onFile(Map<String, dynamic> file) {
    final id = (file['id'] as num).toInt();
    final tr = _byFileId[id];
    if (tr == null) return;
    if (tr.upload) {
      final up = (file['remote']?['uploaded_size'] as num?)?.toInt() ?? 0;
      tr._progress(up);
    } else {
      final local = file['local'] as Map<String, dynamic>? ?? {};
      tr._progress((local['downloaded_size'] as num?)?.toInt() ?? 0);
      if (local['is_downloading_completed'] == true && !(tr._done?.isCompleted ?? true)) {
        tr._done!.complete();
      } else if (local['is_downloading_active'] == false &&
          local['is_downloading_completed'] != true &&
          tr.status == TStatus.active &&
          tr.bytes > 0 &&
          !(tr._done?.isCompleted ?? true)) {
        // download stopped without finishing
        tr.status = TStatus.failed;
        tr.error = 'Download stopped';
        tr._done!.complete();
      }
    }
    notifyListeners();
  }

  /// Finds the upload a Telegram "sent"/"failed" signal belongs to.
  /// Temporary message numbers restart in every channel, so the channel must match too,
  /// and only an upload that is still waiting can be the one.
  Transfer? _uploadFor(int chatId, int oldId) {
    for (final tr in transfers) {
      if (tr.upload && !tr.finished && tr.chatId == chatId && tr.tempMessageId == oldId) return tr;
    }
    return null;
  }

  void _onSent(Map<String, dynamic> message, int oldId) {
    _copyWaiters.remove('${message['chat_id']}:$oldId')?.complete(message);
    final tr = _uploadFor((message['chat_id'] as num).toInt(), oldId);
    if (tr != null) {
      final sentFile = _fileFromMessage(message);
      if (sentFile != null && tr.size > 0 && sentFile.size != (tr.remoteSize ?? tr.size)) {
        tr.status = TStatus.failed; // integrity check: Telegram has a different size than the original
        tr.error = t('err_integrity', {'a': formatBytes(sentFile.size), 'b': formatBytes(tr.size)});
      } else {
        tr.status = TStatus.done;
        tr.verified = sentFile != null;
      }
      tr.bytes = tr.size;
      if (!(tr._done?.isCompleted ?? true)) tr._done!.complete();
      if (tr.status == TStatus.done) {
        try {
          tr.onSent?.call(sentFile);
        } catch (_) {}
      }
    }
    _addMessage(message);
    notifyListeners();
  }

  void _onSendFailed(Map<String, dynamic> message, int oldId, String error) {
    _copyWaiters.remove('${message['chat_id']}:$oldId')?.complete(null);
    final tr = _uploadFor((message['chat_id'] as num).toInt(), oldId);
    if (tr != null) {
      tr.status = TStatus.failed;
      tr.error = error;
      if (!(tr._done?.isCompleted ?? true)) tr._done!.complete();
    }
    notifyListeners();
  }

  // "Uploading 2 of 5" counts only the current batch, not everything since the app opened.
  int _batchTotal = 0;
  int _batchDone = 0;
  int get uploadsTotal => _batchTotal;
  int get uploadsDone => _batchDone;
}

class _Cancelled implements Exception {}


/// Runs in a background isolate: shrinks an image to a JPEG preview (max 320 px). Returns [width, height].
List<int>? _imageThumb(List<String> a) {
  final src = img.decodeImage(File(a[0]).readAsBytesSync());
  if (src == null) return null;
  final small = src.width >= src.height ? img.copyResize(src, width: src.width > 320 ? 320 : src.width) : img.copyResize(src, height: src.height > 320 ? 320 : src.height);
  File(a[1]).writeAsBytesSync(img.encodeJpg(small, quality: 78));
  return [small.width, small.height];
}
