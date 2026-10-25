import Cocoa
import FlutterMacOS

/// External browser sign-in with loopback callback and protected local tokens.
final class ChatGptAuthBridge: NSObject, FlutterPlugin {
  private let storage = MacProviderKeychain(service: "com.studyhub.chatgpt",
    keys: ["chatgpt.session", "chatgpt.registration"])

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "studyhub/chatgpt_auth", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(ChatGptAuthBridge(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "openUsage":
      // Fixed destination; connection credentials never enter this URL.
      if NSWorkspace.shared.open(URL(string: "https://chatgpt.com/settings/usage")!) { result(nil) }
      else { result(FlutterError(code: "usage_unavailable", message: "Could not open ChatGPT usage settings.", details: nil)) }
    case "openAuth":
      guard let text = arguments["url"] as? String, let url = URL(string: text),
            url.scheme == "https", url.host == "auth.openai.com",
            url.path == "/api/accounts/authorize", NSWorkspace.shared.open(url) else {
        result(FlutterError(code: "auth_unavailable", message: "Could not open ChatGPT sign-in.", details: nil))
        return
      }
      result(nil)
    case "closeAuth":
      NSApplication.shared.activate(ignoringOtherApps: true)
      result(nil)
    case "readSecure", "writeSecure", "deleteSecure":
      guard let key = arguments["key"] as? String,
            ["chatgpt.session", "chatgpt.registration"].contains(key) else {
        result(FlutterError(code: "invalid_key", message: "Invalid connection storage key.", details: nil))
        return
      }
      let method = call.method
      let value = arguments["value"] as? String
      MacProviderKeychain.perform({
        switch method {
        case "readSecure": return try self.storage.read(key)
        case "deleteSecure": try self.storage.delete(key); return nil
        case "writeSecure":
          guard let value else { throw MacProviderKeychain.StorageError.unavailable }
          try self.storage.write(key, value: value)
          return nil
        default: throw MacProviderKeychain.StorageError.unavailable
        }
      }, completion: { outcome in
        switch outcome {
        case .success(let value): result(value)
        case .failure: self.storageError(result)
        }
      })
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func storageError(_ result: FlutterResult) {
    result(FlutterError(code: "secure_storage", message: MacProviderKeychain.StorageError.unavailable.localizedDescription, details: nil))
  }
}
