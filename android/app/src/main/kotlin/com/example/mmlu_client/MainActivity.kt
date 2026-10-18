package com.example.mmlu_client

import android.os.Bundle
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        copyFfmpegToFiles()
    }

    private fun copyFfmpegToFiles() {
        try {
            val dest = File(filesDir, "ffmpeg")
            if (dest.exists() && dest.canExecute()) return
            assets.open("arm64-v8a/ffmpeg").use { input ->
                FileOutputStream(dest).use { output ->
                    input.copyTo(output)
                }
            }
            dest.setExecutable(true)
        } catch (e: IOException) {
            // ignore
        }
    }
}
