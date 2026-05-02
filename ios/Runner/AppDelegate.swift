import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Enable highest refresh rate (ProMotion on supported devices)
    // The CADisableMinimumFrameDurationOnPhone key in Info.plist handles this
    // No additional code needed - iOS automatically uses highest refresh rate
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
