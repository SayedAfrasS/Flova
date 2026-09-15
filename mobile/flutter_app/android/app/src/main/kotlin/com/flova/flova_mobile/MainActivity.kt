package com.flova.flova_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import kotlin.concurrent.thread

// WORKFLOW OF THIS FILE:
// 1. Registers a MethodChannel named "com.flova.flova_mobile/native_sha256".
// 2. "hashFile" streams a file in 8 MB chunks through SHA-256 on a background
//    thread and returns the lowercase hex digest (never blocks the UI thread).
// 3. "hashBytes" hashes an in-memory byte array the same way.
// 4. Both return lowercase hex so the Dart side can compare case-insensitively.
class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.flova.flova_mobile/native_sha256"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hashFile" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("BAD_ARGS", "path is required", null)
                        } else {
                            thread {
                                try {
                                    result.success(hashFile(path))
                                } catch (e: Exception) {
                                    result.error("HASH_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    "hashBytes" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.error("BAD_ARGS", "bytes is required", null)
                        } else {
                            thread {
                                try {
                                    val md = MessageDigest.getInstance("SHA-256")
                                    md.update(bytes)
                                    result.success(md.digest().joinToString("") { "%02x".format(it) })
                                } catch (e: Exception) {
                                    result.error("HASH_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hashFile(path: String): String {
        val md = MessageDigest.getInstance("SHA-256")
        File(path).inputStream().use { ins ->
            val buf = ByteArray(8 * 1024 * 1024)
            while (true) {
                val n = ins.read(buf)
                if (n <= 0) break
                md.update(buf, 0, n)
            }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }
}