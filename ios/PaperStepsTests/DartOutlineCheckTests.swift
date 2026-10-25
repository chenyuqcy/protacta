import CoreGraphics
import XCTest
@testable import Protacta

final class DartOutlineCheckTests: XCTestCase {
    private let straight = PaperQuadrilateral(topLeft: CGPoint(x: 0.2, y: 0.15),
                                             topRight: CGPoint(x: 0.8, y: 0.15),
                                             bottomRight: CGPoint(x: 0.8, y: 0.85),
                                             bottomLeft: CGPoint(x: 0.2, y: 0.85))
    private let projective = PaperQuadrilateral(topLeft: CGPoint(x: 0.18, y: 0.17),
                                               topRight: CGPoint(x: 0.78, y: 0.24),
                                               bottomRight: CGPoint(x: 0.85, y: 0.85),
                                               bottomLeft: CGPoint(x: 0.12, y: 0.78))

    func testKnownFlatSilhouettesMatchWithoutClaimingHiddenCreases() throws {
        for state in [0, 2, 3, 4, 5, 6] {
            let image = try render(state: state, pose: straight, printedCodes: true)
            let result = DartOutlineChecker.evaluate(image: image, pose: straight, state: state, timestamp: 7)
            XCTAssertEqual(result.outcome, .visibleMatch, "State \(state): \(result.message)")
            XCTAssertEqual(result.referenceState, state)
            XCTAssertEqual(result.timestamp, 7)
            XCTAssertTrue(result.mismatchedPoints.isEmpty)
            if state == 2 { XCTAssertTrue(result.message.contains("cannot verify")) }
        }
    }

    func testMissingCornerFoldsReturnScopedAdjustmentAndSheetCoordinates() throws {
        let stillUnfolded = try render(state: 0, pose: straight)
        let result = DartOutlineChecker.evaluate(image: stillUnfolded, pose: straight, state: 4, timestamp: 2)
        XCTAssertEqual(result.outcome, .needsAdjustment)
        XCTAssertTrue(result.message.contains("visible outline differs"))
        XCTAssertFalse(result.message.contains("wrong fold"))
        XCTAssertFalse(result.mismatchedPoints.isEmpty)
        XCTAssertLessThanOrEqual(result.mismatchedPoints.count, 24)
        XCTAssertTrue(result.mismatchedPoints.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }

    func testShadowedUnfoldedCornersCannotDisappearIntoAVisibleMatch() throws {
        for pose in [straight, straight.rotated(by: 1), projective] {
            for gray in [UInt8(50), 60, 140, 200, 205] {
                // The actual sheet is still a whole A4 rectangle. Only the two
                // regions that should have folded away are shadowed; the
                // expected folded interior remains bright white throughout.
                let image = try render(state: 0, pose: pose,
                                       grayExteriorOfState: 4, exteriorGray: gray)
                let result = DartOutlineChecker.evaluate(image: image, pose: pose, state: 4, timestamp: 3)
                XCTAssertEqual(result.outcome, .cannotJudge, "Shadowed extra paper at gray \(gray) must not count as background: \(result.message)")
                XCTAssertTrue(result.mismatchedPoints.isEmpty)
            }
        }
    }

    func testOneShadowedCornerIsUnknownWhileClearExtraWhitePaperNeedsAdjustment() throws {
        for pose in [straight, straight.rotated(by: 1), projective] {
            let partiallyShadowed = try render(state: 0, pose: pose,
                                               grayExteriorOfState: 4, exteriorGray: 140, grayOnlyLeft: true)
            let unknown = DartOutlineChecker.evaluate(image: partiallyShadowed, pose: pose, state: 4, timestamp: 3)
            XCTAssertEqual(unknown.outcome, .cannotJudge)
            // These binary raster edges interpolate to gray at subpixel
            // samples. The full, clearly white corner remains a real mismatch;
            // discounting only its narrow interpolation border must not hide it.
            let clearlyUnfolded = try render(state: 0, pose: pose)
            XCTAssertEqual(DartOutlineChecker.evaluate(image: clearlyUnfolded, pose: pose, state: 4, timestamp: 3).outcome,
                           .needsAdjustment)
            let correct = try render(state: 4, pose: pose)
            XCTAssertEqual(DartOutlineChecker.evaluate(image: correct, pose: pose, state: 4, timestamp: 3).outcome,
                           .visibleMatch)
        }
    }

    func testLuminanceSamplingUsesRawImageEdgesAndPixelCenters() throws {
        let image = PaperLuminanceImage(width: 4, height: 3,
                                       pixels: [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110])
        // Independent expected values come directly from the row-major pixels,
        // rather than using the renderer's projective mapping to define them.
        XCTAssertEqual(try XCTUnwrap(image.sample(at: CGPoint(x: 0.375, y: 0.5))), 50, accuracy: 1e-10)
        XCTAssertEqual(try XCTUnwrap(image.sample(at: CGPoint(x: 0.25, y: 0.5))), 45, accuracy: 1e-10)
        XCTAssertEqual(try XCTUnwrap(image.sample(at: CGPoint(x: 0, y: 0.5))), 40, accuracy: 1e-10)
        XCTAssertEqual(try XCTUnwrap(image.sample(at: CGPoint(x: 1, y: 0.5))), 70, accuracy: 1e-10)
        XCTAssertEqual(try XCTUnwrap(image.sample(at: CGPoint(x: 0.625, y: 0))), 20, accuracy: 1e-10)
        XCTAssertEqual(try XCTUnwrap(image.sample(at: CGPoint(x: 0.375, y: 1.0 / 3))), 30, accuracy: 1e-10)
        XCTAssertNil(image.sample(at: CGPoint(x: -0.01, y: 0.5)))
        XCTAssertNil(image.sample(at: CGPoint(x: .nan, y: 0.5)))
        let oneColumn = PaperLuminanceImage(width: 1, height: 3, pixels: [20, 120, 220])
        XCTAssertEqual(try XCTUnwrap(oneColumn.sample(at: CGPoint(x: 0.1, y: 0))), 20, accuracy: 1e-10)
        XCTAssertEqual(try XCTUnwrap(oneColumn.sample(at: CGPoint(x: 0.9, y: 0.5))), 120, accuracy: 1e-10)
        XCTAssertEqual(try XCTUnwrap(oneColumn.sample(at: CGPoint(x: 1, y: 1))), 220, accuracy: 1e-10)
    }

    func testRotatedAndProjectiveIndependentAnalyticShapesMatch() throws {
        let poses = [
            straight.rotated(by: 1),
            projective
        ]
        for pose in poses {
            for state in [0, 3, 4, 5, 6] {
                let result = DartOutlineChecker.evaluate(image: try render(state: state, pose: pose),
                                                        pose: pose, state: state, timestamp: 3)
                XCTAssertEqual(result.outcome, .visibleMatch, "State \(state): \(result.message)")
            }
        }
    }

    func testBlankImageWhiteBackgroundAndLowContrastCannotBeApproved() throws {
        let darkBlank = PaperLuminanceImage(width: 240, height: 320,
                                          pixels: Array(repeating: 0, count: 240 * 320))
        let whiteBlank = PaperLuminanceImage(width: 240, height: 320,
                                           pixels: Array(repeating: 255, count: 240 * 320))
        let whiteMat = try render(state: 0, pose: straight, paper: 255, background: 240)
        let lowContrast = try render(state: 0, pose: straight, paper: 170, background: 120)
        for image in [darkBlank, whiteBlank, whiteMat, lowContrast] {
            XCTAssertEqual(DartOutlineChecker.evaluate(image: image, pose: straight, state: 0, timestamp: 4).outcome,
                           .cannotJudge)
        }
    }

    func testInteriorObstructionOrShadowCannotBeCalledAWrongFold() throws {
        let obstruction = try render(state: 0, pose: straight,
                                     obstruction: CGRect(x: 0.35, y: 0.3, width: 0.3, height: 0.3), obstructionValue: 0)
        let shadow = try render(state: 0, pose: straight,
                                obstruction: CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.3), obstructionValue: 140)
        for image in [obstruction, shadow] {
            XCTAssertEqual(DartOutlineChecker.evaluate(image: image, pose: straight, state: 0, timestamp: 4).outcome,
                           .cannotJudge)
        }
    }

    func testMissingInvalidClippedAndTooSmallPoseCannotBeApproved() throws {
        let image = try render(state: 0, pose: straight)
        let clipped = PaperQuadrilateral(topLeft: CGPoint(x: 0, y: 0), topRight: CGPoint(x: 0.9, y: 0),
                                         bottomRight: CGPoint(x: 0.9, y: 0.9), bottomLeft: CGPoint(x: 0, y: 0.9))
        let small = PaperQuadrilateral(topLeft: CGPoint(x: 0.4, y: 0.4), topRight: CGPoint(x: 0.55, y: 0.4),
                                       bottomRight: CGPoint(x: 0.55, y: 0.6), bottomLeft: CGPoint(x: 0.4, y: 0.6))
        let collapsed = PaperQuadrilateral(topLeft: .zero, topRight: .zero, bottomRight: .zero, bottomLeft: .zero)
        for pose in [nil, clipped, small, collapsed] as [PaperQuadrilateral?] {
            XCTAssertEqual(DartOutlineChecker.evaluate(image: image, pose: pose, state: 0, timestamp: 4).outcome,
                           .cannotJudge)
        }
    }

    func testUnsupportedStatesAndInvalidImageCannotBeApproved() throws {
        let image = try render(state: 0, pose: straight)
        for state in [-1, 1, 7, 8, 9, 10, 11] {
            XCTAssertNil(DartOutlineChecker.outline(state: state))
            XCTAssertEqual(DartOutlineChecker.evaluate(image: image, pose: straight, state: state, timestamp: 4).outcome,
                           .cannotJudge)
        }
        let invalid = PaperLuminanceImage(width: 240, height: 320, pixels: [255])
        XCTAssertEqual(DartOutlineChecker.evaluate(image: invalid, pose: straight, state: 0, timestamp: 4).outcome,
                       .cannotJudge)
        XCTAssertEqual(DartOutlineChecker.evaluate(image: image, pose: straight, state: 0, timestamp: .nan).outcome,
                       .cannotJudge)
    }

    func testGeometryOutlineAgreesWithIndependentlyDefinedNoseAndFoldedEdges() throws {
        for state in [0, 2, 3, 4, 5, 6] {
            let actual = try XCTUnwrap(DartOutlineChecker.outline(state: state))
            let expected = analyticOutline(state: state)
            XCTAssertEqual(actual.count, expected.count, "State \(state): \(actual)")
            for point in expected {
                XCTAssertTrue(actual.contains { hypot($0.x - point.x, $0.y - point.y) < 0.0001 },
                              "Missing \(point) in state \(state): \(actual)")
            }
        }
    }

    func testPracticePaperFootprintsStayInsideSupportedSilhouettes() throws {
        let layout = try XCTUnwrap(DartPracticePaperLayout.bundled)
        XCTAssertEqual(layout.markers.map(\.payload), ["PTC2A", "PTC2B", "PTC2C", "PTC2D"])
        XCTAssertEqual(layout.layoutID, "protacta-dart-a4-ptc2")
        XCTAssertEqual(layout.layoutRevision, 2)
        XCTAssertEqual(layout.codeSideMM, 14)
        XCTAssertEqual(layout.quietZoneMM, 3)
        XCTAssertEqual(layout.sheetSizeMM.width, 210)
        XCTAssertEqual(layout.sheetSizeMM.height, 297)
        let halfWidth = (layout.codeSideMM / 2 + layout.quietZoneMM) / layout.sheetSizeMM.width
        let halfHeight = (layout.codeSideMM / 2 + layout.quietZoneMM) / layout.sheetSizeMM.height
        for state in [0, 2, 3, 4, 5, 6] {
            for marker in layout.markers {
                for dx in [-halfWidth, halfWidth] {
                    for dy in [-halfHeight, halfHeight] {
                        XCTAssertTrue(contains(CGPoint(x: marker.center.x + dx, y: marker.center.y + dy),
                                               polygon: analyticOutline(state: state)),
                                      "Silhouette containment only; material-layer visibility is tested separately")
                    }
                }
            }
        }
    }

    /// Reference shapes use analytic crease intersections, not the production
    /// convex-hull code. Coordinates use an original 210 × 297 mm A4 sheet.
    private func analyticOutline(state: Int) -> [CGPoint] {
        if state == 0 || state == 2 {
            return [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        }
        let corner = 105.0 / 297.0
        let narrow = 105.0 / tan(Double.pi / 8) / 297.0
        let left = state >= 5 ? narrow : corner
        let right = state == 3 ? 0 : state == 6 ? narrow : corner
        return [CGPoint(x: 0, y: left), CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: right),
                CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
    }

    private func render(state: Int, pose: PaperQuadrilateral, paper: UInt8 = 255,
                        background: UInt8 = 0, printedCodes: Bool = false,
                        obstruction: CGRect? = nil, obstructionValue: UInt8 = 0,
                        grayExteriorOfState: Int? = nil, exteriorGray: UInt8 = 140,
                        grayOnlyLeft: Bool = false) throws -> PaperLuminanceImage {
        let registration = try XCTUnwrap(PaperRegistration(quadrilateral: pose))
        let polygon = try analyticOutline(state: state).map { try XCTUnwrap(registration.map($0)) }
        let layout = try XCTUnwrap(DartPracticePaperLayout.bundled)
        var patches: [[CGPoint]] = []
        if printedCodes {
            for marker in layout.markers {
                let dx = layout.codeSideMM / 2 / layout.sheetSizeMM.width
                let dy = layout.codeSideMM / 2 / layout.sheetSizeMM.height
                let box = CGRect(x: marker.center.x - dx, y: marker.center.y - dy, width: dx * 2, height: dy * 2)
                patches.append(try rectangle(box).map { try XCTUnwrap(registration.map($0)) })
            }
        }
        let obstructionPolygon = try obstruction.map { box in
            try rectangle(box).map { try XCTUnwrap(registration.map($0)) }
        }
        let expectedPolygon = try grayExteriorOfState.map { referenceState in
            try analyticOutline(state: referenceState).map { try XCTUnwrap(registration.map($0)) }
        }
        let leftHalf = try rectangle(CGRect(x: 0, y: 0, width: 0.5, height: 1)).map {
            try XCTUnwrap(registration.map($0))
        }
        let width = 240, height = 320
        var pixels = Array(repeating: background, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let point = CGPoint(x: (Double(column) + 0.5) / Double(width),
                                    y: (Double(row) + 0.5) / Double(height))
                if contains(point, polygon: polygon) { pixels[row * width + column] = paper }
                if let expectedPolygon, contains(point, polygon: polygon),
                   !contains(point, polygon: expectedPolygon),
                   !grayOnlyLeft || contains(point, polygon: leftHalf) {
                    pixels[row * width + column] = exteriorGray
                }
                if patches.contains(where: { contains(point, polygon: $0) }) { pixels[row * width + column] = 0 }
                if let obstructionPolygon, contains(point, polygon: obstructionPolygon) {
                    pixels[row * width + column] = obstructionValue
                }
            }
        }
        return PaperLuminanceImage(width: width, height: height, pixels: pixels)
    }

    private func rectangle(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    private func contains(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        var inside = false
        var previous = polygon.count - 1
        for index in polygon.indices {
            let a = polygon[index], b = polygon[previous]
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            previous = index
        }
        return inside
    }
}
