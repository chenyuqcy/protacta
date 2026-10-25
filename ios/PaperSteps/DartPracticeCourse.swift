import CryptoKit
import Foundation

struct DartPracticeAction: Identifiable, Equatable {
    let id: Int
    let title: String
    let instruction: String
    let explanation: String
    let manualCheckpoint: String
    let commonMistake: String
}

/// Complete authored practice sequence. The comparison notes are draft teaching
/// help awaiting real-paper review, not implemented visual assessment criteria.
enum DartPracticeCourse {
    static let requiresRealPaperReview = true
    static let reviewNotice = "Draft practice guide. The full course and camera comparisons still need real-paper review."
    static let creaseAmbiguityNote = "A flat outline cannot show that you made the center crease. Compare the crease yourself; an outline match only checks the visible boundary."

    static let actions: [DartPracticeAction] = PaperLesson.steps.dropFirst().map { step in
        let help = manualHelp[step.id]
        return DartPracticeAction(id: step.id, title: step.title,
                                  instruction: step.instruction, explanation: step.explanation,
                                  manualCheckpoint: help?.checkpoint ?? "Compare your paper with the end of the 3D animation before continuing.",
                                  commonMistake: help?.mistake ?? "Keep the same orientation and replay to see which layer moves.")
    }

    /// Fingerprint both source wording and the added teaching/checkpoint notes.
    /// Bump the geometry/checkpoint revision when semantics change independently.
    static let revision: String = {
        var fields = ["Protacta Classic Dart practice v1", "geometry=1", "outline-checkpoints=1", creaseAmbiguityNote]
        for action in actions {
            fields += [String(action.id), action.title, action.instruction,
                       action.explanation, action.manualCheckpoint, action.commonMistake]
        }
        let text = fields.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }()

    /// UI-safe lookup; persisted state is validated rather than clamped on load.
    static func action(_ id: Int) -> DartPracticeAction {
        actions[min(actions.count, max(1, id)) - 1]
    }

    /// These are candidate planar states, not a claim that an outline proves a
    /// fold's correctness. State 0/2 share the same boundary and hide crease work.
    static func supportsOutlineCheck(state: Int) -> Bool {
        state == 0 || (2...6).contains(state)
    }

    static func supportsPlanarCue(beforeState: Int) -> Bool {
        beforeState == 0 || (2...6).contains(beforeState)
    }

    private static let manualHelp: [Int: (checkpoint: String, mistake: String)] = [
        1: ("Compare the exposed long edges and corners before pressing the center fold. Matching the visible edges does not prove that hidden layers align.",
            "Bring the left long edge onto the right long edge. Match the corners before pressing; do not use a short edge."),
        2: ("Open the whole sheet and compare its center crease from top to bottom. The flat outer boundary cannot verify that crease.",
            "Unfold only the last center fold. Keep the short edge at the top and smooth the sheet without removing your crease."),
        3: ("Compare the left flap with the 3D guide. Its original top edge should sit beside the center crease without crossing it.",
            "Work on the top-left corner in the nose-up view. Replay if you cannot identify the corner or center reference."),
        4: ("Compare the two triangular corner folds. Look at their exposed edges beside the center crease before pressing the second fold.",
            "Repeat on the top-right corner. Do not move the already folded left flap or assume that a symmetric outline proves the hidden layers are right."),
        5: ("Compare the narrowed left side with the guide. Keep the nose pointed and bring the upper left sloping edge toward the center crease.",
            "Move the highlighted left section for this second fold. The right side stays at the earlier stage until the next action."),
        6: ("Compare the two exposed long edges. They should meet evenly near the center while the nose stays pointed.",
            "Make the matching narrowing fold on the right. Check the visible edge positions before pressing; do not crush the nose."),
        7: ("Use the side view to compare the closed body. The left half goes underneath the right, with the nose layers outside.",
            "Lift the paper for the underneath motion. A flat camera outline cannot identify hidden layer order; replay the 3D action if unsure."),
        8: ("Compare the highlighted outer flap and the body's bottom edge. Leave a narrow body beneath the first wing.",
            "Fold the outer flap shown in the animation, not every layer together. Change the 3D view to see which edge meets the body."),
        9: ("Compare both wing outlines and their crease positions. Match the second wing to the first before opening them.",
            "Work on the opposite side. One camera view can hide the first wing or the body; compare manually using the 3D reference."),
        10: ("Look from the front: compare the wing heights, with the narrow body below. This is your own completion check, not a camera-verified result.",
             "Open the existing wing folds gently. Do not flatten the body up into the wings; use the finished 3D reference to compare.")
    ]
}
