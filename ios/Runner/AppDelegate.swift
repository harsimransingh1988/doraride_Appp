import UIKit
import Flutter
import GoogleMaps // Required for GMSServices

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // START: Google Maps API Key Insertion (iOS Key)
    GMSServices.provideAPIKey("AIzaSyCvqX9_aV_PWHckZXgPP3ACssOFj-g41sA")
    // END: Google Maps API Key Insertion
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}