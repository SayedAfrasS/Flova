/// WORKFLOW OF THIS FILE:
/// 1. SessionCrypto manages one secure session between the phone and laptop.
/// 2. generatePublicKey() creates an X25519 keypair using the cryptography
///    package and returns the public key bytes to exchange in hello/hello-ack.
/// 3. deriveKey() performs X25519 Diffie-Hellman to compute a shared 32-byte
///    secret that is identical on both devices.
/// 4. encrypt() uses ChaCha20-Poly1305 to produce a 12-byte nonce plus
///    ciphertext concatenated with a 16-byte auth tag.
/// 5. decrypt() reverses the process and throws when the auth tag fails,
///    which means the frame was tampered with or the session key is wrong.
/// 6. fingerprint returns the first 4 bytes of the shared secret as an
///    8-character uppercase hex string shown on both home screens.
///
/// FUNCTIONS:
///  - generatePublicKey(): creates X25519 keypair, returns public key bytes.
///  - deriveKey()        : DH with peer public key, stores the shared secret.
///  - hasKey             : true once deriveKey has run successfully.
///  - encrypt()          : ChaCha20-Poly1305 AEAD encrypt returning {nonce,cipher}.
///  - decrypt()          : ChaCha20-Poly1305 AEAD decrypt with auth verification.
///  - fingerprint        : 8-char hex fingerprint of the shared secret.
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

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

  String get fingerprint {
    final s = _sharedSecret;
    if (s == null || s.length < 4) return '----';
    return s[0].toRadixString(16).padLeft(2, '0').toUpperCase() +
        s[1].toRadixString(16).padLeft(2, '0').toUpperCase() +
        s[2].toRadixString(16).padLeft(2, '0').toUpperCase() +
        s[3].toRadixString(16).padLeft(2, '0').toUpperCase();
  }
}