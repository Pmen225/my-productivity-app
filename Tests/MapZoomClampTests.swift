import Foundation
import Testing
@testable import Flowmap

/// Task 84 — "allow freee zoom till certain extent in map": the founder
/// asked for a wider pinch range that still clamps. Tests the seam both
/// gesture handlers (`pinchGesture.onEnded` and `zoom(by:)`) clamp against —
/// `MapCanvasView.minimumZoom` / `.maximumZoom` — so a future edit to either
/// call site can't silently drift from the other.
///
/// `@MainActor`: these statics live on a `View`, which defaults its members
/// to main-actor isolation — a non-isolated suite fails to build.
@MainActor
struct MapZoomClampTests {
    @Test func widenedBoundsMatchTheFounderAskedRange() {
        #expect(MapCanvasView.minimumZoom == 0.35)
        #expect(MapCanvasView.maximumZoom == 6.0)
    }

    @Test func clampFloorsAValueBelowMinimum() {
        let raw: CGFloat = 0.1
        let clamped = min(max(raw, MapCanvasView.minimumZoom), MapCanvasView.maximumZoom)
        #expect(clamped == 0.35)
    }

    @Test func clampCeilsAValueAboveMaximum() {
        let raw: CGFloat = 10
        let clamped = min(max(raw, MapCanvasView.minimumZoom), MapCanvasView.maximumZoom)
        #expect(clamped == 6.0)
    }

    @Test func clampPassesThroughAnInRangeValue() {
        let raw: CGFloat = 2
        let clamped = min(max(raw, MapCanvasView.minimumZoom), MapCanvasView.maximumZoom)
        #expect(clamped == 2)
    }

    @Test func anchoredZoomKeepsTheContentPointUnderTheFingers() {
        let currentPan = CGSize(width: 20, height: -10)
        let anchor = CGPoint(x: 200, y: 300)
        let nextPan = MapViewportGeometry.anchoredPanOffset(
            currentPan: currentPan,
            currentZoom: 1,
            nextZoom: 2,
            anchor: anchor
        )

        let contentPoint = CGPoint(
            x: (anchor.x - currentPan.width),
            y: (anchor.y - currentPan.height)
        )
        let projected = CGPoint(
            x: contentPoint.x * 2 + nextPan.width,
            y: contentPoint.y * 2 + nextPan.height
        )
        #expect(abs(projected.x - anchor.x) < 0.0001)
        #expect(abs(projected.y - anchor.y) < 0.0001)
    }

    @Test func canvasPanStartsOnBackgroundButNotOnANode() {
        let frame = CGRect(x: 80, y: 120, width: 120, height: 44)
        #expect(MapViewportGeometry.shouldBeginCanvasPan(at: CGPoint(x: 20, y: 20), nodeFrames: [frame]))
        #expect(!MapViewportGeometry.shouldBeginCanvasPan(at: CGPoint(x: 100, y: 140), nodeFrames: [frame]))
    }
}
