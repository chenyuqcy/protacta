import Foundation
import simd

/// Isolated WWF/Joseph Wu research prototype. The implemented prefix reaches the rear corner folds in
/// source group 18; source-17 precreases are explicitly still missing. It is deliberately not in the catalog.
/// All polygons come from one uncut square and retain their material coordinates.
/// Kinematic folds do not certify paper-layer collision freedom.
enum ElephantGeometry {
    static let width: Float = 0.20
    static let isComplete = false
    static let stepCount = 27
    static let lastStep = stepCount - 1
    private static let epsilon: Float = 1e-7
    private struct Patch {
        var face: PaperFace
        var outer: Bool
        var pocket: Int
        var reversedCorner = false
        var foldedTip = false
    }

    static func frame(step requestedStep: Int, progress requestedProgress: Float) -> PaperFrame {
        let step = min(lastStep, max(0, requestedStep))
        let p = requestedProgress.isFinite ? min(1, max(0, requestedProgress)) : 0
        var faces = sheet()
        var crease: PaperCrease?
        var paths = [[SIMD3<Float>]]()
        func amount(_ index: Int) -> Float { step > index ? 1 : step == index ? p : 0 }
        func pulse(_ index: Int) -> Float { step == index ? sin(.pi * p) : 0 }
        func apply(_ index: Int, origin: SIMD3<Float>, axis: SIMD3<Float>, normal: SIMD3<Float>,
                   angle: Float, fraction: Float, side: Int? = nil, tip: SIMD3<Float>,
                   select: (Patch) -> Bool = { _ in true }, markCorner: Bool = false, markTip: Bool = false) {
            guard step >= index else { return }
            let direction = simd_normalize(axis)
            if step == index {
                let hits = faces.filter { (side == nil || $0.pocket == side) && select($0) }.flatMap { patch -> [SIMD3<Float>] in
                    let face = patch.face
                    var result = [SIMD3<Float>]()
                    for i in face.vertices.indices {
                        let a = face.vertices[i].position, b = face.vertices[(i+1)%face.vertices.count].position
                        let da = simd_dot(a-origin,normal), db = simd_dot(b-origin,normal)
                        if abs(da) < epsilon { result.append(a) }
                        if da*db < 0 { result.append(a+(b-a)*(da/(da-db))) }
                    }
                    return result
                }
                if let first = hits.min(by: { simd_dot($0,direction) < simd_dot($1,direction) }),
                   let last = hits.max(by: { simd_dot($0,direction) < simd_dot($1,direction) }) {
                    crease = PaperCrease(start: first, end: last)
                }
                let reopening = [1,5,6,7,8,15,16,22,23].contains(index) && p > 0.5
                paths = [(0...28).map { i in
                    let t = Float(i)/28
                    return rotate(tip, origin: origin, axis: direction, angle: angle * (reopening ? 1-t : t))
                }]
            }
            faces = fold(faces, origin: origin, axis: direction, normal: normal,
                         angle: angle*fraction, side: side, moving: step == index, select: select, markCorner: markCorner, markTip: markTip)
        }
        let h = width/4
        apply(1, origin: .zero, axis: [1,0,0], normal: [0,0,1], angle: -.pi,
              fraction: pulse(1), tip: [width*0.55,0,width*0.45])
        apply(2, origin: [0,0,-h], axis: [1,0,0], normal: [0,0,-1], angle: .pi,
              fraction: amount(2), tip: [width*0.55,0,-width*0.45])
        apply(3, origin: [0,0,h], axis: [1,0,0], normal: [0,0,1], angle: -.pi,
              fraction: amount(3), tip: [width*0.55,0,width*0.45])
        apply(4, origin: .zero, axis: [1,0,0], normal: [0,0,1], angle: .pi,
              fraction: amount(4), side: 1, tip: [width*0.55,0,h*0.9])
        for index in 5...min(10, max(5,step)) where step >= index {
            let slope: Float = index <= 6 ? 1 : tan(.pi/8)
            let side = index.isMultiple(of: 2) ? 1 : -1
            let reverse = index >= 9
            apply(index, origin: [width,0,0], axis: [-1,0,-slope], normal: [slope,0,-1],
                  angle: (side == -1 ? -1 : 1) * (reverse ? -1 : 1) * .pi,
                  fraction: reverse ? amount(index) : pulse(index), side: side,
                  tip: [width*0.98,0,-h*0.9], markCorner: reverse)
        }
        let shoulder = width-h/tan(Float.pi/8)
        let peak = SIMD3<Float>(width-h/sqrt(2),0,h/sqrt(2))
        for index in 11...min(20,max(11,step)) where step >= index {
            let side = index.isMultiple(of:2) ? 1 : -1
            let direction: Float = side == -1 ? 1 : -1
            if index <= 12 {
                // Only the loose outer layer lifts. Its attached quarter-fold
                // edge is the S-to-peak hinge. The inner book spine stays put.
                apply(index, origin:[shoulder,0,-h], axis:peak-SIMD3<Float>(shoulder,0,-h),
                      normal:[1,0,-1], angle:direction * .pi, fraction:amount(index), side:side,
                      tip:[width,0,0], select:{ $0.outer })
            } else if index <= 14 {
                // Both connected layers cross this line together. The moving
                // outer region is retained so later folds can select its tip.
                apply(index, origin:.zero, axis:[1,0,0], normal:[0,0,1],
                      angle:direction * .pi, fraction:amount(index), side:side,
                      tip:[shoulder+h,0,h*sqrt(2)], markTip:true)
            } else if index <= 16 || index >= 19 {
                let precrease = index <= 16
                apply(index, origin:[width,0,0], axis:[-1,0,-tan(.pi/8)], normal:[tan(.pi/8),0,-1],
                      angle:direction * .pi, fraction:precrease ? pulse(index) : amount(index), side:side,
                      tip:[width-h/sqrt(2),0,-h/sqrt(2)])
            } else {
                let freeTip = SIMD3<Float>(shoulder+h,0,-h*sqrt(2))
                let target = SIMD3<Float>(width-h,0,-h*(sqrt(2)-1))
                let normal = freeTip-target
                apply(index, origin:(freeTip+target)/2, axis:[normal.z,0,-normal.x], normal:normal,
                      angle:direction * .pi, fraction:amount(index), side:side, tip:freeTip,
                      select:{ $0.outer && $0.foldedTip })
            }
        }
        if step >= 21 {
            apply(21,origin:.zero,axis:[1,0,0],normal:[0,0,-1],angle:-.pi,
                  fraction:amount(21),side:1,tip:[width*0.2,0,-h])
        }
        if step >= 22 {
            apply(22,origin:[shoulder,0,0],axis:[0,0,1],normal:[1,0,0],angle:.pi,
                  fraction:pulse(22),tip:[width,0,0])
        }
        if step >= 23 {
            apply(23,origin:[shoulder/2,0,0],axis:[0,0,1],normal:[-1,0,0],angle:-.pi,
                  fraction:pulse(23),tip:[0,0,-h*0.5])
        }
        if step >= 24 {
            apply(24,origin:[shoulder/4,0,0],axis:[0,0,1],normal:[-1,0,0],angle:-.pi,
                  fraction:amount(24),tip:[0,0,-h*0.5])
        }
        // Source group 17's reopening precreases are still under development;
        // they leave the flat endpoint unchanged and are not counted here.
        for index in 25...min(26,max(25,step)) where step >= index {
            let side = index == 25 ? -1 : 1
            let sign = Float(side)
            let corner = SIMD3<Float>(shoulder/4,0,sign*h)
            let target = SIMD3<Float>(shoulder/2,0,sign*(h-shoulder*sqrt(5)/4))
            let normal = corner-target
            apply(index,origin:(corner+target)/2,axis:[normal.z,0,-normal.x],normal:normal,
                  angle:sign * .pi,fraction:amount(index),side:side,tip:corner)
        }
        var renderedFaces = faces.map(\.face)
        // Rendering offsets are tiny and kept separate from physical positions.
        for i in renderedFaces.indices {
            let rank = Float(i % 7) * 0.000035
            for j in renderedFaces[i].vertices.indices { renderedFaces[i].vertices[j].separation = [0,rank,0] }
        }
        let points = renderedFaces.flatMap { $0.vertices.map(\.position) }
        let minimum = points.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude),simd_min)
        let maximum = points.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude),simd_max)
        let lift = max(0,-minimum.y)+0.001
        let offset = SIMD3<Float>(-(minimum.x+maximum.x)/2,lift,-(minimum.z+maximum.z)/2)
        for i in renderedFaces.indices { for j in renderedFaces[i].vertices.indices { renderedFaces[i].vertices[j].position += offset } }
        if let c = crease { crease = PaperCrease(start:c.start+offset+[0,0.002,0],end:c.end+offset+[0,0.002,0]) }
        paths = paths.map { path in
            let shifted = path.map { $0+offset }
            let extra = max(0,0.004-(shifted.map(\.y).min() ?? 0))
            return shifted.map { $0+SIMD3<Float>(0,extra,0) }
        }
        return PaperFrame(faces:renderedFaces,crease:crease,actionPaths:paths,tableLift:lift)
    }

    private static func sheet() -> [Patch] {
        (0..<4).map { strip in
            let a = -width/2+Float(strip)*width/4, b = a+width/4
            let points: [SIMD3<Float>] = [[0,0,a],[0,0,b],[width,0,b],[width,0,a]]
            let side = strip < 2 ? -1 : 1
            return Patch(face:PaperFace(vertices:points.map { PaperVertex(position:$0,source:[$0.x,$0.z]) },originalSide:side),outer:strip == 0 || strip == 3,pocket:side)
        }
    }
    private static func rotate(_ point: SIMD3<Float>, origin: SIMD3<Float>, axis: SIMD3<Float>, angle: Float) -> SIMD3<Float> {
        let v = point-origin
        let rawS = sin(angle), rawC = cos(angle)
        let s: Float = abs(rawS)<1e-6 ? 0 : rawS, c: Float = abs(rawC)<1e-6 ? 0 : rawC
        return origin+v*c+simd_cross(axis,v)*s+axis*simd_dot(axis,v)*(1-c)
    }
    private static func fold(_ faces: [Patch], origin: SIMD3<Float>, axis: SIMD3<Float>, normal: SIMD3<Float>,
                             angle: Float, side: Int?, moving: Bool, select: (Patch) -> Bool,
                             markCorner: Bool, markTip: Bool) -> [Patch] {
        var result = [Patch]()
        for patch in faces {
            let face = patch.face
            guard (side == nil || side == patch.pocket) && select(patch) else { result.append(patch); continue }
            for positive in [false,true] {
                var clipped = [PaperVertex]()
                for i in face.vertices.indices {
                    let a = face.vertices[i], b = face.vertices[(i+1)%face.vertices.count]
                    let da = simd_dot(a.position-origin,normal), db = simd_dot(b.position-origin,normal)
                    let inside = positive ? da >= -epsilon : da <= epsilon
                    if inside { clipped.append(a) }
                    if (da < -epsilon && db > epsilon) || (da > epsilon && db < -epsilon) {
                        clipped.append(PaperVertex.interpolate(a,b,da/(da-db)))
                    }
                }
                var cleaned = [PaperVertex]()
                for vertex in clipped where cleaned.last.map({ simd_distance($0.source,vertex.source) > epsilon }) ?? true { cleaned.append(vertex) }
                if cleaned.count > 2, simd_distance(cleaned[0].source,cleaned.last!.source) < epsilon { cleaned.removeLast() }
                guard cleaned.count >= 3 else { continue }
                var part = PaperFace(vertices:cleaned,originalSide:face.originalSide,isMoving:moving && positive)
                guard part.area > 1e-12 else { continue }
                if positive { for j in part.vertices.indices { part.vertices[j].position = rotate(part.vertices[j].position,origin:origin,axis:axis,angle:angle) } }
                var next = patch; next.face = part
                if positive && markCorner { next.reversedCorner = true }
                if positive && markTip { next.foldedTip = true }
                result.append(next)
            }
        }
        return result
    }
}
