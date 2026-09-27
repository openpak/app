import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Set while a parental screen is open (parental_lock.dart). iOS cannot
  /// refuse a screenshot, so what it gets is the app-switcher picture: the
  /// window is covered whenever the scene stops being active.
  private var secure = false
  private var covers: [UIView] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Notifications rather than SceneDelegate overrides: FlutterSceneDelegate
    // implements the same callbacks to report the app's lifecycle to Dart.
    NotificationCenter.default.addObserver(
      forName: UIScene.willDeactivateNotification, object: nil, queue: .main
    ) { [weak self] note in self?.cover(note.object as? UIWindowScene) }
    NotificationCenter.default.addObserver(
      forName: UIScene.didActivateNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.uncover() }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    FlutterMethodChannel(
      name: "org.openpak/secure", binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { [weak self] call, result in
      guard call.method == "set" else { return result(FlutterMethodNotImplemented) }
      self?.secure = call.arguments as? Bool ?? false
      if self?.secure == false { self?.uncover() }
      result(nil)
    }
  }

  private func cover(_ scene: UIWindowScene?) {
    guard secure, covers.isEmpty, let scene else { return }
    for window in scene.windows {
      let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
      view.frame = window.bounds
      view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      window.addSubview(view)
      covers.append(view)
    }
  }

  private func uncover() {
    covers.forEach { $0.removeFromSuperview() }
    covers.removeAll()
  }
}
