package com.tandem.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : FlutterActivity() {
    private val updateChannel = "com.tandem.app/app_updates"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppVersion" -> result.success(packageManager.getPackageInfo(packageName, 0).versionName ?: "0.0.0")
                "canInstallPackages" -> result.success(Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls())
                "requestInstallPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                        startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                    }
                    result.success(null)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    val apk = path?.let(::File)
                    if (apk == null || !apk.isFile) {
                        result.error("APK_MISSING", "The downloaded update file is missing.", null)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                        result.error("INSTALL_PERMISSION", "Allow Tandem to install apps from this source, then try again.", null)
                    } else {
                        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                }
                "openReceivedFile" -> {
                    val path = call.argument<String>("path")
                    val file = path?.let(::File)
                    val appRoot = filesDir.canonicalFile
                    val target = file?.canonicalFile
                    if (target == null || !target.isFile || !target.path.startsWith(appRoot.path + File.separator)) {
                        result.error("FILE_MISSING", "The received file is no longer available.", null)
                    } else {
                        val extension = target.extension.lowercase()
                        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "application/octet-stream"
                        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", target)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mime)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        try {
                            startActivity(intent)
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("NO_VIEWER", "No app on this phone can open this file type.", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
