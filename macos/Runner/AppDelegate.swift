import Cocoa
import FlutterMacOS

@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
  private var nativeMethodChannel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.gotoim.native/methods",
      binaryMessenger: controller.engine.binaryMessenger
    )
    nativeMethodChannel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "setDesktopBadge" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let count = (call.arguments as? [String: Any])?["count"] as? Int ?? 0
      NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
      result(true)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
}
