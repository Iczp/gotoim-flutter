package com.example.gotoim_flutter.task

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import com.example.gotoim_flutter.GotoIMApplication

/**
 * A generic Activity that hosts a single MiniApp in an independent Android Task.
 *
 * ## Task Identity
 *
 * Each MiniApp is identified by `gotoim://miniapp/{appId}`. The combination of
 * `documentLaunchMode="intoExisting"` in the manifest and `FLAG_ACTIVITY_NEW_DOCUMENT`
 * in the launch intent ensures that:
 *
 * - First open: creates a new Task with the app's identity.
 * - Subsequent opens with the same appId: brings the existing Task to front
 *   and delivers the intent via [onNewIntent].
 *
 * ## FlutterEngine
 *
 * Each MiniApp gets its own [FlutterEngine] created from the shared
 * [FlutterEngineGroup] in [GotoIMApplication]. The engine runs the
 * `miniAppMain` Dart entrypoint, which initializes only the services
 * needed by a MiniApp container (Theme, HTTP, Auth, WebView, JSBridge).
 */
class MiniAppActivity : FlutterActivity() {

    override fun getRenderMode(): RenderMode = RenderMode.surface

    override fun shouldDestroyEngineWithHost(): Boolean = true

    companion object {
        private const val TAG = "MiniAppActivity"
        private const val CHANNEL_NAME = "com.gotoim.mini_app"
        const val ACTION_MINI_APP_MINIMIZED = "com.gotoim.MINI_APP_MINIMIZED"
        const val ACTION_MINI_APP_CLOSED = "com.gotoim.MINI_APP_CLOSED"
        private const val EXTRA_APP_ID = "appId"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_URL = "url"
        private const val EXTRA_ICON_URL = "iconUrl"
        private const val EXTRA_REUSE_EXISTING = "reuseExisting"
    }

    private var appId: String = ""
    private var miniAppUrl: String = ""
    private var miniAppTitle: String = ""
    private var miniAppIconUrl: String? = null
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Extract launch parameters before super.onCreate() so the engine
        // can be configured with the correct entrypoint.
        extractIntentExtras(intent)
        Log.d(TAG, "[AppTask] onCreate appId=$appId url=$miniAppUrl")

        super.onCreate(savedInstanceState)

        // Set the task description (title shown in recent apps).
        setTaskDescription(
            android.app.ActivityManager.TaskDescription(miniAppTitle)
        )
    }

    override fun provideFlutterEngine(context: android.content.Context): FlutterEngine {
        val app = applicationContext as GotoIMApplication
        val flutterLoader = FlutterInjector.instance().flutterLoader()
        val entrypoint = DartExecutor.DartEntrypoint(
            flutterLoader.findAppBundlePath(),
            "miniAppMain"
        )
        return app.engineGroup.createAndRunEngine(context, entrypoint)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)

        // Handle calls from MiniApp Dart side.
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchPayload" -> {
                    result.success(buildPayload())
                }
                "closeTask" -> {
                    Log.d(TAG, "[AppTask] close appId=$appId")
                    val broadcastIntent = Intent(ACTION_MINI_APP_CLOSED).apply {
                        setPackage(packageName)
                        putExtra("appId", appId)
                    }
                    sendBroadcast(broadcastIntent)
                    finishAndRemoveTask()
                    result.success(null)
                }
                "minimizeTask" -> {
                    Log.d(TAG, "[AppTask] minimize appId=$appId")
                    val broadcastIntent = Intent(ACTION_MINI_APP_MINIMIZED).apply {
                        setPackage(packageName)
                        putExtra("appId", appId)
                        putExtra("title", miniAppTitle)
                        putExtra("url", miniAppUrl)
                        putExtra("iconUrl", miniAppIconUrl)
                    }
                    sendBroadcast(broadcastIntent)
                    moveTaskToBack(true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Push initial launch payload to the Dart side.
        channel?.invokeMethod("onLaunch", buildPayload())
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractIntentExtras(intent)
        Log.d(TAG, "[AppTask] onNewIntent appId=$appId url=$miniAppUrl")

        // Deliver new launch payload to Dart.
        channel?.invokeMethod("onNewIntent", buildPayload())
    }

    override fun onDestroy() {
        Log.d(TAG, "[AppTask] onDestroy appId=$appId")
        val broadcastIntent = Intent(ACTION_MINI_APP_CLOSED).apply {
            setPackage(packageName)
            putExtra("appId", appId)
        }
        sendBroadcast(broadcastIntent)
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }


    private fun extractIntentExtras(intent: Intent?) {
        intent?.let {
            appId = it.getStringExtra(EXTRA_APP_ID) ?: appId
            miniAppTitle = it.getStringExtra(EXTRA_TITLE) ?: miniAppTitle
            miniAppUrl = it.getStringExtra(EXTRA_URL) ?: miniAppUrl
            miniAppIconUrl = it.getStringExtra(EXTRA_ICON_URL) ?: miniAppIconUrl
        }
    }

    private fun buildPayload(): Map<String, Any?> = mapOf(
        "appId" to appId,
        "title" to miniAppTitle,
        "url" to miniAppUrl,
        "iconUrl" to miniAppIconUrl
    )
}
