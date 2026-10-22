import Flutter
import Network
import UIKit
import WebKit
import XCTest
@testable import Runner

/// Exercises raw hostile input through the real platform channel and WebKit.
/// These tests intentionally bypass Dart sanitization to validate native isolation.
final class HtmlIsolationTests: XCTestCase {
  @MainActor func testPageScriptsCannotRunWhileSVGAndMathMLRemainVisible() throws {
    let harness = try makeHarness()
    defer { harness.window.isHidden = true }
    try load("""
      <!doctype html><html><head><title>Original lecture</title>
      <script>document.title = 'SCRIPT EXECUTED';</script></head><body>
      <h1>Static learning content</h1>
      <svg id="diagram" xmlns="http://www.w3.org/2000/svg" width="200" height="100" role="img">
        <title>Energy flow</title><rect width="180" height="80" fill="steelblue"/>
        <text x="20" y="45">Energy</text>
        <script>document.title = 'SVG SCRIPT EXECUTED';</script>
      </svg>
      <math id="equation" xmlns="http://www.w3.org/1998/Math/MathML" display="block">
        <mrow><mi>E</mi><mo>=</mo><mi>m</mi><msup><mi>c</mi><mn>2</mn></msup></mrow>
      </math>
      <img src="data:image/png;base64,invalid" onerror="document.title='EVENT EXECUTED'">
      <a id="javascript-link" href="javascript:document.title='URL SCRIPT EXECUTED'">Unsafe link</a>
      </body></html>
      """, into: harness)

    XCTAssertEqual(harness.webView.title, "Original lecture")
    // App-owned inspection runs in an isolated client world; the page remains
    // unable to execute its own script. No inspection bridge exists in the app.
    let inspection = try inspect("""
      (() => {
        const svg = document.getElementById('diagram');
        const math = document.getElementById('equation');
        return {
          title: document.title,
          svgNamespace: svg.namespaceURI,
          svgVisible: svg.getBoundingClientRect().width > 0 && svg.getBoundingClientRect().height > 0,
          mathNamespace: math.namespaceURI,
          mathVisible: math.getBoundingClientRect().width > 0 && math.getBoundingClientRect().height > 0,
          equation: math.textContent
        };
      })()
      """, in: harness.webView)
    let values = try XCTUnwrap(inspection as? [String: Any])
    XCTAssertEqual(values["title"] as? String, "Original lecture")
    XCTAssertEqual(values["svgNamespace"] as? String, "http://www.w3.org/2000/svg")
    XCTAssertEqual(values["mathNamespace"] as? String, "http://www.w3.org/1998/Math/MathML")
    XCTAssertEqual(values["svgVisible"] as? Bool, true)
    XCTAssertEqual(values["mathVisible"] as? Bool, true)
    XCTAssertTrue((values["equation"] as? String ?? "").contains("E=mc2"))

    _ = try inspect("document.getElementById('javascript-link').click(); true", in: harness.webView)
    let settled = expectation(description: "Unsafe URL action settled")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
    wait(for: [settled], timeout: 2)
    XCTAssertEqual(harness.webView.title, "Original lecture")
  }

  @MainActor func testSourceRenderingMakesNoConnectionsAndBlockedNavigationSendsNoHTTP() throws {
    let listener = try NWListener(using: .tcp, on: .any)
    let ready = expectation(description: "Synthetic HTTP trap ready")
    var requests: [String] = []
    var connections: [NWConnection] = []
    listener.stateUpdateHandler = { state in
      if case .ready = state { ready.fulfill() }
    }
    listener.newConnectionHandler = { connection in
      connections.append(connection)
      connection.start(queue: .main)
      connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
        if let data, !data.isEmpty {
          requests.append(String(decoding: data, as: UTF8.self).components(separatedBy: "\r\n").first ?? "Unknown request")
        }
        connection.send(content: Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in connection.cancel() })
      }
    }
    listener.start(queue: .main)
    defer { listener.cancel(); connections.forEach { $0.cancel() } }
    wait(for: [ready], timeout: 5)
    let port = try XCTUnwrap(listener.port)
    let endpoint = "http://127.0.0.1:\(port.rawValue)"
    let harness = try makeHarness()
    defer { harness.window.isHidden = true }
    try load("""
      <!doctype html><html><head><title>Network isolated</title>
      <link rel="preconnect" href="\(endpoint)">
      <link rel="dns-prefetch" href="\(endpoint)">
      <link rel="stylesheet" href="\(endpoint)/style.css">
      <style>@import url('\(endpoint)/import.css'); body { background-image: url('\(endpoint)/background.png'); }</style>
      </head><body>
      <img src="\(endpoint)/image.png">
      <iframe src="\(endpoint)/frame"></iframe>
      <object data="\(endpoint)/object"></object>
      <svg xmlns="http://www.w3.org/2000/svg"><image href="\(endpoint)/svg.png"/></svg>
      <a id="external-link" href="\(endpoint)/navigation">Open remote document</a>
      <p>Only this local document may load.</p>
      </body></html>
      """, into: harness)
    let resourcesSettled = expectation(description: "Untrusted source resource loading settled")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { resourcesSettled.fulfill() }
    wait(for: [resourcesSettled], timeout: 2)
    XCTAssertTrue(connections.isEmpty, "Rendering source HTML must not create even speculative remote connections")
    _ = try inspect("document.getElementById('external-link').click(); true", in: harness.webView)
    // Also exercise a native-initiated request against the actual delegate;
    // no fabricated WKNavigationAction or alternate test delegate is involved.
    harness.webView.load(URLRequest(url: try XCTUnwrap(URL(string: "\(endpoint)/native-navigation"))))
    let settled = expectation(description: "Resource requests and navigation settled")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { settled.fulfill() }
    wait(for: [settled], timeout: 3)
    XCTAssertTrue(requests.isEmpty, "Untrusted HTML sent HTTP requests: \(requests)")
    XCTAssertEqual(harness.webView.title, "Network isolated")
    XCTAssertEqual(harness.webView.url?.scheme, "about")
  }

  @MainActor func testLocalFileSubresourcesCannotReadSyntheticImage() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
    let image = renderer.pngData { context in
      UIColor.red.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
    let file = directory.appendingPathComponent("synthetic.png")
    try image.write(to: file)
    let harness = try makeHarness()
    defer { harness.window.isHidden = true }
    try load("""
      <!doctype html><title>File isolated</title>
      <img id="private-file" src="\(file.absoluteString)"><p>Local file bytes stay outside the page.</p>
      """, into: harness)
    let naturalWidth = try inspect("document.getElementById('private-file').naturalWidth", in: harness.webView)
    XCTAssertEqual((naturalWidth as? NSNumber)?.intValue, 0)
    XCTAssertEqual(harness.webView.title, "File isolated")
  }

  @MainActor private func makeHarness() throws -> HtmlHarness {
    let messenger = HtmlTestMessenger()
    let platformView = StudyHtmlView(frame: CGRect(x: 0, y: 0, width: 768, height: 900), viewId: 701, messenger: messenger)
    let webView = try XCTUnwrap(platformView.view() as? WKWebView)
    let window = UIWindow(frame: webView.frame)
    let controller = UIViewController()
    controller.view = webView
    window.rootViewController = controller
    window.makeKeyAndVisible()
    return HtmlHarness(platformView: platformView, webView: webView, messenger: messenger, window: window)
  }

  @MainActor private func load(_ html: String, into harness: HtmlHarness) throws {
    let reply = expectation(description: "Native load method accepted HTML")
    let loaded = expectation(description: "Actual WebKit navigation completed")
    harness.messenger.event = { call in
      if call.method == "loaded" { loaded.fulfill() }
      if call.method == "failed" { XCTFail("WebKit could not load the isolated document") }
    }
    let handler = try XCTUnwrap(harness.messenger.handlers["studyhub/html/701"])
    let codec = FlutterStandardMethodCodec.sharedInstance()
    let data = codec.encode(FlutterMethodCall(methodName: "load", arguments: html))
    handler(data) { result in
      guard let result else { XCTFail("Native HTML load returned no envelope"); reply.fulfill(); return }
      let decoded = codec.decodeEnvelope(result)
      if let failure = decoded as? FlutterError {
        XCTFail("Native HTML load failed: \(failure.code): \(failure.message ?? "No message")")
        // End promptly with the actionable native error instead of a later timeout.
        loaded.fulfill()
      } else {
        XCTAssertNil(decoded, "Native HTML load must succeed")
      }
      reply.fulfill()
    }
    wait(for: [reply, loaded], timeout: 15)
    harness.messenger.event = nil
  }

  @MainActor private func inspect(_ expression: String, in webView: WKWebView) throws -> Any? {
    let finished = expectation(description: "App-owned isolated DOM inspection")
    var result: Result<Any, Error>?
    webView.evaluateJavaScript(expression, in: nil, in: .defaultClient) { value in
      result = value
      finished.fulfill()
    }
    wait(for: [finished], timeout: 5)
    return try XCTUnwrap(result).get()
  }
}

private struct HtmlHarness {
  // Retain the real object: WebKit's navigation delegate and channel use weak ownership.
  let platformView: StudyHtmlView
  let webView: WKWebView
  let messenger: HtmlTestMessenger
  let window: UIWindow
}

private final class HtmlTestMessenger: NSObject, FlutterBinaryMessenger {
  var handlers: [String: FlutterBinaryMessageHandler] = [:]
  var event: ((FlutterMethodCall) -> Void)?
  private var nextConnection: FlutterBinaryMessengerConnection = 0
  private var channels: [FlutterBinaryMessengerConnection: String] = [:]

  func send(onChannel channel: String, message: Data?) {
    guard let message, channel == "studyhub/html/701" else { return }
    event?(FlutterStandardMethodCodec.sharedInstance().decodeMethodCall(message))
  }

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    send(onChannel: channel, message: message)
    callback?(nil)
  }

  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
    nextConnection += 1
    handlers[channel] = handler
    channels[nextConnection] = channel
    return nextConnection
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {
    if let channel = channels.removeValue(forKey: connection) { handlers.removeValue(forKey: channel) }
  }
}
