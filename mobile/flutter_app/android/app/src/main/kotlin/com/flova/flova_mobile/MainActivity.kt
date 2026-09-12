package com.flova.flova_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * WORKFLOW OF THIS FILE:
 * 1. Standard Flutter activity for the app.
 * 2. Registers a MethodChannel named "com.flova.flova_mobile/hash".
 * 3. "hashFile": streams a file from disk through the native SHA-256
 *    MessageDigest (hardware accelerated) and returns the hex string.
 * 4. "hashBytes": hashes an in-memory byte array the same way.
 * 5. Both run on background threads so the UI thread never blocks.
 *    The Dart side falls back to pure Dart hashing when this channel
 *    is unavailable (other platforms), so integrity never disappears.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.flova.flova_mobile/hash"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hashFile" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "path missing", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                result.success(hexOf(digestFile(File(path))))
                            } catch (e: Exception) {
                                result.error("hash_failed", e.message, null)
                            }
                        }.start()
                    }
                    "hashBytes" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.error("bad_args", "bytes missing", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val md = MessageDigest.getInstance("SHA-256")
                                md.update(bytes)
                                result.success(hexOf(md.digest()))
                            } catch (e: Exception) {
                                result.error("hash_failed", e.message, null)
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // streaming digest so big files never load fully into memory
    private fun digestFile(file: File): ByteArray {
        val md = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { ins ->
            val buf = ByteArray(1 shl 20)
            while (true) {
                val n = ins.read(buf)
                if (n <= 0) break
                md.update(buf, 0, n)
            }
        }
        return md.digest()
    }

    private fun hexOf(bytes: ByteArray): String {
        val sb = StringBuilder(bytes.size * 2)
        for (b in bytes) sb.append(String.format("%02x", b))
        return sb.toString()
    }
}