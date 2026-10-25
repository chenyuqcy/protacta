import ARKit
import Foundation
import QuartzCore

struct DartPracticeCheckRequest: Equatable {
    let revision: Int
    let action: Int
    let requestedAt: TimeInterval
}

enum DartPracticeCameraCoordinates {
    /// The coded IDs establish paper direction. Preserve correspondence even
    /// when TOP appears at the bottom of the phone display.
    static func viewportQuadrilateral(rawTopLeft quad: PaperQuadrilateral,
                                      displayTransform: CGAffineTransform) -> PaperQuadrilateral? {
        guard quad.isValid,
              [displayTransform.a, displayTransform.b, displayTransform.c,
               displayTransform.d, displayTransform.tx, displayTransform.ty].allSatisfy(\.isFinite) else { return nil }
        let points = quad.points.map { $0.applying(displayTransform) }
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { return nil }
        let result = PaperQuadrilateral(topLeft: points[0], topRight: points[1], bottomRight: points[2], bottomLeft: points[3])
        return result.isValid ? result : nil
    }
}

extension LessonController {
    var practiceAction: DartPracticeAction { DartPracticeCourse.action(dartPractice.currentAction) }
    var practiceMessage: String {
        if dartPractice.completed { return "You confirmed all ten actions. Compare the finished wings and body with the 3D reference." }
        if let cameraError { return cameraError }
        if needsRescan { return "The camera paused. Tap Find sheet again before checking or aligning." }
        if !Self.supportsAR && !isPaperGuideFixture { return "Camera guidance needs a supported iPhone or iPad. You can follow every action in 3D and confirm it yourself." }
        if !supportsCurrentPaperGuideStep { return "This shape needs a 3D view. Follow the animation; camera alignment resumes when the marked area is flat and visible." }
        if practiceMarkerVisible { return "Guide aligned with the printed sheet. Follow the dashed crease and movement arrow; move your hands away before checking." }
        return practiceCameraMessage
    }

    func resetDartPracticeCapture(generation: Int) {
        practiceRequestRevision += 1
        practiceCheckRequest = nil
        practiceCheckBusy = false
        practiceMarkerVisible = false
        lastPracticeObservation = nil
        practiceTrackingLost = false
        printedPaperTracker.reset(generation: generation)
        practiceViewportSize = arView?.bounds.size ?? .zero
        practiceViewOrientation = arView?.window?.windowScene?.interfaceOrientation ?? .portrait
        practiceCameraMessage = "Show all four codes on the printed sheet, on a plain dark mat. Keep the whole sheet in view and hands clear."
    }

    func stopDartPracticeCapture() {
        resetDartPracticeCapture(generation: paperRegistrationRevision + 1)
        _ = practiceProgressStore.save(dartPractice)
    }

    func confirmPracticeAction() {
        guard isDartPractice, dartPractice.confirmCurrentAction() else { return }
        _ = practiceProgressStore.save(dartPractice)
        restartPaperGuideTracking()
        if dartPractice.completed {
            // This completion is explicitly declared by the learner. Camera
            // results do not enter this path or advance any lesson state.
            started = true; completed = true; stepIndex = 10; progress = 1; isPlaying = false
            saveLearningProgress()
            arView?.session.pause()
            needsRescan = true
            stopDartPracticeCapture()
        }
    }

    func previousPracticeAction() {
        guard isDartPractice else { return }
        let wasCompleted = dartPractice.completed
        guard dartPractice.previousAction() else { return }
        if wasCompleted { completed = false; saveLearningProgress() }
        _ = practiceProgressStore.save(dartPractice)
        restartPaperGuideTracking()
    }

    func restartDartPractice() {
        guard isDartPractice else { return }
        dartPractice.restart()
        completed = false
        saveLearningProgress()
        _ = practiceProgressStore.save(dartPractice)
        restartPaperGuideTracking()
    }

    func showPracticeActionIn3D() {
        let action = dartPractice.currentAction
        let wasFinished = dartPractice.completed
        leaveAR()
        practiceReferenceActive = true
        goToStep(action)
        if wasFinished { scrub(to: 1) }
    }

    func checkPracticeAction() {
        guard isDartPractice, !dartPractice.completed, !practiceCheckBusy else { return }
        let action = dartPractice.currentAction
        let now = CACurrentMediaTime()
        if !DartPracticeCourse.supportsOutlineCheck(state: action) {
            recordPracticeCannotJudge("This action lifts or covers the marked paper. Compare the layers and edges with the 3D view; the camera cannot judge this step.", at: now)
            return
        }
        guard !needsRescan, cameraError == nil else {
            recordPracticeCannotJudge("Restart the camera and show the whole marked sheet before checking.", at: now)
            return
        }
        if isPaperGuideFixture {
            let result = DartOutlineCheckResult(checkpointID: "dart-outline-\(action)", referenceState: action,
                                               outcome: practiceFixtureVisible ? .visibleMatch : .cannotJudge,
                                               message: practiceFixtureVisible ? "Synthetic UI sample: visible outline match only. Compare the crease and layers yourself." : "Synthetic UI sample: sheet unavailable.",
                                               mismatchedPoints: [], timestamp: now)
            _ = dartPractice.recordCheck(result, at: now)
            return
        }
        practiceRequestRevision += 1
        practiceCheckRequest = DartPracticeCheckRequest(revision: practiceRequestRevision, action: action, requestedAt: now)
        practiceCheckBusy = true
    }

    private func recordPracticeCannotJudge(_ message: String, at now: TimeInterval) {
        let result = DartOutlineCheckResult(checkpointID: "dart-outline-\(dartPractice.currentAction)",
                                           referenceState: dartPractice.currentAction, outcome: .cannotJudge,
                                           message: message, mismatchedPoints: [], timestamp: now)
        _ = dartPractice.recordCheck(result, at: now)
        _ = practiceProgressStore.save(dartPractice)
    }

    func expireDartPracticeCapture(at now: TimeInterval) {
        if let observedAt = lastPracticeObservation,
           !now.isFinite || now < observedAt || now - observedAt > PaperGuideSession.maximumObservationAge {
            practiceMarkerVisible = false
            lastPracticeObservation = nil
            receivePrintedPracticePose(nil, timestamp: now)
        }
        if let request = practiceCheckRequest, now - request.requestedAt > 2 {
            practiceCheckRequest = nil; practiceCheckBusy = false
            recordPracticeCannotJudge("No clear, current camera frame was available. Show the codes on a dark mat and try again, or compare in 3D.", at: now)
        }
    }

    func assessDartPractice(_ frame: ARFrame) {
        guard !dartPractice.completed, let view = arView, view.bounds.width > 1, view.bounds.height > 1 else { return }
        let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
        if practiceViewportSize != view.bounds.size || practiceViewOrientation != orientation { restartPaperGuideTracking() }
        guard case .normal = frame.camera.trackingState else {
            handleDartPracticeTrackingLoss()
            return
        }
        practiceTrackingLost = false
        let viewportSize = view.bounds.size
        let transform = frame.displayTransform(for: orientation, viewportSize: viewportSize)
        let generation = paperRegistrationRevision
        let cameraGeneration = cameraSessionRevision
        let request = practiceCheckRequest
        printedPaperTracker.submit(pixelBuffer: frame.capturedImage, timestamp: frame.timestamp, generation: generation) { [weak self] result in
            let displayed = result.pose.flatMap {
                DartPracticeCameraCoordinates.viewportQuadrilateral(rawTopLeft: $0.quadrilateral, displayTransform: transform)
            }
            // Work stays off the main actor. A result is only used if the same
            // request, action, camera and viewport are still current below.
            let check: DartOutlineCheckResult? = request.flatMap { request in
                guard result.timestamp >= request.requestedAt else { return nil }
                return DartOutlineChecker.evaluate(image: result.luminance ?? PaperLuminanceImage(width: 0, height: 0, pixels: []),
                                                   pose: displayed == nil ? nil : result.pose?.quadrilateral,
                                                   state: request.action, timestamp: result.timestamp)
            }
            Task { @MainActor [weak self] in
                guard let self, self.isDartPractice, !self.needsRescan, !self.practiceTrackingLost,
                      generation == self.paperRegistrationRevision, result.generation == generation,
                      cameraGeneration == self.cameraSessionRevision,
                      self.arView?.bounds.size == viewportSize,
                      (self.arView?.window?.windowScene?.interfaceOrientation ?? .portrait) == orientation else { return }
                self.receiveDartPracticeFrame(timestamp: result.timestamp, displayedPose: displayed, request: request, check: check)
            }
        }
    }

    /// Testable freshness/request boundary. Neither a visual match nor an
    /// unknown result changes the learner's current action.
    func receiveDartPracticeFrame(timestamp: TimeInterval, displayedPose: PaperQuadrilateral?,
                                  request: DartPracticeCheckRequest?, check: DartOutlineCheckResult?,
                                  now: TimeInterval = CACurrentMediaTime()) {
        guard isDartPractice, !needsRescan, !practiceTrackingLost, timestamp.isFinite, now.isFinite,
              timestamp <= now, now - timestamp <= PaperGuideSession.maximumObservationAge,
              lastPracticeObservation.map({ timestamp > $0 }) ?? true else { return }
        lastPracticeObservation = timestamp
        practiceMarkerVisible = displayedPose != nil
        receivePrintedPracticePose(displayedPose, timestamp: timestamp)
        guard let request, request == practiceCheckRequest,
              request.action == dartPractice.currentAction, let check,
              check.timestamp == timestamp, timestamp >= request.requestedAt else { return }
        if dartPractice.recordCheck(check, at: now) {
            practiceCheckRequest = nil; practiceCheckBusy = false
            _ = practiceProgressStore.save(dartPractice)
        }
    }

    func handleDartPracticeTrackingLoss() {
        guard isDartPractice else { return }
        if !practiceTrackingLost { restartPaperGuideTracking() }
        practiceTrackingLost = true
        practiceCameraMessage = "Move slowly and show the flat marked sheet. Alignment resumes after camera tracking recovers."
    }

    func updateDartPracticeFixture() {
        guard isDartPractice, isPaperGuideFixture, !needsRescan, !dartPractice.completed else { return }
        let now = CACurrentMediaTime()
        let quad = practiceFixtureVisible ? PaperQuadrilateral(topLeft: CGPoint(x: 0.22, y: 0.12), topRight: CGPoint(x: 0.78, y: 0.12), bottomRight: CGPoint(x: 0.78, y: 0.88), bottomLeft: CGPoint(x: 0.22, y: 0.88)) : nil
        practiceMarkerVisible = quad != nil
        lastPracticeObservation = now
        receivePrintedPracticePose(quad, timestamp: now)
    }

    func setDartPracticeFixtureVisible(_ visible: Bool) {
        guard isDartPractice, isPaperGuideFixture else { return }
        practiceFixtureVisible = visible
        updateDartPracticeFixture()
    }
}
