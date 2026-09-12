/// WORKFLOW OF THIS FILE:
/// 1. Bridges to the native Android SHA-256 implementation (MethodChannel).
/// 2. Native hashing uses the device's hardware-accelerated crypto and is
///    many times faster than pure Dart hashing, so transfers stay link-bound
///    and the final "Checking file..." step finishes in about a second per GB.
/// 3. Every method falls back to the pure Dart crypto package when the native
///    channel is unavailable, so verification never silently disappears.
///
/// FUNCTIONS:
///  - hashFile()  : SHA-256 hex of a whole file on disk.
///  - hashBytes() : SHA-256 hex of an in-memory byte buffer.
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class NativeSha256 {
  static const _channel = MethodChannel('com.flova.flova_mobile/hash');

  static Future<String> hashFile(String path) async {
    try {
      final hex = await _channel.invokeMethod<String>('hashFile', {'path': path});
      if (hex != null && hex.isNotEmpty) return hex;
    } catch (_) {
      // native unavailable: fall through to dart
    }
    final ds = _DigestSink();
    final input = sha256.startChunkedConversion(ds);
    await for (final chunk in File(path).openRead()) {
      input.add(chunk);
    }
    input.close();
    return ds.digest!.toString();
  }

  static Future<String> hashBytes(Uint8List bytes) async {
    try {
      final hex = await _channel.invokeMethod<String>('hashBytes', {'bytes': bytes});
      if (hex != null && hex.isNotEmpty) return hex;
    } catch (_) {
      // native unavailable: fall through to dart
    }
    return sha256.convert(bytes).toString();
  }
}

// collects the final digest from a chunked sha256 conversion (dart fallback)
class _DigestSink implements Sink<Digest> {
  Digest? digest;
  @override
  void add(Digest d) => digest = d;
  @override
  void close() {}
}