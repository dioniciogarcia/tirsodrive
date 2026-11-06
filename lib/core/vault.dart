// Optional encryption of selected files (AES-256-GCM, key from your password with PBKDF2).
// Telegram only ever stores the scrambled file. Without the password, nobody — not even TirsoDrive — can open it.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const _magic = [0x54, 0x44, 0x45, 0x31]; // "TDE1"
const _chunk = 1024 * 1024;

/// Same password + same Telegram account = same key on every device.
Future<List<int>> deriveVaultKey(String password, int accountId) {
  return Isolate.run(() async {
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 150000, bits: 256);
    final key = await kdf.deriveKeyFromPassword(password: password, nonce: utf8.encode('tirsodrive-vault:$accountId'));
    return key.extractBytes();
  });
}

/// Size of the encrypted file for a plain file of [plain] bytes.
int encryptedSize(int plain) {
  final chunks = plain == 0 ? 1 : (plain + _chunk - 1) ~/ _chunk;
  return 4 + plain + chunks * (12 + 4 + 16);
}

/// Encrypts [src] into [dst] (runs in the background so the app stays smooth).
Future<void> encryptFile(String src, String dst, List<int> key) {
  return Isolate.run(() async {
    final algo = AesGcm.with256bits();
    final secret = SecretKey(key);
    final rnd = Random.secure();
    final input = File(src).openSync();
    final out = File(dst).openSync(mode: FileMode.write);
    try {
      out.writeFromSync(_magic);
      var wroteOne = false;
      while (true) {
        final plain = input.readSync(_chunk);
        if (plain.isEmpty && wroteOne) break;
        final nonce = List<int>.generate(12, (_) => rnd.nextInt(256));
        final box = await algo.encrypt(plain, secretKey: secret, nonce: nonce);
        final len = ByteData(4)..setUint32(0, box.cipherText.length);
        out.writeFromSync(nonce);
        out.writeFromSync(len.buffer.asUint8List());
        out.writeFromSync(box.cipherText);
        out.writeFromSync(box.mac.bytes);
        wroteOne = true;
        if (plain.length < _chunk) break;
      }
    } finally {
      input.closeSync();
      out.closeSync();
    }
  });
}

/// Decrypts [src] into [dst]. Throws [VaultError] when the password is wrong or the file was changed.
Future<void> decryptFile(String src, String dst, List<int> key) async {
  final ok = await Isolate.run(() async {
    final algo = AesGcm.with256bits();
    final secret = SecretKey(key);
    final input = File(src).openSync();
    final out = File(dst).openSync(mode: FileMode.write);
    try {
      final head = input.readSync(4);
      if (head.length != 4 || !List.generate(4, (i) => head[i] == _magic[i]).every((x) => x)) return false;
      while (true) {
        final nonce = input.readSync(12);
        if (nonce.isEmpty) break;
        final lenBytes = input.readSync(4);
        final len = ByteData.sublistView(Uint8List.fromList(lenBytes)).getUint32(0);
        final cipher = input.readSync(len);
        final mac = input.readSync(16);
        final plain = await algo.decrypt(SecretBox(cipher, nonce: nonce, mac: Mac(mac)), secretKey: secret);
        out.writeFromSync(plain);
      }
      return true;
    } on SecretBoxAuthenticationError {
      return false;
    } finally {
      input.closeSync();
      out.closeSync();
    }
  });
  if (!ok) {
    try {
      File(dst).deleteSync();
    } catch (_) {}
    throw VaultError();
  }
}

class VaultError implements Exception {}
