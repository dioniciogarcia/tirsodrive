import 'package:flutter_test/flutter_test.dart';
import 'package:tirsodrive/core/categories.dart';
import 'package:tirsodrive/core/strings.dart';

void main() {
  test('files are routed to the right channel', () {
    expect(routeFile('Super Mario 64.z64'), 'rom_n64');
    expect(routeFile('Pokemon Emerald.GBA'), 'rom_gba');
    expect(routeFile('Mario Kart DS.nds'), 'rom_ds');
    expect(routeFile('Holiday.MP4'), 'videos');
    expect(routeFile('IMG_2041.jpg'), 'photos');
    expect(routeFile('Super Mario 64 TV.apk'), 'games');
    expect(routeFile('saves.7z'), 'compressed');
    expect(routeFile('notes.txt'), 'docs');
    expect(routeFile('Report.PDF'), 'docs');
    expect(routeFile('song.flac'), 'audio');
    expect(routeFile('mix.MP3'), 'audio');
    expect(routeFile('tool.exe'), 'other');
    expect(routeFile('Sonic.md'), 'rom_genesis'); // Mega Drive stays a ROM
    expect(routeFile('noextension'), 'other');
    expect(routeFile('God of War.iso'), isNull); // user picks console
    expect(routeFile('Metroid Prime.rvz'), isNull);
  });
  test('channel names', () {
    expect(categoryByKey('rom_n64')!.channelTitle, 'TD - ROMs - N64');
    expect(categoryByTitle('td - videos')!.key, 'videos');
    for (final c in allCategories) {
      expect(c.channelTitle.startsWith(channelPrefix), isTrue);
    }
  });
  test('sizes and text', () {
    expect(formatBytes(2000 * 1024 * 1024), '2 GB');
    expect(formatBytes(12 * 1024 * 1024), '12 MB');
    appLang = 'es';
    expect(t('upload_n', {'n': 3}), 'Subir 3 archivos');
    appLang = 'en';
    expect(t('upload_n', {'n': 3}), 'Upload 3 files');
  });
}
