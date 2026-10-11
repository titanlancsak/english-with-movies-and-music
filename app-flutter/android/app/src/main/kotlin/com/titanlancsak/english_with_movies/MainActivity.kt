package com.titanlancsak.english_with_movies

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // ffmpeg and whisper-cli ship as lib*.so files; Android extracts them to this
        // folder, the only place an app may run its own programs from.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "english_with_movies/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                else -> result.notImplemented()
            }
        }
    }
}
