import 'dart:math';
import 'dart:typed_data';

/// X25519 + BLAKE2s + Noise_IKpsk2 handshake initiation.
///
/// Pure Dart port of the WireGuard parts of PingNG's WarpScoutEndpointScanner
/// (rezakhosh78/PingNG, MIT). No dependency on the `cryptography` package so
/// scanning thousands of UDP endpoints does not pay the async machinery cost.
class WireGuardCrypto {
  WireGuardCrypto._();

  // ── X25519 (Montgomery ladder over 2^255 - 19) ─────────────
  static final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
  static final BigInt _a24 = BigInt.from(121665);
  static final BigInt _base = BigInt.one << 9;

  /// X25519 scalar multiplication — port of WarpAccountGenerator.scalarMult.
  /// scalar و uBytes باید ۳۲ بایت باشن (Little Endian).
  static Uint8List scalarMult(Uint8List scalar, Uint8List uBytes) {
    final k = Uint8List.fromList(scalar);
    k[0] &= 248;
    k[31] &= 127;
    k[31] |= 64;

    final x1 = _fromLittleEndian(uBytes);
    var x2 = BigInt.one;
    var z2 = BigInt.zero;
    var x3 = x1;
    var z3 = BigInt.one;
    var swap = 0;

    for (var t = 254; t >= 0; t--) {
      final kt = (k[t >> 3] >> (t & 7)) & 1;
      swap ^= kt;
      if (swap == 1) {
        final tx = x2; x2 = x3; x3 = tx;
        final tz = z2; z2 = z3; z3 = tz;
      }
      swap = kt;

      final a = _mod(x2 + z2);
      final aa = _mod(a * a);
      final b = _mod(x2 - z2);
      final bb = _mod(b * b);
      final e = _mod(aa - bb);
      final c = _mod(x3 + z3);
      final d = _mod(x3 - z3);
      final da = _mod(d * a);
      final cb = _mod(c * b);
      x3 = _mod((da + cb) * (da + cb));
      z3 = _mod(x1 * (da - cb) * (da - cb));
      x2 = _mod(aa * bb);
      z2 = _mod(e * (aa + _a24 * e));
    }
    if (swap == 1) {
      final tx = x2; x2 = x3; x3 = tx;
      final tz = z2; z2 = z3; z3 = tz;
    }
    // z2^-1 mod p — Fermat: a^(p-2) mod p
    final inv = z2.modPow(_p - BigInt.two, _p);
    return _toLittleEndian(_mod(x2 * inv));
  }

  static BigInt _mod(BigInt v) {
    final r = v % _p;
    return r.isNegative ? r + _p : r;
  }

  static BigInt _fromLittleEndian(Uint8List bytes) {
    final rev = Uint8List.fromList(bytes.reversed.toList());
    return BigInt.parse(rev.map((b) => b.toRadixString(16).padLeft(2, '0')).join(), radix: 16);
  }

  static Uint8List _toLittleEndian(BigInt value) {
    final bytes = value.toRadixString(16).padLeft(64, '0');
    final result = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      final idx = (31 - i) * 2;
      result[i] = int.parse(bytes.substring(idx, idx + 2), radix: 16);
    }
    return result;
  }

  static Uint8List basePoint() {
    final b = Uint8List(32);
    b[0] = 9;
    return b;
  }

  // ── BLAKE2s ────────────────────────────────────────────────
  static const List<int> _iv = [
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
  ];

  static const List<List<int>> _sigma = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
    [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
    [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
    [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
    [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
    [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
    [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
    [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
  ];

  /// BLAKE2s hash — بیت‌آوت ۳۲ بایت.
  static Uint8List blake2s(Uint8List input) => _blake2sDigest(input, null);

  /// BLAKE2s keyed hash — برای mac1.
  static Uint8List blake2sKeyed(Uint8List key, Uint8List input) =>
      _blake2sDigest(input, key);

  /// BLAKE2s HMAC — برای HKDF.
  static Uint8List blake2sHmac(Uint8List key, Uint8List input) {
    final block = Uint8List(64);
    final kLen = min(key.length, 64);
    block.setRange(0, kLen, key);
    final inner = Uint8List(64);
    final outer = Uint8List(64);
    for (var i = 0; i < 64; i++) {
      inner[i] = block[i] ^ 0x36;
      outer[i] = block[i] ^ 0x5c;
    }
    final innerHash = blake2s(Uint8List.fromList([...inner, ...input]));
    return blake2s(Uint8List.fromList([...outer, ...innerHash]));
  }

  static Uint8List _blake2sDigest(Uint8List input, Uint8List? key) {
    final h = List<int>.from(_iv);
    h[0] ^= 0x01010020 ^ ((key?.length ?? 0) << 8);

    final data = key != null
        ? Uint8List.fromList([...Uint8List(64)..setRange(0, min(key.length, 64), key), ...input])
        : input;

    var offset = 0;
    var counter = 0;
    while (offset < data.length || offset == 0) {
      final remaining = data.length - offset;
      final length = min(64, max(remaining, 0));
      final block = Uint8List(64);
      if (length > 0) block.setRange(0, length, data, offset);
      offset += length;
      counter += length;
      final isLast = offset >= data.length;
      _compress(h, block, counter, isLast);
      if (isLast) break;
    }

    final out = Uint8List(32);
    for (var i = 0; i < 8; i++) {
      out[i * 4] = h[i] & 0xff;
      out[i * 4 + 1] = (h[i] >> 8) & 0xff;
      out[i * 4 + 2] = (h[i] >> 16) & 0xff;
      out[i * 4 + 3] = (h[i] >> 24) & 0xff;
    }
    return out;
  }

  static void _compress(List<int> h, Uint8List block, int counter, bool last) {
    final v = List<int>.filled(16, 0);
    for (var i = 0; i < 8; i++) v[i] = h[i];
    for (var i = 0; i < 8; i++) v[8 + i] = _iv[i];
    v[12] ^= counter & 0xffffffff;
    v[13] ^= (counter >> 32) & 0xffffffff;
    if (last) v[14] = ~v[14] & 0xffffffff;

    final m = List<int>.filled(16, 0);
    for (var i = 0; i < 16; i++) {
      m[i] = block[i * 4] |
          (block[i * 4 + 1] << 8) |
          (block[i * 4 + 2] << 16) |
          (block[i * 4 + 3] << 24);
    }

    for (var round = 0; round < 10; round++) {
      final s = _sigma[round];
      _g(v, 0, 4, 8, 12, m[s[0]], m[s[1]]);
      _g(v, 1, 5, 9, 13, m[s[2]], m[s[3]]);
      _g(v, 2, 6, 10, 14, m[s[4]], m[s[5]]);
      _g(v, 3, 7, 11, 15, m[s[6]], m[s[7]]);
      _g(v, 0, 5, 10, 15, m[s[8]], m[s[9]]);
      _g(v, 1, 6, 11, 12, m[s[10]], m[s[11]]);
      _g(v, 2, 7, 8, 13, m[s[12]], m[s[13]]);
      _g(v, 3, 4, 9, 14, m[s[14]], m[s[15]]);
    }

    for (var i = 0; i < 8; i++) h[i] ^= v[i] ^ v[i + 8];
  }

  static void _g(List<int> v, int a, int b, int c, int d, int x, int y) {
    v[a] = (v[a] + v[b] + x) & 0xffffffff;
    v[d] = _rotr(v[d] ^ v[a], 16);
    v[c] = (v[c] + v[d]) & 0xffffffff;
    v[b] = _rotr(v[b] ^ v[c], 12);
    v[a] = (v[a] + v[b] + y) & 0xffffffff;
    v[d] = _rotr(v[d] ^ v[a], 8);
    v[c] = (v[c] + v[d]) & 0xffffffff;
    v[b] = _rotr(v[b] ^ v[c], 7);
  }

  static int _rotr(int x, int n) {
    x = x & 0xffffffff;
    return ((x >> n) | ((x << (32 - n)) & 0xffffffff)) & 0xffffffff;
  }

  // ── ChaCha20-Poly1305 seal (RFC 8439) ──────────────────────
  /// AEAD seal: یک Nonce صفر ۱۲ بایتی. خروجی = ciphertext || tag(16).
  /// ادغام ChaCha20 stream + Poly1305 MAC. (پیاده‌سازی ساده از RFC 8439.)
  static Uint8List chacha20Poly1305Seal(
    Uint8List key,
    Uint8List plain,
    Uint8List aad,
  ) {
    final nonce = Uint8List(12);
    final cipher = _chacha20Block(key, nonce, 0);
    // تولید 64 بایت اول (counter = 0) برای Poly1305 key
    final polyKey = cipher.sublist(0, 32);

    // رمزنگاری plain با counter = 1
    final encrypted = _chacha20Crypt(key, nonce, plain, 1);

    // Poly1305 tag
    final macData = Uint8List.fromList([
      ..._pad16(aad),
      ...aad,
      ..._pad16(encrypted),
      ...encrypted,
      ..._leUint64(aad.length),
      ..._leUint64(encrypted.length),
    ]);
    final tag = _poly1305(polyKey, macData);

    return Uint8List.fromList([...encrypted, ...tag]);
  }

  static Uint8List _chacha20Block(Uint8List key, Uint8List nonce, int counter) {
    final state = List<int>.filled(16, 0);
    state[0] = 0x61707865;
    state[1] = 0x3320646e;
    state[2] = 0x79622d32;
    state[3] = 0x6b206574;
    for (var i = 0; i < 8; i++) {
      state[4 + i] = key[i * 4] |
          (key[i * 4 + 1] << 8) |
          (key[i * 4 + 2] << 16) |
          (key[i * 4 + 3] << 24);
    }
    state[12] = counter;
    state[13] = nonce[0] | (nonce[1] << 8) | (nonce[2] << 16) | (nonce[3] << 24);
    state[14] = nonce[4] | (nonce[5] << 8) | (nonce[6] << 16) | (nonce[7] << 24);
    state[15] = nonce[8] | (nonce[9] << 8) | (nonce[10] << 16) | (nonce[11] << 24);

    final w = List<int>.from(state);
    for (var i = 0; i < 10; i++) {
      _qr(w, 0, 4, 8, 12);
      _qr(w, 1, 5, 9, 13);
      _qr(w, 2, 6, 10, 14);
      _qr(w, 3, 7, 11, 15);
      _qr(w, 0, 5, 10, 15);
      _qr(w, 1, 6, 11, 12);
      _qr(w, 2, 7, 8, 13);
      _qr(w, 3, 4, 9, 14);
    }
    final out = Uint8List(64);
    for (var i = 0; i < 16; i++) {
      final v = (w[i] + state[i]) & 0xffffffff;
      out[i * 4] = v & 0xff;
      out[i * 4 + 1] = (v >> 8) & 0xff;
      out[i * 4 + 2] = (v >> 16) & 0xff;
      out[i * 4 + 3] = (v >> 24) & 0xff;
    }
    return out;
  }

  static Uint8List _chacha20Crypt(
    Uint8List key,
    Uint8List nonce,
    Uint8List input,
    int initialCounter,
  ) {
    final out = Uint8List(input.length);
    var counter = initialCounter;
    for (var offset = 0; offset < input.length; offset += 64) {
      final block = _chacha20Block(key, nonce, counter++);
      final len = min(64, input.length - offset);
      for (var i = 0; i < len; i++) {
        out[offset + i] = input[offset + i] ^ block[i];
      }
    }
    return out;
  }

  static void _qr(List<int> s, int a, int b, int c, int d) {
    s[a] = (s[a] + s[b]) & 0xffffffff;
    s[d] = _rotl(s[d] ^ s[a], 16);
    s[c] = (s[c] + s[d]) & 0xffffffff;
    s[b] = _rotl(s[b] ^ s[c], 12);
    s[a] = (s[a] + s[b]) & 0xffffffff;
    s[d] = _rotl(s[d] ^ s[a], 8);
    s[c] = (s[c] + s[d]) & 0xffffffff;
    s[b] = _rotl(s[b] ^ s[c], 7);
  }

  static int _rotl(int x, int n) {
    x = x & 0xffffffff;
    return ((x << n) | (x >> (32 - n))) & 0xffffffff;
  }

  static Uint8List _poly1305(Uint8List key, Uint8List msg) {
    final r = _leToBigInt(key.sublist(0, 16)) & BigInt.parse('0ffffffc0ffffffc0ffffffc0fffffff', radix: 16);
    final s = _leToBigInt(key.sublist(16, 32));
    final prime = (BigInt.one << 130) - BigInt.from(5);
    var acc = BigInt.zero;

    for (var i = 0; i < msg.length; i += 16) {
      final len = min(16, msg.length - i);
      final block = Uint8List(17);
      block.setRange(0, len, msg, i);
      block[len] = 0x01;
      acc = ((acc + _leToBigInt(block)) * r) % prime;
    }
    acc = (acc + s) % (BigInt.one << 128);
    return _bigIntToLe(acc, 16);
  }

  static BigInt _leToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (var i = bytes.length - 1; i >= 0; i--) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  static Uint8List _bigIntToLe(BigInt value, int length) {
    final out = Uint8List(length);
    var v = value;
    for (var i = 0; i < length; i++) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v = v >> 8;
    }
    return out;
  }

  static Uint8List _pad16(Uint8List data) {
    final pad = (16 - (data.length % 16)) % 16;
    return Uint8List(pad);
  }

  static Uint8List _leUint64(int value) {
    final out = Uint8List(8);
    for (var i = 0; i < 8; i++) {
      out[i] = (value >> (8 * i)) & 0xff;
    }
    return out;
  }

  // ── WireGuard handshake initiation ─────────────────────────
  static final Uint8List _construction =
      Uint8List.fromList('Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s'.codeUnits);
  static final Uint8List _identifier =
      Uint8List.fromList('WireGuard v1 zx2c4 Jason@zx2c4.com'.codeUnits);
  static final Uint8List _labelMac1 =
      Uint8List.fromList('mac1----'.codeUnits);

  static final Random _random = Random.secure();

  /// مقادیر پیش‌محاسبه — یک بار برای هر scan ساخته می‌شوند.
  static PreparedHandshake? prepare({
    required Uint8List privateKey,
    required Uint8List peerPublicKey,
  }) {
    if (privateKey.length != 32 || peerPublicKey.length != 32) return null;
    final staticPub = scalarMult(privateKey, basePoint());
    final staticShared = scalarMult(privateKey, peerPublicKey);
    final macKey = blake2s(Uint8List.fromList([..._labelMac1, ...peerPublicKey]));
    return PreparedHandshake(
      peerPublicKey: peerPublicKey,
      staticPublicKey: staticPub,
      staticSharedKey: staticShared,
      macKey: macKey,
    );
  }

  /// ساخت یک initiation packet (۱۴۸ بایت) برای هر probe.
  static Initiation? createInitiation(PreparedHandshake prepared) {
    final ephPriv = Uint8List(32);
    for (var i = 0; i < 32; i++) ephPriv[i] = _random.nextInt(256);
    final ephPub = scalarMult(ephPriv, basePoint());

    var hash = blake2s(_construction).sublist(0, 32);
    var chainKey = Uint8List.fromList(hash);
    hash = blake2s(Uint8List.fromList([...hash, ..._identifier]));
    hash = blake2s(Uint8List.fromList([...hash, ...prepared.peerPublicKey]));
    hash = blake2s(Uint8List.fromList([...hash, ...ephPub]));
    chainKey = _kdf1(chainKey, ephPub);

    final firstDh = scalarMult(ephPriv, prepared.peerPublicKey);
    final firstKdf = _kdf2(chainKey, firstDh);
    chainKey = firstKdf[0];
    final staticCipher = chacha20Poly1305Seal(
      firstKdf[1],
      prepared.staticPublicKey,
      hash,
    );
    hash = blake2s(Uint8List.fromList([...hash, ...staticCipher]));

    final secondKdf = _kdf2(chainKey, prepared.staticSharedKey);
    final timestamp = _tai64n();
    final timestampCipher = chacha20Poly1305Seal(
      secondKdf[1],
      timestamp,
      hash,
    );

    final message = Uint8List(116);
    final bd = ByteData.sublistView(message);
    bd.setUint32(0, 1, Endian.little); // type
    final senderIndex = _random.nextInt(0x7fffffff);
    bd.setUint32(4, senderIndex, Endian.little);
    message.setRange(8, 40, ephPub);
    message.setRange(40, 88, staticCipher);
    message.setRange(88, 116, timestampCipher);

    final mac1Full = blake2sKeyed(prepared.macKey, message);
    final packet = Uint8List(148);
    packet.setRange(0, 116, message);
    packet.setRange(116, 132, mac1Full.sublist(0, 16));
    // mac2 = 0
    return Initiation(packet: packet, senderIndex: senderIndex);
  }

  static Uint8List _kdf1(Uint8List chainKey, Uint8List input) {
    final tmp = blake2sHmac(chainKey, input);
    return blake2sHmac(tmp, Uint8List.fromList([1]));
  }

  static List<Uint8List> _kdf2(Uint8List chainKey, Uint8List input) {
    final tmp = blake2sHmac(chainKey, input);
    final first = blake2sHmac(tmp, Uint8List.fromList([1]));
    final second = blake2sHmac(tmp, Uint8List.fromList([2]));
    return [first, second];
  }

  static Uint8List _tai64n() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final seconds = (now ~/ 1000) + 0x4000000000000000;
    final nanos = (now % 1000) * 1000000;
    final out = Uint8List(12);
    final bd = ByteData.sublistView(out);
    bd.setUint64(0, seconds, Endian.big);
    bd.setUint32(8, nanos, Endian.big);
    return out;
  }
}

class PreparedHandshake {
  final Uint8List peerPublicKey;
  final Uint8List staticPublicKey;
  final Uint8List staticSharedKey;
  final Uint8List macKey;
  const PreparedHandshake({
    required this.peerPublicKey,
    required this.staticPublicKey,
    required this.staticSharedKey,
    required this.macKey,
  });
}

class Initiation {
  final Uint8List packet;
  final int senderIndex;
  const Initiation({required this.packet, required this.senderIndex});
}
