import Foundation

/// Independently written broad-paw variation; native teaching review pending.
enum SittingDogLessonContent {
    static let title = "The Sitting Dog · Broad Paws"
    static let material = "One 20 × 20 cm square · Thin paper recommended"
    static let sourceName = "Sitting dog after Joost Langeveld · Authored variation"
    static let sourceURL = URL(string: "https://www.joostlangeveldorigami.nl/diagramsdogsittingdown.html")!
    static let steps: [LessonStep] = {
        let rows: [(String,String,String,String)] = [
            ("Prepare one square","Start with a thin 20 cm square. Keep one diagonal horizontal; the left corner will become the head.","SQUARE PAPER","A larger sheet leaves room for small layered folds."),
            ("Mark the long diagonal","Fold the upper corner to the lower corner, crease, and reopen.","FOLD AND OPEN","This line becomes the body hinge."),
            ("Mark the crossing diagonal","Bring the left corner to the right corner, crease, and open again.","CORNERS TOGETHER","The crossing line locates the two side flaps."),
            ("Mark one tail-side edge","Bring the highlighted lower edge onto the long diagonal. Press and reopen.","EDGE TO CENTER","A temporary fold records the rabbit-ear hinge."),
            ("Mark the matching edge","Repeat the edge-to-center precrease above the diagonal. Open it again.","MATCH BOTH SIDES","Matching creases keep the body symmetric."),
            ("Mark one head-side edge","At the opposite tip, crease the highlighted edge toward the diagonal and reopen.","OTHER END","The two sets of guides meet inside the side corners."),
            ("Complete the edge guides","Repeat on the remaining edge and open the square.","FOUR EDGE GUIDES","This lesson opens each precrease immediately instead of opening them together later."),
            ("Raise the first rabbit ear","Bring the lower side corner inward along its guides. Flatten the small flap toward the right.","CORNER IN","Several hinges close together; the paper remains one sheet."),
            ("Raise the second rabbit ear","Collapse the upper side corner into the matching small flap.","MATCH THE SMALL FLAPS","The long left and right tips remain in place."),
            ("Lay the first flap left","Turn the lower small flap toward the future head.","SMALL FLAP LEFT","This flap will contribute to a front leg."),
            ("Lay the other flap left","Turn the matching upper flap left as well.","MATCH THE FLAPS","Leave the large base flat beneath them."),
            ("Close the body","Fold the upper half behind the lower half along the long diagonal.","HALVE THE BASE","Both little leg flaps should remain accessible."),
            ("Reverse the rear point","Open the rear layers, turn the long right point down around the indicated hinge, and close them.","REAR POINT DOWN","An outside reverse changes the point direction. Ease the layers apart before turning the point, then flatten them together."),
            ("Lift the tail point","Open the rear fold and turn its lower point upward at the crosswise guide.","TAIL POINT UP","Support the wider body while reversing the thin point."),
            ("Crimp the tail base","Ease the rear layers apart, make the two opposing short folds across the tail base, and close them.","SHORT ZIGZAG","The crimp sets the rear-body proportions."),
            ("Narrow one tail edge","Tuck the highlighted long tail edge inward.","ONE EDGE IN","Keep the tail point intact."),
            ("Narrow the other tail edge","Make the same narrow fold on the opposite side.","MATCH THE TAIL","The paired folds create a slimmer tail."),
            ("Lower the tail","Reverse the narrow tail backward and down at its root.","TAIL BACK","The tail should extend behind the seated body."),
            ("Release the front flap","Lift the visible small flap out of the way of the neck fold.","FREE THE SMALL FLAP","Its attachment stays on the body."),
            ("Raise the neck","Reverse the long left section upward, then return the small flap beside the body.","LONG POINT UP","The large point becomes the neck and head."),
            ("Make the neck crimp","Support the lower neck and close the two guided hinges so the head projects left.","SUPPORT BELOW","The neck keeps a short offset beneath the head."),
            ("Narrow the chest","Fold the chest margin inward on both sides.","CHEST EDGES IN","These folds define the upright front of the seated dog."),
            ("Shape the head pleat","Close the short opposing folds near the head base on both sides.","HEAD BASE","The head and long snout acquire separate outlines."),
            ("Soften the head corner","Turn the small upper head corner inward on each side.","TOP CORNER IN","Only the small corner changes."),
            ("Shorten the muzzle","Make the opposing folds across the long nose section.","MUZZLE PLEAT","Keep the lower edge aligned while shortening the point."),
            ("Tuck the nose tip","Turn the remaining pointed tip inward at the short guide.","TIP INSIDE","The sharp paper corner becomes a compact nose."),
            ("Square the first front paw","Tuck the small point on the visible front foot inward.","FIRST PAW","The foot should have a flatter front edge."),
            ("Square the other front paw","Repeat on the matching foot behind it.","OTHER PAW","Compare the two feet before pressing."),
            ("Give the body some volume","Ease the two sides slightly apart and stand the dog on the broad base. Keep both front paws wide.","SHAPE AND STAND","A little space between the two sides makes a wider support. Open gently and adjust the broad base until the dog balances.")
        ]
        return rows.enumerated().map {i,row in LessonStep(id:i,title:row.0,instruction:row.1,cue:row.2,explanation:row.3)}
    }()
}
