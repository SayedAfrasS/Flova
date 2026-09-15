/// WORKFLOW OF THIS FILE:
/// 1. Bridges to the Android native SHA-256 (MessageDigest) via MethodChannel.
/// 2. hashFile streams the file on a native background thread (fast + safe).
/// 3. hashBytes hashes an in-memory chunk (used for per-segment checks).
/// 4. If the native call errors or returns empty, falls back to a pure-Dart
///    chunked SHA-256 so verification never silently breaks.
/// 5. All results are lowercased so comparisons are case-insensitive.
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class NativeSha256 {
  static const MethodChannel _channel =
      MethodChannel('com.flova.flova_mobile/native_sha256');

  static Future<String> hashFile(String path) async {
    try {
      final result = await _channel.invokeMethod<String>('hashFile', {'path': path});
      if (result != null && result.isNotEmpty) return result.toLowerCase();
    } catch (_) {}
    return _dartHashFile(path);
  }

  static Future<String> hashBytes(Uint8List bytes) async {
    try {
      final result = await _channel.invokeMethod<String>('hashBytes', {'bytes': bytes});
      if (result != null && result.isNotEmpty) return result.toLowerCase();
    } catch (_) {}
    return sha256.convert(bytes).toString().toLowerCase();
  }

  static Future<String> _dartHashFile(String path) async {
    final file = File(path);
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    try {
      await for (final chunk in file.openRead()) {
        input.add(chunk);
      }
    } finally {
      input.close();
    }
    return sink.digest.toString().toLowerCase();
  }
}

/// Collects the single Digest emitted by a chunked SHA-256 conversion.
class _DigestSink implements Sink<Digest> {
  Digest? _digest;
  Digest get digest => _digest!;
  @override
  void add(Digest data) => _digest = data;
  @override
  void close() {}
}