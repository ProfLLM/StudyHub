#if os(macOS)
import Foundation
import Security

/// Local macOS login Keychain. Explicit caller-only ACLs are checked before
/// accessing existing items; other apps' or widened records are never adopted.
/// This intentionally has no data-protection fallback or provisioning need.
struct MacProviderKeychain {
  private static let operationQueue = DispatchQueue(label: "com.studyhub.provider-keychain", qos: .userInitiated)
  private static let operationLock = NSLock()
  private let service: String
  private let keys: Set<String>
  private let maximumBytes: Int

  init(service: String, keys: Set<String>, maximumBytes: Int = 64 * 1024) {
    self.service = service
    self.keys = keys
    self.maximumBytes = maximumBytes
  }

  /// Both Flutter bridges share this executor. OS Keychain work stays off the
  /// UI thread; each success or failure is delivered exactly once on main.
  static func perform(_ action: @escaping () throws -> Any?,
    completion: @escaping (Result<Any?, Error>) -> Void) {
    operationQueue.async {
      let outcome = Result { try action() }
      DispatchQueue.main.async { completion(outcome) }
    }
  }

  func read(_ key: String) throws -> String? {
    try withoutPrompts {
      guard let item = try findOwnedItem(key) else { return nil }
      return try string(from: readData(item))
    }
  }

  func write(_ key: String, value: String) throws {
    let data = Data(value.utf8)
    guard !data.isEmpty, data.count <= maximumBytes else { throw StorageError.unavailable }
    try withoutPrompts {
      if let item = try findOwnedItem(key) {
        // The OS must authorize the current code identity before any update.
        // Work on the validated exact reference, never a second name lookup.
        _ = try readData(item)
        let status = data.withUnsafeBytes {
          SecKeychainItemModifyAttributesAndData(item, nil, UInt32(data.count), $0.baseAddress)
        }
        guard status == errSecSuccess else { throw StorageError.unavailable }
      } else {
        var addition = try query(key)
        var access: SecAccess?
        guard SecAccessCreate("StudyHub provider connection" as CFString, nil, &access) == errSecSuccess,
          let access else { throw StorageError.unavailable }
        addition[kSecAttrAccess as String] = access
        addition[kSecValueData as String] = data
        // A duplicate appearing after the lookup fails rather than overwriting.
        guard SecItemAdd(addition as CFDictionary, nil) == errSecSuccess else { throw StorageError.unavailable }
      }
    }
  }

  func delete(_ key: String) throws {
    try withoutPrompts {
      guard let item = try findOwnedItem(key) else { return }
      _ = try readData(item)
      guard SecKeychainItemDelete(item) == errSecSuccess else { throw StorageError.unavailable }
    }
  }

  private func query(_ key: String) throws -> [String: Any] {
    guard keys.contains(key) else { throw StorageError.unavailable }
    return [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service, kSecAttrAccount as String: key,
      kSecAttrSynchronizable as String: false,
      kSecUseDataProtectionKeychain as String: false]
  }

  private func findOwnedItem(_ key: String) throws -> SecKeychainItem? {
    var query = try query(key)
    query[kSecReturnRef as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitAll
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let items = result as? [SecKeychainItem], items.count == 1 else {
      throw StorageError.unavailable
    }
    let item = items[0]
    var access: SecAccess?
    guard SecKeychainItemCopyAccess(item, &access) == errSecSuccess, let access else {
      throw StorageError.unavailable
    }
    try Self.validateCallingAppOnly(access)
    return item
  }

  /// Inspect only ACL metadata, never secret data. Any sensitive allow-all or
  /// foreign-app entry makes the record unusable, even if another entry is ours.
  static func validateCallingAppOnly(_ access: SecAccess) throws {
    var current: SecTrustedApplication?
    guard SecTrustedApplicationCreateFromPath(nil, &current) == errSecSuccess, let current else {
      throw StorageError.unavailable
    }
    let currentData = try trustedData(current)
    let decrypt = SecAccessCopyMatchingACLList(access, kSecACLAuthorizationDecrypt) as? [SecACL] ?? []
    guard !decrypt.isEmpty else { throw StorageError.unavailable }
    let any = SecAccessCopyMatchingACLList(access, kSecACLAuthorizationAny) as? [SecACL] ?? []
    let owners = SecAccessCopyMatchingACLList(access, kSecACLAuthorizationChangeACL) as? [SecACL] ?? []
    guard !owners.isEmpty else { throw StorageError.unavailable }
    for (acl, owner) in (decrypt + any).map({ ($0, false) }) + owners.map({ ($0, true) }) {
      var applications: CFArray?
      var description: CFString?
      var selector = SecKeychainPromptSelector()
      guard SecACLCopyContents(acl, &applications, &description, &selector) == errSecSuccess,
        let trusted = applications as? [SecTrustedApplication] else { throw StorageError.unavailable }
      // The default owner ACL has no trusted apps and requires user approval;
      // this helper disables that UI. nil would mean every app and is rejected.
      if owner && trusted.isEmpty { continue }
      guard trusted.count == 1, try trustedData(trusted[0]) == currentData else {
        throw StorageError.unavailable
      }
    }
  }

  private static func trustedData(_ application: SecTrustedApplication) throws -> Data {
    var result: CFData?
    guard SecTrustedApplicationCopyData(application, &result) == errSecSuccess, let result else {
      throw StorageError.unavailable
    }
    return result as Data
  }

  private func readData(_ item: SecKeychainItem) throws -> Data {
    var length: UInt32 = 0
    var bytes: UnsafeMutableRawPointer?
    guard SecKeychainItemCopyAttributesAndData(item, nil, nil, nil, &length, &bytes) == errSecSuccess else {
      throw StorageError.unavailable
    }
    defer { SecKeychainItemFreeAttributesAndData(nil, bytes) }
    guard length <= maximumBytes, let bytes else { throw StorageError.unavailable }
    return Data(bytes: bytes, count: Int(length))
  }

  private func string(from data: Data) throws -> String {
    guard let result = String(data: data, encoding: .utf8) else { throw StorageError.unavailable }
    return result
  }

  private func withoutPrompts<T>(_ action: () throws -> T) throws -> T {
    Self.operationLock.lock()
    defer { Self.operationLock.unlock() }
    var allowed: DarwinBoolean = false
    guard SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess,
      SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { throw StorageError.unavailable }
    defer { SecKeychainSetUserInteractionAllowed(allowed.boolValue) }
    return try action()
  }

  enum StorageError: LocalizedError {
    case unavailable
    var errorDescription: String? {
      "Could not access StudyHub's local Keychain connection. Unlock the login Keychain. If the app's identity changed, disconnect using the original signed app, or remove only the matching com.studyhub provider entry in Keychain Access, then reconnect. Entries with unexpected permissions are not replaced."
    }
  }
}
#endif
