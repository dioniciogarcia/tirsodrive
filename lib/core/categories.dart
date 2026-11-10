// Categories, consoles and the rules that decide which channel a file goes to.
import 'package:flutter/material.dart';

const String channelPrefix = 'TD - ';

class Category {
  final String key;
  final String channelTitle; // exact Telegram channel name
  final String en;
  final String es;
  final String tag; // short badge text
  final Color color;
  final bool isRom;
  final bool isApk; // an APK channel for one console (Tirso Compiler's output)
  final String? logo; // console PNG in assets/consoles/
  const Category(this.key, this.channelTitle, this.en, this.es, this.tag, this.color, {this.isRom = false, this.isApk = false, this.logo});

  String label(String lang) => lang == 'es' ? es : en;

  /// Name with its group, e.g. "ROMs · N64" or "APKs · N64".
  String full(String lang) => isRom ? 'ROMs · ${label(lang)}' : (isApk ? 'APKs · ${label(lang)}' : label(lang));

  String? get logoAsset => logo == null ? null : 'assets/consoles/$logo.png';
}

const _romColor = Color(0xFF3BA7F5);

const List<Category> libraryCategories = [
  Category('videos', 'TD - Videos', 'Videos', 'Videos', 'VID', Color(0xFFE86F6F)),
  Category('photos', 'TD - Photos', 'Photos', 'Fotos', 'IMG', Color(0xFF6FD39A)),
  Category('games', 'TD - Games', 'Other games (APKs)', 'Otros juegos (APKs)', 'APK', Color(0xFFF5A524)),
  Category('audio', 'TD - Audio', 'Audio', 'Audio', 'AUD', Color(0xFF4FD1D9)),
  Category('docs', 'TD - Documents', 'Documents', 'Documentos', 'DOC', Color(0xFF7C9CF5)),
  Category('compressed', 'TD - Compressed', 'Compressed', 'Comprimidos', 'ZIP', Color(0xFFB58CF2)),
  Category('other', 'TD - Other', 'Other', 'Otros', '···', Color(0xFF8C97AD)),
];

const _apkColor = Color(0xFFF5A524);

/// "Games (APKs)" by console: the same consoles Tirso Compiler builds for. Channel names match the ones the
/// Connected programs setup creates ("TD - N64 APKs", …), so they show up here automatically.
const List<Category> apkCategories = [
  Category('apk_n64', 'TD - N64 APKs', 'Nintendo 64', 'Nintendo 64', 'N64', _apkColor, isApk: true, logo: 'n64'),
  Category('apk_gba', 'TD - GBA APKs', 'Game Boy Advance', 'Game Boy Advance', 'GBA', _apkColor, isApk: true, logo: 'gba'),
  Category('apk_ds', 'TD - DS APKs', 'Nintendo DS', 'Nintendo DS', 'DS', _apkColor, isApk: true, logo: 'ds'),
  Category('apk_gc', 'TD - GameCube APKs', 'GameCube', 'GameCube', 'GC', _apkColor, isApk: true, logo: 'gc'),
  Category('apk_wii', 'TD - Wii APKs', 'Wii', 'Wii', 'WII', _apkColor, isApk: true, logo: 'wii'),
  Category('apk_ps1', 'TD - PS1 APKs', 'PlayStation', 'PlayStation', 'PS1', _apkColor, isApk: true, logo: 'ps1'),
  Category('apk_ps2', 'TD - PS2 APKs', 'PlayStation 2', 'PlayStation 2', 'PS2', _apkColor, isApk: true, logo: 'ps2'),
  Category('apk_psp', 'TD - PSP APKs', 'PSP', 'PSP', 'PSP', _apkColor, isApk: true, logo: 'psp'),
];

const List<Category> romCategories = [
  Category('rom_nes', 'TD - ROMs - NES', 'NES', 'NES', 'NES', _romColor, isRom: true, logo: 'nes'),
  Category('rom_snes', 'TD - ROMs - SNES', 'SNES', 'SNES', 'SNES', _romColor, isRom: true, logo: 'snes'),
  Category('rom_gb', 'TD - ROMs - Game Boy', 'Game Boy / Color', 'Game Boy / Color', 'GB', _romColor, isRom: true, logo: 'gb'),
  Category('rom_gba', 'TD - ROMs - GBA', 'Game Boy Advance', 'Game Boy Advance', 'GBA', _romColor, isRom: true, logo: 'gba'),
  Category('rom_n64', 'TD - ROMs - N64', 'Nintendo 64', 'Nintendo 64', 'N64', _romColor, isRom: true, logo: 'n64'),
  Category('rom_ds', 'TD - ROMs - DS', 'Nintendo DS', 'Nintendo DS', 'DS', _romColor, isRom: true, logo: 'ds'),
  Category('rom_3ds', 'TD - ROMs - 3DS', 'Nintendo 3DS', 'Nintendo 3DS', '3DS', _romColor, isRom: true, logo: '3ds'),
  Category('rom_gc', 'TD - ROMs - GameCube', 'GameCube', 'GameCube', 'GC', _romColor, isRom: true, logo: 'gc'),
  Category('rom_wii', 'TD - ROMs - Wii', 'Wii', 'Wii', 'WII', _romColor, isRom: true, logo: 'wii'),
  Category('rom_ps1', 'TD - ROMs - PS1', 'PlayStation', 'PlayStation', 'PS1', _romColor, isRom: true, logo: 'ps1'),
  Category('rom_ps2', 'TD - ROMs - PS2', 'PlayStation 2', 'PlayStation 2', 'PS2', _romColor, isRom: true, logo: 'ps2'),
  Category('rom_psp', 'TD - ROMs - PSP', 'PSP', 'PSP', 'PSP', _romColor, isRom: true, logo: 'psp'),
  Category('rom_genesis', 'TD - ROMs - Genesis', 'Genesis / Mega Drive', 'Genesis / Mega Drive', 'MD', _romColor, isRom: true, logo: 'genesis'),
];

List<Category> get allCategories => [...libraryCategories, ...apkCategories, ...romCategories];

Category? categoryByKey(String key) {
  for (final c in allCategories) {
    if (c.key == key) return c;
  }
  return null;
}

Category? categoryByTitle(String title) {
  for (final c in allCategories) {
    if (c.channelTitle.toLowerCase() == title.toLowerCase()) return c;
  }
  return null;
}

const Map<String, String> _extToKey = {
  // videos
  'mp4': 'videos', 'mkv': 'videos', 'avi': 'videos', 'mov': 'videos', 'wmv': 'videos', 'flv': 'videos',
  'webm': 'videos', 'm4v': 'videos', '3gp': 'videos', 'ts': 'videos', 'mpg': 'videos', 'mpeg': 'videos',
  // photos
  'jpg': 'photos', 'jpeg': 'photos', 'png': 'photos', 'gif': 'photos', 'webp': 'photos', 'heic': 'photos',
  'heif': 'photos', 'bmp': 'photos', 'tif': 'photos', 'tiff': 'photos', 'dng': 'photos', 'raw': 'photos',
  // audio
  'mp3': 'audio', 'm4a': 'audio', 'flac': 'audio', 'wav': 'audio', 'ogg': 'audio', 'oga': 'audio', 'opus': 'audio',
  'aac': 'audio', 'wma': 'audio', 'aiff': 'audio', 'aif': 'audio', 'amr': 'audio', 'mid': 'audio', 'midi': 'audio',
  // documents
  'pdf': 'docs', 'doc': 'docs', 'docx': 'docs', 'xls': 'docs', 'xlsx': 'docs', 'xlsm': 'docs', 'ppt': 'docs',
  'pptx': 'docs', 'odt': 'docs', 'ods': 'docs', 'odp': 'docs', 'txt': 'docs', 'rtf': 'docs', 'csv': 'docs',
  'epub': 'docs', 'mobi': 'docs', 'json': 'docs', 'xml': 'docs', 'html': 'docs', 'htm': 'docs',
  // games
  'apk': 'games', 'xapk': 'games', 'apks': 'games', 'apkm': 'games',
  // compressed
  'zip': 'compressed', 'rar': 'compressed', '7z': 'compressed', 'tar': 'compressed', 'gz': 'compressed',
  'tgz': 'compressed', 'bz2': 'compressed', 'xz': 'compressed',
  // ROMs with a clear console
  'nes': 'rom_nes', 'fds': 'rom_nes', 'unf': 'rom_nes',
  'sfc': 'rom_snes', 'smc': 'rom_snes',
  'gb': 'rom_gb', 'gbc': 'rom_gb',
  'gba': 'rom_gba',
  'z64': 'rom_n64', 'n64': 'rom_n64', 'v64': 'rom_n64',
  'nds': 'rom_ds', 'dsi': 'rom_ds',
  '3ds': 'rom_3ds', 'cia': 'rom_3ds', 'cci': 'rom_3ds', 'cxi': 'rom_3ds',
  'gcm': 'rom_gc', 'gcz': 'rom_gc',
  'wbfs': 'rom_wii', 'wad': 'rom_wii', 'wia': 'rom_wii',
  'cue': 'rom_ps1', 'ccd': 'rom_ps1', 'ecm': 'rom_ps1',
  'cso': 'rom_psp', 'zso': 'rom_psp',
  'md': 'rom_genesis', 'gen': 'rom_genesis', 'smd': 'rom_genesis',
};

/// Extensions used by several consoles: the user picks the console.
const Map<String, List<String>> ambiguousExt = {
  'iso': ['rom_ps2', 'rom_psp', 'rom_gc', 'rom_wii', 'rom_ps1'],
  'chd': ['rom_ps1', 'rom_ps2'],
  'rvz': ['rom_gc', 'rom_wii'],
  'ciso': ['rom_gc', 'rom_wii', 'rom_psp'],
  'pbp': ['rom_psp', 'rom_ps1'],
  'bin': ['rom_ps1', 'rom_genesis', 'other'],
  'img': ['rom_ps1', 'other'],
};

const Map<String, String> _libretroSystems = {
  'rom_nes': 'Nintendo - Nintendo Entertainment System',
  'rom_snes': 'Nintendo - Super Nintendo Entertainment System',
  'rom_gb': 'Nintendo - Game Boy',
  'rom_gba': 'Nintendo - Game Boy Advance',
  'rom_n64': 'Nintendo - Nintendo 64',
  'rom_ds': 'Nintendo - Nintendo DS',
  'rom_3ds': 'Nintendo - Nintendo 3DS',
  'rom_gc': 'Nintendo - GameCube',
  'rom_wii': 'Nintendo - Wii',
  'rom_ps1': 'Sony - PlayStation',
  'rom_ps2': 'Sony - PlayStation 2',
  'rom_psp': 'Sony - PlayStation Portable',
  'rom_genesis': 'Sega - Mega Drive - Genesis',
};

/// Box art from the libretro thumbnails project, matched by file name
/// (works best with standard names such as "Pokemon - Emerald Version (USA, Europe).gba").
String? boxArtUrl(String? categoryKey, String fileName) {
  var system = _libretroSystems[categoryKey];
  if (system == null) return null;
  if (categoryKey == 'rom_gb' && extensionOf(fileName) == 'gbc') system = 'Nintendo - Game Boy Color';
  final dot = fileName.lastIndexOf('.');
  var title = dot > 0 ? fileName.substring(0, dot) : fileName;
  title = title.replaceAll(RegExp(r'[&*/:`<>?\\|"]'), '_');
  return 'https://thumbnails.libretro.com/${Uri.encodeComponent(system)}/Named_Boxarts/${Uri.encodeComponent(title)}.png';
}

String extensionOf(String name) {
  final i = name.lastIndexOf('.');
  if (i < 0 || i == name.length - 1) return '';
  return name.substring(i + 1).toLowerCase();
}

/// Returns the category key for a file name, or null when the user has to choose (ambiguous).
String? routeFile(String name) {
  final ext = extensionOf(name);
  if (ambiguousExt.containsKey(ext)) return null;
  if (_extToKey[ext] == 'games') return apkConsoleFromName(name) ?? 'games';
  return _extToKey[ext] ?? 'other';
}

String mimeFor(String name) {
  const m = {
    'mp4': 'video/mp4', 'mkv': 'video/x-matroska', 'webm': 'video/webm', 'mov': 'video/quicktime', 'avi': 'video/x-msvideo',
    'm4v': 'video/mp4', '3gp': 'video/3gpp', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
    'gif': 'image/gif', 'webp': 'image/webp', 'heic': 'image/heic', 'bmp': 'image/bmp', 'pdf': 'application/pdf',
    'apk': 'application/vnd.android.package-archive', 'zip': 'application/zip', 'rar': 'application/vnd.rar',
    '7z': 'application/x-7z-compressed', 'mp3': 'audio/mpeg', 'm4a': 'audio/mp4', 'txt': 'text/plain', 'flac': 'audio/flac', 'wav': 'audio/wav', 'ogg': 'audio/ogg',
    'opus': 'audio/ogg', 'aac': 'audio/aac', 'epub': 'application/epub+zip',
  };
  return m[extensionOf(name)] ?? 'application/octet-stream';
}

/// Picks the console APK channel when the file name says which console it is ("Mario Kart DS.apk",
/// "God of War PS2 TV.apk"); null when it doesn't (the file goes to "Other games" and can be moved).
String? apkConsoleFromName(String name) {
  final words = name.toLowerCase().replaceAll(RegExp(r'\.[a-z0-9]+$'), '').split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();
  final text = ' ${words.join(' ')} ';
  const hints = {
    'apk_n64': ['n64', 'nintendo 64'],
    'apk_gba': ['gba', 'game boy advance'],
    'apk_ds': ['nds', 'ds', 'nintendo ds'],
    'apk_gc': ['gamecube', 'game cube', 'gc'],
    'apk_wii': ['wii'],
    'apk_ps1': ['ps1', 'psx', 'playstation 1'],
    'apk_ps2': ['ps2', 'playstation 2'],
    'apk_psp': ['psp'],
  };
  for (final e in hints.entries) {
    for (final h in e.value) {
      if (text.contains(' $h ')) return e.key;
    }
  }
  return null;
}
