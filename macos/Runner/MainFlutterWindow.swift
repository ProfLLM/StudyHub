import Cocoa
import FlutterMacOS
import WebKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 1100, height: 760))
    self.minSize = NSSize(width: 600, height: 500)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    let htmlRegistrar = flutterViewController.registrar(forPlugin: "StudyHubHtml")
    htmlRegistrar.register(StudyHtmlFactory(messenger: htmlRegistrar.messenger), withId: "studyhub/html")
    let assignmentRegistrar = flutterViewController.registrar(forPlugin: "StudyHubAssignment")
    assignmentRegistrar.register(StudyAssignmentFactory(messenger: assignmentRegistrar.messenger), withId: "studyhub/assignment")
    ChatGptAuthBridge.register(with: flutterViewController.registrar(forPlugin: "StudyHubChatGptAuth"))

    super.awakeFromNib()
  }
}

/// An isolated static renderer. The page has no native message bridge.
final class StudyHtmlFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    StudyHtmlView(viewId: viewId, messenger: messenger)
  }
}

final class StudyHtmlView: NSView, WKNavigationDelegate {
  private let webView: WKWebView
  private let channel: FlutterMethodChannel

  init(viewId: Int64, messenger: FlutterBinaryMessenger) {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    webView = WKWebView(frame: .zero, configuration: configuration)
    channel = FlutterMethodChannel(name: "studyhub/html/\(viewId)", binaryMessenger: messenger)
    super.init(frame: .zero)
    webView.navigationDelegate = self
    webView.setAccessibilityLabel("HTML lecture notes")
    webView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(webView)
    NSLayoutConstraint.activate([
      webView.leadingAnchor.constraint(equalTo: leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: trailingAnchor),
      webView.topAnchor.constraint(equalTo: topAnchor),
      webView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterError(code: "closed", message: "Preview closed.", details: nil)); return }
      guard call.method == "load" else { result(FlutterMethodNotImplemented); return }
      guard let html = call.arguments as? String, html.utf8.count <= 4 * 1024 * 1024 else {
        result(FlutterError(code: "invalid_html", message: "HTML notes are too large.", details: nil)); return
      }
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

  required init?(coder: NSCoder) { fatalError("Use init(viewId:messenger:)") }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    let local = navigationAction.request.url?.scheme == "about"
    decisionHandler(local && navigationAction.targetFrame?.isMainFrame == true ? .allow : .cancel)
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { channel.invokeMethod("loaded", arguments: nil) }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { channel.invokeMethod("failed", arguments: nil) }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { channel.invokeMethod("failed", arguments: nil) }
}
