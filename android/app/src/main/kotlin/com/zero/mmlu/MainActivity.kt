package com.zero.mmlu

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * 原生桥：运行时权限 / 公共目录 / 媒体扫描(入相册) / 下载完成通知。
 * 只用平台原生 API，不依赖 androidx.core 或任何 Flutter 插件，规避 AGP 9 / R8 兼容问题。
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val sp = getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
            val enabled = if (sp.contains("flutter.privacy_block_shot")) sp.getBoolean("flutter.privacy_block_shot", true) else sp.getBoolean("privacy_block_shot", true)
            if (enabled) {
                window.setFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE, android.view.WindowManager.LayoutParams.FLAG_SECURE)
            }
        } catch (_: Exception) {}
    }

    fun applySecure(enabled: Boolean) {
        runOnUiThread {
            if (enabled) {
                window.setFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE, android.view.WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
            }
        }
    }

    companion object {
        private const val CHANNEL = "mmlu/native"
        private const val CHANNEL_ID = "mmlu_downloads"
        private const val PERM_REQ = 0x4D4C // "ML"
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        copyFfmpegToFiles()
        createNotificationChannel()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "ensurePermissions" -> ensurePermissions(
                    requestManage = call.argument<Boolean>("requestManage") ?: true,
                    result = result,
                )
                "isStorageReady" -> result.success(isStorageReady())
                "publicDir" -> {
                    val type = call.argument<String>("type") ?: "Download"
                    val rel = call.argument<String>("relative") ?: "mmlu"
                    result.success(publicDir(type, rel)?.absolutePath)
                }
                "scanMedia" -> {
                    call.argument<String>("path")?.let { scanMedia(it) }
                    result.success(true)
                }
                "notify" -> {
                    notify(
                        id = call.argument<Int>("id")
                            ?: (System.currentTimeMillis() % 100000).toInt(),
                        title = call.argument<String>("title") ?: "下载完成",
                        body = call.argument<String>("body") ?: "",
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("native_error", e.message, null)
        }
    }

    // ---- 权限 ---------------------------------------------------------------

    private fun runtimePermissions(): List<String> {
        val perms = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) { // 33+
            perms += Manifest.permission.POST_NOTIFICATIONS
            perms += Manifest.permission.READ_MEDIA_IMAGES
            perms += Manifest.permission.READ_MEDIA_VIDEO
        } else {
            if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.Q) { // <= 29
                perms += Manifest.permission.WRITE_EXTERNAL_STORAGE
            }
            perms += Manifest.permission.READ_EXTERNAL_STORAGE
        }
        return perms
    }

    private fun isStorageReady(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) { // 30+
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    private fun ensurePermissions(requestManage: Boolean, result: MethodChannel.Result) {
        val missing = runtimePermissions().filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            pendingPermissionResult = result
            requestPermissions(missing.toTypedArray(), PERM_REQ)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !Environment.isExternalStorageManager()) {
            if (requestManage) {
                try {
                    startActivity(
                        Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                            .setData(Uri.parse("package:$packageName"))
                    )
                } catch (e: Exception) {
                    try {
                        startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                    } catch (_: Exception) {
                    }
                }
            }
            result.success(mapOf("storage" to false, "managePrompted" to requestManage))
            return
        }
        result.success(mapOf("storage" to true, "managePrompted" to false))
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERM_REQ) {
            val r = pendingPermissionResult
            pendingPermissionResult = null
            val ok = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            r?.success(ok)
        }
    }

    // ---- 目录 / 媒体 / 通知 --------------------------------------------------

    private fun publicDir(type: String, relative: String): File? {
        return try {
            val base = Environment.getExternalStoragePublicDirectory(type)
            val dir = File(base, relative)
            if (!dir.exists()) dir.mkdirs()
            dir
        } catch (e: Exception) {
            null
        }
    }

    private fun scanMedia(path: String) {
        try {
            MediaScannerConnection.scanFile(applicationContext, arrayOf(path), null, null)
        } catch (_: Exception) {
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                "下载",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply { description = "下载完成通知" }
            val nm = getSystemService(NOTIFICATION_SERVICE) as? NotificationManager
            nm?.createNotificationChannel(ch)
        }
    }

    private fun notify(id: Int, title: String, body: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        try {
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
            val n = builder
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle(title)
                .setContentText(body)
                .setAutoCancel(true)
                .build()
            val nm = getSystemService(NOTIFICATION_SERVICE) as? NotificationManager
            nm?.notify(id, n)
        } catch (_: Exception) {
        }
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
