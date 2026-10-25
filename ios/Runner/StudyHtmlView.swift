import Flutter
import UIKit
import WebKit

final class StudyHtmlFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    StudyHtmlView(frame: frame, viewId: viewId, messenger: messenger)
  }
}

/// No page-to-native handlers, persistent website storage, scripts, or remote loads.
final class StudyHtmlView: NSObject, FlutterPlatformView, WKNavigationDelegate {
  private let webView: WKWebView
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    webView = WKWebView(frame: frame, configuration: configuration)
    channel = FlutterMethodChannel(name: "studyhub/html/\(viewId)", binaryMessenger: messenger)
    super.init()
    webView.navigationDelegate = self
    webView.accessibilityLabel = "HTML lecture notes"
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterError(code: "closed", message: "Preview closed.", details: nil)); return }
      guard call.method == "load" else { result(FlutterMethodNotImplemented); return }
      guard let html = call.arguments as? String, html.utf8.count <= 4 * 1024 * 1024 else {
        result(FlutterError(code: "invalid_html", message: "HTML notes are too large.", details: nil)); return
      }
      // Independent of the document CSP: block every network and file request.
      let rules = #"[{"trigger":{"url-filter":"^https?:"},"action":{"type":"block"}},{"trigger":{"url-filter":"^wss?:"},"action":{"type":"block"}},{"trigger":{"url-filter":"^file:"},"action":{"type":"block"}},{"trigger":{"url-filter":"^ftp:"},"action":{"type":"block"}}]"#
      WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "studyhub-static-html-v1", encodedContentRuleList: rules) { [weak self] list, _ in
        guard let self, let list else {
          result(FlutterError(code: "isolation", message: "Safe preview is unavailable.", details: nil)); return
        }
        self.webView.configuration.userContentController.add(list)
        let isolation = #"<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src 'none'; connect-src 'none'; media-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">"#
        self.webView.loadHTMLString(isolation + html, baseURL: nil)
        result(nil)
      }
    }
  }

  func view() -> UIView { webView }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    let local = navigationAction.request.url?.scheme == "about"
    decisionHandler(local && navigationAction.targetFrame?.isMainFrame == true ? .allow : .cancel)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    channel.invokeMethod("loaded", arguments: nil)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    channel.invokeMethod("failed", arguments: nil)
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    channel.invokeMethod("failed", arguments: nil)
  }
}
