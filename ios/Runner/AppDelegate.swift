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
