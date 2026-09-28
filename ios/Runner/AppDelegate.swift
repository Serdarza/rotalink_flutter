import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var captureShield: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(updateCaptureShield),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(updateCaptureShield),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  /// iOS ekran görüntüsünün engellenmesine izin vermez; ekran kaydı / yansıtma
  /// sırasında içerik siyah bir perdeyle gizlenir.
  @objc private func updateCaptureShield() {
    let keyWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    guard let window = keyWindow else { return }

    if window.screen.isCaptured {
      if captureShield == nil {
        let shield = UIView(frame: window.bounds)
        shield.backgroundColor = .black
        shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let label = UILabel()
        label.text = "Ekran kaydı sırasında içerik gösterilmez."
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        shield.addSubview(label)
        NSLayoutConstraint.activate([
          label.centerXAnchor.constraint(equalTo: shield.centerXAnchor),
          label.centerYAnchor.constraint(equalTo: shield.centerYAnchor),
          label.leadingAnchor.constraint(greaterThanOrEqualTo: shield.leadingAnchor, constant: 24),
          label.trailingAnchor.constraint(lessThanOrEqualTo: shield.trailingAnchor, constant: -24),
        ])
        captureShield = shield
      }
      if let shield = captureShield, shield.superview !== window {
        shield.frame = window.bounds
        window.addSubview(shield)
      }
    } else {
      captureShield?.removeFromSuperview()
      captureShield = nil
    }
  }
}
