import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tirsodrive/core/vault.dart';

void main() {
  test('encrypt → decrypt gives back the exact file; wrong password is refused', () async {
    final dir = Directory.systemTemp.createTempSync('vault');
    final rnd = Random(1);
    for (final size in [0, 10, 1024 * 1024, 2 * 1024 * 1024 + 123]) {
      final plain = File('${dir.path}/p$size')..writeAsBytesSync(List.generate(size, (_) => rnd.nextInt(256)));
      final key = await deriveVaultKey('correct horse', 42);
      await encryptFile(plain.path, '${dir.path}/e$size', key);
      expect(File('${dir.path}/e$size').lengthSync(), encryptedSize(size));
      await decryptFile('${dir.path}/e$size', '${dir.path}/d$size', key);
      expect(File('${dir.path}/d$size').readAsBytesSync(), plain.readAsBytesSync());
      final wrong = await deriveVaultKey('wrong', 42);
      expect(() => decryptFile('${dir.path}/e$size', '${dir.path}/x$size', wrong), throwsA(isA<VaultError>()));
    }
    // same password on another account gives a different key
    expect(await deriveVaultKey('correct horse', 43), isNot(await deriveVaultKey('correct horse', 42)));
    dir.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
