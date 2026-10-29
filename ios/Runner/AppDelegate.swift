import EventKit
import EventKitUI
import Flutter
import GoogleMaps
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let calendarStore = EKEventStore()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let mapsKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !mapsKey.isEmpty, !mapsKey.contains("$(") {
      GMSServices.provideAPIKey(mapsKey)
    }
    // BGTaskScheduler, planlanan görevin işleyicisi kayıtlı değilse uygulamayı çökertir.
    // Kimlik, Info.plist ve lib/services/pro_update_notifier.dart ile aynı olmalı.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.serdarza.rotalink.proUpdates",
      earliestBeginInSeconds: NSNumber(value: 12 * 60 * 60)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerCalendarChannel(messenger: engineBridge.applicationRegistrar.messenger())
  }

  // MARK: - Takvime Ekle (Konaklama detayı)

  /// Dart: lib/services/calendar_event_service.dart ("rotalink/calendar" / "addEvent").
  private func registerCalendarChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "rotalink/calendar", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "addEvent", let args = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.presentCalendarEditor(args: args, result: result)
    }
  }

  private func presentCalendarEditor(args: [String: Any], result: @escaping FlutterResult) {
    let store = calendarStore
    let show: () -> Void = { [weak self] in
      DispatchQueue.main.async {
        guard let self = self, let top = self.topViewController() else {
          result(false)
          return
        }
        let beginMs = (args["beginMillis"] as? NSNumber)?.doubleValue
          ?? Date().timeIntervalSince1970 * 1000
        let endMs = (args["endMillis"] as? NSNumber)?.doubleValue ?? (beginMs + 3_600_000)
        let event = EKEvent(eventStore: store)
        event.title = args["title"] as? String ?? ""
        event.notes = args["notes"] as? String ?? ""
        event.startDate = Date(timeIntervalSince1970: beginMs / 1000)
        event.endDate = Date(timeIntervalSince1970: endMs / 1000)
        event.calendar = store.defaultCalendarForNewEvents

        let editor = EKEventEditViewController()
        editor.eventStore = store
        editor.event = event
        editor.editViewDelegate = self
        top.present(editor, animated: true)
        result(true)
      }
    }

    if #available(iOS 17.0, *) {
      // EventKitUI düzenleme ekranı iOS 17+ ayrı süreçte çalışır; izin istemez.
      show()
    } else {
      store.requestAccess(to: .event) { granted, _ in
        if granted {
          show()
        } else {
          DispatchQueue.main.async { result(false) }
        }
      }
    }
  }

  private func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
      ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}

extension AppDelegate: EKEventEditViewDelegate {
  func eventEditViewController(
    _ controller: EKEventEditViewController,
    didCompleteWith action: EKEventEditViewAction
  ) {
    controller.dismiss(animated: true)
  }
}
