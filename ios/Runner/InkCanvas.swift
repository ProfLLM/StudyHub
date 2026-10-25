import Flutter
import PencilKit
import UIKit

/// All stored strokes use this coordinate system regardless of the window size.
/// Resizing fits the entire native view uniformly; it never transforms PKDrawing.
struct InkCanvasGeometry {
  static let logicalWidth: CGFloat = 768
  let scale: CGFloat
  let viewport: CGSize
  let contentHeight: CGFloat

  init(viewport physicalViewport: CGSize, inkBottom: CGFloat?) {
    let width = max(physicalViewport.width, 1)
    scale = width / Self.logicalWidth
    viewport = CGSize(width: Self.logicalWidth, height: max(physicalViewport.height / scale, 1))
    // With no ink there is nowhere to scroll. Only drawing, never scrolling,
    // extends the surface by up to one blank viewport below the last mark.
    contentHeight = max(viewport.height, max(inkBottom ?? 0, 0) + viewport.height)
  }

  func clampedOffset(_ offset: CGPoint) -> CGPoint {
    CGPoint(x: 0, y: min(max(offset.y, 0), max(contentHeight - viewport.height, 0)))
  }
}

struct InkExport {
  static let tileHeight: CGFloat = 1200
  static let overlap: CGFloat = 160
  static let maximumPages = 32
  static let maximumBytes = 32 * 1024 * 1024
  static let maximumSourceBytes = 16 * 1024 * 1024

  static func rectangles(for bounds: CGRect) throws -> [CGRect] {
    if bounds.isNull || bounds.isEmpty { return [] }
    guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
      bounds.width.isFinite, bounds.height.isFinite,
      bounds.width < 4096, bounds.height < 1_000_000
    else { throw InkError.exportTooLarge }
    let rect = bounds.insetBy(dx: -24, dy: -24)
    // Avoid an unbounded allocation before applying the page limit.
    let estimatedPages = max(1, Int(ceil(max(rect.height - overlap, 0) / (tileHeight - overlap))))
    guard estimatedPages <= maximumPages else { throw InkError.exportTooLarge }
    var pages: [CGRect] = []
    var top = rect.minY
    while top < rect.maxY {
      let height = min(tileHeight, rect.maxY - top)
      pages.append(CGRect(x: rect.minX, y: top, width: rect.width, height: height))
      if top + height >= rect.maxY { break }
      top += tileHeight - overlap
    }
    return pages
  }
}

enum InkError: LocalizedError {
  case invalidDrawing
  case exportTooLarge
  case imageEncoding

  var errorDescription: String? {
    switch self {
    case .invalidDrawing:
      return "These ink notes could not be opened safely. The saved source has been preserved."
    case .exportTooLarge:
      return "These notes are too large to send in one request. Shorten the lecture or split its notes before trying again."
    case .imageEncoding:
      return "A notes image could not be created. Your editable ink is still available."
    }
  }
}

/// Independent of Flutter channels so native drawing, resizing, and export can
/// be tested with synthetic PKDrawing fixtures on an iPad simulator.
final class InkSurface: UIView, PKCanvasViewDelegate {
  let canvas = PKCanvasView()
  private let toolPicker = PKToolPicker()
  var onChanged: (() -> Void)?
  private var applyingLayout = false
  private var activeTool = false
  private var toolChanged = false
  private var loadingSource = false
  private var observedDrawing = PKDrawing()
  private(set) var changeId = 0
  private(set) var active = true
  var toolPickerVisible: Bool { toolPicker.isVisible }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .white
    clipsToBounds = true
    overrideUserInterfaceStyle = .light
    canvas.backgroundColor = .white
    canvas.isOpaque = true
    canvas.drawingPolicy = .pencilOnly
    canvas.panGestureRecognizer.minimumNumberOfTouches = 1
    canvas.tool = PKInkingTool(.pen, color: UIColor(white: 0.12, alpha: 1), width: 2.5)
    canvas.bounces = false
    canvas.alwaysBounceVertical = false
    canvas.alwaysBounceHorizontal = false
    canvas.bouncesZoom = false
    canvas.minimumZoomScale = 1
    canvas.maximumZoomScale = 1
    canvas.pinchGestureRecognizer?.isEnabled = false
    canvas.contentInset = .zero
    canvas.contentInsetAdjustmentBehavior = .never
    canvas.isDirectionalLockEnabled = true
    canvas.showsHorizontalScrollIndicator = false
    canvas.scrollsToTop = true
    canvas.delegate = self
    canvas.accessibilityIdentifier = "lecture-ink-canvas"
    canvas.accessibilityLabel = "Lecture handwriting canvas"
    canvas.accessibilityHint = "Write with Apple Pencil. Drag with a finger to scroll vertically."
    addSubview(canvas)
    toolPicker.showsDrawingPolicyControls = false
    toolPicker.addObserver(canvas)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit { toolPicker.removeObserver(canvas) }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updateToolPickerVisibility()
  }

  func setActive(_ active: Bool) {
    self.active = active
    canvas.isUserInteractionEnabled = active
    updateToolPickerVisibility()
  }

  private func updateToolPickerVisibility() {
    if active && window != nil {
      toolPicker.setVisible(true, forFirstResponder: canvas)
      canvas.becomeFirstResponder()
    } else {
      toolPicker.setVisible(false, forFirstResponder: canvas)
      canvas.resignFirstResponder()
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    updateGeometry()
  }

  var geometry: InkCanvasGeometry {
    InkCanvasGeometry(
      viewport: bounds.size,
      inkBottom: canvas.drawing.strokes.isEmpty ? nil : canvas.drawing.bounds.maxY
    )
  }

  func updateGeometry() {
    guard !applyingLayout else { return }
    applyingLayout = true
    defer { applyingLayout = false }
    let geometry = self.geometry
    let originalOffset = canvas.contentOffset
    // Canvas bounds are logical points; its transform fits those points into
    // the available physical width. PKDrawing's coordinates remain untouched.
    canvas.transform = CGAffineTransform(scaleX: geometry.scale, y: geometry.scale)
    canvas.bounds.size = geometry.viewport
    canvas.center = CGPoint(x: bounds.midX, y: bounds.midY)
    canvas.contentSize = CGSize(width: InkCanvasGeometry.logicalWidth, height: geometry.contentHeight)
    canvas.setContentOffset(geometry.clampedOffset(originalOffset), animated: false)
  }

  func loadDrawing(_ data: Data?) throws {
    let drawing: PKDrawing
    do {
      if let data, !data.isEmpty {
        guard data.count <= InkExport.maximumSourceBytes else { throw InkError.invalidDrawing }
        drawing = try PKDrawing(data: data)
      } else {
        drawing = PKDrawing()
      }
    } catch { throw InkError.invalidDrawing }
    if !drawing.strokes.isEmpty {
      let rect = drawing.bounds
      guard rect.origin.x.isFinite, rect.origin.y.isFinite,
        rect.width.isFinite, rect.height.isFinite,
        abs(rect.minX) < 1_000_000, abs(rect.minY) < 1_000_000,
        rect.width < 1_000_000, rect.height < 1_000_000
      else { throw InkError.invalidDrawing }
    }
    loadingSource = true
    canvas.drawing = drawing
    observedDrawing = drawing
    changeId = 0
    loadingSource = false
    canvas.undoManager?.removeAllActions()
    updateGeometry()
  }

  /// PKDrawing is a value type. Capture its value and transient revision before
  /// encoding/rendering, so a response cannot pair different ink revisions.
  @discardableResult
  private func observeMutation(_ source: PKDrawing? = nil) -> Bool {
    guard !loadingSource else { return false }
    let source = source ?? canvas.drawing
    guard source != observedDrawing else { return false }
    observedDrawing = source
    changeId += 1
    return true
  }

  private func notifyMutation() {
    if observeMutation() { onChanged?() }
  }

  func setFingerDrawing(_ enabled: Bool) {
    canvas.drawingPolicy = enabled ? .anyInput : .pencilOnly
    // Explicit testing mode: the very same touch cannot both ink and pan.
    // Disable Draw mode for one-finger pan; normal Pencil mode always pans.
    canvas.panGestureRecognizer.minimumNumberOfTouches = enabled ? 2 : 1
    canvas.accessibilityHint = enabled
      ? "Finger drawing is enabled. Use two fingers to pan, or switch to Pan mode."
      : "Write with Apple Pencil. Drag with a finger to scroll vertically."
  }

  func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
    activeTool = true
    toolChanged = false
  }

  func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
    activeTool = false
    updateGeometry()
    let changed = observeMutation()
    if toolChanged || changed { onChanged?() }
    toolChanged = false
  }

  func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
    updateGeometry()
    // Some PencilKit tools update their drawing after didEndUsingTool; both
    // callbacks feed one debouncer, so the final stroke is always included.
    let changed = observeMutation()
    if changed {
      if activeTool { toolChanged = true }
      else { onChanged?() }
    }
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard !applyingLayout else { return }
    let clamped = geometry.clampedOffset(scrollView.contentOffset)
    if scrollView.contentOffset != clamped {
      applyingLayout = true
      scrollView.contentOffset = clamped
      applyingLayout = false
    }
  }

  func clearDrawing() {
    guard !canvas.drawing.strokes.isEmpty else { return }
    replaceDrawing(PKDrawing())
  }

  private func replaceDrawing(_ drawing: PKDrawing) {
    let previous = canvas.drawing
    canvas.undoManager?.registerUndo(withTarget: self) { target in
      target.replaceDrawing(previous)
    }
    canvas.drawing = drawing
    updateGeometry()
    notifyMutation()
  }

  func undoDrawing() {
    canvas.undoManager?.undo()
    updateGeometry()
    notifyMutation()
  }

  func redoDrawing() {
    canvas.undoManager?.redo()
    updateGeometry()
    notifyMutation()
  }

  func snapshot() throws -> [String: Any] {
    let source = canvas.drawing
    observeMutation(source)
    return try snapshot(drawing: source, changeId: changeId)
  }

  func captureSnapshot() throws -> [String: Any] {
    let source = canvas.drawing
    observeMutation(source)
    let version = changeId
    var result = try snapshot(drawing: source, changeId: version)
    result["images"] = try exportImages(drawing: source).map { FlutterStandardTypedData(bytes: $0) }
    return result
  }

  private func snapshot(drawing: PKDrawing, changeId: Int) throws -> [String: Any] {
    let data = drawing.dataRepresentation()
    guard data.count <= InkExport.maximumSourceBytes else { throw InkError.exportTooLarge }
    let preview: Data
    if drawing.strokes.isEmpty {
      preview = try whitePNG(drawing: drawing, rect: CGRect(x: 0, y: 0, width: 1, height: 1), scale: 1)
    } else {
      let rect = drawing.bounds.insetBy(dx: -24, dy: -24)
      let scale = min(1, 1024 / max(rect.width, rect.height, 1))
      preview = try whitePNG(drawing: drawing, rect: rect, scale: scale)
    }
    guard preview.count <= InkExport.maximumSourceBytes else { throw InkError.exportTooLarge }
    return ["drawing": FlutterStandardTypedData(bytes: data), "preview": FlutterStandardTypedData(bytes: preview), "changeId": changeId]
  }

  func exportImages() throws -> [Data] {
    let source = canvas.drawing
    return try exportImages(drawing: source)
  }

  private func exportImages(drawing: PKDrawing) throws -> [Data] {
    if drawing.strokes.isEmpty { return [] }
    let rectangles = try InkExport.rectangles(for: drawing.bounds)
    var images: [Data] = []
    var totalBytes = 0
    for rect in rectangles {
      // 1536 pixels across a normal 768-point page preserves fine equations.
      let scale = min(2, 1536 / rect.width)
      let image = try whitePNG(drawing: drawing, rect: rect, scale: scale)
      totalBytes += image.count
      guard totalBytes <= InkExport.maximumBytes else { throw InkError.exportTooLarge }
      images.append(image)
    }
    return images
  }

  #if DEBUG
  /// Deterministic synthetic equation/arrow strokes enter the normal mutation
  /// boundary. No persistence or domain model is modified by this test hook.
  func seedSyntheticDrawing() {
    func stroke(_ coordinates: [CGPoint], color: UIColor) -> PKStroke {
      let points = coordinates.enumerated().map { index, location in
        PKStrokePoint(location: location, timeOffset: Double(index) * 0.03,
          size: CGSize(width: 3, height: 3), opacity: 1, force: 1,
          azimuth: 0, altitude: .pi / 2)
      }
      let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0))
      return PKStroke(ink: PKInk(.pen, color: color), path: path)
    }
    let paths: [[CGPoint]] = [
      [CGPoint(x: 65, y: 100), CGPoint(x: 100, y: 140), CGPoint(x: 140, y: 90)],
      [CGPoint(x: 170, y: 105), CGPoint(x: 220, y: 105)],
      [CGPoint(x: 170, y: 125), CGPoint(x: 220, y: 125)],
      [CGPoint(x: 260, y: 140), CGPoint(x: 260, y: 90), CGPoint(x: 290, y: 115), CGPoint(x: 320, y: 90), CGPoint(x: 320, y: 140)],
      [CGPoint(x: 80, y: 260), CGPoint(x: 350, y: 260)],
      [CGPoint(x: 315, y: 235), CGPoint(x: 350, y: 260), CGPoint(x: 315, y: 285)],
      [CGPoint(x: 400, y: 220), CGPoint(x: 570, y: 220), CGPoint(x: 570, y: 310), CGPoint(x: 400, y: 310), CGPoint(x: 400, y: 220)]
    ]
    let strokes = paths.enumerated().map { index, path in
      stroke(path, color: index < 4 ? .black : UIColor(red: 0.1, green: 0.25, blue: 0.8, alpha: 1))
    }
    replaceDrawing(PKDrawing(strokes: strokes))
  }
  #endif

  private func whitePNG(drawing: PKDrawing, rect: CGRect, scale: CGFloat) throws -> Data {
    guard rect.width > 0, rect.height > 0, scale.isFinite, scale > 0 else { throw InkError.imageEncoding }
    let image = drawing.strokes.isEmpty ? UIImage() : drawing.image(from: rect, scale: scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let size = CGSize(width: max(1, ceil(rect.width * scale)), height: max(1, ceil(rect.height * scale)))
    let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      if !drawing.strokes.isEmpty { image.draw(in: CGRect(origin: .zero, size: size)) }
    }
    guard let data = rendered.pngData() else { throw InkError.imageEncoding }
    return data
  }
}

final class InkCanvasFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    InkPlatformView(frame: frame, viewId: viewId, arguments: args, messenger: messenger)
  }
}

private final class InkPlatformView: NSObject, FlutterPlatformView {
  private let surface: InkSurface
  private let channel: FlutterMethodChannel
  private var loadError: Error?
  private var initialized = false
  private var pendingSave: DispatchWorkItem?
  private var backgroundObserver: NSObjectProtocol?

  init(frame: CGRect, viewId: Int64, arguments: Any?, messenger: FlutterBinaryMessenger) {
    surface = InkSurface(frame: frame)
    channel = FlutterMethodChannel(name: "studyhub/ink/\(viewId)", binaryMessenger: messenger)
    super.init()
    let data = (arguments as? [String: Any])?["drawing"] as? FlutterStandardTypedData
    do { try surface.loadDrawing(data?.data) }
    catch {
      loadError = error
      surface.isUserInteractionEnabled = false
    }
    surface.onChanged = { [weak self] in self?.scheduleSave() }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "inkClosed", message: "The lecture canvas has closed.", details: nil))
        return
      }
      self.handle(call, result: result)
    }
    backgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.emitSnapshot() }
  }

  deinit {
    pendingSave?.cancel()
    if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { surface }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if let loadError {
      result(FlutterError(code: "invalidInk", message: loadError.localizedDescription, details: nil))
      return
    }
    do {
      switch call.method {
      case "initialize":
        initialized = true
        result(nil)
      case "flush":
        pendingSave?.cancel()
        result(try surface.snapshot())
      case "exportImages":
        result(try surface.exportImages().map { FlutterStandardTypedData(bytes: $0) })
      case "captureSnapshot":
        // Keep autosave pending if image export fails (for example page limits).
        result(try surface.captureSnapshot())
      case "setActive":
        guard let active = call.arguments as? Bool else {
          result(FlutterError(code: "invalidInput", message: "Choose an active notes view.", details: nil))
          return
        }
        surface.setActive(active)
        result(nil)
      #if DEBUG
      case "seedSyntheticDrawing":
        surface.seedSyntheticDrawing()
        result(nil)
      #endif
      case "setFingerDrawing":
        guard let enabled = call.arguments as? Bool else {
          result(FlutterError(code: "invalidInput", message: "Choose Draw or Pan mode.", details: nil))
          return
        }
        surface.setFingerDrawing(enabled)
        result(nil)
      case "undo": surface.undoDrawing(); result(nil)
      case "redo": surface.redoDrawing(); result(nil)
      case "clear": surface.clearDrawing(); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "ink", message: error.localizedDescription, details: nil))
    }
  }

  private func scheduleSave() {
    pendingSave?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.emitSnapshot() }
    pendingSave = work
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(450), execute: work)
  }

  private func emitSnapshot() {
    pendingSave?.cancel()
    guard initialized, loadError == nil else { return }
    do { channel.invokeMethod("drawingChanged", arguments: try surface.snapshot()) }
    catch { channel.invokeMethod("inkError", arguments: error.localizedDescription) }
  }
}
