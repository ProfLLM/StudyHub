import Cocoa
import FlutterMacOS
import Security

/// External browser sign-in with loopback callback and protected local tokens.
final class ChatGptAuthBridge: NSObject, FlutterPlugin {
  private let service = "com.studyhub.chatgpt"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "studyhub/chatgpt_auth", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(ChatGptAuthBridge(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
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
      var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrService as String: service, kSecAttrAccount as String: key,
                                 kSecAttrSynchronizable as String: false]
      if call.method == "readSecure" {
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { result(nil); return }
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { storageError(result); return }
        result(value)
      } else if call.method == "deleteSecure" {
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { result(nil) }
        else { storageError(result) }
      } else {
        guard let value = arguments["value"] as? String, let data = value.data(using: .utf8) else {
          storageError(result); return
        }
        let attributes: [String: Any] = [kSecValueData as String: data,
          kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
          query.merge(attributes) { _, new in new }
          status = SecItemAdd(query as CFDictionary, nil)
        }
        if status == errSecSuccess { result(nil) } else { storageError(result) }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func storageError(_ result: FlutterResult) {
    result(FlutterError(code: "secure_storage", message: "Could not access secure ChatGPT connection storage.", details: nil))
  }
}
