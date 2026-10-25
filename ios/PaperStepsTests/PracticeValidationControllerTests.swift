import XCTest
@testable import Protacta

final class PracticeValidationControllerTests: XCTestCase {
    func testAnonymousIDsAreRequiredAndRemainSafeMetadata() {
        var identity = PracticeValidationIdentity()
        XCTAssertFalse(identity.isValid)
        identity.operatorID = "P01"; identity.sheetID = "sheet.001"; identity.attemptID = "P01-attempt-001"
        XCTAssertTrue(identity.isValid)
        for bad in ["", ".", "..", "a/b", "a\\b", "a\nb", "a b", String(repeating: "x", count: 81)] {
            var invalid = identity; invalid.sheetID = bad
            XCTAssertFalse(invalid.isValid, bad)
        }
    }

    func testRequestUsesIdentityAtTheExplicitSaveAction() {
        var identity = validIdentity()
        let request = ticket(identity: identity)
        identity.operatorID = "P02"; identity.split = .evaluation
        XCTAssertEqual(request.identity.operatorID, "P01")
        XCTAssertEqual(request.identity.split, .development)
    }

    func testOnlyFreshlyRequestedSameActionCameraAndRegistrationCanBeRecorded() {
        let request = ticket()
        XCTAssertTrue(request.accepts(frameTimestamp: 100.1, action: 3, cameraRevision: 4, registrationRevision: 5, now: 100.2))
        XCTAssertFalse(request.accepts(frameTimestamp: 99.99, action: 3, cameraRevision: 4, registrationRevision: 5, now: 100.2))
        XCTAssertFalse(request.accepts(frameTimestamp: 100.1, action: 4, cameraRevision: 4, registrationRevision: 5, now: 100.2))
        XCTAssertFalse(request.accepts(frameTimestamp: 100.1, action: 3, cameraRevision: 6, registrationRevision: 5, now: 100.2))
        XCTAssertFalse(request.accepts(frameTimestamp: 100.1, action: 3, cameraRevision: 4, registrationRevision: 6, now: 100.2))
        XCTAssertFalse(request.accepts(frameTimestamp: 100.3, action: 3, cameraRevision: 4, registrationRevision: 5, now: 100.2))
        XCTAssertFalse(request.accepts(frameTimestamp: .nan, action: 3, cameraRevision: 4, registrationRevision: 5, now: 100.2))
        XCTAssertFalse(request.accepts(frameTimestamp: 100.1, action: 3, cameraRevision: 4, registrationRevision: 5, now: .infinity))
        XCTAssertFalse(request.accepts(frameTimestamp: 100.1, action: 3, cameraRevision: 4, registrationRevision: 5, now: 102.01))
    }

    func testExpiredAnalysisCanBeCollectedWithoutApprovingLiveAlignment() {
        let request = ticket()
        XCTAssertTrue(request.accepts(frameTimestamp: 100.1, action: 3, cameraRevision: 4, registrationRevision: 5, now: 100.8),
                      "An explicit test may record a slow result for latency analysis; exporter requires cannotJudge for expired data")
        XCTAssertGreaterThan(100.8 - 100.1, PaperGuideSession.maximumObservationAge)
    }

    @MainActor
    func testNormalPracticeNeverArmsAPhotoCapture() {
        let controller = makeController()
        XCTAssertFalse(controller.validationEnabled)
        controller.enterDartPractice()
        controller.requestValidationSample()
        XCTAssertNil(controller.validationRequest)
        XCTAssertFalse(controller.validationBusy)
        XCTAssertNil(controller.lastValidationDirectory)
    }

    @MainActor
    func testActionChangeAndBackgroundCancelExplicitCaptureTicket() {
        let controller = makeController()
        controller.enterDartPractice()
        controller.validationRequest = ticket()
        controller.validationBusy = true; controller.validationFrameInFlight = true
        controller.confirmPracticeAction()
        XCTAssertNil(controller.validationRequest)
        XCTAssertFalse(controller.validationBusy)
        XCTAssertFalse(controller.validationFrameInFlight)
        controller.validationRequest = ticket()
        controller.validationBusy = true
        controller.background()
        XCTAssertNil(controller.validationRequest)
        XCTAssertFalse(controller.validationBusy)
        XCTAssertTrue(controller.validationStatus.contains("canceled"))
    }

    @MainActor
    func testMissingCameraFrameTimesOutWithoutCreatingEvidence() {
        let controller = makeController()
        controller.validationRequest = ticket()
        controller.validationBusy = true
        controller.expireValidationCapture(at: 102.01)
        XCTAssertNil(controller.validationRequest)
        XCTAssertFalse(controller.validationBusy)
        XCTAssertNil(controller.lastValidationDirectory)
        XCTAssertTrue(controller.validationStatus.contains("Nothing was saved"))
    }

    private func validIdentity() -> PracticeValidationIdentity {
        var identity = PracticeValidationIdentity()
        identity.operatorID = "P01"; identity.sheetID = "sheet-001"; identity.attemptID = "attempt-001"
        return identity
    }
    private func ticket(identity: PracticeValidationIdentity? = nil) -> PracticeValidationRequest {
        PracticeValidationRequest(identity: identity ?? validIdentity(), action: 3, requestedAt: 100, cameraRevision: 4, registrationRevision: 5)
    }
    @MainActor private func makeController() -> LessonController {
        LessonController(progressStore: LearningProgressStore(defaults: nil), practiceStore: PracticeProgressStore(defaults: nil))
    }
}
