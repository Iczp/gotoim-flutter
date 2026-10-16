package com.example.gotoim_flutter.native

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.media.AudioManager
import android.media.MediaDrm
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import java.security.MessageDigest
import java.util.UUID
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class NativeDevicePlugin(
    private val context: Context,
    private var activity: Activity?
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "NativeDevicePlugin"
        private const val METHOD_CHANNEL = "com.gotoim.native/methods"
        private const val SCREENSHOT_CHANNEL = "com.gotoim.native/user_capture_screen"
        private const val ACCELEROMETER_CHANNEL = "com.gotoim.native/accelerometer"
        private const val GYROSCOPE_CHANNEL = "com.gotoim.native/gyroscope"
        private const val PROXIMITY_CHANNEL = "com.gotoim.native/proximity"

        fun register(engine: FlutterEngine, context: Context, activity: Activity?): NativeDevicePlugin {
            val plugin = NativeDevicePlugin(context, activity)
            plugin.setupChannels(engine)
            return plugin
        }
    }

    private var methodChannel: MethodChannel? = null
    private var screenshotEventSink: EventChannel.EventSink? = null
    private var screenshotObserver: ContentObserver? = null

    private var sensorManager: SensorManager? = null
    private var accelerometerEventSink: EventChannel.EventSink? = null
    private var accelerometerListener: SensorEventListener? = null

    private var gyroscopeEventSink: EventChannel.EventSink? = null
    private var gyroscopeListener: SensorEventListener? = null

    private var proximityEventSink: EventChannel.EventSink? = null
    private var proximityListener: SensorEventListener? = null

    fun setActivity(act: Activity?) {
        this.activity = act
    }

    private fun setupChannels(engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager

        // Method Channel
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).apply {
            setMethodCallHandler(this@NativeDevicePlugin)
        }

        // Screenshot EventChannel
        EventChannel(messenger, SCREENSHOT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                screenshotEventSink = events
                registerScreenshotObserver()
            }

            override fun onCancel(arguments: Any?) {
                unregisterScreenshotObserver()
                screenshotEventSink = null
            }
        })

        // Accelerometer EventChannel (~5 times/sec = 200,000 microseconds)
        EventChannel(messenger, ACCELEROMETER_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                accelerometerEventSink = events
                registerAccelerometer()
            }

            override fun onCancel(arguments: Any?) {
                unregisterAccelerometer()
                accelerometerEventSink = null
            }
        })

        // Gyroscope EventChannel
        EventChannel(messenger, GYROSCOPE_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                gyroscopeEventSink = events
                registerGyroscope()
            }

            override fun onCancel(arguments: Any?) {
                unregisterGyroscope()
                gyroscopeEventSink = null
            }
        })

        // Proximity EventChannel
        EventChannel(messenger, PROXIMITY_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                proximityEventSink = events
                registerProximity()
            }

            override fun onCancel(arguments: Any?) {
                unregisterProximity()
                proximityEventSink = null
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getBatteryInfo" -> {
                try {
                    val bm = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                    val level = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 100
                    val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                    val batteryStatus = context.registerReceiver(null, ifilter)
                    val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                    val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                            status == BatteryManager.BATTERY_STATUS_FULL
                    val statusStr = when (status) {
                        BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
                        BatteryManager.BATTERY_STATUS_DISCHARGING -> "discharging"
                        BatteryManager.BATTERY_STATUS_FULL -> "full"
                        BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "notCharging"
                        else -> "unknown"
                    }
                    result.success(
                        mapOf(
                            "level" to level,
                            "isCharging" to isCharging,
                            "status" to statusStr
                        )
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "getBatteryInfo error", e)
                    result.success(
                        mapOf(
                            "level" to 100,
                            "isCharging" to false,
                            "status" to "unknown"
                        )
                    )
                }
            }

            "getScreenBrightness" -> {
                try {
                    val window = activity?.window
                    val lp = window?.attributes
                    var brightness = lp?.screenBrightness ?: -1f
                    if (brightness < 0) {
                        val sysBrightness = Settings.System.getInt(
                            context.contentResolver,
                            Settings.System.SCREEN_BRIGHTNESS,
                            128
                        )
                        brightness = sysBrightness / 255.0f
                    }
                    result.success(brightness.toDouble())
                } catch (e: Exception) {
                    Log.e(TAG, "getScreenBrightness error", e)
                    result.success(1.0)
                }
            }

            "setScreenBrightness" -> {
                val brightness = (call.argument<Double>("brightness") ?: 1.0).toFloat()
                activity?.runOnUiThread {
                    activity?.window?.let { win ->
                        val lp = win.attributes
                        lp.screenBrightness = brightness.coerceIn(0.0f, 1.0f)
                        win.attributes = lp
                    }
                }
                result.success(true)
            }

            "vibrate" -> {
                val durationArg = call.argument<Int>("duration")
                val type = call.argument<String>("type") ?: "medium"

                val defaultDuration = when (type) {
                    "selection" -> 18
                    "light" -> 25
                    "heavy" -> 65
                    "medium" -> 40
                    else -> 100
                }
                val duration = (durationArg ?: defaultDuration).coerceAtLeast(10)

                val amplitude = when (type) {
                    "selection" -> 90
                    "light" -> 130
                    "heavy" -> 255
                    "medium" -> 180
                    else -> VibrationEffect.DEFAULT_AMPLITUDE
                }

                try {
                    val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                        vm?.defaultVibrator
                    } else {
                        @Suppress("DEPRECATION")
                        context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                    }

                    if (vibrator != null && vibrator.hasVibrator()) {
                        var vibrated = false
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val effectId = when (type) {
                                "selection" -> VibrationEffect.EFFECT_TICK
                                "light" -> VibrationEffect.EFFECT_CLICK
                                "heavy" -> VibrationEffect.EFFECT_HEAVY_CLICK
                                "medium" -> VibrationEffect.EFFECT_CLICK
                                else -> -1
                            }
                            if (effectId != -1) {
                                try {
                                    vibrator.vibrate(VibrationEffect.createPredefined(effectId))
                                    vibrated = true
                                } catch (ignored: Exception) {
                                    // Vendor fallback (e.g. Huawei/Honor) to createOneShot below
                                }
                            }
                        }

                        if (!vibrated) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                vibrator.vibrate(
                                    VibrationEffect.createOneShot(
                                        duration.toLong(),
                                        amplitude
                                    )
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                vibrator.vibrate(duration.toLong())
                            }
                        }
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "vibrate error", e)
                    result.success(false)
                }
            }

            "makePhoneCall" -> {
                val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                try {
                    val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phoneNumber")).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "makePhoneCall error", e)
                    result.success(false)
                }
            }

            "setFlashlight" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                try {
                    val cameraManager =
                        context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
                    val cameraId = cameraManager?.cameraIdList?.firstOrNull { id ->
                        cameraManager.getCameraCharacteristics(id)
                            .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                    }
                    if (cameraManager == null || cameraId == null) {
                        result.success(false)
                    } else {
                        cameraManager.setTorchMode(cameraId, enabled)
                        result.success(true)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "setFlashlight error", e)
                    result.success(false)
                }
            }

            "getSystemVolume" -> {
                try {
                    val audioManager =
                        context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                    val maximum = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: 0
                    val current = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: 0
                    result.success(if (maximum > 0) current.toDouble() / maximum else 0.0)
                } catch (e: Exception) {
                    Log.e(TAG, "getSystemVolume error", e)
                    result.success(null)
                }
            }

            "setSystemVolume" -> {
                val normalized = (call.argument<Double>("volume") ?: 0.0)
                    .coerceIn(0.0, 1.0)
                try {
                    val audioManager =
                        context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                    val maximum = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: 0
                    if (audioManager == null || maximum <= 0) {
                        result.success(false)
                    } else {
                        audioManager.setStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            (maximum * normalized).toInt(),
                            0
                        )
                        result.success(true)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "setSystemVolume error", e)
                    result.success(false)
                }
            }

            "minimizeApp" -> {
                try {
                    val moved = activity?.moveTaskToBack(true) ?: false
                    result.success(moved)
                } catch (e: Exception) {
                    Log.e(TAG, "minimizeApp error", e)
                    result.success(false)
                }
            }

            "exitApp" -> {
                try {
                    result.success(true)
                    activity?.finishAffinity()
                    android.os.Process.killProcess(android.os.Process.myPid())
                } catch (e: Exception) {
                    Log.e(TAG, "exitApp error", e)
                    result.success(false)
                }
            }

            "restartApp" -> {
                try {
                    val ctx = activity ?: context
                    val pm = ctx.packageManager
                    val intent = pm.getLaunchIntentForPackage(ctx.packageName)
                    if (intent != null) {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                        result.success(true)
                        ctx.startActivity(intent)
                        activity?.finish()
                        android.os.Process.killProcess(android.os.Process.myPid())
                    } else {
                        result.success(false)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "restartApp error", e)
                    result.success(false)
                }
            }

            "getPermanentDeviceId" -> {
                try {
                    val id = getPermanentDeviceId()
                    result.success(id)
                } catch (e: Exception) {
                    Log.e(TAG, "getPermanentDeviceId error", e)
                    result.success(null)
                }
            }

            else -> result.notImplemented()
        }
    }

    // --- Screenshot Observer ---
    private fun registerScreenshotObserver() {
        try {
            screenshotObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean, uri: Uri?) {
                    super.onChange(selfChange, uri)
                    screenshotEventSink?.success(System.currentTimeMillis())
                }
            }
            context.contentResolver.registerContentObserver(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                true,
                screenshotObserver!!
            )
        } catch (e: Exception) {
            Log.e(TAG, "registerScreenshotObserver failed", e)
        }
    }

    private fun unregisterScreenshotObserver() {
        screenshotObserver?.let {
            try {
                context.contentResolver.unregisterContentObserver(it)
            } catch (e: Exception) {
                Log.e(TAG, "unregisterScreenshotObserver error", e)
            }
            screenshotObserver = null
        }
    }

    // --- Accelerometer ---
    private fun registerAccelerometer() {
        val sensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
        accelerometerListener = object : SensorEventListener {
            private var lastUpdate = 0L

            override fun onSensorChanged(event: SensorEvent?) {
                event?.let {
                    val now = System.currentTimeMillis()
                    // Throttle to ~5 times per second (200ms)
                    if (now - lastUpdate >= 180) {
                        lastUpdate = now
                        accelerometerEventSink?.success(
                            mapOf(
                                "x" to it.values[0],
                                "y" to it.values[1],
                                "z" to it.values[2]
                            )
                        )
                    }
                }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        sensorManager?.registerListener(
            accelerometerListener,
            sensor,
            SensorManager.SENSOR_DELAY_NORMAL
        )
    }

    private fun unregisterAccelerometer() {
        accelerometerListener?.let {
            sensorManager?.unregisterListener(it)
            accelerometerListener = null
        }
    }

    // --- Gyroscope ---
    private fun registerGyroscope() {
        val sensor = sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE) ?: return
        gyroscopeListener = object : SensorEventListener {
            private var lastUpdate = 0L

            override fun onSensorChanged(event: SensorEvent?) {
                event?.let {
                    val now = System.currentTimeMillis()
                    if (now - lastUpdate >= 180) {
                        lastUpdate = now
                        gyroscopeEventSink?.success(
                            mapOf(
                                "x" to it.values[0],
                                "y" to it.values[1],
                                "z" to it.values[2]
                            )
                        )
                    }
                }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        sensorManager?.registerListener(
            gyroscopeListener,
            sensor,
            SensorManager.SENSOR_DELAY_NORMAL
        )
    }

    private fun unregisterGyroscope() {
        gyroscopeListener?.let {
            sensorManager?.unregisterListener(it)
            gyroscopeListener = null
        }
    }

    // --- Proximity ---
    private fun registerProximity() {
        val sensor = sensorManager?.getDefaultSensor(Sensor.TYPE_PROXIMITY) ?: return
        val maxRange = sensor.maximumRange
        proximityListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent?) {
                event?.let {
                    val distance = it.values[0]
                    val isNear = distance < maxRange && distance < 5.0f
                    proximityEventSink?.success(
                        mapOf(
                            "distance" to distance,
                            "isNear" to isNear
                        )
                    )
                }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        sensorManager?.registerListener(
            proximityListener,
            sensor,
            SensorManager.SENSOR_DELAY_NORMAL
        )
    }

    private fun unregisterProximity() {
        proximityListener?.let {
            sensorManager?.unregisterListener(it)
            proximityListener = null
        }
    }

    private fun getPermanentDeviceId(): String {
        // 1. Widevine MediaDrm Hardware ID (survives app uninstall and reinstall, zero permissions required)
        try {
            val widevineUuid = UUID(-0x121074568629b532L, -0x5c37d8232ae2de13L)
            val mediaDrm = MediaDrm(widevineUuid)
            val idBytes = mediaDrm.getPropertyByteArray(MediaDrm.PROPERTY_DEVICE_UNIQUE_ID)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                mediaDrm.close()
            } else {
                @Suppress("DEPRECATION")
                mediaDrm.release()
            }
            if (idBytes != null && idBytes.isNotEmpty()) {
                val hex = bytesToHex(idBytes)
                if (hex.isNotBlank()) {
                    return hashToUuid(idBytes)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "MediaDrm widevine id fallback: ${e.message}")
        }

        // 2. Fallback to Settings.Secure.ANDROID_ID (stable across reinstalls for same signing key)
        try {
            val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
            if (!androidId.isNullOrBlank() && androidId != "9774d56d682e549c") {
                return hashToUuid(androidId.toByteArray(Charsets.UTF_8))
            }
        } catch (e: Exception) {
            Log.w(TAG, "Settings.Secure.ANDROID_ID fallback: ${e.message}")
        }

        // 3. Fallback to Hardware Fingerprint
        val hardwareInfo = "${Build.BOARD}|${Build.BRAND}|${Build.DEVICE}|${Build.HARDWARE}|${Build.MANUFACTURER}|${Build.MODEL}|${Build.PRODUCT}"
        return hashToUuid(hardwareInfo.toByteArray(Charsets.UTF_8))
    }

    private fun hashToUuid(bytes: ByteArray): String {
        val md = MessageDigest.getInstance("SHA-256")
        val digest = md.digest(bytes)
        val sb = StringBuilder()
        for (i in 0 until 16) {
            sb.append(String.format("%02x", digest[i]))
        }
        val hex = sb.toString()
        return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}"
    }

    private fun bytesToHex(bytes: ByteArray): String {
        val sb = StringBuilder()
        for (b in bytes) {
            sb.append(String.format("%02x", b))
        }
        return sb.toString()
    }

    fun onDestroy() {
        unregisterScreenshotObserver()
        unregisterAccelerometer()
        unregisterGyroscope()
        unregisterProximity()
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
    }
}
