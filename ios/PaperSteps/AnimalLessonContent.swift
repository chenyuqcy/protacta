import Foundation

/// Original wording for traditional folds. Notes explain the current action;
/// they do not claim to inspect or assess the learner's real paper.
enum AnimalLessonContent {
    static func material(for kind: AnimalKind) -> String {
        "One 15 × 15 cm square · No cutting or glue"
    }
    static func sourceName(for kind: AnimalKind) -> String {
        switch kind {
        case .fox: return "Origami Way · Easy Fox Head"
        case .rabbit: return "Ingenium · Origami Rabbit"
        case .butterfly: return "San Diego Public Library · Traditional Butterfly"
        }
    }
    static func sourceURL(for kind: AnimalKind) -> URL {
        switch kind {
        case .fox: return URL(string: "https://www.origamiway.com/easy-origami-fox-head/")!
        case .rabbit: return URL(string: "https://ingenium.ca/en/learn/science-at-home/origami-rabbit/")!
        case .butterfly: return URL(string: "https://www.sandiego.gov/sites/default/files/fold_an_origami_butterfly.pdf")!
        }
    }
    static func steps(for kind: AnimalKind) -> [LessonStep] {
        switch kind { case .fox: return fox; case .rabbit: return rabbit; case .butterfly: return butterfly }
    }
    private static func lesson(_ rows: [(String, String, String, String)]) -> [LessonStep] {
        rows.enumerated().map { index, row in LessonStep(id: index, title: row.0, instruction: row.1, cue: row.2, explanation: row.3) }
    }
    static let fox = lesson([
        ("Begin with a diamond", "Place a square with one corner pointing away. Keep the side you want outside facing down.", "ONE CORNER POINTS AWAY", "A square with equal sides gives the two ears matching starting points. Plain white paper works too."),
        ("Make the large triangle", "Bring the far corner to the near corner. Line up both edges and press the long fold.", "FAR CORNER TO NEAR CORNER", "The closed edge will run across the top of the face. The corner nearest you becomes its pointed chin."),
        ("Find the middle", "Bring the left corner across to the right. Press the center fold gently.", "MATCH THE TWO SIDE POINTS", "This temporary fold marks the center of the face so the two ears can be balanced."),
        ("Open the triangle", "Unfold the last move. Keep the long edge at the top and the single point facing you.", "REOPEN THE CENTER FOLD", "The center mark is only a guide. Both side corners need to be free for the ear folds."),
        ("Lift the left ear", "Swing the left corner upward along the angled guide. Leave its tip to the left of the center line.", "LEFT POINT UP AND IN", "The ear fold begins at the lower point. Changing the angle slightly changes your fox's expression."),
        ("Match the right ear", "Fold the right corner upward. Compare the two tips before pressing this crease.", "TWO POINTED EARS", "Aim for a similar height and distance from the center. A tiny difference gives the face character."),
        ("Reveal your fox", "Turn the whole model over. Your pointed ears and tapered face are complete. Add eyes and a nose on your real paper if you like.", "TURN THE WHOLE MODEL OVER", "This is a turn, not another crease. Optional pencil details make the folded silhouette into your own character.")
    ])
    static let rabbit = lesson([
        ("Prepare a square", "Place a 15 cm square like a diamond. The corner nearest you will travel upward first.", "SQUARE PAPER · DIAMOND VIEW", "Thin paper makes the narrow ears easier to flatten. Put your chosen outside color face down."),
        ("Fold a triangle", "Bring the near corner to the far corner. Match the two points and press the long edge.", "BOTTOM POINT TO TOP POINT", "Keep the triangular point facing away. Its long bottom edge will supply the rabbit's ears."),
        ("Mark the center", "Fold the left corner over to meet the right corner. Press a guide crease through the middle.", "LEFT POINT TO RIGHT POINT", "A clear center mark helps keep the two long ears evenly spaced."),
        ("Open the triangle", "Unfold the last move. Smooth the paper while keeping the center crease visible.", "UNFOLD THE LAST MOVE", "We need the full triangle for the next fold; the crease remains as an alignment guide."),
        ("Fold the ear band", "Fold a narrow strip of the long bottom edge upward. Keep its new edge straight and parallel to the old edge.", "LIFT A NARROW BOTTOM STRIP", "This strip supplies the ear width. A strip about 1.2 cm deep works well on a 15 cm square."),
        ("Raise the left ear", "Swing the left half upward along the diagonal guide. Bring the folded lower edge toward the center crease.", "LEFT SIDE UP TO CENTER", "Keep the new ear beside the center. Fold the complete stack on this side, including the narrow band."),
        ("Raise the right ear", "Repeat on the right. Compare the two long tips and press both diagonal folds.", "MATCH THE TWO LONG EARS", "The center point between the ears is still part of the forehead. We will fold only that point down later."),
        ("Turn the rabbit over", "Lift and turn the whole model over. Keep the two long ears pointing away from you.", "TURN OVER · EARS STAY UP", "The smooth reverse becomes the face. Turning the paper does not create a new fold."),
        ("Tuck the forehead back", "Fold the central point backward between the ears. Leave both long ear flaps unfolded.", "ONLY THE MIDDLE POINT GOES BACK", "Folding this small cap makes a flatter forehead. The separate ear layers stay tall and visible."),
        ("Round the chin", "Fold the little lower point behind the face. Your rabbit is complete. Decorate your real paper with a face if you like.", "SMALL LOWER POINT BEHIND", "The final short fold softens the chin. Eyes, a nose, and whiskers are optional pencil decorations.")
    ])
    static let butterfly = lesson([
        ("Prepare your square", "Set a 15 cm square on the table with an edge facing you. Start with your chosen outside color facing up.", "ONE SQUARE · EDGES STRAIGHT", "This butterfly uses a double-boat base. The first guide creases help its two pockets open without tearing."),
        ("Mark the horizontal middle", "Bring the far edge to the near edge, press the fold, then open the square again.", "FOLD IN HALF · THEN OPEN", "This line separates the two ends. Watch the animation return the paper to its starting position."),
        ("Mark the vertical middle", "Bring the left edge to the right edge and press. Open the paper again so the two center lines cross.", "MATCH THE SIDES · REOPEN", "The crossing point becomes a guide for the corners and the two long edge folds."),
        ("Crease the first diagonal", "Bring the near-left corner to the far-right corner. Press the diagonal, then open the sheet.", "CORNER TO OPPOSITE CORNER", "Match the corners before pressing. This diagonal will later bend inside one of the opening pockets."),
        ("Crease the other diagonal", "Bring the near-right corner to the far-left corner. Press and unfold once more.", "MAKE THE SECOND DIAGONAL", "The diagonal pair gives both halves the same crease pattern."),
        ("Mark four corner folds", "Bring each corner to the center. Press all four folds, then open the paper back to a square.", "FOUR CORNERS TO CENTER · OPEN", "These short diagonals guide the pocket corners outward. The demonstration folds the four independent corners together."),
        ("Bring in the left edge", "Bring the left edge to the center line. Press the long fold and leave it closed.", "LEFT EDGE MEETS THE MIDDLE", "The folded strip forms one side of each pocket. Keep its edge straight along the center guide."),
        ("Bring in the right edge", "Fold the right edge to meet the left edge at the center. Keep both strips folded.", "TWO EDGES MEET", "You now have a narrow rectangle with two loose edges down its middle."),
        ("Open the far pocket", "Lift the far end. Ease its two loose corners outward while bringing the end edge toward the center. Press the resulting trapezoid flat.", "CORNERS OUT · END EDGE IN", "This is a squash fold. Let the diagonal creases bend while the shared corners stay connected; do not pull the paper apart."),
        ("Open the near pocket", "Repeat at the near end. Pull the two corners outward and lower the end edge toward the center.", "MATCH THE SECOND POCKET", "The two flattened ends form a double-boat base. Compare their outlines before continuing."),
        ("Lift the far-left point", "Fold only the far-left loose flap upward along its diagonal. Leave the layers underneath lying flat.", "TOP LEFT FLAP ONLY", "The flap swings on the diagonal from the middle toward the far-left crease junction."),
        ("Lift the far-right point", "Raise the matching loose flap on the right. Press both folds so the two tall points match.", "MATCH THE OTHER LOOSE FLAP", "These pointed flaps become the butterfly's smaller wings. The broad boat beneath will form its larger wings."),
        ("Fold the far half behind", "Lift the far half and fold it underneath along the horizontal middle. Keep the other boat in place.", "FAR HALF GOES UNDERNEATH", "The two pairs of wings now overlap. Lift the model as the paper travels behind it."),
        ("Turn the whole model over", "Turn the paper over without making a new crease. Keep the long pointed section facing you.", "TURN OVER · POINT TOWARD YOU", "The smooth top layer is now accessible for the small shaping folds."),
        ("Narrow the left side", "Fold the left corner of the pointed section inward along the guide. Leave the broad wing underneath unchanged.", "SMALL LEFT CORNER INWARD", "This crease narrows the smaller wing near the body. Follow the highlighted layers rather than folding the broad wing."),
        ("Narrow the right side", "Make the matching shaping fold on the right. Compare the two sides and press them gently.", "MATCH THE SMALL RIGHT FOLD", "Even shaping folds make the smaller wing pair easier to recognize when the butterfly opens."),
        ("Bring the wings together", "Fold the left half onto the right along the middle. Lift the folded model and hold its narrow center.", "FOLD IN HALF · HOLD THE BODY", "The demonstration tips the paper upright so you can see the separate wing layers."),
        ("Open the first wing pair", "Hold the narrow center and fold the highlighted outer wing pair away from it along the angled guide.", "WINGS AWAY FROM THE BODY", "Leave a small ridge at the center. This angled fold separates the two pointed tips at the lower end."),
        ("Open the other wing pair", "Fold the other wing pair out to match. Leave the wings gently raised above the narrow body. Your butterfly is complete.", "FOUR WINGS · ONE NARROW BODY", "Compare the shape from the front. You can adjust the wing angle gently on your real paper without adding another sharp crease.")
    ])
}
