import Foundation

enum LessonVoiceResponse: Equatable {
    case message(String)
    case narration(String)
}

extension LessonController {
    var canUseVoiceGuide: Bool { started && hasLessonAccess }

    /// The same access, tracking and playback gates apply to buttons and voice.
    /// Recognition never changes geometry, grants access or confirms a real fold.
    func performVoiceCommand(_ command: VoiceCommand) -> LessonVoiceResponse {
        if command == .stopListening { return .message("Voice control is off.") }
        guard hasLessonAccess else { return .message("This lesson requires full library access.") }
        guard started else { return .message("Start or continue a lesson first.") }

        switch command {
        case .readStep:
            pauseAndSave()
            return .narration("\(currentStep.title). \(currentStep.instruction)")
        case .why:
            pauseAndSave()
            return .narration(currentStep.explanation)
        case .explainSimply, .help:
            pauseAndSave()
            guard let help = FoldHelp.forStep(lesson: lesson, stepIndex: stepIndex) else {
                return .message("Open the written notes for this fold.")
            }
            if command == .explainSimply { return .narration(help.simplerInstruction) }
            return .narration("\(help.simplerInstruction) Check your fold: \(help.checkpoint) Watch out: \(help.commonMistake)")
        case .pause:
            pauseAndSave()
            return .message("Fold paused.")
        case .slower, .normalSpeed:
            slowMotion = command == .slower
            saveLearningProgress()
            return .message(slowMotion ? "Playback set to half speed." : "Playback set to normal speed.")
        case .next, .back, .replay, .restart, .resume:
            guard canAnimate else {
                return .message(isPaperGuide ? "Use the 3D guide to play the fold animation. The paper guide shows the center crease on your real sheet." : "Place the paper and wait for stable tracking before playing a fold.")
            }
            switch command {
            case .next:
                guard !completed else { return .message("Lesson complete. Say Restart lesson when you have a new sheet.") }
                guard !isPlaying else { return .message("The fold is playing. Wait for it to finish, or say Pause.") }
                let finishingPartialFold = progress < 0.999
                next()
                return .message(completed ? "Lesson complete." : finishingPartialFold ? "Finishing this fold." : "Playing the next fold.")
            case .back:
                guard stepIndex > 0 else { return .message("You are at the beginning of this lesson.") }
                back()
                return .message("Previous step.")
            case .replay:
                guard stepIndex > 0 else { return .message("Say Next fold to begin the first fold.") }
                replay()
                return .message("Replaying this fold.")
            case .restart:
                // Reset only the current teaching state. begin() leaves the AR
                // session, table anchor, placement transform and access intact.
                begin()
                return .message("Lesson restarted with a flat sheet. Say Next fold when you are ready.")
            case .resume:
                guard !completed, stepIndex > 0, progress < 0.999 else {
                    return .message("This step is finished. Say Next fold to continue.")
                }
                guard !isPlaying else { return .message("The fold is already playing.") }
                togglePlayback()
                return .message("Continuing this fold.")
            default:
                return .message("Use one command at a time.")
            }
        case .stopListening:
            return .message("Voice control is off.")
        }
    }
}
