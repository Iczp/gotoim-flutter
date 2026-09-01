package com.example.gotoim_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.example.gotoim_flutter.native.NativeDevicePlugin
import com.example.gotoim_flutter.task.MiniAppActivity

class MainActivity : FlutterActivity() {

    override fun getRenderMode(): RenderMode = RenderMode.texture

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL_NAME = "com.gotoim.task_manager"
    }

    private var nativeDevicePlugin: NativeDevicePlugin? = null
    private var taskManagerChannel: MethodChannel? = null

    private val taskReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                MiniAppActivity.ACTION_MINI_APP_MINIMIZED -> {
                    val payload = mapOf(
                        "appId" to intent.getStringExtra("appId"),
                        "title" to intent.getStringExtra("title"),
                        "url" to intent.getStringExtra("url"),
                        "iconUrl" to intent.getStringExtra("iconUrl")
                    )
                    Log.d(TAG, "[AppTask] onReceive ACTION_MINI_APP_MINIMIZED $payload")
                    taskManagerChannel?.invokeMethod("onMiniAppMinimized", payload)
                }
                MiniAppActivity.ACTION_MINI_APP_CLOSED -> {
                    val payload = mapOf(
                        "appId" to intent.getStringExtra("appId")
                    )
                    Log.d(TAG, "[AppTask] onReceive ACTION_MINI_APP_CLOSED $payload")
                    taskManagerChannel?.invokeMethod("onMiniAppClosed", payload)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register Native / Device capabilities plugin
        nativeDevicePlugin = NativeDevicePlugin.register(flutterEngine, applicationContext, this)

        // Register Task Manager Channel
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        taskManagerChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "openMiniApp" -> {
                    val appId = call.argument<String>("appId")
                    val title = call.argument<String>("title")
                    val url = call.argument<String>("url")
                    val iconUrl = call.argument<String>("iconUrl")
                    val reuseExisting = call.argument<Boolean>("reuseExisting") ?: true

                    if (appId == null || url == null) {
                        result.error("INVALID_ARGUMENT", "appId and url are required", null)
                        return@setMethodCallHandler
                    }

                    Log.d(TAG, "[AppTask] openMiniApp appId=$appId url=$url reuse=$reuseExisting")

                    val intent = Intent(this, MiniAppActivity::class.java).apply {
                        // Task identity: gotoim://miniapp/{appId}
                        data = Uri.parse("gotoim://miniapp/$appId")

                        // Create a new document task or bring existing one to front.
                        addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT)
                        if (!reuseExisting) {
                            addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
                        }

                        putExtra("appId", appId)
                        putExtra("title", title ?: appId)
                        putExtra("url", url)
                        putExtra("iconUrl", iconUrl)
                        putExtra("reuseExisting", reuseExisting)
                    }

                    startActivity(intent)
                    result.success(null)
                }
                "closeCurrentTask" -> {
                    Log.d(TAG, "[AppTask] closeCurrentTask (main activity)")
                    // The main activity should not be removed from recents.
                    // This is a no-op from the main activity's perspective.
                    result.success(null)
                }
                "closeTaskByAppId" -> {
                    val appId = call.argument<String>("appId")
                    Log.d(TAG, "[AppTask] closeTaskByAppId appId=$appId")
                    if (appId != null) {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                        for (appTask in am.appTasks) {
                            val taskInfo = appTask.taskInfo
                            if (taskInfo?.baseIntent?.data?.toString() == "gotoim://miniapp/$appId") {
                                appTask.finishAndRemoveTask()
                                break
                            }
                        }

                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Register broadcast receiver for mini app events
        val filter = IntentFilter().apply {
            addAction(MiniAppActivity.ACTION_MINI_APP_MINIMIZED)
            addAction(MiniAppActivity.ACTION_MINI_APP_CLOSED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(taskReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(taskReceiver, filter)
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(taskReceiver)
        } catch (_: Exception) {}
        taskManagerChannel?.setMethodCallHandler(null)
        taskManagerChannel = null
        nativeDevicePlugin?.onDestroy()
        nativeDevicePlugin = null
        super.onDestroy()
    }
}

