import Flutter
import UIKit
import UIKit.UIGestureRecognizerSubclass
import UserNotifications
import Vision

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NotelyHandwriting") {
      Handwriting.register(with: registrar.messenger())
    }
  }
}

/// Reads handwriting, on the device, with Vision: "recognize" takes a PNG
/// of dark ink on white ("png") and answers its lines of text, top to
/// bottom (empty when there's nothing it can read).
enum Handwriting {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "notely/handwriting", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognize",
        let args = call.arguments as? [String: Any],
        let png = args["png"] as? FlutterStandardTypedData,
        let image = UIImage(data: png.data)?.cgImage
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        var lines: [String] = []
        do {
          try VNImageRequestHandler(cgImage: image).perform([request])
          let found = (request.results ?? [])
            // Vision's y runs up the image: the top line has the largest.
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
          lines = found.compactMap { $0.topCandidates(1).first?.string }
        } catch {
          lines = []
        }
        DispatchQueue.main.async { result(lines) }
      }
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
      case "listenForSamples":
        result(PencilSamples.shared.attach(messenger: messenger))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Passes on every sample the Apple Pencil reports while touching, which
/// Flutter's own touch events leave out: iOS reports the Pencil up to 240
/// times a second, but only the latest sample per screen refresh reaches
/// Flutter, at whole-point precision. This watches the Pencil's touches
/// (without taking them from Flutter) and sends each event's coalesced
/// samples, at full precision, on "notely/pencil-samples": six numbers a
/// sample (phase 0 began, 1 moved, 2 ended, 3 cancelled; time in seconds;
/// x and y in the Flutter view's points; force; maximum force).
final class PencilSamples: UIGestureRecognizer, UIGestureRecognizerDelegate {
  static let shared = PencilSamples()

  private var channel: FlutterBasicMessageChannel?
  /// The Flutter view, whose points samples are given in.
  private weak var flutterView: UIView?

  private init() {
    super.init(target: nil, action: nil)
    cancelsTouchesInView = false
    delaysTouchesBegan = false
    delaysTouchesEnded = false
    allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
    delegate = self
  }

  /// Starts watching the app's window. Returns whether it is.
  func attach(messenger: FlutterBinaryMessenger) -> Bool {
    if channel == nil {
      channel = FlutterBasicMessageChannel(
        name: "notely/pencil-samples", binaryMessenger: messenger,
        codec: FlutterStandardMessageCodec.sharedInstance())
    }
    if flutterView != nil { return true }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })
      ?? scenes.first?.windows.first,
      let flutterView = window.rootViewController?.view
    else { return false }
    window.addGestureRecognizer(self)
    self.flutterView = flutterView
    return true
  }

  private func send(_ touches: Set<UITouch>, _ event: UIEvent?, phase: Double) {
    guard let channel, let flutterView else { return }
    var data: [Double] = []
    for touch in touches where touch.type == .pencil {
      let samples = event?.coalescedTouches(for: touch) ?? [touch]
      for sample in samples {
        let at = sample.preciseLocation(in: flutterView)
        data += [
          phase, sample.timestamp, Double(at.x), Double(at.y),
          Double(sample.force), Double(sample.maximumPossibleForce),
        ]
      }
    }
    if data.isEmpty { return }
    channel.sendMessage(FlutterStandardTypedData(float64: data.withUnsafeBufferPointer {
      Data(buffer: $0)
    }))
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    send(touches, event, phase: 0)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    send(touches, event, phase: 1)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    send(touches, event, phase: 2)
    // Never recognizes anything: done, ready for the next touch.
    state = .failed
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    send(touches, event, phase: 3)
    state = .failed
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
  ) -> Bool { true }
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
