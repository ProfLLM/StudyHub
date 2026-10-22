import Flutter
import SafariServices
import Security
import UIKit

/// System-owned sign-in UI and device-only Keychain storage for SIWC tokens.
final class ChatGptAuthBridge: NSObject, FlutterPlugin, SFSafariViewControllerDelegate {
  private let channel: FlutterMethodChannel
  private var browser: SFSafariViewController?
  private let service = "com.studyhub.chatgpt"

  private init(channel: FlutterMethodChannel) { self.channel = channel }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "studyhub/chatgpt_auth", binaryMessenger: registrar.messenger())
    let instance = ChatGptAuthBridge(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "openAuth":
      guard let text = arguments["url"] as? String, let url = URL(string: text),
            url.scheme == "https", url.host == "auth.openai.com",
            url.path == "/api/accounts/authorize", browser == nil,
            let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
              .flatMap({ $0.windows }).first(where: { $0.isKeyWindow }),
            var presenter = window.rootViewController else {
        result(FlutterError(code: "auth_unavailable", message: "Could not present ChatGPT sign-in.", details: nil))
        return
      }
      while let next = presenter.presentedViewController { presenter = next }
      let controller = SFSafariViewController(url: url)
      controller.delegate = self
      controller.modalPresentationStyle = .fullScreen
      browser = controller
      presenter.present(controller, animated: true) { result(nil) }
    case "closeAuth":
      let controller = browser
      browser = nil
      if let controller = controller {
        controller.dismiss(animated: true) { result(nil) }
      } else { result(nil) }
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

  func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
    browser = nil
    channel.invokeMethod("authCancelled", arguments: nil)
  }

  private func storageError(_ result: FlutterResult) {
    result(FlutterError(code: "secure_storage", message: "Could not access secure ChatGPT connection storage.", details: nil))
  }
}
