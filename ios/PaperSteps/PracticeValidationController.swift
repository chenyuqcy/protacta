import ARKit
import Foundation
import Darwin

struct PracticeValidationIdentity {
    var sessionID = UUID().uuidString.lowercased()
    var operatorID = ""
    var sheetID = ""
    var attemptID = ""
    var split: PracticeValidationSample.Split = .development

    var isValid: Bool {
        [sessionID, operatorID, sheetID, attemptID].allSatisfy(Self.validID)
    }
    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && value.utf8.count <= 80 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.").contains($0)
        }
    }
}

struct PracticeValidationRequest {
    let id = UUID()
    let identity: PracticeValidationIdentity
    let action: Int
    let requestedAt: TimeInterval
    let cameraRevision: Int
    let registrationRevision: Int

    func accepts(frameTimestamp: TimeInterval, action: Int, cameraRevision: Int,
                 registrationRevision: Int, now: TimeInterval) -> Bool {
        identity.isValid && (1...10).contains(self.action) && self.action == action && self.cameraRevision == cameraRevision &&
        self.registrationRevision == registrationRevision &&
        frameTimestamp.isFinite && requestedAt.isFinite && now.isFinite &&
        requestedAt >= 0 && frameTimestamp >= requestedAt && frameTimestamp <= now && now - requestedAt <= 2
    }
}

extension LessonController {
    var validationEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--practice-validation")
        #else
        return false
        #endif
    }

    var validationAllowsPhysicalCamera: Bool {
        #if DEBUG && !targetEnvironment(simulator)
        return validationEnabled && !isPaperGuideFixture &&
            !ProcessInfo.processInfo.arguments.contains("--ui-testing") &&
            !ProcessInfo.processInfo.arguments.contains("--paper-guide-fixture")
        #else
        return false
        #endif
    }

    var canSaveValidationSample: Bool {
        validationAllowsPhysicalCamera && Self.supportsAR && isDartPractice &&
        !dartPractice.completed && !needsRescan && !practiceTrackingLost && cameraError == nil &&
        !validationBusy && validationIdentity.isValid
    }

    var validationAvailabilityMessage: String {
        if !validationAllowsPhysicalCamera {
            return "Real test recording needs a Debug build on an iPhone or iPad. Simulator drawings cannot become physical evidence."
        }
        if !validationIdentity.isValid { return "Enter short anonymous operator, sheet and attempt IDs in Practice setup before saving." }
        if dartPractice.completed { return "Reopen an action before recording its camera check." }
        if needsRescan || practiceTrackingLost || cameraError != nil { return "Recover the camera before saving a test frame." }
        return "Save one full camera image and its analysis locally. Nothing is uploaded. Normal practice does not save photos."
    }

    func requestValidationSample() {
        guard canSaveValidationSample else { validationStatus = validationAvailabilityMessage; return }
        validationRequest = PracticeValidationRequest(identity: validationIdentity,
                                                      action: dartPractice.currentAction,
                                                      requestedAt: ProcessInfo.processInfo.systemUptime,
                                                      cameraRevision: cameraSessionRevision,
                                                      registrationRevision: paperRegistrationRevision)
        validationFrameInFlight = false
        validationBusy = true
        validationStatus = "Waiting for the next camera frame…"
    }

    func resetValidationCapture(generation: Int) {
        if validationBusy { validationStatus = "Capture canceled because the camera or action changed. No old result is reused." }
        validationRequest = nil
        validationFrameInFlight = false
        validationBusy = false
        validationCapture.reset(generation: generation)
    }

    func expireValidationCapture(at now: TimeInterval) {
        guard let request = validationRequest, now - request.requestedAt > 2 else { return }
        validationRequest = nil; validationFrameInFlight = false; validationBusy = false
        validationStatus = "No current frame arrived. Nothing was saved; recover the camera and try again."
    }

    func finishValidationCapture(_ request: PracticeValidationRequest, frame: PrintedPaperFrame,
                                 pixelBuffer: CVPixelBuffer, result: DartOutlineCheckResult,
                                 viewportSize: CGSize, orientation: UIInterfaceOrientation,
                                 transform: CGAffineTransform) {
        let now = ProcessInfo.processInfo.systemUptime
        guard validationAllowsPhysicalCamera, validationRequest?.id == request.id,
              request.accepts(frameTimestamp: frame.timestamp, action: dartPractice.currentAction,
                              cameraRevision: cameraSessionRevision, registrationRevision: paperRegistrationRevision, now: now) else { return }
        let expired = now - frame.timestamp > PaperGuideSession.maximumObservationAge
        let exportedResult = expired ? DartOutlineCheckResult(checkpointID: result.checkpointID,
                                                              referenceState: result.referenceState, outcome: .cannotJudge,
                                                              message: "This processed frame was too old for live guidance.",
                                                              mismatchedPoints: [], timestamp: frame.timestamp) : result
        // The immutable identity is copied when the person presses Save; later
        // edits to labels cannot relabel an already requested physical frame.
        let origin = "\(request.identity.sessionID)_frame_\(String(format: "%.9f", frame.timestamp))"
        let sample = PracticeValidationSample(source: .physicalCamera, split: request.identity.split,
                                             sessionID: request.identity.sessionID, operatorID: request.identity.operatorID,
                                             sheetID: request.identity.sheetID, attemptID: request.identity.attemptID,
                                             originID: origin, sourceBasename: origin + ".png",
                                             courseRevision: DartPracticeCourse.revision,
                                             appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                                             appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                                             deviceModel: Self.validationDeviceModel, osVersion: UIDevice.current.systemVersion,
                                             capturedUptime: frame.timestamp, processedUptime: frame.processedUptime,
                                             processingFailure: frame.processingFailure,
                                             processingMs: max(0, frame.processedUptime - frame.processingStartedUptime) * 1000,
                                             frameAgeMs: max(0, now - frame.timestamp) * 1000,
                                             frameDisposition: expired ? .expired : .fresh,
                                             imageWidth: CVPixelBufferGetWidth(pixelBuffer), imageHeight: CVPixelBufferGetHeight(pixelBuffer),
                                             viewportSize: viewportSize, viewportOrientation: Self.validationOrientation(orientation),
                                             rawToViewport: transform, rawSheetQuadrilateral: frame.pose?.quadrilateral,
                                             markerQuadrilaterals: frame.pose?.markerQuads ?? [:], result: exportedResult)
        validationRequest = nil
        validationFrameInFlight = false
        validationStatus = "Saving one local camera sample…"
        let accepted = validationCapture.save(pixelBuffer: pixelBuffer, sample: sample,
                                               frameTimestamp: frame.timestamp, generation: request.registrationRevision) { [weak self] outcome in
            Task { @MainActor [weak self] in
                guard let self, request.registrationRevision == self.paperRegistrationRevision,
                      request.cameraRevision == self.cameraSessionRevision else { return }
                self.validationBusy = false
                switch outcome {
                case .success(let directory):
                    self.lastValidationDirectory = directory
                    self.validationStatus = "Saved one local test photo and metadata. No human label or physical acceptance has been assigned."
                case .failure:
                    self.validationStatus = "The local sample could not be saved. Nothing was uploaded; try again."
                }
            }
        }
        if !accepted {
            validationBusy = false
            validationStatus = "The previous capture is still finishing. Try saving again in a moment."
        }
    }

    private static func validationOrientation(_ orientation: UIInterfaceOrientation) -> String {
        switch orientation {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        default: return "unknown"
        }
    }

    private static var validationDeviceModel: String {
        var info = utsname()
        guard uname(&info) == 0 else { return "unknown" }
        let count = MemoryLayout.size(ofValue: info.machine)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: count) { String(cString: $0) }
        }
    }
}
