import Foundation

/// Original English notes for a private, source-referenced geometry prototype.
/// These authored explanations are not AI or camera-based folding assessment.
enum FullFoxLessonContent {
    static let title = "The Long-Tail Fox"
    static let material = "One 15 × 15 cm square · Thin paper recommended"
    static let sourceName = "Adapted from Caleb Witte’s Fox · OrigamiUSA"
    static let sourceURL = URL(string: "https://origamiusa.org/thefold/article/diagrams-fox-1")!
    static let sourcePanels = [0,1,2,3,5,6,8,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27]
    static let steps: [LessonStep] = {
        let rows: [(String,String,String,String)] = [
            ("Begin with one square", "Lay a thin square flat, with one diagonal running left to right. The left corner will supply the head; the right corner will supply the tail.", "ONE UNCUT SQUARE", "The two remaining corners become small flaps that later form the front legs."),
            ("Mark the first edge guides", "At the right end, bring each highlighted outer edge toward the long diagonal. Press the crease, then open the paper again.", "CREASE AND REOPEN", "These temporary folds locate one side of each rabbit ear. Both sides are shown in this action."),
            ("Mark the matching edge guides", "Repeat the edge-to-diagonal folds from the left end, opening the square after each crease.", "MATCH BOTH SIDES", "The crossing guides locate the inner hinge where several folds will meet."),
            ("Collapse the fish base", "Lift the two side corners along their guides and close them into small rabbit-ear flaps. Lay both small points toward the right.", "TWO SMALL FLAPS", "Several hinges move together. Keep the long left and right points in place while the side corners come inward."),
            ("Mark the broad corner folds", "Fold each broad side corner to the middle of the base, then open it again. Leave the two small points accessible.", "MARK BOTH CORNERS", "These guides prepare the broad corners to turn inward. Open the paper again after each crease."),
            ("Fold the broad corners inward", "Turn each marked broad corner inward along its guide, one side at a time. Keep the small pointed flaps free.", "CORNERS INWARD", "These inward folds narrow the body while keeping the two small flaps accessible for the front legs."),
            ("Close the long body", "Fold the upper half behind the lower half along the long middle line.", "LONG EDGE TO LONG EDGE", "The base becomes a narrow layered shape. Keep the small flaps free for the legs."),
            ("Reverse the tail point", "Open the two body halves fully to reveal the tail creases. Turn the long right point down while bringing the halves back together, enclosing the point between them.", "RIGHT POINT DOWN", "Opening the body reveals the two tail creases. The tail changes direction as both halves close around it."),
            ("Move the small flaps left", "Fold the visible small point toward the left. Make the matching fold on the flap behind it.", "BOTH SMALL POINTS LEFT", "These flaps will become the legs; moving them aside gives access to the tail."),
            ("Open the front tail layer", "Lift only the highlighted front layer of the reversed tail and fold it across the diagonal guide.", "FRONT LAYER ONLY", "The two paper halves overlap here. Moving every visible layer would change the wrong part of the body."),
            ("Raise the tail section", "Bring the hanging tail point upward around the diagonal crease, keeping the long body still.", "TAIL UP", "The connected tail flap moves even though other paper lies on the same side of the guide."),
            ("Tuck the rear tail layer", "Fold the remaining rear tail layer behind the diagonal edge to make a narrow triangular tail section.", "REAR LAYER BEHIND", "The front and rear operations produce the same outer tail outline from different paper layers."),
            ("Crimp the tail base", "Mark a meeting point one fifth of the way from the lower root toward the tail tip. Fold at the upper guide first, then return the point along the lower guide.", "SHORT ZIGZAG", "This version uses a shallower crimp to leave a longer visible tail. The two guide lines meet at the marked point on the original free edge."),
            ("Reverse the tail outward", "Open the tail layers and turn the upper point across the upright guide. Close them with the point on the outside.", "TAIL POINT OUT", "The tail now extends from its folded root. Follow the tail component rather than turning the whole body."),
            ("Bring the leg flaps forward", "Return both small flaps toward the tail end, one at a time. Reorient the model so the long head section rises above them.", "TWO LEG FLAPS", "Changing the viewing direction adds no crease. The small flaps retain their original attachment to the body."),
            ("Angle the front legs", "Fold the outer portion of each small flap behind its sloping guide.", "ONE LEG, THEN THE OTHER", "Keep the upper attachment still and follow the sloping guide across each flap. Match the second leg to the first."),
            ("Reverse the leg points", "Open each narrow leg fold and turn its point through the indicated crease, then close it again.", "POINTS FORWARD", "The points come around the inside of the leg folds instead of forming an extra loose flap."),
            ("Narrow the leg edges", "Tuck the short inner margin of each leg behind the highlighted line.", "SMALL INNER EDGES", "This local shaping keeps the visible leg point long while reducing the bulky inner corner."),
            ("Raise the neck", "Open the long left section at its lower angled guide. Reverse the section outward and close it in its new direction.", "LONG SECTION UP", "The original left corner supplies the entire neck, head and nose; no separate piece is added."),
            ("Turn the head downward", "Reverse the long head point inside the layers around the upper sloping guide.", "HEAD POINT DOWN", "Hold the lower neck still while the long tip changes direction."),
            ("Bring the head point up", "Make the next inside reverse along the indicated edge and bring the long point back upward.", "FOLLOW THE INNER HINGE", "The same tip passes through a second reverse. The broad layers beside it will remain as the ears."),
            ("Turn out the muzzle", "Reverse the long point outward over the upper guide so it extends in front of the face.", "MUZZLE FORWARD", "The head now has a broad ear section and a long narrow point for the muzzle."),
            ("Shorten the muzzle", "Fold the muzzle back at the first crimp line, then forward at the second line carried with the folded paper.", "TWO CLOSE FOLDS", "The second hinge belongs to the moving paper. This shortens the muzzle while retaining the original nose point."),
            ("Roll the nose tip twice", "Turn the tiny end of the muzzle inward. Make a second small turn behind it to blunt the tip.", "TINY TIP FOLDS", "Use light pressure at this small scale. The two turns produce a short nose without cutting the paper."),
            ("Shape and stand the fox", "Ease the paired ears and legs apart, soften the tail, and stand the model upright on its lower folds.", "GENTLE FINAL SHAPING", "Curve the tail gently instead of pinching it into a sharp zigzag. Open the ears and legs a little at a time, keeping their roots together.")
        ]
        return rows.enumerated().map { index,row in
            LessonStep(id:index,title:row.0,instruction:row.1,cue:row.2,explanation:row.3)
        }
    }()
}
