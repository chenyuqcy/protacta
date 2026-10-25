import XCTest
@testable import Protacta

final class FoldHelpTests: XCTestCase {
    private let authoredSteps: [(lesson: OrigamiLesson, id: Int, title: String)] = [
        (.crane, 3, "Open the first pocket"),
        (.crane, 5, "Complete the square base"),
        (.crane, 9, "Lift the first petal"),
        (.crane, 14, "Finish the bird base"),
        (.crane, 22, "Reverse the neck upward"),
        (.crane, 23, "Reverse the tail upward"),
        (.crane, 25, "Tuck the beak inside"),
        (.star, 1, "Curve a loose loop"),
        (.star, 2, "Pass the tip through"),
        (.star, 3, "Settle a five-sided knot"),
        (.star, 4, "Hide the short end"),
        (.star, 7, "Build the paper layers"),
        (.star, 8, "Secure the last tip"),
        (.star, 9, "Press the first edge"),
        (.star, 13, "Finish your lucky star")
    ]

    func testEveryValidStepHasNonemptyEnglishHelp() throws {
        for lesson in OrigamiLesson.allCases {
            for stepIndex in lesson.steps.indices {
                let context = "\(lesson.rawValue) step \(stepIndex)"
                let help = try XCTUnwrap(FoldHelp.forStep(lesson: lesson, stepIndex: stepIndex), context)
                for text in [help.simplerInstruction, help.checkpoint, help.commonMistake] {
                    XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, context)
                    XCTAssertNotNil(text.range(of: "[A-Za-z]", options: .regularExpression), context)
                    XCTAssertNil(text.range(of: "[\\x{3400}-\\x{9FFF}]", options: .regularExpression), context)
                }
            }
        }
    }

    func testInvalidIndicesReturnNoHelp() {
        for lesson in OrigamiLesson.allCases {
            for index in [Int.min, -1, lesson.steps.count, Int.max] {
                XCTAssertNil(FoldHelp.forStep(lesson: lesson, stepIndex: index))
            }
        }
    }

    func testAuthoredHelpIDsStillMatchTheirLessonActions() throws {
        for fixture in authoredSteps {
            let step = fixture.lesson.steps[fixture.id]
            XCTAssertEqual(step.id, fixture.id)
            XCTAssertEqual(step.title, fixture.title, "Update help when lesson actions change.")
            let help = try XCTUnwrap(FoldHelp.forStep(lesson: fixture.lesson, stepIndex: fixture.id))
            XCTAssertNotEqual(help.simplerInstruction, step.instruction, fixture.title)
        }
    }

    func testOtherStepsReuseCurrentAuthoredInstructions() throws {
        for lesson in OrigamiLesson.allCases {
            for step in lesson.steps where step.id != 0 {
                guard !authoredSteps.contains(where: { $0.lesson == lesson && $0.id == step.id }) else { continue }
                let help = try XCTUnwrap(FoldHelp.forStep(lesson: lesson, stepIndex: step.id))
                XCTAssertEqual(help.simplerInstruction, step.instruction)
                XCTAssertEqual(help.checkpoint, "Compare your paper with the end of this animation before continuing.")
                XCTAssertEqual(help.commonMistake, "Keep the same orientation as the guide. Replay if you are unsure which layer moves.")
            }
        }
    }

    func testPreparationUsesEachLessonsMaterial() throws {
        for lesson in OrigamiLesson.allCases {
            let help = try XCTUnwrap(FoldHelp.forStep(lesson: lesson, stepIndex: 0))
            XCTAssertEqual(help.simplerInstruction, lesson.steps[0].instruction)
            XCTAssertTrue(help.checkpoint.contains(lesson.material))
            XCTAssertFalse(help.commonMistake.contains("which layer moves"))
        }
        let star = try XCTUnwrap(FoldHelp.forStep(lesson: .star, stepIndex: 0))
        XCTAssertTrue(star.checkpoint.contains("strip"))
        XCTAssertFalse(star.checkpoint.lowercased().contains("square"))
        let crane = try XCTUnwrap(FoldHelp.forStep(lesson: .crane, stepIndex: 0))
        XCTAssertTrue(crane.checkpoint.contains("square"))
    }

    func testCraneReverseFoldsRetainLeftNeckRightTailAndSmallBeak() throws {
        let neck = try XCTUnwrap(FoldHelp.forStep(lesson: .crane, stepIndex: 22))
        XCTAssertTrue(neck.simplerInstruction.contains("left point"))
        XCTAssertTrue(neck.simplerInstruction.contains("up between the layers"))
        let tail = try XCTUnwrap(FoldHelp.forStep(lesson: .crane, stepIndex: 23))
        XCTAssertTrue(tail.simplerInstruction.contains("right point"))
        XCTAssertTrue(tail.checkpoint.contains("left neck stays raised"))
        let beak = try XCTUnwrap(FoldHelp.forStep(lesson: .crane, stepIndex: 25))
        XCTAssertTrue(beak.simplerInstruction.contains("small tip down inside"))
        XCTAssertTrue(beak.commonMistake.contains("not the whole neck"))
    }

    func testCranePetalFoldsMoveOnePocketAndKeepSeparateLowerPoints() throws {
        let first = try XCTUnwrap(FoldHelp.forStep(lesson: .crane, stepIndex: 9))
        XCTAssertTrue(first.simplerInstruction.contains("only the front bottom corner"))
        XCTAssertTrue(first.simplerInstruction.contains("both sides inward"))
        let second = try XCTUnwrap(FoldHelp.forStep(lesson: .crane, stepIndex: 14))
        XCTAssertTrue(second.simplerInstruction.contains("second long diamond"))
        XCTAssertTrue(second.checkpoint.contains("two separate points below"))
    }

    func testStarKnotAndTucksStayFlatBeforeSideShaping() throws {
        let thread = try XCTUnwrap(FoldHelp.forStep(lesson: .star, stepIndex: 2))
        XCTAssertTrue(thread.simplerInstruction.contains("short tip through the loop"))
        XCTAssertTrue(thread.commonMistake.contains("not the long tail"))
        let knot = try XCTUnwrap(FoldHelp.forStep(lesson: .star, stepIndex: 3))
        XCTAssertTrue(knot.checkpoint.contains("flat pentagon"))
        XCTAssertTrue(knot.commonMistake.contains("Avoid a hard pull"))
        let shortTuck = try XCTUnwrap(FoldHelp.forStep(lesson: .star, stepIndex: 4))
        XCTAssertTrue(shortTuck.simplerInstruction.contains("short tip"))
        XCTAssertTrue(shortTuck.commonMistake.contains("long tail remains"))
        let finalTuck = try XCTUnwrap(FoldHelp.forStep(lesson: .star, stepIndex: 8))
        XCTAssertTrue(finalTuck.checkpoint.contains("flat pentagon"))
        XCTAssertTrue(finalTuck.commonMistake.contains("without force"))
    }

    func testStarVolumeComesFromGentleSidePresses() throws {
        let first = try XCTUnwrap(FoldHelp.forStep(lesson: .star, stepIndex: 9))
        XCTAssertTrue(first.simplerInstruction.contains("middle of the highlighted side inward"))
        XCTAssertTrue(first.commonMistake.contains("side, not the broad face"))
        let last = try XCTUnwrap(FoldHelp.forStep(lesson: .star, stepIndex: 13))
        XCTAssertTrue(last.simplerInstruction.contains("middle of the last side inward"))
        XCTAssertTrue(last.checkpoint.contains("all five points"))
        XCTAssertTrue(last.checkpoint.contains("lightly rounded"))
    }
}
