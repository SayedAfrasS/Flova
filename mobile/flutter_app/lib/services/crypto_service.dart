/// WORKFLOW OF THIS FILE:
/// 1. SessionCrypto manages one secure session between the phone and laptop.
/// 2. generatePublicKey() creates an X25519 keypair using the cryptography
///    package and returns the public key bytes to exchange in hello/hello-ack.
/// 3. deriveKey() performs X25519 Diffie-Hellman to compute a shared 32-byte
///    secret that is identical on both devices.
/// 4. encrypt() uses ChaCha20-Poly1305 and returns base64 strings (for JSON).
/// 5. encryptRaw() uses ChaCha20-Poly1305 and returns raw bytes (for binary).
/// 6. decrypt() accepts base64 strings and returns plaintext bytes.
/// 7. decryptRaw() accepts raw bytes and returns plaintext bytes.
/// 8. fingerprint returns the first 4 bytes of the shared secret as an
///    8-character uppercase hex string shown on both home screens.
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class EncryptedData {
  final Uint8List nonce;
  final Uint8List ciphertext;
  EncryptedData(this.nonce, this.ciphertext);
}

class SessionCrypto {
  final X25519 _x25519 = X25519();
  SimpleKeyPair? _keyPair;
  SecretKey? _sessionKey;
  Uint8List? _publicKey;
  Uint8List? _sharedSecret;

  Future<Uint8List> generatePublicKey() async {
    _keyPair = await _x25519.newKeyPair();
    final pub = await _keyPair!.extractPublicKey();
    _publicKey = Uint8List.fromList(pub.bytes);
    return _publicKey!;
  }

  Uint8List? get publicKey => _publicKey;

  Future<void> deriveKey(Uint8List peerPublicKey) async {
    if (_keyPair == null) {
      throw Exception('keypair not generated');
    }
    final peer = SimplePublicKey(peerPublicKey.toList(), type: KeyPairType.x25519);
    final shared = await _x25519.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey: peer,
    );
    final bytes = await shared.extractBytes();
    _sharedSecret = Uint8List.fromList(bytes);
    _sessionKey = SecretKey(bytes);
  }

  bool get hasKey => _sessionKey != null;

  // For JSON frames: return base64 strings
  Future<Map<String, String>> encrypt(Uint8List plaintext) async {
    if (_sessionKey == null) throw Exception('session key not derived');
    final algo = Chacha20.poly1305Aead();
    final box = await algo.encrypt(plaintext, secretKey: _sessionKey!);
    final cipherWithMac = Uint8List(box.cipherText.length + box.mac.bytes.length);
    cipherWithMac.setRange(0, box.cipherText.length, box.cipherText);
    cipherWithMac.setRange(box.cipherText.length, cipherWithMac.length, box.mac.bytes);
    return {
      'nonce': base64Encode(box.nonce),
      'cipher': base64Encode(cipherWithMac),
    };
  }

  // For binary frames: return raw bytes
  Future<EncryptedData> encryptRaw(Uint8List plaintext) async {
    if (_sessionKey == null) throw Exception('session key not derived');
    final algo = Chacha20.poly1305Aead();
    final box = await algo.encrypt(plaintext, secretKey: _sessionKey!);
    final cipherWithMac = Uint8List(box.cipherText.length + box.mac.bytes.length);
    cipherWithMac.setRange(0, box.cipherText.length, box.cipherText);
    cipherWithMac.setRange(box.cipherText.length, cipherWithMac.length, box.mac.bytes);
    return EncryptedData(Uint8List.fromList(box.nonce), cipherWithMac);
  }

  // For JSON frames: accept base64 strings
  Future<Uint8List> decrypt(String nonceB64, String cipherB64) async {
    if (_sessionKey == null) throw Exception('session key not derived');
    final algo = Chacha20.poly1305Aead();
    final nonce = base64Decode(nonceB64);
    final cipherWithMac = base64Decode(cipherB64);
    const macLength = 16;
    if (cipherWithMac.length < macLength) {
      throw Exception('ciphertext too short');
    }
    final cipherText = cipherWithMac.sublist(0, cipherWithMac.length - macLength);
    final macBytes = cipherWithMac.sublist(cipherWithMac.length - macLength);
    final box = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
    final plaintext = await algo.decrypt(box, secretKey: _sessionKey!);
    return Uint8List.fromList(plaintext);
  }

  // For binary frames: accept raw bytes
  Future<Uint8List> decryptRaw(Uint8List nonce, Uint8List cipherWithMac) async {
    if (_sessionKey == null) throw Exception('session key not derived');
    final algo = Chacha20.poly1305Aead();
    const macLength = 16;
    if (cipherWithMac.length < macLength) {
      throw Exception('ciphertext too short');
    }
    final cipherText = cipherWithMac.sublist(0, cipherWithMac.length - macLength);
    final macBytes = cipherWithMac.sublist(cipherWithMac.length - macLength);
    final box = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
    final plaintext = await algo.decrypt(box, secretKey: _sessionKey!);
    return Uint8List.fromList(plaintext);
  }

  String get fingerprint {
    final s = _sharedSecret;
    if (s == null || s.length < 4) return '----';
    return s[0].toRadixString(16).padLeft(2, '0').toUpperCase() +
        s[1].toRadixString(16).padLeft(2, '0').toUpperCase() +
        s[2].toRadixString(16).padLeft(2, '0').toUpperCase() +
        s[3].toRadixString(16).padLeft(2, '0').toUpperCase();
  }
}