#if os(iOS)
import Flutter
import UIKit
#else
import FlutterMacOS
import Cocoa
#endif
import WebKit

/// The generated page is an opaque sandboxed child of an app-owned host.
/// Only main-frame messages reach Flutter; there are no credentials, network
/// capabilities, file access, provider calls or library operations on this bridge.
final class StudyAssignmentRenderer: NSObject, WKNavigationDelegate {
  let webView: WKWebView
  private let channel: FlutterMethodChannel
  private var loaded = false

  init(viewId: Int64, messenger: FlutterBinaryMessenger) {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    // URL rules and CSP do not cover WebRTC's ICE sockets or DNS. Use the
    // public per-view Lockdown setting, which removes WebRTC in all frames.
    // Older systems must never load generated scripts without that boundary.
    if #available(iOS 16.0, macOS 13.0, *) {
      config.defaultWebpagePreferences.isLockdownModeEnabled = true
      config.defaultWebpagePreferences.allowsContentJavaScript = true
    } else {
      config.defaultWebpagePreferences.allowsContentJavaScript = false
    }
    config.preferences.javaScriptCanOpenWindowsAutomatically = false
    webView = WKWebView(frame: .zero, configuration: config)
    channel = FlutterMethodChannel(name: "studyhub/assignment/\(viewId)", binaryMessenger: messenger)
    super.init()
    config.userContentController.add(AssignmentMessageHandler(self), name: "assignment")
    webView.navigationDelegate = self
    #if os(iOS)
    webView.accessibilityLabel = "Interactive lecture assignment"
    #else
    webView.setAccessibilityLabel("Interactive lecture assignment")
    #endif
    channel.setMethodCallHandler { [weak self] call, reply in
      guard let self else { reply(FlutterError(code: "closed", message: "Assignment closed.", details: nil)); return }
      if call.method == "flush" {
        guard self.loaded else { reply(FlutterError(code: "loading", message: "Wait for the assignment to load.", details: nil)); return }
        self.webView.callAsyncJavaScript("return await window.studyhubFlush();", arguments: [:], in: nil, in: .page) { result in
          switch result {
          case .success(let value): reply(value)
          case .failure: reply(FlutterError(code: "snapshot", message: "Could not capture assignment answers. Please retry.", details: nil))
          }
        }
        return
      }
      guard call.method == "load", let html = call.arguments as? String, html.utf8.count <= 16 * 1024 * 1024 else {
        reply(FlutterError(code: "document", message: "Invalid assignment document.", details: nil)); return
      }
      guard #available(iOS 16.0, macOS 13.0, *) else {
        reply(FlutterError(code: "unsupported_os", message: "Interactive assignments require iPadOS 16 or macOS 13 or later.", details: nil)); return
      }
      self.loaded = false
      // Block every URL scheme, allowing only in-memory documents and data
      // images. Navigation below independently rejects data URLs and new windows.
      let rules = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}},{"trigger":{"url-filter":"^about:"},"action":{"type":"ignore-previous-rules"}},{"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}}]"#
      WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "studyhub-assignment-v1", encodedContentRuleList: rules) { [weak self] list, _ in
        guard let self, let list else { reply(FlutterError(code: "isolation", message: "Assignment isolation unavailable.", details: nil)); return }
        self.webView.configuration.userContentController.add(list)
        // Defense in depth in addition to both packaged document CSPs.
        let isolation = #"<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; frame-src about:; connect-src 'none'; font-src 'none'; media-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; worker-src 'none'">"#
        self.webView.loadHTMLString(isolation + html, baseURL: nil)
        reply(nil)
      }
    }
  }

  fileprivate func receive(_ message: WKScriptMessage) {
    guard message.frameInfo.isMainFrame, message.webView === webView,
      let json = message.body as? String, json.utf8.count <= 6 * 1024 * 1024,
      let data = json.data(using: .utf8),
      let packet = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let type = packet["type"] as? String else { return }
    if type == "ready" { loaded = true; channel.invokeMethod("ready", arguments: nil) }
    if type == "state", loaded, let answers = packet["answers"] as? String,
      answers.utf8.count <= 4 * 1024 * 1024 {
      channel.invokeMethod("answers", arguments: answers)
    }
    if type == "error" { channel.invokeMethod("failed", arguments: "Assignment answers could not be saved. Retry or reduce the size of a sketch.") }
  }

  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    let url = action.request.url?.absoluteString
    decisionHandler(action.targetFrame != nil && action.navigationType == .other &&
      (url == "about:blank" || url == "about:srcdoc") ? .allow : .cancel)
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { channel.invokeMethod("failed", arguments: "The assignment could not open. Saved answers are preserved.") }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { channel.invokeMethod("failed", arguments: "The assignment could not open. Saved answers are preserved.") }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    loaded = false
    channel.invokeMethod("failed", arguments: "The assignment stopped responding. Reopen it to restore saved answers.")
  }
  deinit { webView.stopLoading(); webView.configuration.userContentController.removeScriptMessageHandler(forName: "assignment") }
}

private final class AssignmentMessageHandler: NSObject, WKScriptMessageHandler {
  weak var owner: StudyAssignmentRenderer?
  init(_ owner: StudyAssignmentRenderer) { self.owner = owner }
  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) { owner?.receive(message) }
}

#if os(iOS)
final class StudyAssignmentFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    StudyAssignmentView(viewId: viewId, messenger: messenger)
  }
}
final class StudyAssignmentView: NSObject, FlutterPlatformView {
  let renderer: StudyAssignmentRenderer
  init(viewId: Int64, messenger: FlutterBinaryMessenger) { renderer = StudyAssignmentRenderer(viewId: viewId, messenger: messenger) }
  func view() -> UIView { renderer.webView }
}
#else
final class StudyAssignmentFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    StudyAssignmentView(viewId: viewId, messenger: messenger)
  }
}
final class StudyAssignmentView: NSView {
  let renderer: StudyAssignmentRenderer
  init(viewId: Int64, messenger: FlutterBinaryMessenger) {
    renderer = StudyAssignmentRenderer(viewId: viewId, messenger: messenger)
    super.init(frame: .zero)
    let web = renderer.webView
    web.translatesAutoresizingMaskIntoConstraints = false
    addSubview(web)
    NSLayoutConstraint.activate([web.leadingAnchor.constraint(equalTo: leadingAnchor),web.trailingAnchor.constraint(equalTo: trailingAnchor),web.topAnchor.constraint(equalTo: topAnchor),web.bottomAnchor.constraint(equalTo: bottomAnchor)])
  }
  required init?(coder: NSCoder) { fatalError("Use init(viewId:messenger:)") }
}
#endif
