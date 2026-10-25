#if os(macOS)
import Foundation
import Security
import XCTest
@testable import StudyHub

/// Every OS item uses a fresh UUID service and disposable fake values. These
/// tests never inspect either provider's real credential namespace.
final class MacProviderKeychainTests: XCTestCase {
  func testSharedExecutorRunsActualKeychainOffMainAndCompletesOnceOnMain() throws {
    try withFixture { fixture in
      let completed = expectation(description: "Success and failure each complete once")
      completed.expectedFulfillmentCount = 2
      completed.assertForOverFulfill = true
      var successes = 0
      var failures = 0
      MacProviderKeychain.perform({
        XCTAssertFalse(Thread.isMainThread)
        try fixture.store.write(fixture.key, value: fixture.value)
        return try fixture.store.read(fixture.key)
      }, completion: { result in
        XCTAssertTrue(Thread.isMainThread)
        successes += 1
        switch result {
        case .success(let value): XCTAssertEqual(value as? String, fixture.value)
        case .failure(let error): XCTFail("Disposable fixture failed: \(error)")
        }
        completed.fulfill()
      })
      MacProviderKeychain.perform({
        XCTAssertFalse(Thread.isMainThread)
        return try fixture.store.read("unrelated.secret")
      }, completion: { result in
        XCTAssertTrue(Thread.isMainThread)
        failures += 1
        if case .success = result { XCTFail("Invalid key unexpectedly succeeded") }
        completed.fulfill()
      })
      wait(for: [completed], timeout: 5)
      XCTAssertEqual(successes, 1)
      XCTAssertEqual(failures, 1)
    }
  }

  func testActualLoginKeychainRoundTripAndStoredCallerOnlyACL() throws {
    try withFixture { fixture in
      let store = fixture.store
      XCTAssertNil(try store.read(fixture.key))
      try store.write(fixture.key, value: "disposable synthetic session")
      let item = try fixture.item()
      var access: SecAccess?
      XCTAssertEqual(SecKeychainItemCopyAccess(item, &access), errSecSuccess)
      try MacProviderKeychain.validateCallingAppOnly(XCTUnwrap(access))
      XCTAssertEqual(try store.read(fixture.key), "disposable synthetic session")
      try store.write(fixture.key, value: "updated disposable synthetic session")
      XCTAssertEqual(try store.read(fixture.key), "updated disposable synthetic session")
      try store.delete(fixture.key)
      XCTAssertNil(try store.read(fixture.key))
      try store.delete(fixture.key)
    }
  }

  func testActualAllowAllRecordCannotBeReadOverwrittenOrDeleted() throws {
    try withFixture { fixture in
      let access = try callingAppAccess()
      let decrypt = try XCTUnwrap(SecAccessCopyMatchingACLList(access, kSecACLAuthorizationDecrypt) as? [SecACL])
      for acl in decrypt {
        XCTAssertEqual(SecACLSetContents(acl, nil, "Disposable widened fixture" as CFString,
          SecKeychainPromptSelector()), errSecSuccess)
      }
      try fixture.add(access: access)
      XCTAssertThrowsError(try fixture.store.read(fixture.key))
      XCTAssertThrowsError(try fixture.store.write(fixture.key, value: "must never be stored"))
      XCTAssertThrowsError(try fixture.store.delete(fixture.key))
      XCTAssertEqual(try fixture.rawValue(), fixture.value)
    }
  }

  func testActualAdditionalForeignTrustedAppIsRejectedWithoutReplacingSource() throws {
    try withFixture { fixture in
      var current: SecTrustedApplication?
      var foreign: SecTrustedApplication?
      XCTAssertEqual(SecTrustedApplicationCreateFromPath(nil, &current), errSecSuccess)
      XCTAssertEqual(SecTrustedApplicationCreateFromPath("/usr/bin/true", &foreign), errSecSuccess)
      var access: SecAccess?
      XCTAssertEqual(SecAccessCreate("Disposable foreign fixture" as CFString,
        [try XCTUnwrap(current), try XCTUnwrap(foreign)] as CFArray, &access), errSecSuccess)
      try fixture.add(access: XCTUnwrap(access))
      XCTAssertThrowsError(try fixture.store.read(fixture.key))
      XCTAssertThrowsError(try fixture.store.write(fixture.key, value: "must never be stored"))
      XCTAssertThrowsError(try fixture.store.delete(fixture.key))
      XCTAssertEqual(try fixture.rawValue(), fixture.value)
    }
  }

  func testForeignOnlyAndMissingTrustedAppACLsFailClosed() throws {
    var foreign: SecTrustedApplication?
    XCTAssertEqual(SecTrustedApplicationCreateFromPath("/usr/bin/true", &foreign), errSecSuccess)
    for applications in [[try XCTUnwrap(foreign)], []] {
      var access: SecAccess?
      XCTAssertEqual(SecAccessCreate("Disposable ACL only" as CFString,
        applications as CFArray, &access), errSecSuccess)
      XCTAssertThrowsError(try MacProviderKeychain.validateCallingAppOnly(XCTUnwrap(access)))
    }
  }

  func testAnAdditionalAllowAllAuthorizationCannotBypassNarrowDecryptACL() throws {
    let access = try callingAppAccess()
    var extra: SecACL?
    XCTAssertEqual(SecACLCreateWithSimpleContents(access, nil, "Disposable ACL only" as CFString,
      SecKeychainPromptSelector(), &extra), errSecSuccess)
    XCTAssertEqual(SecACLUpdateAuthorizations(try XCTUnwrap(extra),
      [kSecACLAuthorizationAny] as CFArray), errSecSuccess)
    XCTAssertThrowsError(try MacProviderKeychain.validateCallingAppOnly(access))
  }

  func testInvalidKeySizeAndMalformedUTF8FailClosed() throws {
    try withFixture { fixture in
      XCTAssertThrowsError(try fixture.store.read("unrelated.secret"))
      XCTAssertThrowsError(try fixture.store.write("unrelated.secret", value: "synthetic"))
      XCTAssertThrowsError(try fixture.store.delete("unrelated.secret"))
      XCTAssertThrowsError(try fixture.store.write(fixture.key, value: ""))
      XCTAssertThrowsError(try fixture.store.write(fixture.key,
        value: String(repeating: "x", count: 64 * 1024 + 1)))
      XCTAssertNil(try fixture.store.read(fixture.key))
      try fixture.add(access: callingAppAccess(), data: Data([0xff, 0xff]))
      XCTAssertThrowsError(try fixture.store.read(fixture.key))
    }
  }

  private func callingAppAccess() throws -> SecAccess {
    var access: SecAccess?
    XCTAssertEqual(SecAccessCreate("Disposable StudyHub fixture" as CFString, nil, &access), errSecSuccess)
    return try XCTUnwrap(access)
  }

  private func withFixture(_ action: (Fixture) throws -> Void) throws {
    var allowed: DarwinBoolean = false
    XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&allowed), errSecSuccess)
    XCTAssertEqual(SecKeychainSetUserInteractionAllowed(false), errSecSuccess)
    defer { SecKeychainSetUserInteractionAllowed(allowed.boolValue) }
    let fixture = Fixture()
    defer {
      let status = SecItemDelete(fixture.query as CFDictionary)
      XCTAssertTrue(status == errSecSuccess || status == errSecItemNotFound,
        "Exact synthetic fixture cleanup failed with status \(status)")
    }
    try action(fixture)
  }

  private struct Fixture {
    let service = "com.studyhub.test." + UUID().uuidString.lowercased()
    let key = "synthetic.session"
    let value = "disposable original fixture"
    var store: MacProviderKeychain { MacProviderKeychain(service: service, keys: [key]) }
    var query: [String: Any] {
      [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
        kSecAttrAccount as String: key, kSecUseDataProtectionKeychain as String: false,
        kSecAttrSynchronizable as String: false]
    }
    func add(access: SecAccess, data: Data? = nil) throws {
      var query = self.query
      query[kSecAttrAccess as String] = access
      query[kSecValueData as String] = data ?? Data(value.utf8)
      XCTAssertEqual(SecItemAdd(query as CFDictionary, nil), errSecSuccess)
    }
    func item() throws -> SecKeychainItem {
      var query = self.query
      query[kSecReturnRef as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var result: CFTypeRef?
      XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
      return try XCTUnwrap(result) as! SecKeychainItem
    }
    func rawValue() throws -> String {
      var query = self.query
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var result: CFTypeRef?
      XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
      return try XCTUnwrap(String(data: XCTUnwrap(result as? Data), encoding: .utf8))
    }
  }
}
#endif
