import Foundation

struct LessonStep: Identifiable {
    let id: Int
    let title: String
    let instruction: String
    let cue: String
    let explanation: String
}

enum PaperLesson {
    static let title = "The Classic Dart"
    static let material = "One white A4 sheet · No cutting or glue"
    static let sourceName = "Fold 'N Fly · Basic Dart"
    static let sourceURL = URL(string: "https://www.foldnfly.com/1.html")!

    // Each index matches one PaperGeometry state. Explanations are authored lesson
    // notes, not AI answers or camera-based assessments of the user's paper.
    static let steps: [LessonStep] = [
        LessonStep(
            id: 0,
            title: "Start with a blank sheet",
            instruction: "Lay an A4 sheet flat with a short edge at the top. Left and right follow this nose-up view.",
            cue: "SHORT EDGE AT THE TOP",
            explanation: "A consistent starting direction makes the next folds easier to follow. The finished nose will point toward this top edge."
        ),
        LessonStep(
            id: 1,
            title: "Make the center crease",
            instruction: "Bring the left long edge onto the right long edge. Match the corners, then press the fold.",
            cue: "LEFT EDGE TO RIGHT EDGE",
            explanation: "This crease is a guide for the nose and body. Matching the edges now helps both sides stay even."
        ),
        LessonStep(
            id: 2,
            title: "Open the sheet",
            instruction: "Unfold the sheet and smooth it flat. Keep the center crease running from top to bottom.",
            cue: "UNFOLD AND KEEP THE CREASE",
            explanation: "We reopen the paper to work on each corner. The center crease remains our reference line."
        ),
        LessonStep(
            id: 3,
            title: "Fold the left corner",
            instruction: "Swing the top-left corner inward. Match its top edge to the center crease and press the diagonal fold.",
            cue: "TOP-LEFT CORNER INWARD",
            explanation: "The diagonal fold begins the pointed nose. Keep the edge beside the center crease without crossing it."
        ),
        LessonStep(
            id: 4,
            title: "Fold the right corner",
            instruction: "Repeat with the top-right corner. Bring its top edge to the center crease so the two folds match.",
            cue: "MATCH THE OTHER CORNER",
            explanation: "The two corners should form matching triangles. Compare their edges before pressing the second crease."
        ),
        LessonStep(
            id: 5,
            title: "Narrow the left side",
            instruction: "Bring the upper left sloping edge to the center crease. Keep the nose pointed and flatten the fold.",
            cue: "LEFT SLOPING EDGE TO CENTER",
            explanation: "This second fold makes the nose narrower and adds another paper layer near the front."
        ),
        LessonStep(
            id: 6,
            title: "Narrow the right side",
            instruction: "Bring the upper right sloping edge to the center crease. Match the left side and press the fold.",
            cue: "RIGHT SLOPING EDGE TO CENTER",
            explanation: "Check that the two long edges meet evenly. An uneven fold here carries through into the finished wings."
        ),
        LessonStep(
            id: 7,
            title: "Close the body",
            instruction: "Lift the paper. Fold the left half underneath the right along the center crease, keeping the nose layers outside.",
            cue: "LEFT HALF UNDERNEATH",
            explanation: "Keep the nose pointing away as you hold the paper. The center crease becomes the bottom edge; the outside layers will form wings."
        ),
        LessonStep(
            id: 8,
            title: "Fold the first wing",
            instruction: "Hold the body and fold the highlighted outer flap down. Match its long sloping edge to the body's bottom edge.",
            cue: "OUTER EDGE TO BODY EDGE",
            explanation: "Leave a narrow body beneath the wing. Press this crease firmly; it sets the shape to match on the other side."
        ),
        LessonStep(
            id: 9,
            title: "Fold the other wing",
            instruction: "Repeat on the opposite side. Fold the other outer edge to the body edge, matching the first wing.",
            cue: "MATCH BOTH WING FOLDS",
            explanation: "Compare the wing outlines and crease positions. Matching both sides gives you a more even starting shape."
        ),
        LessonStep(
            id: 10,
            title: "Open your finished wings",
            instruction: "Lift both wings until they sit level, with the narrow body below. Your paper dart is complete.",
            cue: "WINGS LEVEL · BODY BELOW",
            explanation: "Look from the front to compare the wings. Hold the body gently for a test glide in a clear space, away from people."
        )
    ]
}
