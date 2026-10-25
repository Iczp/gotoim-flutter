import Cocoa
import FlutterMacOS
import ObjectiveC

/// One bridge per engine. A subwindow may not be attached when the plugin's
/// creation callback runs: resolve its OWN controller window when called.
final class WindowControls: NSObject, NSWindowDelegate {
  private static var associationKey: UInt8 = 0
  private weak var controller: FlutterViewController?
  private weak var initialWindow: NSWindow?
  private weak var originalDelegate: NSWindowDelegate?
  private weak var boundWindow: NSWindow?
  private let channel: FlutterMethodChannel

  private init(controller: FlutterViewController, window: NSWindow?) {
    self.controller = controller
    self.initialWindow = window
    self.channel = FlutterMethodChannel(name: "gotoim/window",
      binaryMessenger: controller.engine.binaryMessenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self,
            let window = self.controller?.view.window ?? self.initialWindow else {
        result(FlutterError(code: "WINDOW_UNAVAILABLE",
          message: "This engine has no attached window", details: nil))
        return
      }
      self.bind(window)
      self.handle(call, window: window, result: result)
    }
  }

  static func register(with controller: FlutterViewController, window: NSWindow? = nil) {
    let bridge = WindowControls(controller: controller, window: window)
    objc_setAssociatedObject(controller, &associationKey, bridge,
      .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  }

  private func bind(_ window: NSWindow) {
    guard boundWindow !== window else { return }
    originalDelegate = window.delegate
    window.delegate = self
    boundWindow = window
  }

  override func responds(to selector: Selector!) -> Bool {
    return super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
  }

  override func forwardingTarget(for selector: Selector!) -> Any? {
    if originalDelegate?.responds(to: selector) == true { return originalDelegate }
    return super.forwardingTarget(for: selector)
  }

  private func requestClose(_ window: NSWindow) {
    channel.invokeMethod("closeRequested", arguments: nil)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Keep cached engines alive; Dart updates the main window registry.
    requestClose(sender)
    return false
  }

  private func handle(_ call: FlutterMethodCall, window: NSWindow, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "configure":
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.styleMask.insert(.fullSizeContentView)
      window.isMovableByWindowBackground = false
      result(window.isZoomed)
    case "drag":
      guard let event = NSApp.currentEvent else {
        result(FlutterError(code: "NO_POINTER_EVENT", message: "No current drag event", details: nil))
        return
      }
      window.performDrag(with: event)
      result(true)
    case "minimize":
      window.miniaturize(nil)
      result(window.isZoomed)
    case "toggleMaximize":
      window.zoom(nil)
      result(window.isZoomed)
    case "restore":
      window.deminiaturize(nil)
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      result(window.isZoomed)
    case "toggleVisibility":
      if window.isVisible && !window.isMiniaturized {
        window.orderOut(nil)
      } else {
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
      }
      result(window.isVisible)
    case "pin":
      window.level = (call.arguments as? Bool ?? false) ? .floating : .normal
      result(true)
    case "close":
      requestClose(window)
      result(true)
    case "destroy":
      window.delegate = originalDelegate
      result(true)
      window.close()
    case "hide":
      window.orderOut(nil)
      result(true)
    case "center":
      let current = window.contentView?.bounds.size ?? window.frame.size
      let width = (args["width"] as? NSNumber)?.doubleValue ?? Double(current.width)
      let height = (args["height"] as? NSNumber)?.doubleValue ?? Double(current.height)
      guard width > 0, height > 0, width.isFinite, height.isFinite else {
        result(FlutterError(code: "INVALID_BOUNDS", message: "Invalid window size", details: nil))
        return
      }
      window.setContentSize(NSSize(width: CGFloat(width), height: CGFloat(height)))
      window.center()
      result(true)
    case "setToolWindow":
      let enabled = call.arguments as? Bool ?? true
      window.isExcludedFromWindowsMenu = enabled
      if enabled { window.collectionBehavior.insert(.transient) }
      else { window.collectionBehavior.remove(.transient) }
      result(true)
    case "getWindowRect":
      guard let view = controller?.view else {
        result(FlutterError(code: "WINDOW_UNAVAILABLE", message: "Missing view", details: nil))
        return
      }
      let scale = window.backingScaleFactor
      let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
      let frame = window.frame
      let client = window.convertToScreen(view.convert(view.bounds, to: nil))
      result([
        "left": Int((frame.minX * scale).rounded()),
        "top": Int(((primaryTop - frame.maxY) * scale).rounded()),
        "right": Int((frame.maxX * scale).rounded()),
        "bottom": Int(((primaryTop - frame.minY) * scale).rounded()),
        "clientLeft": Int((client.minX * scale).rounded()),
        "clientTop": Int(((primaryTop - client.maxY) * scale).rounded()),
        "clientWidth": Int((client.width * scale).rounded()),
        "clientHeight": Int((client.height * scale).rounded()),
        "dpi": Int((scale * 96).rounded())
      ])
    case "isDocked": result(false)
    case "browserDockDiagnostics":
      result(["supported": false, "platform": "macOS",
        "reason": "Docking lifecycle and visibility protocols are not implemented",
        "nativeFirstFrameAck": false])
    default:
      // Incomplete docking/capture/modal/hover operations must not report success.
      result(FlutterMethodNotImplemented)
    }
  }
}
