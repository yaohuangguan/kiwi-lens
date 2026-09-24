import Flutter
import CoreLocation
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let headingHandler = DeviceHeadingStreamHandler()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "MAPS_API_KEY") as? String,
       !apiKey.isEmpty,
       !apiKey.contains("$(") {
      GMSServices.provideAPIKey(apiKey)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    FlutterEventChannel(
      name: "kiwi_lens/device_heading",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setStreamHandler(headingHandler)
    FlutterMethodChannel(
      name: "kiwi_lens/share",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { [weak self] call, result in
      guard call.method == "shareText",
            let arguments = call.arguments as? [String: Any],
            let text = arguments["text"] as? String,
            !text.isEmpty else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        guard let root = self?.window?.rootViewController ??
          (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
          result(FlutterError(code: "NO_WINDOW", message: "No active iOS window", details: nil))
          return
        }
        let share = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = share.popoverPresentationController {
          popover.sourceView = root.view
          popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 1, height: 1)
        }
        (root.presentedViewController ?? root).present(share, animated: true)
        result(nil)
      }
    }
  }
}

// Core Location heading follows the physical top of the iPhone, unlike GPS course.
private final class DeviceHeadingStreamHandler: NSObject, FlutterStreamHandler, CLLocationManagerDelegate {
  private let locationManager = CLLocationManager()
  private var sink: FlutterEventSink?

  override init() {
    super.init()
    locationManager.delegate = self
    locationManager.headingOrientation = .portrait
    locationManager.headingFilter = 2
    locationManager.distanceFilter = 25
    locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    guard CLLocationManager.headingAvailable() else { return nil }
    // True north is available only while this manager also receives locations.
    if locationManager.authorizationStatus == .authorizedWhenInUse ||
       locationManager.authorizationStatus == .authorizedAlways {
      locationManager.startUpdatingLocation()
      locationManager.startUpdatingHeading()
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    locationManager.stopUpdatingHeading()
    locationManager.stopUpdatingLocation()
    sink = nil
    return nil
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if sink != nil && (manager.authorizationStatus == .authorizedWhenInUse ||
                       manager.authorizationStatus == .authorizedAlways) && CLLocationManager.headingAvailable() {
      manager.startUpdatingLocation()
      manager.startUpdatingHeading()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
    guard heading.headingAccuracy >= 0, heading.trueHeading >= 0 else { return }
    sink?(["heading": heading.trueHeading, "accuracy": heading.headingAccuracy])
  }
}
