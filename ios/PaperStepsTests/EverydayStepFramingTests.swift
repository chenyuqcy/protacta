import XCTest
import simd
@testable import Protacta

final class EverydayStepFramingTests: XCTestCase {
    func testWholeMovementFitsAtDensePositionsBetweenFramingSamples() throws {
        for course in EverydayTutorialCourse.all {
            for action in course.actions.indices {
                let frame = EverydayStepFraming.action(courseID: course.id, actionIndex: action)
                // Deliberately use a different grid from the framing calculation.
                for sample in 0...60 {
                    try assertFits(course: course.id, action: action, progress: Double(sample) / 60,
                                   scale: SIMD3(repeating: 1), in: frame)
                }
            }
        }
    }

    func testCalibratedClothMovementFitsWithoutChangingPhysicalDimensions() throws {
        let scales: [SIMD3<Float>] = [[0.17, sqrt(0.0272), 0.16], [1.6, sqrt(1.28), 0.8]]
        for id in [EverydayTutorialID.towel, .tShirt, .flatBedsheet] {
            for scale in scales {
                for action in EverydayTutorialCourse.course(id).actions.indices {
                    let frame = EverydayStepFraming.action(courseID: id, actionIndex: action, objectScale: scale)
                    for sample in 0...12 {
                        try assertFits(course: id, action: action, progress: Double(sample) / 12,
                                       scale: scale, in: frame)
                    }
                }
            }
        }
    }

    func testFinalPacketsGetSubstantiallyTighterFramesThanTheWholeCourse() throws {
        for id in [EverydayTutorialID.towel, .tShirt, .flatBedsheet] {
            let whole = EverydayMeshGeometry.envelope(courseID: id)
            let wholeRadius = simd_length(whole.maximum - whole.minimum) * 0.5
            let finished = EverydayStepFraming.completed(courseID: id)
            XCTAssertLessThan(finished.radius, wholeRadius * 0.5, "\(id): final packet should fill more of the screen")
            try assertFits(course: id, action: EverydayTutorialCourse.course(id).actions.count - 1,
                           progress: 1, scale: SIMD3(repeating: 1), in: finished)
        }
        for id in [EverydayTutorialID.tShirt, .flatBedsheet] {
            let whole = EverydayMeshGeometry.envelope(courseID: id)
            let wholeRadius = simd_length(whole.maximum - whole.minimum) * 0.5
            let last = EverydayStepFraming.action(courseID: id,
                                                 actionIndex: EverydayTutorialCourse.course(id).actions.count - 1)
            XCTAssertLessThan(last.radius, wholeRadius * 0.7)
        }
    }

    func testActionFramesAreDeterministicAndClampIndicesAndInvalidScale() {
        for course in EverydayTutorialCourse.all {
            let first = EverydayStepFraming.action(courseID: course.id, actionIndex: 0)
            XCTAssertEqual(first, EverydayStepFraming.action(courseID: course.id, actionIndex: -99))
            XCTAssertEqual(first, EverydayStepFraming.action(courseID: course.id, actionIndex: 0,
                                                             objectScale: [.nan, -1, 0]))
            XCTAssertEqual(first, EverydayStepFraming.action(courseID: course.id, actionIndex: 0))
            XCTAssertEqual(EverydayStepFraming.action(courseID: course.id, actionIndex: 999),
                           EverydayStepFraming.action(courseID: course.id, actionIndex: course.actions.count - 1))
        }
    }

    func testExplicitPoseFocusIsTighterAndIncludesTheCurrentRenderedSurface() throws {
        for id in [EverydayTutorialID.towel, .tShirt, .flatBedsheet] {
            let index = EverydayTutorialCourse.course(id).actions.count - 1
            let movement = EverydayStepFraming.action(courseID: id, actionIndex: index)
            let focus = EverydayStepFraming.pose(courseID: id, actionIndex: index, progress: 1)
            XCTAssertLessThan(focus.radius, movement.radius * 0.75)
            XCTAssertEqual(focus, EverydayStepFraming.completed(courseID: id))
            try assertFits(course: id, action: index, progress: 1, scale: SIMD3(repeating: 1), in: focus)
            let flat = EverydayStepFraming.pose(courseID: id, actionIndex: 0, progress: 0)
            XCTAssertEqual(flat, EverydayStepFraming.pose(courseID: id, actionIndex: -1, progress: .nan))
        }
    }

    private func assertFits(course: EverydayTutorialID, action: Int, progress: Double, scale: SIMD3<Float>,
                            in frame: EverydayStepFraming.Frame,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        let parts = EverydayMeshGeometry.parts(courseID: course, actionIndex: action, progress: progress, objectScale: scale)
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var furthest: Float = 0
        for part in parts {
            let surface = try EverydaySurfaceMesh.make(part: part)
            for point in surface.positions {
                minimum = simd_min(minimum, point); maximum = simd_max(maximum, point)
                furthest = max(furthest, simd_distance(point, frame.center))
            }
        }
        let context = "\(course) action \(action) movement \(progress) scale \(scale)"
        for axis in 0..<3 {
            XCTAssertGreaterThanOrEqual(minimum[axis], frame.minimum[axis] - 0.000001, context, file: file, line: line)
            XCTAssertLessThanOrEqual(maximum[axis], frame.maximum[axis] + 0.000001, context, file: file, line: line)
        }
        XCTAssertLessThanOrEqual(furthest, frame.radius + 0.000001, context, file: file, line: line)
    }
}
