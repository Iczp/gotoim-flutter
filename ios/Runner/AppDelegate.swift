import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private var screenshotEventSink: FlutterEventSink?
  private var proximityEventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
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
