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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "StudyHubInk") {
      registrar.register(InkCanvasFactory(messenger: registrar.messenger()), withId: "studyhub/ink")
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "StudyHubChatGptAuth") {
      ChatGptAuthBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "StudyHubHtml") {
      registrar.register(StudyHtmlFactory(messenger: registrar.messenger()), withId: "studyhub/html")
    }
  }
}
