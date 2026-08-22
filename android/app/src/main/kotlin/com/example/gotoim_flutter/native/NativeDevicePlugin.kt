package com.example.gotoim_flutter.native

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
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
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
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
                val duration = call.argument<Int>("duration") ?: 100
                try {
                    val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                        vm?.defaultVibrator
                    } else {
                        @Suppress("DEPRECATION")
                        context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vibrator?.vibrate(
                            VibrationEffect.createOneShot(
                                duration.toLong(),
                                VibrationEffect.DEFAULT_AMPLITUDE
                            )
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator?.vibrate(duration.toLong())
                    }
                    result.success(true)
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

    fun onDestroy() {
        unregisterScreenshotObserver()
        unregisterAccelerometer()
        unregisterGyroscope()
        unregisterProximity()
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
    }
}
