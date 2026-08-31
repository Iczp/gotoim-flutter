import UIKit
import Flutter
import CoreMotion
import AVFoundation
import MediaPlayer

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private var screenshotEventSink: FlutterEventSink?
  private var proximityEventSink: FlutterEventSink?
  private let systemVolumeView = MPVolumeView(frame: .zero)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      systemVolumeView.alpha = 0.01
      systemVolumeView.frame = .zero
      controller.view.addSubview(systemVolumeView)
      setupNativeChannels(binaryMessenger: controller.binaryMessenger)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setupNativeChannels(binaryMessenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(name: "com.gotoim.native/methods", binaryMessenger: binaryMessenger)
    methodChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "getBatteryInfo":
        UIDevice.current.isBatteryMonitoringEnabled = true
        let rawLevel = UIDevice.current.batteryLevel
        let level = rawLevel >= 0 ? Int(rawLevel * 100) : 100
        let state = UIDevice.current.batteryState
        let isCharging = state == .charging || state == .full
        let statusStr: String
        switch state {
        case .charging: statusStr = "charging"
        case .unplugged: statusStr = "discharging"
        case .full: statusStr = "full"
        default: statusStr = "unknown"
        }
        result(["level": level, "isCharging": isCharging, "status": statusStr])

      case "getScreenBrightness":
        result(Double(UIScreen.main.brightness))

      case "setScreenBrightness":
        if let args = call.arguments as? [String: Any], let b = args["brightness"] as? Double {
          UIScreen.main.brightness = CGFloat(b)
          result(true)
        } else {
          result(false)
        }

      case "vibrate":
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        result(true)

      case "makePhoneCall":
        if let args = call.arguments as? [String: Any],
           let number = args["phoneNumber"] as? String,
           let url = URL(string: "tel://\(number)"),
           UIApplication.shared.canOpenURL(url) {
          UIApplication.shared.open(url, options: [:], completionHandler: { success in
            result(success)
          })
        } else {
          result(false)
        }

      case "setFlashlight":
        let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
        guard let camera = AVCaptureDevice.default(for: .video), camera.hasTorch else {
          result(false)
          return
        }
        do {
          try camera.lockForConfiguration()
          defer { camera.unlockForConfiguration() }
          if enabled {
            try camera.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
          } else {
            camera.torchMode = .off
          }
          result(true)
        } catch {
          result(false)
        }

      case "getSystemVolume":
        result(Double(AVAudioSession.sharedInstance().outputVolume))

      case "setSystemVolume":
        let volume = ((call.arguments as? [String: Any])?["volume"] as? NSNumber)?.floatValue ?? 0
        if let slider = self.systemVolumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
          slider.value = min(max(volume, 0), 1)
          result(true)
        } else {
          result(false)
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Screenshot Event Channel
    let screenshotChannel = FlutterEventChannel(name: "com.gotoim.native/user_capture_screen", binaryMessenger: binaryMessenger)
    screenshotChannel.setStreamHandler(ScreenshotStreamHandler())

    // Proximity Event Channel
    let proximityChannel = FlutterEventChannel(name: "com.gotoim.native/proximity", binaryMessenger: binaryMessenger)
    proximityChannel.setStreamHandler(ProximityStreamHandler())

    // Motion Event Channels. Both streams emit at approximately five samples
    // per second, matching the Dart Native sensor contract.
    let accelerometerChannel = FlutterEventChannel(
      name: "com.gotoim.native/accelerometer",
      binaryMessenger: binaryMessenger
    )
    accelerometerChannel.setStreamHandler(
      MotionStreamHandler(kind: .accelerometer)
    )

    let gyroscopeChannel = FlutterEventChannel(
      name: "com.gotoim.native/gyroscope",
      binaryMessenger: binaryMessenger
    )
    gyroscopeChannel.setStreamHandler(MotionStreamHandler(kind: .gyroscope))
  }
}

class ScreenshotStreamHandler: NSObject, FlutterStreamHandler {
  private var observer: NSObjectProtocol?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    observer = NotificationCenter.default.addObserver(
      forName: UIApplication.userDidTakeScreenshotNotification,
      object: nil,
      queue: .main
    ) { _ in
      events(Int(Date().timeIntervalSince1970 * 1000))
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let obs = observer {
      NotificationCenter.default.removeObserver(obs)
      observer = nil
    }
    return nil
  }
}

class ProximityStreamHandler: NSObject, FlutterStreamHandler {
  private var observer: NSObjectProtocol?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    UIDevice.current.isProximityMonitoringEnabled = true
    observer = NotificationCenter.default.addObserver(
      forName: UIDevice.proximityStateDidChangeNotification,
      object: nil,
      queue: .main
    ) { _ in
      let isNear = UIDevice.current.proximityState
      events(["distance": isNear ? 0.0 : 5.0, "isNear": isNear])
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let obs = observer {
      NotificationCenter.default.removeObserver(obs)
      observer = nil
    }
    UIDevice.current.isProximityMonitoringEnabled = false
    return nil
  }
}

private enum MotionKind {
  case accelerometer
  case gyroscope
}

/// Bridges CoreMotion into the same EventChannel payload used by Android:
/// `{x, y, z}`. CoreMotion only runs while Flutter has an active listener,
/// and is stopped immediately when that listener is cancelled.
private final class MotionStreamHandler: NSObject, FlutterStreamHandler {
  private let kind: MotionKind
  private let motionManager = CMMotionManager()
  private let operationQueue = OperationQueue.main

  init(kind: MotionKind) {
    self.kind = kind
    super.init()
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    let interval = 0.2 // Approximately 5 Hz, consistent with Android.

    switch kind {
    case .accelerometer:
      guard motionManager.isAccelerometerAvailable else {
        return FlutterError(
          code: "NOT_SUPPORTED",
          message: "This device does not provide an accelerometer.",
          details: nil
        )
      }
      motionManager.accelerometerUpdateInterval = interval
      motionManager.startAccelerometerUpdates(to: operationQueue) {
        data, error in
        guard error == nil, let acceleration = data?.acceleration else { return }
        events([
          "x": acceleration.x,
          "y": acceleration.y,
          "z": acceleration.z,
        ])
      }

    case .gyroscope:
      guard motionManager.isGyroAvailable else {
        return FlutterError(
          code: "NOT_SUPPORTED",
          message: "This device does not provide a gyroscope.",
          details: nil
        )
      }
      motionManager.gyroUpdateInterval = interval
      motionManager.startGyroUpdates(to: operationQueue) { data, error in
        guard error == nil, let rotationRate = data?.rotationRate else { return }
        events([
          "x": rotationRate.x,
          "y": rotationRate.y,
          "z": rotationRate.z,
        ])
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    switch kind {
    case .accelerometer:
      motionManager.stopAccelerometerUpdates()
    case .gyroscope:
      motionManager.stopGyroUpdates()
    }
    return nil
  }
}
