import Foundation
import simd

/// Traditional jumping frog from one uncut 1:2 rectangle. The published source
/// explicitly permits the half-square start. Every point retains its original
/// paper coordinate; both pocket linkages use shared rigid triangle vertices.
enum FrogGeometry {
    static let width: Float = 0.075
    static let height: Float = 0.15
    static let stepCount = 23
    private static let epsilon: Float = 0.0000002
    private struct Fold {
        var origin: SIMD3<Float>
        var axis: SIMD3<Float>
        var normal: SIMD3<Float>
        var angle: Float
        var arrow: SIMD3<Float>
        var layer: Int? = nil
        var layers: Set<Int>? = nil
        var resultLayer: Int? = nil
        var separation: Float = 0.00012
    }

    static func frame(step requestedStep: Int, progress requestedProgress: Float) -> PaperFrame {
        let step = min(stepCount - 1, max(0, requestedStep))
        let p = requestedProgress.isFinite ? min(1, max(0, requestedProgress)) : 0
        let w = width / 2, q = w / 2
        let relaxation: Float = step == 22 ? p : 0
        var faces = head(collapse: step == 5 ? p : (step > 5 ? 1 : 0))
        faces.append(face([[-w,0],[w,0],[w,2*w],[-w,2*w]], layer: 2))
        var crease: PaperCrease?
        var paths = [[SIMD3<Float>]]()
        func perform(_ fold: Fold, at index: Int, amount: Float? = nil) {
            guard step >= index else { return }
            let active = step == index
            if active { crease = clippedCrease(fold, faces: faces); paths = [arrowPath(fold)] }
            faces = apply(fold, to: faces, fraction: amount ?? (active ? p : 1), active: active)
        }
        if (1...4).contains(step) {
            let cycle = p <= 0.5 ? p * 2 : (1 - p) * 2
            let folds: [Fold] = [
                Fold(origin: .zero, axis: [1,0,0], normal: [0,0,-1], angle: .pi, arrow: [w*0.5,0,-w*1.8]),
                Fold(origin: [0,0,-w], axis: simd_normalize([1,0,1]), normal: [1,0,-1], angle: .pi, arrow: [w*0.85,0,-w*1.85]),
                Fold(origin: [0,0,-w], axis: simd_normalize([1,0,-1]), normal: [-1,0,-1], angle: .pi, arrow: [-w*0.85,0,-w*1.85]),
                Fold(origin: [0,0,-w], axis: [1,0,0], normal: [0,0,-1], angle: -.pi, arrow: [w*0.5,0,-w*1.85])
            ]
            var fold = folds[step-1]
            crease = clippedCrease(fold, faces: faces)
            faces = apply(fold, to: faces, fraction: cycle, active: true)
            if p > 0.5 { fold.arrow = rotated(fold.arrow, origin: fold.origin, axis: fold.axis, angle: fold.angle); fold.angle *= -1 }
            paths = [arrowPath(fold)]
        }
        if step == 5 {
            crease = PaperCrease(start: [-w,0,-w], end: [w,0,-w])
            paths = [-1, Float(1)].map { sign in (0...24).map { i in
                waterbombMidpoint(sign: sign, fraction: Float(i)/24)
            } }
            for i in faces.indices where faces[i].originalSide != 2 { faces[i].isMoving = true }
        }
        // The front flap and its folded-under half have a free edge at the tip.
        // Keeping both in layer 1 prevents a tear when the leg swings out.
        for (index, sign) in [(6, Float(-1)), (7, Float(1))] {
            let fold = Fold(origin: .zero, axis: simd_normalize([sign * sqrt(3),0,-1]),
                            normal: [sign,0,sqrt(3)], angle: -sign * (.pi - relaxation * 0.16),
                            arrow: [sign*w*0.88,0,-w*0.03], layer: 1, resultLayer: index, separation: 0.00085)
            perform(fold, at: index)
        }
        perform(Fold(origin: [0,0,w], axis: [1,0,0], normal: [0,0,1], angle: -.pi,
                     arrow: [w*0.35,0,w*1.85], layer: 2, resultLayer: 3), at: 8)
        for (index, sign) in [(9, Float(-1)), (10, Float(1))] {
            perform(Fold(origin: [sign*q,0,0], axis: [0,0,1], normal: [sign,0,0], angle: sign * .pi,
                         arrow: [sign*w*0.88,0,q], layers: [0,2,3]), at: index)
        }
        if step >= 11 && step <= 14 {
            let fold = Fold(origin: [0,0,q], axis: [1,0,0], normal: [0,0,1], angle: -.pi,
                            arrow: [q*0.4,0,w*0.9], layers: [2,3], resultLayer: 4)
            perform(fold, at: 11, amount: step == 11 ? p : (step == 14 ? 1-p : 1))
            if step == 14 {
                crease = PaperCrease(start: [-q,0,q], end: [q,0,q])
                var open = fold; open.arrow.z = q*0.1; open.angle = .pi
                paths = [arrowPath(open)]
            }
            for (index, sign) in [(12, Float(-1)), (13, Float(1))] where step >= index {
                var precrease = Fold(origin: .zero, axis: simd_normalize([sign,0,1]), normal: [sign,0,-1],
                                     angle: sign * .pi, arrow: [sign*q*0.88,0,q*0.08], layer: 4)
                if step == 14 {
                    // The retained crease is a boundary in the paper mesh. Move
                    // its cutting plane with the opening flap, then split with
                    // zero rotation so the guide cannot float above the paper.
                    precrease.origin = rotated(precrease.origin, origin: fold.origin, axis: fold.axis, angle: .pi*p)
                    precrease.axis = rotated(precrease.axis, origin: .zero, axis: fold.axis, angle: .pi*p)
                    precrease.normal = rotated(precrease.normal, origin: .zero, axis: fold.axis, angle: .pi*p)
                }
                let active = step == index
                if active { crease = clippedCrease(precrease, faces: faces) }
                let amount: Float = active ? (p <= 0.5 ? 2*p : 2*(1-p)) : 0
                faces = apply(precrease, to: faces, fraction: amount, active: active)
                if active {
                    if p > 0.5 {
                        precrease.arrow = rotated(precrease.arrow, origin: precrease.origin, axis: precrease.axis, angle: precrease.angle)
                        precrease.angle *= -1
                    }
                    paths = [arrowPath(precrease)]
                }
            }
        }
        if step >= 15 {
            // Same material, new triangulation of the same pose at t=0. Every
            // back-sheet source coordinate is retained, including the doubled hem.
            faces.removeAll { $0.originalSide == 2 || $0.originalSide == 3 }
            faces += rearPocket(fraction: step == 15 ? p : 1)
            if step == 15 {
                crease = PaperCrease(start: [-q,0,q], end: [q,0,q])
                paths = [-1,Float(1)].map { sign in (0...24).map { i in
                    let c = pocketCorner(Float(i)/24)
                    return SIMD3<Float>(-sign*c.x,c.y,-c.z)
                } }
            }
        }
        for (index, sign) in [(16, Float(-1)), (17, Float(1))] {
            perform(Fold(origin: .zero, axis: simd_normalize([sign,0,1]), normal: [sign,0,-1],
                         angle: sign * .pi, arrow: [sign*w*0.88,0,q*0.05], layer: 5, resultLayer: index), at: index)
        }
        for (index, sign, layer) in [(18, Float(-1),16), (19, Float(1),17)] {
            let slope = tan(Float.pi/8)
            perform(Fold(origin: .zero, axis: simd_normalize([sign*slope,0,1]), normal: [-sign,0,slope],
                         angle: -sign * .pi, arrow: [sign*q*0.08,0,w*0.9], layer: layer), at: index)
        }
        let springAngle = -Float.pi + relaxation * 0.42
        perform(Fold(origin: .zero, axis: [1,0,0], normal: [0,0,1], angle: springAngle,
                     arrow: [w*0.4,0,w*0.65], layers: [2,3,5,16,17], resultLayer: 20), at: 20)
        if step >= 21 {
            let origin = rotated([0,0,w/4], origin: .zero, axis: [1,0,0], angle: springAngle)
            let normal = rotated([0,0,1], origin: .zero, axis: [1,0,0], angle: springAngle)
            let arrow = rotated([w*0.3,0,w*0.65], origin: .zero, axis: [1,0,0], angle: springAngle)
            perform(Fold(origin: origin, axis: [1,0,0], normal: normal, angle: .pi - relaxation * 0.84,
                         arrow: arrow, layer: 20), at: 21)
        }
        if step == 22 {
            // Turning the complete paper and gently releasing existing creases
            // makes the spring visible. There is no new or scaled mesh here.
            turnOver(&faces, amount: p)
            transform(&faces, origin: .zero, axis: [1,0,0], angle: -0.21*p)
            crease = nil; paths = turnPath()
        }
        if step <= 4 {
            for i in faces.indices {
                let vertices = faces[i].vertices
                faces[i].outlinedEdges = vertices.indices.map { j in
                    let a = vertices[j].source, b = vertices[(j+1)%vertices.count].source
                    func onLine(_ n: SIMD2<Float>, _ d: Float) -> Bool {
                        abs(simd_dot(a,n)-d) < 0.000001 && abs(simd_dot(b,n)-d) < 0.000001
                    }
                    return onLine([1,0],w) || onLine([1,0],-w) || onLine([0,1],2*w) || onLine([0,1],-2*w)
                        || (step >= 1 && onLine([0,1],0))
                        || (step >= 2 && onLine([1,-1],w))
                        || (step >= 3 && onLine([1,1],-w))
                        || (step >= 4 && onLine([0,1],-w))
                }
            }
        }
        return aboveTable(faces, crease: crease, paths: paths)
    }

    private static func face(_ source: [SIMD2<Float>], layer: Int) -> PaperFace {
        var vertices = source.map { PaperVertex(position: [$0.x,0,$0.y], source: $0) }
        let a=source[1]-source[0],b=source[2]-source[0]
        if a.x*b.y-a.y*b.x > 0 { vertices.reverse() }
        return PaperFace(vertices: vertices, originalSide: layer)
    }
    private static func head(collapse p: Float) -> [PaperFace] {
        let w=width/2
        let O=SIMD3<Float>(0,0,-w), AL=SIMD3<Float>(-w,0,0), AR=SIMD3<Float>(w,0,0)
        let BL=rotated([-w,0,-2*w],origin:O,axis:[1,0,0],angle:.pi*p)
        let BR=rotated([w,0,-2*w],origin:O,axis:[1,0,0],angle:.pi*p)
        let ML=waterbombMidpoint(sign:-1,fraction:p), MR=waterbombMidpoint(sign:1,fraction:p)
        let sources: [SIMD2<Float>] = [[0,-w],[-w,0],[w,0],[-w,-w],[w,-w],[-w,-2*w],[w,-2*w]]
        let poses=[O,AL,AR,ML,MR,BL,BR]
        let panels=[([0,1,2],0),([0,1,3],0),([0,3,5],1),([0,5,6],1),([0,6,4],1),([0,4,2],0)]
        return panels.enumerated().map { index, panel in
            let (ids, layer) = panel
            var vertices=ids.map { PaperVertex(position:poses[$0],source:sources[$0]) }
            let a=vertices[1].source-vertices[0].source,b=vertices[2].source-vertices[0].source
            if a.x*b.y-a.y*b.x>0 {vertices.reverse()}
            let rank: Float = [0,1,2,3,2,1][index]
            for i in vertices.indices { vertices[i].separation = [0, rank * 0.00008 * p, 0] }
            return PaperFace(vertices:vertices,originalSide:layer)
        }
    }
    private static func waterbombMidpoint(sign: Float, fraction p: Float) -> SIMD3<Float> {
        let w=Double(width)/2
        if p <= 0.000001 {return [sign*Float(w),0,-Float(w)]}
        if p >= 0.999999 {return .zero}
        let t=Double.pi*Double(p)
        let a=SIMD3<Double>(0,0,-w),b=SIMD3<Double>(w,0,0),c=SIMD3<Double>(w,w*sin(t),-w-w*cos(t))
        let candidates=intersections(a,b,c,w,w,w)
        let m=candidates.0.x < candidates.1.x ? candidates.0 : candidates.1
        return [sign*Float(m.x),Float(m.y),Float(m.z)]
    }
    private static func rearPocket(fraction p: Float) -> [PaperFace] {
        let q=width/4
        var result=[PaperFace]()
        for xs: Float in [-1,1] { for hem in [false,true] {
            let Q=SIMD3<Float>(-q,0,-q), L=SIMD3<Float>.zero
            let T=rotated([-q,0,-2*q],origin:Q,axis:[1,0,0],angle:.pi*p)
            let U=rotated([0,0,-2*q],origin:Q,axis:[1,0,0],angle:.pi*p)
            let V=rotated([0,0,-q],origin:Q,axis:simd_normalize(L-Q),angle:.pi*p)
            let data: [(SIMD2<Float>,SIMD3<Float>)]=[
                ([-q,-q],Q),([-2*q,0],L),([-q,0],[-q,0,0]),([0,0],.zero),([0,-q],[0,0,-q]),
                ([-q,-2*q],T),([0,-2*q],U),([-2*q,-q],V),([-2*q,-2*q],pocketCorner(p))]
            let panels=[[0,5,8],[0,8,7],[0,7,1],[0,1,2],[0,4,6],[0,6,5],[0,2,3],[0,3,4]]
            for (index, ids) in panels.enumerated() {
                var vertices=ids.map { id -> PaperVertex in
                    let pair=data[id], z = -pair.0.y
                    return PaperVertex(position:[pair.1.x*xs,pair.1.y,-pair.1.z],source:[pair.0.x*xs,hem ? 4*q-z : z])
                }
                let a=vertices[1].source-vertices[0].source,b=vertices[2].source-vertices[0].source
                if a.x*b.y-a.y*b.x>0 {vertices.reverse()}
                let flap=[0,1,2,5].contains(index)
                var f=PaperFace(vertices:vertices,originalSide:flap ? 5 : (hem ? 3 : 2),isMoving:p>0 && p<1)
                // Separate coincident rendered sheets; the source geometry above remains exact.
                let rank = Float(index + 1 + (hem ? 8 : 0))
                for i in f.vertices.indices {f.vertices[i].separation=f.normal*(rank * 0.000045)}
                result.append(f)
            }
        }}
        return result
    }
    private static func pocketCorner(_ p: Float) -> SIMD3<Float> {
        let q=Double(width)/4
        if p <= 0.000001 {return [0,0,Float(-2*q)]}
        if p >= 0.999999 {return [Float(-2*q),0,0]}
        let t=Double.pi*Double(p)
        let a=SIMD3<Double>(-q,0,-q),b=SIMD3<Double>(-q,q*sin(t),-q-q*cos(t))
        let c=SIMD3<Double>(-q*(1-cos(t))/2,q*sin(t)/sqrt(2),-q*(1+cos(t))/2)
        let candidates=intersections(a,b,c,q*sqrt(2),q,q)
        return SIMD3<Float>(candidates.0.x<candidates.1.x ? candidates.0 : candidates.1)
    }
    private static func intersections(_ a: SIMD3<Double>,_ b: SIMD3<Double>,_ c: SIMD3<Double>,_ r1: Double,_ r2: Double,_ r3: Double) -> (SIMD3<Double>,SIMD3<Double>) {
        let d=simd_distance(a,b),ex=(b-a)/d,delta=c-a,i=simd_dot(ex,delta)
        let perpendicular=delta-i*ex,j=simd_length(perpendicular),ey=perpendicular/j,ez=simd_cross(ex,ey)
        let x=(r1*r1-r2*r2+d*d)/(2*d)
        let y=(r1*r1-r3*r3+i*i+j*j-2*i*x)/(2*j)
        let z=sqrt(max(0,r1*r1-x*x-y*y)),base=a+ex*x+ey*y
        return (base+ez*z,base-ez*z)
    }
    private static func transform(_ faces: inout [PaperFace], origin: SIMD3<Float>, axis: SIMD3<Float>, angle: Float) {
        for i in faces.indices {for j in faces[i].vertices.indices {
            faces[i].vertices[j].position=rotated(faces[i].vertices[j].position,origin:origin,axis:axis,angle:angle)
            faces[i].vertices[j].separation=rotated(faces[i].vertices[j].separation,origin:.zero,axis:axis,angle:angle)
        }}
    }
    private static func apply(_ fold: Fold, to faces: [PaperFace], fraction: Float, active: Bool) -> [PaperFace] {
        let axis = simd_normalize(fold.axis)
        let angle = fold.angle * fraction
        var result = [PaperFace]()
        for face in faces {
            guard (fold.layer == nil || fold.layer == face.originalSide) && (fold.layers?.contains(face.originalSide) ?? true) else {
                result.append(face); continue
            }
            let pieces = split(face.vertices, point: fold.origin, normal: fold.normal)
            if pieces.stationary.count >= 3 {
                result.append(PaperFace(vertices: pieces.stationary, originalSide: face.originalSide,
                                        isMoving: face.isMoving))
            }
            if pieces.moving.count >= 3 {
                let vertices = pieces.moving.map { original -> PaperVertex in
                    var v = original
                    v.position = rotated(v.position, origin: fold.origin, axis: axis, angle: angle)
                    v.separation = rotated(v.separation, origin: .zero, axis: axis, angle: angle)
                        + SIMD3<Float>(0, fold.separation * sin(abs(angle) / 2), 0)
                    return v
                }
                result.append(PaperFace(vertices: vertices, originalSide: fold.resultLayer ?? face.originalSide,
                                        isMoving: active || face.isMoving))
            }
        }
        return result.filter { $0.area > 1e-12 }
    }

    private static func split(_ vertices: [PaperVertex], point: SIMD3<Float>, normal: SIMD3<Float>)
        -> (stationary: [PaperVertex], moving: [PaperVertex]) {
        func clip(_ positive: Bool) -> [PaperVertex] {
            guard !vertices.isEmpty else { return [] }
            var output = [PaperVertex]()
            for i in vertices.indices {
                let a = vertices[i], b = vertices[(i + 1) % vertices.count]
                let da = simd_dot(a.position - point, normal), db = simd_dot(b.position - point, normal)
                let ai = positive ? da >= -epsilon : da <= epsilon
                let bi = positive ? db >= -epsilon : db <= epsilon
                if ai { output.append(a) }
                if ai != bi, abs(da - db) > epsilon {
                    output.append(.interpolate(a, b, min(1, max(0, da / (da - db)))))
                }
            }
            var clean = [PaperVertex]()
            for v in output where clean.last.map({ simd_distance($0.position, v.position) > epsilon }) ?? true {
                clean.append(v)
            }
            if clean.count > 1, simd_distance(clean[0].position, clean.last!.position) < epsilon { clean.removeLast() }
            return clean
        }
        return (clip(false), clip(true))
    }

    private static func clippedCrease(_ fold: Fold, faces: [PaperFace]) -> PaperCrease? {
        let axis = simd_normalize(fold.axis)
        var distances = [Float]()
        for face in faces where (fold.layer == nil || fold.layer == face.originalSide) && (fold.layers?.contains(face.originalSide) ?? true) {
            for i in face.vertices.indices {
                let a = face.vertices[i].position, b = face.vertices[(i + 1) % face.vertices.count].position
                let da = simd_dot(a - fold.origin, fold.normal), db = simd_dot(b - fold.origin, fold.normal)
                if abs(da) < epsilon { distances.append(simd_dot(a - fold.origin, axis)) }
                if da * db < 0 { distances.append(simd_dot(a + (b - a) * da / (da - db) - fold.origin, axis)) }
            }
        }
        guard let lo = distances.min(), let hi = distances.max(), hi - lo > 0.00001 else { return nil }
        return PaperCrease(start: fold.origin + axis * lo, end: fold.origin + axis * hi)
    }

    private static func arrowPath(_ fold: Fold) -> [SIMD3<Float>] {
        (0...24).map { i in
            rotated(fold.arrow, origin: fold.origin, axis: simd_normalize(fold.axis),
                    angle: fold.angle * (0.08 + 0.84 * Float(i) / 24))
        }
    }

    private static func turnPath() -> [[SIMD3<Float>]] {
        [(0...24).map { i in rotated([-width * 0.4, 0, 0], origin: .zero, axis: [0, 0, 1], angle: -.pi * Float(i) / 24) }]
    }

    private static func turnOver(_ faces: inout [PaperFace], amount: Float) {
        for i in faces.indices {
            for j in faces[i].vertices.indices {
                faces[i].vertices[j].position = rotated(faces[i].vertices[j].position, origin: .zero, axis: [0, 0, 1], angle: -.pi * amount)
                faces[i].vertices[j].separation = rotated(faces[i].vertices[j].separation, origin: .zero, axis: [0, 0, 1], angle: -.pi * amount)
            }
            faces[i].isMoving = amount < 1
        }
    }

    private static func aboveTable(_ original: [PaperFace], crease originalCrease: PaperCrease?, paths originalPaths: [[SIMD3<Float>]]) -> PaperFrame {
        var faces = original
        var crease = originalCrease
        let minY = faces.flatMap(\.vertices).map { $0.position.y }.min() ?? 0
        let lift = max(0, -minY) + 0.0015
        for i in faces.indices { for j in faces[i].vertices.indices { faces[i].vertices[j].position.y += lift } }
        if var c = crease { c.start.y += lift + 0.001; c.end.y += lift + 0.001; crease = c }
        let paths = originalPaths.map { path in
            let height = max(lift + 0.006, 0.006 - (path.map(\.y).min() ?? 0))
            return path.map { $0 + SIMD3<Float>(0, height, 0) }
        }
        return PaperFrame(faces: faces, crease: crease, actionPaths: paths, tableLift: lift)
    }

    private static func rotated(_ point: SIMD3<Float>, origin: SIMD3<Float>, axis: SIMD3<Float>, angle: Float) -> SIMD3<Float> {
        let v = point - origin
        let rawS = sin(angle), rawC = cos(angle)
        let s: Float = abs(rawS) < 1e-6 ? 0 : rawS, c: Float = abs(rawC) < 1e-6 ? 0 : rawC
        return origin + v * c + simd_cross(axis, v) * s + axis * simd_dot(axis, v) * (1 - c)
    }

}
