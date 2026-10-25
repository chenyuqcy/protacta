import Foundation
import simd

/// Small final paper-forming approximation, followed by a standing turn.
/// This preserves source joints, but is not a rigid-fold or balance simulation.
enum ElephantStandingStudy {
    static let width: Float = 0.20
    static let openingAngle: Float = 8 * .pi / 180

    static func frame(progress requested: Float, input: PaperFrame) -> PaperFrame {
        let p = requested.isFinite ? min(1, max(0, requested)) : 0
        let t = p*p*(3-2*p), angle = openingAngle*t
        let c = cos(angle), sn = sin(angle), turn = Float.pi/2*t
        let turnC = cos(turn), turnS = sin(turn)
        let centerZ = (input.bounds.minimum.z+input.bounds.maximum.z)/2
        let h = width/4
        var faces = input.faces
        for i in faces.indices {
            faces[i].isMoving = true
            for j in faces[i].vertices.indices {
                var v = faces[i].vertices[j]
                let q = abs(v.source.y)
                // The original quarter folds have an inner and an outer wall.
                // Matching material points always receive the same offset.
                let foldedDepth = max(0, min(q, 2*h-q))
                let side: Float = v.source.y < 0 ? -1 : 1
                let y = v.position.y + side*foldedDepth*sn
                let z = centerZ+(v.position.z-centerZ)*c
                v.position = [v.position.x, y*turnC-z*turnS, y*turnS+z*turnC]
                v.separation = .zero
                faces[i].vertices[j] = v
            }
        }
        let points = faces.flatMap { $0.vertices.map(\.position) }
        let lo = points.reduce(SIMD3<Float>(repeating:.greatestFiniteMagnitude),simd_min)
        let hi = points.reduce(SIMD3<Float>(repeating:-.greatestFiniteMagnitude),simd_max)
        // Keep the same horizontal origin at the flat endpoint, then center the
        // completed standing footprint as the whole sheet rotates.
        let offset = SIMD3<Float>(-(lo.x+hi.x)/2*t, max(0,0.001-lo.y), -(lo.z+hi.z)/2*t)
        for i in faces.indices {
            for j in faces[i].vertices.indices {
                faces[i].vertices[j].position += offset
                faces[i].vertices[j].separation = faces[i].normal*Float(i%5)*0.00002
            }
        }
        return PaperFrame(faces:faces, crease:nil, actionPaths:[], tableLift:input.tableLift+offset.y)
    }
}
