package org.openpak.openpak

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// A FragmentActivity: local_auth's biometric prompt is a fragment.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // FLAG_SECURE while a parental screen is open: no screenshots, no
        // screen recording, and a blank picture in recent apps. A few lines
        // here rather than a plugin; parental_lock.dart sets and clears it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.openpak/secure")
            .setMethodCallHandler { call, result ->
                if (call.method != "set") return@setMethodCallHandler result.notImplemented()
                if (call.arguments == true) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            }
        // The updater (lib/updater.dart): where to download to, whether the app
        // may install packages, and the hand-off to the system installer.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.openpak/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dir" -> result.success(File(cacheDir, "updates").apply { mkdirs() }.path)
                    "canInstall" -> result.success(packageManager.canRequestPackageInstalls())
                    "allowInstall" -> {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                    }
                    "install" -> {
                        val file = File(call.arguments as String)
                        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                        startActivity(
                            Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
