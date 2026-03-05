// =============================================================================
// NOTITIA — Service de fichier .notitia (sérialisation + chiffrement)
// =============================================================================
// Format binaire :
//   [4 octets] Magic : "NTIA"
//   [1 octet]  Version : 0x01
//   [1 octet]  Flags : bit 0 = compressed, bit 1 = encrypted
//   [N octets] Payload : zlib(JSON) ou AES-256-CBC(zlib(JSON))
//
// Crypto 100% Dart — zéro dépendance native :
//   - SHA-256 (FIPS 180-4) pour checksum & PBKDF2-PRF
//   - PBKDF2-HMAC-SHA256 (100 000 itérations, 32 octets)
//   - AES-256-CBC avec IV aléatoire (16 octets préfixés)
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/transcription.dart';

// =============================================================================
// MODÈLES
// =============================================================================

enum NotitiaContentType { transcription, mindMap, unknown }

class NotitiaFileMetadata {
  final String appVersion;
  final String createdAt;
  final NotitiaContentType contentType;

  const NotitiaFileMetadata({
    this.appVersion = '2.0',
    required this.createdAt,
    this.contentType = NotitiaContentType.transcription,
  });

  Map<String, dynamic> toJson() => {
        'app_version': appVersion,
        'created_at': createdAt,
        'content_type': contentType.name,
      };

  factory NotitiaFileMetadata.fromJson(Map<String, dynamic> json) {
    final typeStr = json['content_type'] as String? ?? 'transcription';
    return NotitiaFileMetadata(
      appVersion: json['app_version'] as String? ?? '1.0',
      createdAt: json['created_at'] as String? ?? '',
      contentType: NotitiaContentType.values
          .firstWhere((e) => e.name == typeStr, orElse: () => NotitiaContentType.unknown),
    );
  }
}

class NotitiaFile {
  final NotitiaFileMetadata metadata;
  final Map<String, dynamic> content;

  const NotitiaFile({required this.metadata, required this.content});

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'content': content,
      };

  factory NotitiaFile.fromJson(Map<String, dynamic> json) => NotitiaFile(
        metadata: NotitiaFileMetadata.fromJson(
            json['metadata'] as Map<String, dynamic>? ?? {}),
        content: json['content'] as Map<String, dynamic>? ?? {},
      );
}

// =============================================================================
// RÉSULTAT D'IMPORT
// =============================================================================

class ImportResult {
  final bool success;
  final String message;
  final Transcription? transcription;

  const ImportResult({
    required this.success,
    required this.message,
    this.transcription,
  });
}

// =============================================================================
// SERVICE PRINCIPAL
// =============================================================================

class NotitiaFileService {
  static const List<int> _magic = [0x4E, 0x54, 0x49, 0x41]; // "NTIA"
  static const int _version = 0x01;
  static const int _flagCompressed = 0x01;
  static const int _flagEncrypted = 0x02;

  // ---------------------------------------------------------------------------
  // CRÉER UN NOTITIA FILE DEPUIS UNE TRANSCRIPTION
  // ---------------------------------------------------------------------------

  static NotitiaFile createFromTranscription(Transcription t) {
    return NotitiaFile(
      metadata: NotitiaFileMetadata(
        createdAt: DateTime.now().toIso8601String(),
        contentType: NotitiaContentType.transcription,
      ),
      content: t.toJson(),
    );
  }

  // ---------------------------------------------------------------------------
  // EXPORT → fichier .notitia
  // ---------------------------------------------------------------------------

  static Future<String> exportToFile(NotitiaFile notitia,
      {String? password}) async {
    final jsonBytes =
        utf8.encode(const JsonEncoder().convert(notitia.toJson()));

    // 1. zlib compress
    final compressed = ZLibCodec(level: 6).encode(jsonBytes);

    int flags = _flagCompressed;
    Uint8List payload;

    // 2. Optionnel : chiffrement AES-256-CBC
    if (password != null && password.isNotEmpty) {
      flags |= _flagEncrypted;
      final salt = _randomBytes(16);
      final key = _Pbkdf2.deriveKey(password, salt);
      final iv = _randomBytes(16);
      final encrypted =
          _AesCbc.encrypt(Uint8List.fromList(compressed), key, iv);
      // salt(16) + iv(16) + ciphertext
      payload = Uint8List(32 + encrypted.length);
      payload.setRange(0, 16, salt);
      payload.setRange(16, 32, iv);
      payload.setRange(32, payload.length, encrypted);
    } else {
      payload = Uint8List.fromList(compressed);
    }

    // 3. Assembler : magic(4) + version(1) + flags(1) + payload
    final out = BytesBuilder();
    out.add(_magic);
    out.addByte(_version);
    out.addByte(flags);
    out.add(payload);

    // 4. Écrire dans le cache
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${dir.path}/note_$ts.notitia');
    await file.writeAsBytes(out.toBytes());

    debugPrint(
        '[NotitiaFileService] Exported ${file.path} (${out.length} bytes)');
    return file.path;
  }

  // ---------------------------------------------------------------------------
  // IMPORT ← fichier .notitia
  // ---------------------------------------------------------------------------

  static Future<ImportResult> importFile(String filePath,
      {String? password}) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        return const ImportResult(
            success: false, message: 'Fichier introuvable.');
      }

      final bytes = await file.readAsBytes();
      if (bytes.length < 6) {
        return const ImportResult(
            success: false, message: 'Fichier trop petit.');
      }

      // Vérifier magic
      if (bytes[0] != _magic[0] ||
          bytes[1] != _magic[1] ||
          bytes[2] != _magic[2] ||
          bytes[3] != _magic[3]) {
        return const ImportResult(
            success: false,
            message: 'Format de fichier invalide (magic manquant).');
      }

      final flags = bytes[5];
      var payload = bytes.sublist(6);

      // Déchiffrement si nécessaire
      if (flags & _flagEncrypted != 0) {
        if (password == null || password.isEmpty) {
          return const ImportResult(
              success: false,
              message: 'Ce fichier est chiffré. Mot de passe requis.');
        }
        if (payload.length < 32) {
          return const ImportResult(
              success: false, message: 'Données chiffrées corrompues.');
        }
        final salt = payload.sublist(0, 16);
        final iv = payload.sublist(16, 32);
        final ciphertext = payload.sublist(32);
        final key =
            _Pbkdf2.deriveKey(password, Uint8List.fromList(salt));
        payload = _AesCbc.decrypt(
            Uint8List.fromList(ciphertext), key, Uint8List.fromList(iv));
      }

      // Décompresser
      List<int> jsonBytes;
      if (flags & _flagCompressed != 0) {
        jsonBytes = ZLibCodec().decode(payload);
      } else {
        jsonBytes = payload;
      }

      final jsonStr = utf8.decode(jsonBytes);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final notitia = NotitiaFile.fromJson(json);

      // Reconstruire la Transcription
      final t = Transcription.fromJson(notitia.content);

      return ImportResult(
        success: true,
        message: 'Import réussi : ${t.title}',
        transcription: t,
      );
    } catch (e) {
      debugPrint('[NotitiaFileService] Import error: $e');
      return ImportResult(success: false, message: 'Erreur : $e');
    }
  }

  // ---------------------------------------------------------------------------
  // SHA-256 PUBLIC (pour checksum de bytes bruts)
  // ---------------------------------------------------------------------------

  static String sha256Bytes(Uint8List data) => _Sha256.hashHex(data);

  // ---------------------------------------------------------------------------
  // CHECKSUM D'UN NOTITIA FILE (pour vérification d'intégrité)
  // ---------------------------------------------------------------------------

  static String computeChecksum(Map<String, dynamic> json) {
    final encoded = utf8.encode(const JsonEncoder().convert(json));
    return _Sha256.hashHex(Uint8List.fromList(encoded));
  }

  // ---------------------------------------------------------------------------
  // NETTOYAGE
  // ---------------------------------------------------------------------------

  static void cleanupFile(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) {
        f.deleteSync();
        debugPrint('[NotitiaFileService] Cleaned up: $path');
      }
    } catch (e) {
      debugPrint('[NotitiaFileService] Cleanup error: $e');
    }
  }

  static Future<void> cleanupAllTempFiles() async {
    try {
      final dir = await getTemporaryDirectory();
      final files = dir.listSync().whereType<File>();
      for (final f in files) {
        if (f.path.endsWith('.notitia')) {
          f.deleteSync();
          debugPrint('[NotitiaFileService] Cleaned: ${f.path}');
        }
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // UTILITAIRES CRYPTO INTERNES
  // ---------------------------------------------------------------------------

  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(length, (_) => rng.nextInt(256)));
  }
}

// =============================================================================
// SHA-256 (FIPS 180-4) — implémentation pure Dart
// =============================================================================

class _Sha256 {
  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  static int _rotr(int x, int n) =>
      ((x & 0xFFFFFFFF) >>> n) | ((x << (32 - n)) & 0xFFFFFFFF);

  static Uint8List hash(Uint8List data) {
    final bitLen = data.length * 8;
    final padded = BytesBuilder();
    padded.add(data);
    padded.addByte(0x80);
    while ((padded.length % 64) != 56) {
      padded.addByte(0x00);
    }
    final lenBytes = ByteData(8);
    lenBytes.setUint32(0, (bitLen >> 32) & 0xFFFFFFFF);
    lenBytes.setUint32(4, bitLen & 0xFFFFFFFF);
    padded.add(lenBytes.buffer.asUint8List());

    final msg = padded.toBytes();
    var h0 = 0x6a09e667,
        h1 = 0xbb67ae85,
        h2 = 0x3c6ef372,
        h3 = 0xa54ff53a;
    var h4 = 0x510e527f,
        h5 = 0x9b05688c,
        h6 = 0x1f83d9ab,
        h7 = 0x5be0cd19;

    for (var i = 0; i < msg.length; i += 64) {
      final w = List<int>.filled(64, 0);
      for (var t = 0; t < 16; t++) {
        w[t] = (msg[i + t * 4] << 24) |
            (msg[i + t * 4 + 1] << 16) |
            (msg[i + t * 4 + 2] << 8) |
            msg[i + t * 4 + 3];
      }
      for (var t = 16; t < 64; t++) {
        final s0 =
            _rotr(w[t - 15], 7) ^ _rotr(w[t - 15], 18) ^ ((w[t - 15] & 0xFFFFFFFF) >>> 3);
        final s1 =
            _rotr(w[t - 2], 17) ^ _rotr(w[t - 2], 19) ^ ((w[t - 2] & 0xFFFFFFFF) >>> 10);
        w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & 0xFFFFFFFF;
      }

      var a = h0, b = h1, c = h2, d = h3;
      var e = h4, f = h5, g = h6, h = h7;

      for (var t = 0; t < 64; t++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
        final temp1 = (h + s1 + ch + _k[t] + w[t]) & 0xFFFFFFFF;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xFFFFFFFF;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xFFFFFFFF;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xFFFFFFFF;
      }

      h0 = (h0 + a) & 0xFFFFFFFF;
      h1 = (h1 + b) & 0xFFFFFFFF;
      h2 = (h2 + c) & 0xFFFFFFFF;
      h3 = (h3 + d) & 0xFFFFFFFF;
      h4 = (h4 + e) & 0xFFFFFFFF;
      h5 = (h5 + f) & 0xFFFFFFFF;
      h6 = (h6 + g) & 0xFFFFFFFF;
      h7 = (h7 + h) & 0xFFFFFFFF;
    }

    final out = ByteData(32);
    out.setUint32(0, h0);
    out.setUint32(4, h1);
    out.setUint32(8, h2);
    out.setUint32(12, h3);
    out.setUint32(16, h4);
    out.setUint32(20, h5);
    out.setUint32(24, h6);
    out.setUint32(28, h7);
    return out.buffer.asUint8List();
  }

  static String hashHex(Uint8List data) {
    final digest = hash(data);
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

// =============================================================================
// PBKDF2-HMAC-SHA256
// =============================================================================

class _Pbkdf2 {
  static const int _iterations = 100000;
  static const int _keyLen = 32;

  static Uint8List deriveKey(String password, Uint8List salt) {
    final passBytes = utf8.encode(password);
    return _pbkdf2(Uint8List.fromList(passBytes), salt, _iterations, _keyLen);
  }

  static Uint8List _hmacSha256(Uint8List key, Uint8List message) {
    const blockSize = 64;
    var k = key;
    if (k.length > blockSize) k = _Sha256.hash(k);
    if (k.length < blockSize) {
      final padded = Uint8List(blockSize);
      padded.setRange(0, k.length, k);
      k = padded;
    }
    final iPad = Uint8List(blockSize);
    final oPad = Uint8List(blockSize);
    for (var i = 0; i < blockSize; i++) {
      iPad[i] = k[i] ^ 0x36;
      oPad[i] = k[i] ^ 0x5c;
    }
    final inner = BytesBuilder();
    inner.add(iPad);
    inner.add(message);
    final innerHash = _Sha256.hash(inner.toBytes());
    final outer = BytesBuilder();
    outer.add(oPad);
    outer.add(innerHash);
    return _Sha256.hash(outer.toBytes());
  }

  static Uint8List _pbkdf2(
      Uint8List password, Uint8List salt, int iterations, int keyLen) {
    final numBlocks = (keyLen + 31) ~/ 32;
    final out = BytesBuilder();
    for (var blockIndex = 1; blockIndex <= numBlocks; blockIndex++) {
      final saltBlock = BytesBuilder();
      saltBlock.add(salt);
      saltBlock.add([
        (blockIndex >> 24) & 0xFF,
        (blockIndex >> 16) & 0xFF,
        (blockIndex >> 8) & 0xFF,
        blockIndex & 0xFF,
      ]);
      var u = _hmacSha256(password, saltBlock.toBytes());
      var result = Uint8List.fromList(u);
      for (var i = 1; i < iterations; i++) {
        u = _hmacSha256(password, u);
        for (var j = 0; j < result.length; j++) {
          result[j] ^= u[j];
        }
      }
      out.add(result);
    }
    return Uint8List.fromList(out.toBytes().sublist(0, keyLen));
  }
}

// =============================================================================
// AES-256-CBC — implémentation pure Dart
// =============================================================================

class _AesCbc {
  static Uint8List encrypt(Uint8List plain, Uint8List key, Uint8List iv) {
    final aes = _Aes(key);
    // PKCS7 padding
    final padLen = 16 - (plain.length % 16);
    final padded = Uint8List(plain.length + padLen);
    padded.setRange(0, plain.length, plain);
    for (var i = plain.length; i < padded.length; i++) {
      padded[i] = padLen;
    }
    final out = Uint8List(padded.length);
    var prev = iv;
    for (var i = 0; i < padded.length; i += 16) {
      final block = Uint8List(16);
      for (var j = 0; j < 16; j++) {
        block[j] = padded[i + j] ^ prev[j];
      }
      final encrypted = aes.encryptBlock(block);
      out.setRange(i, i + 16, encrypted);
      prev = encrypted;
    }
    return out;
  }

  static Uint8List decrypt(Uint8List cipher, Uint8List key, Uint8List iv) {
    final aes = _Aes(key);
    final out = Uint8List(cipher.length);
    var prev = iv;
    for (var i = 0; i < cipher.length; i += 16) {
      final block = cipher.sublist(i, i + 16);
      final decrypted = aes.decryptBlock(Uint8List.fromList(block));
      for (var j = 0; j < 16; j++) {
        out[i + j] = decrypted[j] ^ prev[j];
      }
      prev = Uint8List.fromList(block);
    }
    // Remove PKCS7 padding
    final padLen = out.last;
    if (padLen > 0 && padLen <= 16) {
      return out.sublist(0, out.length - padLen);
    }
    return out;
  }
}

// =============================================================================
// AES CORE (Rijndael 256-bit key, single block)
// =============================================================================

class _Aes {
  late final List<List<int>> _encKey;
  late final List<List<int>> _decKey;
  static const int _rounds = 14; // AES-256

  _Aes(Uint8List key) {
    _encKey = _expandKey(key);
    _decKey = _invertKey(_encKey);
  }

  Uint8List encryptBlock(Uint8List input) {
    var state = List<int>.from(input);
    state = _addRoundKey(state, _encKey[0]);
    for (var r = 1; r < _rounds; r++) {
      state = _subBytes(state);
      state = _shiftRows(state);
      state = _mixColumns(state);
      state = _addRoundKey(state, _encKey[r]);
    }
    state = _subBytes(state);
    state = _shiftRows(state);
    state = _addRoundKey(state, _encKey[_rounds]);
    return Uint8List.fromList(state);
  }

  Uint8List decryptBlock(Uint8List input) {
    var state = List<int>.from(input);
    state = _addRoundKey(state, _decKey[_rounds]);
    for (var r = _rounds - 1; r > 0; r--) {
      state = _invShiftRows(state);
      state = _invSubBytes(state);
      state = _addRoundKey(state, _decKey[r]);
      state = _invMixColumns(state);
    }
    state = _invShiftRows(state);
    state = _invSubBytes(state);
    state = _addRoundKey(state, _decKey[0]);
    return Uint8List.fromList(state);
  }

  // --- AES internals ---

  static final List<int> _sBox = _generateSBox();
  static final List<int> _invSBox = _generateInvSBox();

  static List<int> _generateSBox() {
    final s = List<int>.filled(256, 0);
    s[0] = 0x63;
    var p = 1, q = 1;
    do {
      p = p ^ ((p << 1) ^ ((p & 0x80 != 0) ? 0x1B : 0)) & 0xFF;
      q ^= (q << 1) & 0xFF;
      q ^= (q << 2) & 0xFF;
      q ^= (q << 4) & 0xFF;
      q ^= (q & 0x80 != 0) ? 0x09 : 0;
      q &= 0xFF;
      final xformed = q ^
          ((q << 1) | (q >> 7)) & 0xFF ^
          ((q << 2) | (q >> 6)) & 0xFF ^
          ((q << 3) | (q >> 5)) & 0xFF ^
          ((q << 4) | (q >> 4)) & 0xFF;
      s[p] = (xformed ^ 0x63) & 0xFF;
    } while (p != 1);
    return s;
  }

  static List<int> _generateInvSBox() {
    final inv = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      inv[_sBox[i]] = i;
    }
    return inv;
  }

  static List<int> _subBytes(List<int> s) =>
      List<int>.generate(16, (i) => _sBox[s[i]]);

  static List<int> _invSubBytes(List<int> s) =>
      List<int>.generate(16, (i) => _invSBox[s[i]]);

  static List<int> _shiftRows(List<int> s) {
    return [
      s[0], s[5], s[10], s[15],
      s[4], s[9], s[14], s[3],
      s[8], s[13], s[2], s[7],
      s[12], s[1], s[6], s[11],
    ];
  }

  static List<int> _invShiftRows(List<int> s) {
    return [
      s[0], s[13], s[10], s[7],
      s[4], s[1], s[14], s[11],
      s[8], s[5], s[2], s[15],
      s[12], s[9], s[6], s[3],
    ];
  }

  static int _gmul(int a, int b) {
    var p = 0;
    var aa = a, bb = b;
    for (var i = 0; i < 8; i++) {
      if (bb & 1 != 0) p ^= aa;
      final hiBit = aa & 0x80;
      aa = (aa << 1) & 0xFF;
      if (hiBit != 0) aa ^= 0x1B;
      bb >>= 1;
    }
    return p & 0xFF;
  }

  static List<int> _mixColumns(List<int> s) {
    final r = List<int>.filled(16, 0);
    for (var c = 0; c < 4; c++) {
      final i = c * 4;
      r[i] = _gmul(2, s[i]) ^ _gmul(3, s[i + 1]) ^ s[i + 2] ^ s[i + 3];
      r[i + 1] = s[i] ^ _gmul(2, s[i + 1]) ^ _gmul(3, s[i + 2]) ^ s[i + 3];
      r[i + 2] = s[i] ^ s[i + 1] ^ _gmul(2, s[i + 2]) ^ _gmul(3, s[i + 3]);
      r[i + 3] = _gmul(3, s[i]) ^ s[i + 1] ^ s[i + 2] ^ _gmul(2, s[i + 3]);
    }
    return r;
  }

  static List<int> _invMixColumns(List<int> s) {
    final r = List<int>.filled(16, 0);
    for (var c = 0; c < 4; c++) {
      final i = c * 4;
      r[i] = _gmul(14, s[i]) ^
          _gmul(11, s[i + 1]) ^
          _gmul(13, s[i + 2]) ^
          _gmul(9, s[i + 3]);
      r[i + 1] = _gmul(9, s[i]) ^
          _gmul(14, s[i + 1]) ^
          _gmul(11, s[i + 2]) ^
          _gmul(13, s[i + 3]);
      r[i + 2] = _gmul(13, s[i]) ^
          _gmul(9, s[i + 1]) ^
          _gmul(14, s[i + 2]) ^
          _gmul(11, s[i + 3]);
      r[i + 3] = _gmul(11, s[i]) ^
          _gmul(13, s[i + 1]) ^
          _gmul(9, s[i + 2]) ^
          _gmul(14, s[i + 3]);
    }
    return r;
  }

  static List<int> _addRoundKey(List<int> s, List<int> rk) =>
      List<int>.generate(16, (i) => s[i] ^ rk[i]);

  static const List<int> _rcon = [
    0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36
  ];

  static List<List<int>> _expandKey(Uint8List key) {
    final nk = 8; // AES-256
    final nb = 4;
    final nr = 14;
    final w = List<int>.filled(nb * (nr + 1) * 4, 0);
    for (var i = 0; i < nk * 4; i++) {
      w[i] = key[i];
    }
    for (var i = nk; i < nb * (nr + 1); i++) {
      var temp = w.sublist((i - 1) * 4, i * 4);
      if (i % nk == 0) {
        temp = [
          _sBox[temp[1]] ^ _rcon[(i ~/ nk) - 1],
          _sBox[temp[2]],
          _sBox[temp[3]],
          _sBox[temp[0]],
        ];
      } else if (i % nk == 4) {
        temp = [_sBox[temp[0]], _sBox[temp[1]], _sBox[temp[2]], _sBox[temp[3]]];
      }
      for (var j = 0; j < 4; j++) {
        w[i * 4 + j] = w[(i - nk) * 4 + j] ^ temp[j];
      }
    }
    final roundKeys = <List<int>>[];
    for (var r = 0; r <= nr; r++) {
      roundKeys.add(w.sublist(r * 16, r * 16 + 16));
    }
    return roundKeys;
  }

  static List<List<int>> _invertKey(List<List<int>> ek) =>
      List<List<int>>.from(ek);
}
