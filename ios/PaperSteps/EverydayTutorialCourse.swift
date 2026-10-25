import CryptoKit
import Foundation

enum EverydayTutorialCategory: String, Codable, CaseIterable, Identifiable {
    case clothing, linens, knots, ties
    var id: String { rawValue }
    var title: String {
        switch self {
        case .clothing: return "Clothes"
        case .linens: return "Home linens"
        case .knots: return "Everyday knots"
        case .ties: return "Neckties"
        }
    }
}

enum EverydayTutorialID: String, Codable, CaseIterable, Identifiable {
    case tShirt = "t_shirt"
    case towel = "towel"
    case flatBedsheet = "flat_bedsheet"
    case squareKnot = "square_knot"
    case fourInHand = "four_in_hand"
    var id: String { rawValue }
    var category: EverydayTutorialCategory {
        switch self {
        case .tShirt: return .clothing
        case .towel, .flatBedsheet: return .linens
        case .squareKnot: return .knots
        case .fourInHand: return .ties
        }
    }
}

struct EverydayTutorialAction: Identifiable, Equatable {
    let id: Int
    let title: String
    let instruction: String
    let manualCheckpoint: String
    let commonMistake: String
    let help: String

    /// The visual player takes action.id - 1, then interpolates progress 0...1.
    var visualStartIndex: Int { id - 1 }
    var visualEndIndex: Int { id }
}

struct EverydayTutorialReference: Equatable {
    let title: String
    let url: URL
}

/// Original prototype teaching text and schematic stages. These courses have
/// complete procedures but still need real follow-through review. They make no
/// claim to camera alignment, computer-vision grading or load-bearing knot use.
struct EverydayTutorialCourse: Identifiable {
    let id: EverydayTutorialID
    let title: String
    let summary: String
    let materials: [String]
    let setup: String
    let actions: [EverydayTutorialAction]
    let references: [EverydayTutorialReference]

    var category: EverydayTutorialCategory { id.category }
    var reviewNotice: String { "Authored prototype: follow along and compare the result yourself. This course and its diagrams still need real follow-through review; the camera does not check these actions." }
    var requiresRealFollowThroughReview: Bool { true }
    var supportsCameraCheck: Bool { false }

    /// Only this course's saves change when its text or visual semantics change.
    /// Bump visualRevision when the renderer changes a stage's physical meaning.
    var revision: String {
        let visualRevision = 1
        var fields = ["Protacta everyday course v1", id.rawValue, category.rawValue,
                      String(visualRevision), title, summary, setup, reviewNotice] + materials
        for action in actions {
            fields += [String(action.id), action.title, action.instruction,
                       action.manualCheckpoint, action.commonMistake, action.help,
                       String(action.visualStartIndex), String(action.visualEndIndex)]
        }
        fields += references.flatMap { [$0.title, $0.url.absoluteString] }
        let bytes = fields.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(bytes.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static let all: [EverydayTutorialCourse] = [tShirt, towel, flatBedsheet, squareKnot, fourInHand]

    static func course(_ id: EverydayTutorialID) -> EverydayTutorialCourse {
        switch id {
        case .tShirt: return tShirt
        case .towel: return towel
        case .flatBedsheet: return flatBedsheet
        case .squareKnot: return squareKnot
        case .fourInHand: return fourInHand
        }
    }

    private static func actions(_ rows: [(String, String, String, String, String)]) -> [EverydayTutorialAction] {
        rows.enumerated().map { index, row in
            EverydayTutorialAction(id: index + 1, title: row.0, instruction: row.1,
                                   manualCheckpoint: row.2, commonMistake: row.3, help: row.4)
        }
    }

    private static let tShirt = EverydayTutorialCourse(
        id: .tShirt, title: "Fold a T-shirt", summary: "Turn a short-sleeved shirt into a flat storage rectangle.",
        materials: ["One short-sleeved T-shirt", "A clean, flat surface"],
        setup: "Lay the shirt face down, with its neck at the far/top edge and hem nearest you. Smooth the body and spread the sleeves. Left and right refer to the diagram in front of you.",
        actions: actions([
            ("Bring in the left side",
             "Fold the left side of the body inward along a line from shoulder to hem. Let the left sleeve travel with that panel.",
             "The new left edge runs straight from shoulder to hem; the lower hem stays level.",
             "Dragging only the sleeve leaves the body wide and uneven.",
             "Hold the shoulder and hem together as you bring in the whole side. Smooth the folded panel without stretching it."),
            ("Tuck the left sleeve",
             "Fold the projecting left sleeve back and down over the folded panel, keeping its tip inside the body's outline.",
             "No part of the left sleeve sticks past the storage rectangle you are forming.",
             "A sleeve tip left outside will unfold when you pick up the shirt.",
             "If the sleeve is long for this panel, make a small return fold so it lies on the body rather than pulling the shoulder."),
            ("Bring in the right side",
             "Fold the right side inward to make a long, narrow body rectangle, matching the width of the left fold.",
             "The two long outer edges are roughly parallel, and the neck remains flat at the top.",
             "Unequal panel widths can leave a sloping packet or twist the collar.",
             "Adjust this fold before pressing. Use the hem and shoulder as two landmarks for a straight outer edge."),
            ("Tuck the right sleeve",
             "Fold the remaining sleeve back and down so it sits inside the narrow body rectangle.",
             "Both sleeves are contained, with no thick sleeve bundle sticking out at either side.",
             "Folding a bunched sleeve into the next step makes a bulky corner.",
             "Lift the sleeve just enough to flatten it, then lay it back inside the body. Keep the neck at the top."),
            ("Bring the hem up",
             "Lift the bottom hem to the shoulder line. Keep both long sides aligned and smooth the resulting half-height packet.",
             "The hem reaches the top without pulling the collar out of shape; the side edges still match.",
             "Pulling the hem tight can stretch the neck or trap a diagonal wrinkle.",
             "Use two hands to lift the whole lower section. Open this one fold and smooth it if the fabric twists."),
            ("Fold the packet once more",
             "Bring the packet's lower folded edge up to its top edge. Smooth it gently into a compact rectangle.",
             "The packet has aligned edges and contained sleeves and stays together when lifted from underneath.",
             "Loose sleeve tips or a trapped collar can reopen the finished fold.",
             "Set the shirt down and compare each edge. If a corner is bulky, reopen the last fold and adjust the fabric rather than compressing it.")
        ]), references: [])

    private static let towel = EverydayTutorialCourse(
        id: .towel, title: "Fold a rectangular towel", summary: "Fold the width in thirds, then shorten the long strip.",
        materials: ["One rectangular towel", "A clean surface large enough to spread it"],
        setup: "Lay the towel flat with its long edges running away from you and a short edge at the far/top side. Smooth it and imagine three equal columns across its width.",
        actions: actions([
            ("Fold the left third inward",
             "Bring the left long third over the middle third. Its outer long edge should reach the line between the middle and right thirds.",
             "The left section lies on the middle section, with straight, parallel long edges.",
             "Taking half the towel instead of one third leaves no matching section for the next fold.",
             "Before folding, compare the three column widths. Lift the left top and bottom corners together so the fold does not twist."),
            ("Cover it with the right third",
             "Bring the right third over the folded middle stack. Match its long edge to the new left edge of the strip.",
             "A long rectangle about one third of the original width remains, with both loose long edges contained.",
             "An angled right fold makes one end of the strip wider than the other.",
             "Match the near corners first, then the far corners. Smooth along the strip to release trapped folds."),
            ("Fold the strip in half",
             "Lift the short edge nearest you up to the far short edge. Align the corners and place the folded towel down flat.",
             "The short edges meet and the towel forms a tidy rectangle with the long thirds tucked inside.",
             "Lifting only one corner can skew the layers or pull a third back out.",
             "Support the whole near edge with both hands. If it shifts, reopen just this last fold, align the strip and try again.")
        ]), references: [])

    private static let flatBedsheet = EverydayTutorialCourse(
        id: .flatBedsheet, title: "Fold a flat bedsheet", summary: "Match four successive edge pairs to make a storage rectangle.",
        materials: ["One flat rectangular bedsheet without elastic corners", "A clean bed or table large enough for the sheet"],
        setup: "This course is for a FLAT sheet, not a fitted sheet. Spread it on a clean surface with the long edges running away from you. Align the corners and smooth the fabric; the far/top edge stays the reference.",
        actions: actions([
            ("Match the long edges",
             "Bring the left long edge across to the right long edge. Match both pairs of corners, then smooth the half-width rectangle.",
             "The two right long edges and their near/far corners meet without a twist.",
             "Matching only the near corners leaves a diagonal fold at the far end.",
             "Align the far corners as well as the near ones before setting the lifted layer down. Smooth from the fold toward the loose edges."),
            ("Match the short edges",
             "Lift the short edge nearest you up to the far short edge, keeping the doubled long edges together.",
             "All loose short-edge corners are aligned at the top, and the packet is half its previous height.",
             "A hidden lower corner can lag behind and form a bulge inside.",
             "Check the corner stack with your fingers. Lift and settle the upper layer if a lower corner has slipped; do not stretch the sheet."),
            ("Halve the packet's width",
             "Bring the packet's left edge to its right edge. Keep the top and bottom corners lined up as you fold.",
             "The new long edges line up, with no corner hanging outside the smaller rectangle.",
             "Confusing a folded edge with a loose layer can move only part of the stack.",
             "Pick up the full left edge, including every layer. Support the packet underneath while moving it."),
            ("Halve its height and finish",
             "Bring the packet's lower edge up to its top edge. Smooth the final rectangle and lift it from underneath for storage.",
             "The rectangle has aligned outer edges and no trailing sheet layer when lifted gently.",
             "Compressing an uneven stack hides a misplaced corner instead of fixing it.",
             "If a corner trails, reopen this last fold, line up the packet and fold again. A fitted sheet needs a different method; do not force its elastic corners into this sequence.")
        ]), references: [])

    private static let squareKnot = EverydayTutorialCourse(
        id: .squareKnot, title: "Practice a square knot", summary: "Make two opposite half-knots with clearly named ends.",
        materials: ["One soft practice cord with long free ends", "Two different colours of tape to label ends A and B", "A flat surface"],
        setup: "Mark A blue and B orange. Bring the two ends of the same cord together above the table, A on the left and B on the right. Keep the standing sections loose below. This is loose everyday binding practice, not a load-bearing fastening or a way to join ropes under strain.",
        actions: actions([
            ("Cross A over B",
             "Carry A from the left across the front of B to the right. Hold the crossing loosely.",
             "A is the strand on top at the crossing, with its free end on the right.",
             "Passing A behind B changes the crossing shown in this version.",
             "Follow the blue end label rather than the hand holding it. Keep enough free cord for the tuck."),
            ("Tuck A under for the first half",
             "Take A under B and through the gap to finish the first half-knot. Set the free ends apart, A on the right and B on the left.",
             "One loose half-knot is formed; the named ends have exchanged sides.",
             "Pulling tight now makes the opposite second crossing harder to see.",
             "Leave a little space at the crossing. Check the A/B labels again before beginning the next half."),
            ("Cross A back over B",
             "A is now on the right. Lay A across the front of B from right to left, reversing the previous crossing direction.",
             "A is on top again, but travels right to left this time.",
             "Repeating the same left-to-right crossing makes two half-knots of the same handedness.",
             "Read the current end positions, not the starting picture: right over left follows left over right."),
            ("Tuck through the second gap",
             "Pass A under B and through the new gap. Leave the two linked half-knots loose enough to inspect.",
             "A comes out to the left and B to the right; the two halves turn in opposite directions.",
             "Threading through an old loop instead of the new gap creates a different knot.",
             "Trace A from its free tip back through the second crossing. If the route is unclear, undo only this half and replay."),
            ("Dress the flat knot",
             "Gently draw the free ends and their standing sections apart together, settling the knot into two interlocking loops.",
             "The knot lies flat, and each free end runs beside its own standing section rather than crossing over the whole knot.",
             "A twisted granny knot is not repaired by pulling harder. Appearance does not make this practice knot load-bearing.",
             "If the halves twist, loosen and remake the second half in the opposite direction. Keep this exercise as loose binding practice; it is not a security test.")
        ]), references: [
            EverydayTutorialReference(title: "Scouts: reef-knot teaching sequence", url: URL(string: "https://www.scouts.org.uk/activities/tie-a-tasty-reef-knot/")!),
            EverydayTutorialReference(title: "Scouts Malta: knotting and reef-knot limitations", url: URL(string: "https://scouts.mt/wp-content/uploads/SK_Downloads/Training/Cubs/Bronze_Arrow/B09_Knotting.pdf")!)
        ])

    private static let fourInHand = EverydayTutorialCourse(
        id: .fourInHand, title: "Tie a four-in-hand", summary: "Follow the wide end around, up and down into a wearable necktie knot.",
        materials: ["One necktie", "A collared shirt", "A mirror or the labelled front-view diagram"],
        setup: "Raise the collar and drape the tie with seams toward the shirt. W is the wide end on YOUR right (diagram-left); N is narrow on YOUR left (diagram-right). Start with W lower than N; the exact length needs adjustment for your tie and height. The diagrams face you. Move W while keeping N mostly still.",
        actions: actions([
            ("Wide end across the front",
             "Take W across the front of N from your right to your left: diagram-left to diagram-right.",
             "W lies on top of N at the first crossing.",
             "Using the diagram's left as your own left reverses these instructions.",
             "Find W's label first. Keep the patterned face out and the crossing just below the collar."),
            ("Wide end behind",
             "Carry W behind N, back toward your right: diagram-right to diagram-left.",
             "W returns to your right after passing behind the narrow blade.",
             "Crossing the front again skips the wrap behind N.",
             "Hold the first crossing lightly; let W travel behind it without twisting the fabric."),
            ("Make the front band",
             "Bring W across the front once more toward your left. Keep a finger beneath this new horizontal band.",
             "A flat front band spans the knot, with space underneath for W to pass later.",
             "Tightening this band immediately closes the opening you need.",
             "The front band is the small new opening. It is different from the large loop around the collar."),
            ("Go up through the neck loop",
             "Lift W from underneath, behind the forming knot, and up through the large neck loop.",
             "W's tip points upward above the knot; the front band remains open below it.",
             "Entering the front band upward instead confuses the two openings.",
             "Use the loop surrounding the collar for this move. Keep the finger holding the front band clear of W's path."),
            ("Come down through the band",
             "Guide W down through the front band held by your finger. Remove the finger and draw the wide blade through without twisting it.",
             "W hangs down the front and covers N; the band gathers around it.",
             "Sending W down behind the knot misses the front band.",
             "Pause before pulling. Trace the visible band and place W through that opening, not back through the neck loop."),
            ("Set and slide the knot",
             "Gently draw W downward to settle the knot. Hold N and slide the knot upward until it sits comfortably at the collar.",
             "The knot is slim and slightly asymmetric, with a flat wide blade and a comfortable neck loop.",
             "Pulling both blades together can twist the knot or change the loop unexpectedly.",
             "Make small adjustments. A little asymmetry is normal for this knot; compare the wrap rather than forcing a wide triangular shape."),
            ("Finish the collar and tail",
             "Put N through the keeper on the back of W, then lower the collar. Check the wide tip near your belt line.",
             "The narrow blade is contained behind W and the front lies flat. The collar covers the neck loop.",
             "A much-too-short wide blade needs a different starting length, not a harder pull.",
             "To change the final length, loosen and restart with more or less W hanging down initially. Keep the finished loop comfortable while adjusting.")
        ]), references: [
            EverydayTutorialReference(title: "Ties.com: four-in-hand sequence", url: URL(string: "https://www.ties.com/how-to-tie-a-tie/four-in-hand")!),
            EverydayTutorialReference(title: "OTAA: four-in-hand sequence", url: URL(string: "https://www.otaa.com/en-us/pages/how-to-tie-a-four-in-hand-knot")!)
        ])
}
