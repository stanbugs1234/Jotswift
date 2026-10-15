import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
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
enum PencilChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "notely/pencil", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "prefersPencilOnlyDrawing":
        result(UIPencilInteraction.prefersPencilOnlyDrawing)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
