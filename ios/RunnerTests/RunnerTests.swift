import Flutter
import PencilKit
import UIKit
import XCTest
@testable import Runner

/// Synthetic input validates our geometry/source/export boundary. It does not
/// simulate Pencil pressure, latency, or palm rejection on physical hardware.
final class RunnerTests: XCTestCase {
  func testEmptyCanvasCannotScroll() {
    let geometry = InkCanvasGeometry(viewport: CGSize(width: 768, height: 900), inkBottom: nil)
    XCTAssertEqual(geometry.contentHeight, 900)
    XCTAssertEqual(geometry.clampedOffset(CGPoint(x: 80, y: 4000)), .zero)
    XCTAssertEqual(geometry.clampedOffset(CGPoint(x: -100, y: -50)), .zero)
  }

  func testDrawingLeavesExactlyOneBlankViewportAndOffsetsCannotExpandIt() {
    let geometry = InkCanvasGeometry(viewport: CGSize(width: 768, height: 900), inkBottom: 1700)
    XCTAssertEqual(geometry.contentHeight, 2600)
    for attemptedY in [CGFloat(-1_000_000), 0, 500, 1700, 1_000_000] {
      let offset = geometry.clampedOffset(CGPoint(x: 900, y: attemptedY))
      XCTAssertEqual(offset.x, 0)
      XCTAssertGreaterThanOrEqual(offset.y, 0)
      XCTAssertLessThanOrEqual(offset.y, 1700)
      XCTAssertEqual(geometry.contentHeight, 2600)
    }
    XCTAssertEqual(geometry.clampedOffset(CGPoint(x: 10, y: 1_000_000)).y, 1700)
  }

  func testResizeChangesOnlyPresentationAndBlankViewport() {
    let portrait = InkCanvasGeometry(viewport: CGSize(width: 768, height: 1000), inkBottom: 600)
    let landscape = InkCanvasGeometry(viewport: CGSize(width: 1024, height: 600), inkBottom: 600)
    let split = InkCanvasGeometry(viewport: CGSize(width: 384, height: 1000), inkBottom: 600)
    XCTAssertEqual(portrait.viewport.width, 768)
    XCTAssertEqual(landscape.viewport.width, 768)
    XCTAssertEqual(split.viewport.width, 768)
    XCTAssertEqual(landscape.scale, 1024 / 768, accuracy: 0.00001)
    XCTAssertEqual(split.scale, 0.5)
    for geometry in [portrait, landscape, split] {
      XCTAssertEqual(geometry.contentHeight - geometry.viewport.height, 600, accuracy: 0.00001)
    }
  }

  @MainActor func testNativeResizeDoesNotMoveStrokeCoordinatesOrPermitSidewaysScrolling() throws {
    let surface = InkSurface(frame: CGRect(x: 0, y: 0, width: 768, height: 900))
    let source = drawing(from: CGPoint(x: 80, y: 90), to: CGPoint(x: 600, y: 1600))
    try surface.loadDrawing(source.dataRepresentation())
    surface.layoutIfNeeded()
    surface.canvas.contentOffset = CGPoint(x: 500, y: 100_000)
    surface.scrollViewDidScroll(surface.canvas)
    XCTAssertEqual(surface.canvas.contentOffset.x, 0)
    XCTAssertEqual(surface.canvas.contentOffset.y, source.bounds.maxY, accuracy: 0.001)
    for size in [CGSize(width: 1024, height: 600), CGSize(width: 384, height: 1000)] {
      surface.frame.size = size
      surface.layoutIfNeeded()
      XCTAssertEqual(surface.canvas.drawing.bounds, source.bounds)
      XCTAssertEqual(surface.canvas.drawing.strokes[0].path[0].location, CGPoint(x: 80, y: 90))
      XCTAssertEqual(surface.canvas.contentSize.width, 768)
      XCTAssertEqual(surface.canvas.contentOffset.x, 0)
      XCTAssertEqual(surface.canvas.zoomScale, 1)
      XCTAssertFalse(surface.canvas.bounces)
    }
  }

  @MainActor func testErasingLastStrokeRemovesExtraScrollAndClampsOffset() throws {
    let surface = InkSurface(frame: CGRect(x: 0, y: 0, width: 768, height: 900))
    try surface.loadDrawing(drawing(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 400, y: 2000)).dataRepresentation())
    surface.layoutIfNeeded()
    surface.canvas.contentOffset.y = 1800
    surface.clearDrawing()
    XCTAssertTrue(surface.canvas.drawing.strokes.isEmpty)
    XCTAssertEqual(surface.canvas.contentOffset, .zero)
    XCTAssertEqual(surface.canvas.contentSize.height, 900)
    XCTAssertTrue(try surface.exportImages().isEmpty)
  }

  @MainActor func testSourceRoundTripPreviewAndInvalidLoadPreserveExistingSource() throws {
    let surface = InkSurface(frame: CGRect(x: 0, y: 0, width: 768, height: 900))
    let source = drawing(from: CGPoint(x: 30, y: 40), to: CGPoint(x: 710, y: 1800))
    try surface.loadDrawing(source.dataRepresentation())
    let snapshot = try surface.snapshot()
    let data = try XCTUnwrap(snapshot["drawing"] as? FlutterStandardTypedData).data
    let preview = try XCTUnwrap(snapshot["preview"] as? FlutterStandardTypedData).data
    let restored = try PKDrawing(data: data)
    XCTAssertEqual(restored.bounds, source.bounds)
    XCTAssertEqual(restored.strokes.count, 1)
    let thumbnail = try XCTUnwrap(UIImage(data: preview))
    XCTAssertLessThanOrEqual(max(thumbnail.size.width, thumbnail.size.height), 1024)
    XCTAssertThrowsError(try surface.loadDrawing(Data("invalid ink".utf8)))
    XCTAssertEqual(surface.canvas.drawing.bounds, source.bounds)
  }

  @MainActor func testClearUndoRedoRetainsOriginalEditableSource() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 768, height: 900))
    let controller = UIViewController()
    let surface = InkSurface(frame: window.bounds)
    controller.view = surface
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    let source = drawing(from: CGPoint(x: 40, y: 50), to: CGPoint(x: 500, y: 800))
    try surface.loadDrawing(source.dataRepresentation())
    XCTAssertNotNil(surface.canvas.undoManager)
    surface.clearDrawing()
    XCTAssertTrue(surface.canvas.drawing.strokes.isEmpty)
    surface.undoDrawing()
    XCTAssertEqual(surface.canvas.drawing.bounds, source.bounds)
    surface.redoDrawing()
    XCTAssertTrue(surface.canvas.drawing.strokes.isEmpty)
  }

  @MainActor func testFingerModeIsExplicitAndPencilModeRetainsFingerPan() {
    let surface = InkSurface(frame: CGRect(x: 0, y: 0, width: 768, height: 900))
    XCTAssertEqual(surface.canvas.drawingPolicy, .pencilOnly)
    surface.setFingerDrawing(true)
    XCTAssertEqual(surface.canvas.drawingPolicy, .anyInput)
    XCTAssertEqual(surface.canvas.panGestureRecognizer.minimumNumberOfTouches, 2)
    surface.setFingerDrawing(false)
    XCTAssertEqual(surface.canvas.drawingPolicy, .pencilOnly)
    XCTAssertEqual(surface.canvas.panGestureRecognizer.minimumNumberOfTouches, 1)
  }

  func testExportTilesAreOrderedCroppedAndOverlap() throws {
    let source = CGRect(x: 20, y: 120, width: 700, height: 3000)
    let pages = try InkExport.rectangles(for: source)
    XCTAssertEqual(pages.count, 3)
    XCTAssertEqual(pages.first?.minY, source.minY - 24)
    XCTAssertEqual(pages.last?.maxY, source.maxY + 24)
    XCTAssertEqual(pages.first?.minX, source.minX - 24)
    for index in 1..<pages.count {
      XCTAssertGreaterThan(pages[index].minY, pages[index - 1].minY)
      XCTAssertEqual(pages[index - 1].maxY - pages[index].minY, InkExport.overlap)
    }
    XCTAssertEqual(try InkExport.rectangles(for: .null).count, 0)
    XCTAssertThrowsError(try InkExport.rectangles(for: CGRect(x: 0, y: 0, width: 700, height: 100_000)))
    XCTAssertThrowsError(try InkExport.rectangles(for: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10)))
  }

  @MainActor func testExportPNGsIncludeAllPagesWithOpaqueWhiteBackground() throws {
    let surface = InkSurface(frame: CGRect(x: 0, y: 0, width: 768, height: 900))
    let source = drawing(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 650, y: 3000))
    try surface.loadDrawing(source.dataRepresentation())
    let images = try surface.exportImages()
    XCTAssertEqual(images.count, 3)
    for data in images {
      let image = try XCTUnwrap(UIImage(data: data))
      XCTAssertGreaterThan(image.size.width, 1000)
      XCTAssertLessThanOrEqual(image.size.width, 1536)
      XCTAssertLessThanOrEqual(image.size.height, 2400)
      let cgImage = try XCTUnwrap(image.cgImage)
      XCTAssertTrue(cgImage.alphaInfo == .none || cgImage.alphaInfo == .noneSkipLast || cgImage.alphaInfo == .noneSkipFirst)
    }
    XCTAssertEqual(surface.canvas.drawing.bounds, source.bounds, "Export cannot replace editable ink")
  }

  @MainActor func testAtomicSnapshotKeepsMatchingSourceImagesAndMutationId() throws {
    let surface = InkSurface(frame: CGRect(x: 0, y: 0, width: 768, height: 900))
    let source = drawing(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 650, y: 3000))
    try surface.loadDrawing(source.dataRepresentation())
    let captured = try surface.captureSnapshot()
    XCTAssertEqual(captured["changeId"] as? Int, 0)
    let data = try XCTUnwrap(captured["drawing"] as? FlutterStandardTypedData).data
    let restored = try PKDrawing(data: data)
    let images = try XCTUnwrap(captured["images"] as? [FlutterStandardTypedData])
    XCTAssertEqual(images.count, try InkExport.rectangles(for: restored.bounds).count)
    XCTAssertEqual(images.count, 3)
    surface.clearDrawing()
    XCTAssertEqual(surface.changeId, 1)
    XCTAssertEqual(restored.bounds, source.bounds, "A later clear cannot mutate an already captured value")
    XCTAssertEqual(captured["changeId"] as? Int, 0)
    let empty = try surface.captureSnapshot()
    XCTAssertEqual(empty["changeId"] as? Int, 1)
    XCTAssertTrue(try XCTUnwrap(empty["images"] as? [FlutterStandardTypedData]).isEmpty)
    let preview = try XCTUnwrap(empty["preview"] as? FlutterStandardTypedData).data
    XCTAssertEqual(try XCTUnwrap(UIImage(data: preview)).size, CGSize(width: 1, height: 1))
    XCTAssertLessThan(data.count, InkExport.maximumSourceBytes)
  }

  @MainActor func testMutationCounterDoesNotCountLoadResizeExportOrDuplicateCallbacks() throws {
    let surface = InkSurface(frame: CGRect(x: 0, y: 0, width: 768, height: 900))
    try surface.loadDrawing(drawing(from: CGPoint(x: 30, y: 40), to: CGPoint(x: 400, y: 800)).dataRepresentation())
    var changes = 0
    surface.onChanged = { changes += 1 }
    surface.canvasViewDrawingDidChange(surface.canvas)
    surface.frame.size = CGSize(width: 384, height: 600)
    surface.layoutIfNeeded()
    surface.setFingerDrawing(true)
    surface.setActive(false)
    _ = try surface.snapshot()
    _ = try surface.exportImages()
    _ = try surface.captureSnapshot()
    XCTAssertEqual(surface.changeId, 0)
    XCTAssertEqual(changes, 0)
    surface.canvas.drawing = drawing(from: CGPoint(x: 90, y: 100), to: CGPoint(x: 600, y: 1200))
    surface.canvasViewDrawingDidChange(surface.canvas)
    XCTAssertEqual(surface.changeId, 1)
    surface.canvasViewDrawingDidChange(surface.canvas)
    surface.canvasViewDidEndUsingTool(surface.canvas)
    _ = try surface.snapshot()
    XCTAssertEqual(surface.changeId, 1)
    surface.clearDrawing()
    XCTAssertEqual(surface.changeId, 2)
    surface.clearDrawing()
    XCTAssertEqual(surface.changeId, 2)
  }

  @MainActor func testInactiveCanvasHidesToolPickerAndResignsInput() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 768, height: 900))
    let controller = UIViewController()
    let surface = InkSurface(frame: window.bounds)
    controller.view = surface
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    surface.setActive(false)
    XCTAssertFalse(surface.active)
    XCTAssertFalse(surface.canvas.isFirstResponder)
    XCTAssertFalse(surface.canvas.isUserInteractionEnabled)
    XCTAssertFalse(surface.toolPickerVisible)
    surface.setActive(true)
    XCTAssertTrue(surface.active)
    XCTAssertTrue(surface.canvas.isFirstResponder)
    XCTAssertTrue(surface.canvas.isUserInteractionEnabled)
  }

  #if DEBUG
  @MainActor func testDebugSeedUsesNormalMutationAndExportBoundary() throws {
    let surface = InkSurface(frame: CGRect(x: 0, y: 0, width: 768, height: 900))
    try surface.loadDrawing(nil)
    var changes = 0
    surface.onChanged = { changes += 1 }
    surface.seedSyntheticDrawing()
    XCTAssertEqual(surface.changeId, 1)
    XCTAssertGreaterThan(changes, 0)
    let captured = try surface.captureSnapshot()
    let data = try XCTUnwrap(captured["drawing"] as? FlutterStandardTypedData).data
    XCTAssertEqual(try PKDrawing(data: data).strokes.count, 7)
    XCTAssertEqual(try XCTUnwrap(captured["images"] as? [FlutterStandardTypedData]).count, 1)
    XCTAssertEqual(captured["changeId"] as? Int, 1)
  }
  #endif

  private func drawing(from start: CGPoint, to end: CGPoint) -> PKDrawing {
    let points = [start, end].enumerated().map { index, point in
      PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
        size: CGSize(width: 3, height: 3), opacity: 1, force: 1,
        azimuth: 0, altitude: .pi / 2)
    }
    let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0))
    return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
  }
}
