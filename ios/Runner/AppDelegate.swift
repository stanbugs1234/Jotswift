import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Lets reminders show while Notely is open (flutter_local_notifications).
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NotelyPencil") {
      PencilChannel.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NotelyOpenIn") {
      OpenIn.shared.register(with: registrar.messenger())
    }
  }
}

/// Tells Dart about the iPad's Settings → Apple Pencil → "Only Draw with
/// Apple Pencil", so fingers scroll instead of drawing when it's on.
///
/// Also passes on Apple Pencil double-taps and squeezes ("pencilAction",
/// with the gesture and the action chosen in the iPad's settings) once
/// Dart asks with "listenForTaps".
enum PencilChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "notely/pencil", binaryMessenger: messenger)
    PencilTaps.shared.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "prefersPencilOnlyDrawing":
        result(UIPencilInteraction.prefersPencilOnlyDrawing)
      case "listenForTaps":
        result(PencilTaps.shared.attach())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Watches for Apple Pencil double-taps (2nd generation and Pro) and
/// squeezes (Pro) anywhere in the app's window.
final class PencilTaps: NSObject, UIPencilInteractionDelegate {
  static let shared = PencilTaps()

  var channel: FlutterMethodChannel?
  private weak var window: UIWindow?

  /// Adds the Pencil interaction to the app's window. Returns whether it's
  /// listening.
  func attach() -> Bool {
    if window != nil { return true }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })
      ?? scenes.first?.windows.first
    else { return false }
    let interaction = UIPencilInteraction()
    interaction.delegate = self
    window.addInteraction(interaction)
    self.window = window
    return true
  }

  private func send(_ gesture: String, _ action: UIPencilPreferredAction) {
    channel?.invokeMethod(
      "pencilAction", arguments: ["gesture": gesture, "action": Self.name(of: action)])
  }

  static func name(of action: UIPencilPreferredAction) -> String {
    switch action {
    case .ignore: return "ignore"
    case .switchEraser: return "switchEraser"
    case .switchPrevious: return "switchPrevious"
    case .showColorPalette: return "showColorPalette"
    default:
      // Ink attributes, the contextual palette, a shortcut: show the pen
      // options, the closest thing in Jotswift.
      return "showInkAttributes"
    }
  }

  // Before iOS 17.5.
  func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    send("tap", UIPencilInteraction.preferredTapAction)
  }

  @available(iOS 17.5, *)
  func pencilInteraction(
    _ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap
  ) {
    send("tap", UIPencilInteraction.preferredTapAction)
  }

  @available(iOS 17.5, *)
  func pencilInteraction(
    _ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
  ) {
    guard squeeze.phase == .ended else { return }
    send("squeeze", UIPencilInteraction.preferredSqueezeAction)
  }
}

/// Passes PDFs and images that other apps send ("Open in Jotswift", from the
/// share sheet or Files) to Dart, as "open" with a list of {name, data}.
/// Files that arrive before Dart listens wait until it asks with
/// "takePending".
final class OpenIn {
  static let shared = OpenIn()

  private var channel: FlutterMethodChannel?
  private var pending: [[String: Any]] = []
  private var listening = false

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "notely/open", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, call.method == "takePending" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.listening = true
      result(self.pending)
      self.pending = []
    }
  }

  func receive(_ urls: [URL]) {
    let files: [[String: Any]] = urls.compactMap { url in
      guard url.isFileURL else { return nil }
      let scoped = url.startAccessingSecurityScopedResource()
      defer {
        if scoped { url.stopAccessingSecurityScopedResource() }
      }
      guard let data = try? Data(contentsOf: url) else { return nil }
      // Copies iOS made for us (in Documents/Inbox) aren't needed after.
      if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
      return ["name": url.lastPathComponent, "data": FlutterStandardTypedData(bytes: data)]
    }
    if files.isEmpty { return }
    if listening, let channel {
      channel.invokeMethod("open", arguments: files)
    } else {
      pending += files
    }
  }
}
