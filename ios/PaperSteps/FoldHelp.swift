/// Authored help tied to the existing lesson steps. Checkpoints are for the
/// learner to compare; they do not assess camera images or verify a real fold.
struct FoldHelp {
    let simplerInstruction: String
    let checkpoint: String
    let commonMistake: String

    static func forStep(lesson: OrigamiLesson, stepIndex: Int) -> FoldHelp? {
        let steps = lesson.steps
        guard steps.indices.contains(stepIndex) else { return nil }
        let step = steps[stepIndex]

        switch (lesson, stepIndex) {
        case (.crane, 3):
            return FoldHelp(
                simplerInstruction: "Lift the top flap. Open the pocket inside it, then flatten that pocket into a diamond.",
                checkpoint: "Compare the diamond with the guide. Its center crease should stay straight, with the other layers underneath.",
                commonMistake: "Move the upper layers, not the whole stack. Support the paper underneath while opening the pocket."
            )
        case (.crane, 5):
            return FoldHelp(
                simplerInstruction: "Open the remaining triangular pocket. Flatten it into a diamond like the first one.",
                checkpoint: "Check the square base against the guide: the loose, opening corners point down and the closed tip points up.",
                commonMistake: "Check which end opens before continuing. The loose corners need to stay at the bottom for the next folds."
            )
        case (.crane, 9):
            return FoldHelp(
                simplerInstruction: "Lift only the front bottom corner. Bring both sides inward on the creases you marked, then flatten the long diamond.",
                checkpoint: "Compare the raised front flap with the guide. The side edges fold inward as this one layer rises.",
                commonMistake: "Do not lift all the bottom layers together. Keep the side folds on the existing creases and replay to see which layer moves."
            )
        case (.crane, 14):
            return FoldHelp(
                simplerInstruction: "Lift the bottom corner facing you. Fold its sides inward on their creases, then flatten this second long diamond.",
                checkpoint: "Compare your bird base with the guide. Look for the broad upper flaps and two separate points below.",
                commonMistake: "Work on the visible pocket. Keep the two lower points separate; they will become the neck and tail."
            )
        case (.crane, 22):
            return FoldHelp(
                simplerInstruction: "Open the layers around the left point a little. Lift that point up between the layers on its marked crease, then close them.",
                checkpoint: "Compare the left neck with the guide. It rises from inside the surrounding layers after you close them.",
                commonMistake: "The left point goes inside the layers. Replay the opening motion if it is unclear where to tuck it."
            )
        case (.crane, 23):
            return FoldHelp(
                simplerInstruction: "Open the layers around the right point. Raise the point between them on its crease, then close the body again.",
                checkpoint: "Compare both raised points with the guide: the right tail is up and the left neck stays raised.",
                commonMistake: "Use the right point for this fold. Keep the left neck raised while the tail moves inside the layers."
            )
        case (.crane, 25):
            return FoldHelp(
                simplerInstruction: "Open the neck layers slightly. Push just the small tip down inside on the crease you made, then close the layers around it.",
                checkpoint: "Compare the little beak at the end of the left neck with the guide. The small tip turns downward inside the neck layers.",
                commonMistake: "Use the small crease near the tip. This step folds the beak, not the whole neck."
            )
        case (.star, 1):
            return FoldHelp(
                simplerInstruction: "Near the left end, curve the strip into a loose loop. Leave a short tip and a long tail.",
                checkpoint: "Compare the loop with the guide. Leave an opening large enough for the short tip to pass through next.",
                commonMistake: "Keep the loop loose for now. Tightening it before threading the tip makes the next movement harder to follow."
            )
        case (.star, 2):
            return FoldHelp(
                simplerInstruction: "Pass the short tip through the loop and out the other side. Hold the long tail gently.",
                checkpoint: "Pause the guide at the end of the movement. Compare where the short tip passes through the loop.",
                commonMistake: "Thread the short tip, not the long tail. Replay or turn the model to inspect the crossing."
            )
        case (.star, 3):
            return FoldHelp(
                simplerInstruction: "Ease the knot snug with small adjustments. Flatten it gently into a five-sided shape.",
                checkpoint: "Compare the flat pentagon with the guide. Look for five sides and no open gaps in the knot.",
                commonMistake: "Avoid a hard pull. Adjust the corners a little at a time; the knot stays flat at this stage."
            )
        case (.star, 4):
            return FoldHelp(
                simplerInstruction: "Fold the short tip against the pentagon. Slide it beneath a nearby paper layer.",
                checkpoint: "Compare the tucked short tip with the guide. It should sit inside the pentagon's outline.",
                commonMistake: "Use the short tip here. The long tail remains available for wrapping around the pentagon next."
            )
        case (.star, 7):
            return FoldHelp(
                simplerInstruction: "Keep wrapping the long tail around each next edge of the pentagon. Turn the paper as needed and stop with a short final tip.",
                checkpoint: "Compare the five-sided outline with the guide. Replay to follow the repeated wraps and the short tip left at the end.",
                commonMistake: "Your number of wraps can vary. Follow the edges and keep each wrap tidy without crushing the paper."
            )
        case (.star, 8):
            return FoldHelp(
                simplerInstruction: "Slide the last short tip under an outer paper layer to hold the wrapping in place.",
                checkpoint: "Compare with the guide: the end is tucked in and the shape is still a compact, flat pentagon.",
                commonMistake: "Use a nearby pocket that accepts the tip without force. Shape the sides only after this tuck."
            )
        case (.star, 9):
            return FoldHelp(
                simplerInstruction: "Hold the pentagon by its edges. Use a fingernail to gently press the middle of the highlighted side inward.",
                checkpoint: "Compare the first pressed side with the guide. The side moves inward while the surrounding paper begins to lift.",
                commonMistake: "Press the side, not the broad face. Squeezing the broad faces flat works against the rounded shape."
            )
        case (.star, 13):
            return FoldHelp(
                simplerInstruction: "Press the middle of the last side inward. Gently adjust all five points to finish the little rounded star.",
                checkpoint: "Turn the guide and compare all five points and the star's thickness. Keep your paper star lightly rounded.",
                commonMistake: "Use gentle adjustments around the sides. Avoid crushing the raised faces flat."
            )
        default:
            if stepIndex == 0 {
                return FoldHelp(
                    simplerInstruction: step.instruction,
                    checkpoint: "Check the paper listed for this lesson: \(lesson.material).",
                    commonMistake: "Check the paper's starting orientation before making the first fold."
                )
            }
            return FoldHelp(
                simplerInstruction: step.instruction,
                checkpoint: "Compare your paper with the end of this animation before continuing.",
                commonMistake: "Keep the same orientation as the guide. Replay if you are unsure which layer moves."
            )
        }
    }
}
