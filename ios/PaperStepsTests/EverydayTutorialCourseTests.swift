import XCTest
@testable import Protacta

final class EverydayTutorialCourseTests: XCTestCase {
    func testCatalogContainsFiveCompleteDistinctEverydayCourses() {
        XCTAssertEqual(EverydayTutorialCourse.all.count, 5)
        XCTAssertEqual(Set(EverydayTutorialCourse.all.map(\.id)), Set(EverydayTutorialID.allCases))
        let counts: [EverydayTutorialID: Int] = [.tShirt: 6, .towel: 3, .flatBedsheet: 4, .squareKnot: 5, .fourInHand: 7]
        for id in EverydayTutorialID.allCases {
            let course = EverydayTutorialCourse.course(id)
            XCTAssertEqual(course.id, id)
            XCTAssertEqual(course.actions.count, counts[id])
            XCTAssertFalse(course.title.isEmpty)
            XCTAssertFalse(course.summary.isEmpty)
            XCTAssertFalse(course.setup.isEmpty)
            XCTAssertFalse(course.materials.isEmpty)
            XCTAssertTrue(course.materials.allSatisfy { !$0.isEmpty })
            XCTAssertFalse(course.title.lowercased().contains("coming soon"))
        }
    }

    func testEveryActionHasContiguousTeachingAndRendererStages() {
        for course in EverydayTutorialCourse.all {
            XCTAssertEqual(course.actions.map(\.id), Array(1...course.actions.count))
            XCTAssertEqual(course.actions.map(\.visualStartIndex), Array(0..<course.actions.count))
            XCTAssertEqual(course.actions.map(\.visualEndIndex), Array(1...course.actions.count))
            for action in course.actions {
                for field in [action.title, action.instruction, action.manualCheckpoint, action.commonMistake, action.help] {
                    XCTAssertFalse(field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                   "\(course.id.rawValue) action \(action.id)")
                }
            }
        }
    }

    func testAllCoursesClearlyRemainManualDraftsWithoutCameraApproval() {
        for course in EverydayTutorialCourse.all {
            XCTAssertTrue(course.requiresRealFollowThroughReview)
            XCTAssertFalse(course.supportsCameraCheck)
            XCTAssertTrue(course.reviewNotice.contains("real follow-through review"))
            XCTAssertTrue(course.reviewNotice.contains("camera does not check"))
        }
    }

    func testMaterialAndDirectionBoundariesRemainExplicit() {
        let sheet = EverydayTutorialCourse.course(.flatBedsheet)
        XCTAssertTrue(sheet.setup.contains("not a fitted sheet"))
        XCTAssertTrue(sheet.materials.joined().contains("without elastic corners"))
        let knot = EverydayTutorialCourse.course(.squareKnot)
        XCTAssertTrue(knot.setup.contains("not a load-bearing"))
        XCTAssertTrue(knot.actions[1].instruction.contains("A on the right and B on the left"))
        XCTAssertTrue(knot.actions[2].instruction.contains("right to left"))
        let tie = EverydayTutorialCourse.course(.fourInHand)
        XCTAssertTrue(tie.setup.contains("YOUR right (diagram-left)"))
        XCTAssertTrue(tie.actions[3].instruction.contains("neck loop"))
        XCTAssertTrue(tie.actions[4].instruction.contains("front band"))
    }

    func testCourseRevisionsAreDistinctAndTeachingReferencesAreAvailable() {
        let revisions = EverydayTutorialCourse.all.map(\.revision)
        XCTAssertEqual(Set(revisions).count, EverydayTutorialCourse.all.count)
        XCTAssertTrue(revisions.allSatisfy { $0.count == 64 })
        XCTAssertEqual(EverydayTutorialID.tShirt.category, .clothing)
        XCTAssertEqual(EverydayTutorialID.towel.category, .linens)
        XCTAssertEqual(EverydayTutorialID.flatBedsheet.category, .linens)
        for id: EverydayTutorialID in [.squareKnot, .fourInHand] {
            let references = EverydayTutorialCourse.course(id).references
            XCTAssertFalse(references.isEmpty)
            XCTAssertTrue(references.allSatisfy { !$0.title.isEmpty && $0.url.scheme == "https" })
        }
    }
}
