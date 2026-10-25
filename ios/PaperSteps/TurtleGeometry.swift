import Foundation
import simd

/// Traditional no-cut turtle: one source square and 23 folding/shaping actions.
/// Final leg bends are authored forming approximations, not rigid-panel physics.
enum TurtleGeometry {
    static let width: Float = 0.15
    /// Ready state plus 23 meaningful actions.
    static let plannedActionCount = 23
    static let stepCount = 24
    static let lastStep = stepCount - 1
    static let isComplete = true
    private static let a = width / 2
    private static let k = tan(Float.pi / 8)
    private static let epsilon: Float = 0.00000015

    private struct Patch {
        var face: PaperFace
        /// Main pentagon is zero; the original bottom corners are -1 and +1.
        var part: Int
    }

    static func frame(step requestedStep: Int, progress requestedProgress: Float) -> PaperFrame {
        let step = min(lastStep, max(0, requestedStep))
        let p = requestedProgress.isFinite ? min(1, max(0, requestedProgress)) : 0
        func amount(_ index: Int) -> Float {
            if step > index { return 1 }
            guard step == index else { return 0 }
            // Relax and restore the shell around the three later flat folds.
            if (17...19).contains(index) { return min(1,max(0,(p-0.2)/0.6)) }
            return p
        }
        var patches = initialPatches()
        var crease: PaperCrease?
        var paths = [[SIMD3<Float>]]()

        if step == 1 {
            let origin = SIMD3<Float>.zero, axis = SIMD3<Float>(0, 0, 1)
            fold(&patches, origin: origin, axis: axis, normal: [-1, 0, 0],
                 angle: .pi * sin(.pi * p), select: { _ in true }, active: true)
            crease = PaperCrease(start: [0, 0, -a], end: [0, 0, a])
            paths = [arc([-a * 0.85, 0, 0], origin, axis, .pi)]
        }
        for side in [-1, 1] {
            let index = side == -1 ? 2 : 3
            guard step >= index else { continue }
            let x = Float(side), origin = SIMD3<Float>(x * a, 0, 0)
            let axis = SIMD3<Float>(-x, 0, 1)
            turn(&patches, origin: origin, axis: axis, angle: x * .pi * amount(index),
                 select: { $0.part == side }, active: step == index)
            if step == index {
                crease = PaperCrease(start: origin, end: [0, 0, a])
                paths = [arc([x * a, 0, a], origin, axis, x * .pi)]
            }
        }
        for side in [-1, 1] {
            let index = side == -1 ? 4 : 5
            guard step >= index else { continue }
            let x = Float(side), origin = SIMD3<Float>(0, 0, a)
            let axis = SIMD3<Float>(x * k, 0, -1)
            let angle = -x * .pi * amount(index)
            // The old corner is attached to this entire flap. It crosses the
            // new hinge in projection only, and must not acquire a new crease.
            fold(&patches, origin: origin, axis: axis, normal: [x, 0, k],
                 angle: angle, select: { $0.part == 0 }, active: step == index)
            turn(&patches, origin: origin, axis: axis, angle: angle,
                 select: { $0.part == side }, active: step == index)
            if step == index {
                crease = PaperCrease(start: origin, end: [x * 2 * a * k, 0, -a])
                paths = [arc([x * a, 0, -a], origin, axis, -x * .pi)]
            }
        }

        // A rigid reorientation, included with the second edge fold rather than
        // counted as an extra origami operation.
        let presentation = Float.pi * amount(5)
        turn(&patches, origin: .zero, axis: [0, 1, 0], angle: presentation,
             select: { _ in true }, active: false)
        if let c = crease {
            crease = PaperCrease(start: rotate(c.start, .zero, [0, 1, 0], presentation),
                                 end: rotate(c.end, .zero, [0, 1, 0], presentation))
        }
        paths = paths.map { $0.map { rotate($0, .zero, [0, 1, 0], presentation) } }

        for side in [-1, 1] {
            let x = Float(side), index = side == -1 ? 6 : 8, tag = side == -1 ? 10 : 11
            let origin = SIMD3<Float>(0, 0, a), axis = SIMD3<Float>(-x, 0, 1)
            if step >= index {
                fold(&patches, origin: origin, axis: axis, normal: [x, 0, 1],
                     angle: x * .pi * amount(index), select: { _ in true }, active: step == index, movingPart: tag)
                if step == index {
                    crease = PaperCrease(start: [x * a * 0.72,0,a * 0.28], end: origin)
                    paths = [arc([x * a * 0.72,0,a * 1.05], origin, axis, x * .pi)]
                }
            }
            if step >= index + 1 {
                let out = SIMD3<Float>(0, 0, a * 0.78)
                fold(&patches, origin: out, axis: axis, normal: [-x, 0, -1],
                     angle: -x * .pi * amount(index + 1), select: { $0.part == tag }, active: step == index + 1, movingPart: tag + 20)
                if step == index + 1 {
                    crease = PaperCrease(start: [x * a * 0.35,0,a * 0.43], end: out)
                    paths = [arc([0,0,a * 0.20], out, axis, -x * .pi)]
                }
            }
        }

        let headBase = a * (1 - sqrt(Float(2))) / sqrt(Float(2))
        if step >= 10 {
            let origin = SIMD3<Float>(0,0,headBase)
            fold(&patches, origin: origin, axis: [1,0,0], normal: [0,0,-1],
                 angle: .pi * amount(10), select: { _ in true }, active: step == 10, movingPart: 20)
            if step == 10 {
                crease = PaperCrease(start: [-a/sqrt(2),0,headBase], end: [a/sqrt(2),0,headBase])
                paths = [arc([0,0,-a], origin, [1,0,0], .pi)]
            }
        }
        if step >= 11 {
            let headReturn = a * (sqrt(Float(2)) - 1.5)
            let origin = SIMD3<Float>(0,0,headReturn)
            fold(&patches, origin: origin, axis: [1,0,0], normal: [0,0,1],
                 angle: -.pi * amount(11), select: { $0.part == 20 }, active: step == 11, movingPart: 21)
            if step == 11 {
                crease = PaperCrease(start: [-a/2,0,headReturn], end: [a/2,0,headReturn])
                paths = [arc([0,0,a*(sqrt(2)-1)], origin, [1,0,0], -.pi)]
            }
        }

        // The precrease and swivel use the same attached bottom-corner layer.
        // Three rigid sectors meet around C; the shared edge point is solved
        // from distances, so the head and front leg never separate.
        for side in [1, -1] {
            let pre = side == 1 ? 12 : 14
            let swivel = pre + 1
            guard step >= pre else { continue }
            let x = Float(side)
            let c = SIMD3<Float>(x * a * (sqrt(2) - 1) / 2, 0, a * (sqrt(2) - 1.5))
            let f = SIMD3<Float>(x * a / sqrt(2), 0, headBase)
            let n = SIMD3<Float>(x * k, 0, 1)
            fold(&patches, origin: c, axis: f - c, normal: n,
                 angle: -x * .pi * (step == pre ? sin(.pi * p) : 0),
                 select: { $0.face.originalSide == -side && ($0.part == 20 || $0.part == 21) },
                 active: step == pre)
            if step == pre {
                crease = PaperCrease(start: c, end: f)
                paths = [arc([x*a/2,0,c.z], c, f-c, -x * .pi)]
            }
            if step >= swivel {
                applySwivel(&patches, side: side, progress: amount(swivel), active: step == swivel)
                if step == swivel {
                    crease = PaperCrease(start: c, end: [x*a*0.18,0,a*(-(2-sqrt(2))+0.18)])
                    paths = [arc([x*a/2,0,c.z], c, f-c, -x * .pi)]
                }
            }
        }

        // Rounding cuts across the shell and the connected leg-root band, but
        // not the free foot flap which overlaps it only in the flat projection.
        for side in [-1,1] {
            let index = side == -1 ? 17 : 18
            guard step >= index else { continue }
            let x=Float(side), origin=SIMD3<Float>(x*a*0.52,0,a*0.40)
            let axis=SIMD3<Float>(-x*0.24,0,1)
            fold(&patches,origin:origin,axis:axis,normal:[x,0,0.24],angle:-x * .pi * amount(index),
                 select:{$0.face.originalSide == 0 && $0.part != 30 && $0.part != 31},active:step == index)
            if step == index {
                crease=PaperCrease(start:[x*a*0.548,0,a*0.282],end:[x*a*0.487,0,a*0.537])
                paths=[arc([x*a*0.586,0,a*0.414],origin,axis,-x * .pi)]
            }
        }
        if step >= 19 {
            let q=amount(19), first=min(1,q*2), second=max(0,q*2-1)
            let root=SIMD3<Float>(0,0,a*0.89), out=SIMD3<Float>(0,0,a*0.86)
            fold(&patches,origin:root,axis:[1,0,0],normal:[0,0,1],angle:-.pi*first,
                 select:{$0.part == 0 || $0.part == 10 || $0.part == 11},active:step == 19,movingPart:40)
            fold(&patches,origin:out,axis:[1,0,0],normal:[0,0,-1],angle:.pi*second,
                 select:{$0.part == 40},active:step == 19)
            if step == 19 {
                crease=PaperCrease(start:[-a*0.11,0,root.z],end:[a*0.11,0,root.z])
                paths=[arc([0,0,a],root,[1,0,0],-.pi)]
            }
        }
        var shell: Float = step < 16 ? 0 : amount(16)
        if (17...19).contains(step) {
            shell = p < 0.2 ? 1-smooth(p/0.2) : p > 0.8 ? smooth((p-0.8)/0.2) : 0
        }
        if step >= 16 {
            conePleat(&patches,progress:shell,active:step == 16)
            if step == 16 {
                crease=PaperCrease(start:[0,0,a*(sqrt(2)-1)],end:conePoint([0,0,a],progress:shell))
                paths=[]
            } else {
                if let c=crease { crease=PaperCrease(start:conePoint(c.start,progress:shell),end:conePoint(c.end,progress:shell)) }
                paths=paths.map{$0.map{conePoint($0,progress:shell)}}
            }
        }
        if step >= 20 {
            // Fine material triangles carry local forming bends. This changes
            // surface curvature while retaining the same source square.
            patches=patches.flatMap { patch in
                patch.face.originalSide != 0 || patch.part == 30 || patch.part == 31 ? subdivide(patch,level:2) : [patch]
            }
            for side in [-1,1] {
                let index=side == -1 ? 20 : 21
                guard step >= index else { continue }
                shapeLeg(&patches,side:side,rear:false,progress:amount(index),shell:shell,active:step == index)
            }
            for side in [-1,1] {
                let index=side == -1 ? 22 : 23
                guard step >= index else { continue }
                shapeLeg(&patches,side:side,rear:true,progress:amount(index),shell:shell,active:step == index)
            }
            if step >= 20 {
                let rear=step >= 22, x:Float = (step == 20 || step == 22) ? -1 : 1
                let tip=SIMD3<Float>(x*a*(rear ? 0.4871068 : 1/sqrt(2)),0,a*(rear ? 0.9011068 : 1/sqrt(2)-1))
                let root=SIMD3<Float>(x*a*(rear ? 0.26 : 0.35),0,a*(rear ? 0.56 : -0.20))
                crease=PaperCrease(start:conePoint(root,progress:shell),end:conePoint(tip,progress:shell));paths=[]
            }
        }
        if step >= 16 {
            let flip = Float.pi * amount(16)
            turn(&patches,origin:.zero,axis:[0,0,1],angle:flip,select:{_ in true},active:false)
            if let c=crease { crease=PaperCrease(start:rotate(c.start,.zero,[0,0,1],flip),end:rotate(c.end,.zero,[0,0,1],flip)) }
            paths=paths.map{$0.map{rotate($0,.zero,[0,0,1],flip)}}
        }

        var faces = patches.map(\.face)
        let minimumY = faces.flatMap(\.vertices).map(\.position.y).min() ?? 0
        let lift = max(0, -minimumY) + 0.001
        for i in faces.indices {
            if faces[i].outlinedEdges == nil { faces[i].outlinedEdges = faces[i].vertices.indices.map { j in
                let first = faces[i].vertices[j].source
                let second = faces[i].vertices[(j + 1) % faces[i].vertices.count].source
                let left = abs(first.y - first.x - a) < 1e-6 && abs(second.y - second.x - a) < 1e-6
                let right = abs(first.y + first.x - a) < 1e-6 && abs(second.y + second.x - a) < 1e-6
                return !(left && step < 2) && !(right && step < 3)
            } }
            for j in faces[i].vertices.indices {
                faces[i].vertices[j].position.y += lift
                // Rendering separation only; the source-to-position map is
                // still the exact uncut sheet and is what validation checks.
                let part = patches[i].part
                let flip = step >= 16 ? Float.pi * amount(16) : 0
                let level: Float = abs(faces[i].originalSide) == 1 ? 0.00025 :
                    (part == 30 || part == 31 ? 0.00045 : part == 10 || part == 11 ? 0.00030 : part == 40 ? 0.00020 : 0)
                faces[i].vertices[j].separation = rotate([0,level,0],.zero,[0,0,1],flip) + SIMD3<Float>(0,faces[i].normal.y < 0 ? 0.00006 : -0.00006,0)
            }
        }
        if let c = crease {
            crease = PaperCrease(start: c.start + [0, lift, 0], end: c.end + [0, lift, 0])
        }
        paths = paths.map { $0.map { $0 + SIMD3<Float>(0, lift + 0.002, 0) } }
        return PaperFrame(faces: faces, crease: crease, actionPaths: paths, tableLift: lift)
    }

    private static func smooth(_ p: Float) -> Float { let q=min(1,max(0,p)); return q*q*(3-2*q) }

    private static let dartHalfAngle: Double = 0.24
    private static let coneSectors = 32
    private static var shellPivot: SIMD3<Float> { [0,0,a*(sqrt(2)-1)] }

    /// A polyhedral developable cone around the actual tail-dart vertex. Each
    /// sector is a rigid rotation: equal source angles have equal spherical
    /// distances. Two dart sectors close together without removing any paper.
    private static func coneRays(progress: Float) -> (angles:[Float], directions:[SIMD3<Float>]) {
        let d=dartHalfAngle, n=coneSectors, omega=2*Double.pi-2*d
        let sourceAngle=omega/Double(n), t=Double(smooth(progress))
        let azimuth=sourceAngle+(2*Double.pi/Double(n)-sourceAngle)*t
        let h2=max(0,(cos(sourceAngle)-cos(azimuth))/(1-cos(azimuth)))
        let h=sqrt(h2), radius=sqrt(max(0,1-h2))
        var main=(0...n).map { j -> SIMD3<Double> in
            let angle=2*d+Double(j)*azimuth
            return [radius*sin(angle),h,radius*cos(angle)]
        }
        if progress >= 1 { main[n]=main[0] }
        let first=main[n], last=main[0], dot=simd_dot(first,last)
        let base=cos(d)/(1+dot)*(first+last)
        var normal=simd_cross(first,last)
        if simd_length(normal) < 1e-9 { normal=[-h*sin(2*d),radius,-h*cos(2*d)] }
        normal=simd_normalize(normal)
        // The inner branch keeps the dart beneath the shell after the
        // whole-model flip, instead of forming an exterior ridge.
        let middle=base+normal*sqrt(max(0,1-simd_length_squared(base)))
        let angles=[Float(0),Float(d)] + (0...n).map{Float(2*d+Double($0)*sourceAngle)}
        let rays=[SIMD3<Float>(first),SIMD3<Float>(middle)] + main.map{SIMD3<Float>($0)}
        return (angles,rays)
    }

    private static func conePoint(_ point: SIMD3<Float>, progress: Float) -> SIMD3<Float> {
        guard progress > 0 else { return point }
        let c=shellPivot, data=coneRays(progress:progress), v=point-c
        var theta=atan2(v.x,v.z); if theta < 0 { theta += 2*Float.pi }
        var index=data.angles.count-2
        for i in 0..<(data.angles.count-1) where theta >= data.angles[i]-1e-6 && theta <= data.angles[i+1]+1e-6 { index=i;break }
        let lo=SIMD3<Float>(sin(data.angles[index]),0,cos(data.angles[index]))
        let hi=SIMD3<Float>(sin(data.angles[index+1]),0,cos(data.angles[index+1]))
        return rigidMap(point,c,c+a*lo,c+a*hi,c,c+a*data.directions[index],c+a*data.directions[index+1])
    }

    private static func conePleat(_ patches: inout [Patch], progress: Float, active: Bool) {
        guard progress > 0 else { return }
        let c=shellPivot, data=coneRays(progress:progress)
        var result=[Patch]()
        for patch in patches {
            for i in 0..<(data.angles.count-1) {
                let lo=data.angles[i], hi=data.angles[i+1]
                let start=clip(patch.face.vertices,origin:c,normal:[cos(lo),0,-sin(lo)],positive:true)
                guard start.count >= 3 else { continue }
                let vertices=clip(start,origin:c,normal:[-cos(hi),0,sin(hi)],positive:true)
                guard vertices.count >= 3 else { continue }
                var q=patch;q.face.vertices=vertices
                guard q.face.area > 1e-12 else { continue }
                q.face.outlinedEdges=inheritedEdges(vertices,from:patch.face)
                q.face.vertices=vertices.map { vertex in
                    var value=vertex
                    let fromLo=SIMD3<Float>(sin(lo),0,cos(lo)), fromHi=SIMD3<Float>(sin(hi),0,cos(hi))
                    value.position=rigidMap(vertex.position,c,c+a*fromLo,c+a*fromHi,c,c+a*data.directions[i],c+a*data.directions[i+1])
                    return value
                }
                q.face.isMoving=active;result.append(q)
            }
        }
        patches=result
    }

    private static func inheritedEdges(_ vertices:[PaperVertex],from face:PaperFace) -> [Bool] {
        vertices.indices.map { i in
            let first=vertices[i].source, second=vertices[(i+1)%vertices.count].source
            for j in face.vertices.indices where face.outlinedEdges?[j] ?? true {
                let a=face.vertices[j].source,b=face.vertices[(j+1)%face.vertices.count].source,d=b-a
                let length=simd_length(d)
                if length < 1e-8 { continue }
                func on(_ p:SIMD2<Float>) -> Bool {
                    abs(d.x*(p.y-a.y)-d.y*(p.x-a.x))/length < 2e-7 && simd_dot(p-a,d) >= -1e-9 && simd_dot(p-b,d) <= 1e-9
                }
                if on(first) && on(second) { return true }
            }
            return false
        }
    }

    private static func subdivide(_ patch:Patch,level:Int) -> [Patch] {
        guard patch.face.vertices.count >= 3 else { return [] }
        var triangles=[Patch]()
        for i in 1..<(patch.face.vertices.count-1) {
            var q=patch;q.face.vertices=[patch.face.vertices[0],patch.face.vertices[i],patch.face.vertices[i+1]]
            q.face.outlinedEdges=inheritedEdges(q.face.vertices,from:patch.face)
            if q.face.area > 1e-12 { triangles.append(q) }
        }
        for _ in 0..<level {
            triangles=triangles.flatMap { q -> [Patch] in
                let v=q.face.vertices, ab=PaperVertex.interpolate(v[0],v[1],0.5),bc=PaperVertex.interpolate(v[1],v[2],0.5),ca=PaperVertex.interpolate(v[2],v[0],0.5)
                return [[v[0],ab,ca],[ab,v[1],bc],[ca,bc,v[2]],[ab,bc,ca]].map { vertices in
                    var next=q;next.face.vertices=vertices;next.face.outlinedEdges=inheritedEdges(vertices,from:q.face);return next
                }
            }
        }
        return triangles
    }

    /// A longitudinal shaping bend tapers to zero at the leg root. It is a
    /// forming approximation, not a claim that these intermediate panels stay
    /// perfectly rigid. The shared attachment is stationary and uncut.
    private static func shapeLeg(_ patches:inout [Patch],side:Int,rear:Bool,progress:Float,shell:Float,active:Bool) {
        guard progress > 0 else { return }
        let x=Float(side)
        if rear {
            let flatRoot=SIMD3<Float>(x*a*0.4871068,0,a*0.78)
            let root=conePoint(flatRoot,progress:shell)
            let across=simd_normalize(conePoint(flatRoot+[0.001,0,0],progress:shell)-root)
            let forwardHint=conePoint(flatRoot+[0,0,0.001],progress:shell)-root
            let forward=simd_normalize(forwardHint-across*simd_dot(forwardHint,across))
            let normal=simd_normalize(simd_cross(forward,across))
            let curvature=progress*2.35/(a*0.12132)
            for i in patches.indices where patches[i].part == (side == -1 ? 30 : 31) {
                for j in patches[i].face.vertices.indices {
                    let v=patches[i].face.vertices[j].position-root
                    let u=simd_dot(v,forward), h=simd_dot(v,normal)
                    guard u>0,curvature>1e-5 else { continue }
                    let theta=curvature*u
                    let uu=sin(theta)/curvature-h*sin(theta)
                    let hh=(1-cos(theta))/curvature+h*cos(theta)
                    patches[i].face.vertices[j].position=root+across*simd_dot(v,across)+forward*uu+normal*hh
                }
                if active { patches[i].face.isMoving=true }
            }
            return
        }
        let tip=conePoint([x*a*(rear ? 0.4871068 : 1/sqrt(2)),0,a*(rear ? 0.9011068 : 1/sqrt(2)-1)],progress:shell)
        let root=conePoint([x*a*(rear ? 0.26 : 0.35),0,a*(rear ? 0.56 : -0.20)],progress:shell)
        let axis=simd_normalize(tip-root), length=simd_distance(tip,root)
        // The local normal is read from the cone's material tangent plane.
        let flatRoot=SIMD3<Float>(x*a*(rear ? 0.26 : 0.35),0,a*(rear ? 0.56 : -0.20))
        let normal=simd_normalize(conePoint(flatRoot+[0,0.001,0],progress:shell)-root)
        let outer=x*simd_normalize(simd_cross(normal,axis))
        for i in patches.indices {
            let patch=patches[i]
            let selected=rear ? patch.part == (side == -1 ? 30 : 31) : patch.face.originalSide == -side
            guard selected else { continue }
            for j in patches[i].face.vertices.indices {
                let point=patches[i].face.vertices[j].position, v=point-root
                let along=simd_dot(v,axis)/length
                guard simd_dot(v,outer) > 0, along > 0.12 else { continue }
                let weight=smooth((along-0.12)/0.58)
                patches[i].face.vertices[j].position=rotate(point,root,axis,x*Float.pi*(rear ? 0.43 : 0.48)*progress*weight)
            }
            if active { patches[i].face.isMoving=true }
        }
    }

    private static func applySwivel(_ patches: inout [Patch], side: Int, progress: Float, active: Bool) {
        let x = Float(side), p = progress
        let c = SIMD3<Float>(x*a*(sqrt(2)-1)/2,0,a*(sqrt(2)-1.5))
        let r = SIMD3<Float>(x*a/2,0,c.z)
        let f = SIMD3<Float>(x*a/sqrt(2),0,a*(1/sqrt(2)-1))
        let v = SIMD3<Float>(x*a*0.18,0,a*(-(2-sqrt(2))+0.18))
        let rEnd = rotate(r,c,f-c,-x * .pi)
        let reflectedEnd = rotate(rEnd,c,v-c,.pi)
        let edge = r-v
        let fraction = (simd_length_squared(r)-simd_length_squared(reflectedEnd)-2*simd_dot(v,r-reflectedEnd)) / (2*simd_dot(edge,r-reflectedEnd))
        let m = v + fraction*edge
        let movingR = rotate(r,c,f-c,-x * .pi*p)
        let movingM: SIMD3<Float>
        if p <= 0 { movingM = m }
        else if p >= 1 { movingM = rotate(m,c,v-c,-x * .pi) }
        else { movingM = spherePoint(c,v,movingR,simd_distance(m,c),simd_distance(m,v),simd_distance(m,r)) }
        var result = [Patch]()
        func normal(_ end: SIMD3<Float>) -> SIMD3<Float> { let d=end-c; return [x*abs(d.z),0,abs(d.x)*((d.x*x)>=0 ? 1 : -1)] }
        let nv = normal(v), nm = normal(m)
        for patch in patches {
            guard patch.face.originalSide == -side else { result.append(patch); continue }
            if patch.part == 21 {
                // Split along the head valley C–V, then its coupled mountain C–M.
                let stay = clip(patch.face.vertices,origin:c,normal:nv,positive:false)
                if stay.count >= 3 { var q=patch; q.face.vertices=stay; if q.face.area > 1e-12 { result.append(q) } }
                let moving = clip(patch.face.vertices,origin:c,normal:nv,positive:true)
                guard moving.count >= 3 else { continue }
                for outer in [false,true] {
                    let vertices=clip(moving,origin:c,normal:nm,positive:outer)
                    guard vertices.count >= 3 else { continue }
                    var q=patch; q.face.vertices=vertices
                    guard q.face.area > 1e-12 else { continue }
                    q.face.vertices=vertices.map { vertex in
                        var value=vertex
                        value.position = outer ? rigidMap(vertex.position,c,m,r,c,movingM,movingR) : rigidMap(vertex.position,c,v,m,c,v,movingM)
                        return value
                    }
                    q.face.isMoving=active; result.append(q)
                }
            } else if patch.part == 20 {
                let n=SIMD3<Float>(x*k,0,1)
                for moving in [false,true] {
                    let vertices=clip(patch.face.vertices,origin:c,normal:n,positive:moving)
                    guard vertices.count >= 3 else { continue }
                    var q=patch; q.face.vertices=vertices
                    guard q.face.area > 1e-12 else { continue }
                    if moving {
                        q.face.vertices=vertices.map { vertex in var value=vertex; value.position=rotate(value.position,c,f-c,-x * .pi*p); return value }
                        q.face.isMoving=active
                    }
                    result.append(q)
                }
            } else { result.append(patch) }
        }
        patches=result
    }

    /// Orthonormal frame transport: preserves every face distance, including
    /// sub-triangles introduced by an earlier precrease.
    private static func rigidMap(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
                                 _ aa: SIMD3<Float>, _ bb: SIMD3<Float>, _ cc: SIMD3<Float>) -> SIMD3<Float> {
        func basis(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> simd_float3x3 {
            let u=simd_normalize(b-a), n=simd_normalize(simd_cross(u,c-a)), v=simd_cross(n,u)
            return simd_float3x3(columns:(u,v,n))
        }
        return aa + basis(aa,bb,cc) * basis(a,b,c).transpose * (p-a)
    }

    /// Intersection of three spheres. The upper branch lifts the top layer;
    /// the other branch drives it through the stationary head surface.
    private static func spherePoint(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
                                    _ rA: Float, _ rB: Float, _ rC: Float) -> SIMD3<Float> {
        // Use Double for the near-flat endpoints of the linkage.
        let a=SIMD3<Double>(a), b=SIMD3<Double>(b), c=SIMD3<Double>(c)
        let ra=Double(rA), rb=Double(rB), rc=Double(rC)
        let ex=simd_normalize(b-a), d=simd_length(b-a), i=simd_dot(ex,c-a)
        let ey=simd_normalize(c-a-i*ex), ez=simd_cross(ex,ey), j=simd_dot(ey,c-a)
        let xx=(ra*ra-rb*rb+d*d)/(2*d)
        let yy=(ra*ra-rc*rc+i*i+j*j-2*i*xx)/(2*j)
        let zz=sqrt(max(0,ra*ra-xx*xx-yy*yy))
        let base=a+xx*ex+yy*ey
        let first=base+zz*ez, second=base-zz*ez
        return SIMD3<Float>(first.y >= second.y ? first : second)
    }

    private static func initialPatches() -> [Patch] {
        let polygons: [(Int, [SIMD2<Float>])] = [
            (0, [[-a,-a],[-a,0],[0,a],[a,0],[a,-a]]),
            (-1, [[-a,0],[-a,a],[0,a]]),
            (1, [[0,a],[a,a],[a,0]])
        ]
        return polygons.map { part, points in
            Patch(face: PaperFace(vertices: points.map {
                PaperVertex(position: [$0.x,0,$0.y], source: $0)
            }, originalSide: part), part: part)
        }
    }

    private static func fold(_ patches: inout [Patch], origin: SIMD3<Float>, axis: SIMD3<Float>,
                             normal: SIMD3<Float>, angle: Float,
                             select: (Patch) -> Bool, active: Bool, movingPart: Int? = nil) {
        var result = [Patch]()
        for patch in patches {
            guard select(patch) else { result.append(patch); continue }
            for moving in [false, true] {
                let vertices = clip(patch.face.vertices, origin: origin, normal: normal, positive: moving)
                guard vertices.count >= 3 else { continue }
                var piece = patch
                piece.face.vertices = vertices
                guard piece.face.area > 1e-12 else { continue }
                if moving {
                    piece.face.vertices = vertices.map { vertex in
                        var value = vertex
                        value.position = rotate(value.position, origin, axis, angle)
                        return value
                    }
                    piece.face.isMoving = active
                    if let movingPart { piece.part = movingPart }
                }
                result.append(piece)
            }
        }
        patches = result
    }

    private static func turn(_ patches: inout [Patch], origin: SIMD3<Float>, axis: SIMD3<Float>,
                             angle: Float, select: (Patch) -> Bool, active: Bool) {
        for i in patches.indices where select(patches[i]) {
            for j in patches[i].face.vertices.indices {
                patches[i].face.vertices[j].position = rotate(patches[i].face.vertices[j].position, origin, axis, angle)
            }
            if active { patches[i].face.isMoving = true }
        }
    }

    private static func clip(_ vertices: [PaperVertex], origin: SIMD3<Float>,
                             normal: SIMD3<Float>, positive: Bool) -> [PaperVertex] {
        var output = [PaperVertex]()
        for index in vertices.indices {
            let current = vertices[index], next = vertices[(index + 1) % vertices.count]
            let d1 = simd_dot(current.position - origin, normal)
            let d2 = simd_dot(next.position - origin, normal)
            let inside1 = positive ? d1 >= -epsilon : d1 <= epsilon
            let inside2 = positive ? d2 >= -epsilon : d2 <= epsilon
            if inside1 { output.append(current) }
            if inside1 != inside2 && abs(d1 - d2) > 1e-12 {
                output.append(.interpolate(current, next, d1 / (d1 - d2)))
            }
        }
        var unique = [PaperVertex]()
        for vertex in output where unique.last.map({ simd_distance($0.source, vertex.source) > 1e-9 }) ?? true {
            unique.append(vertex)
        }
        if unique.count > 1 && simd_distance(unique[0].source, unique.last!.source) < 1e-9 { unique.removeLast() }
        return unique
    }

    private static func rotate(_ point: SIMD3<Float>, _ origin: SIMD3<Float>, _ axis: SIMD3<Float>, _ angle: Float) -> SIMD3<Float> {
        origin + simd_quatf(angle: angle, axis: simd_normalize(axis)).act(point - origin)
    }

    private static func arc(_ point: SIMD3<Float>, _ origin: SIMD3<Float>, _ axis: SIMD3<Float>, _ angle: Float) -> [SIMD3<Float>] {
        (0...24).map { rotate(point, origin, axis, angle * Float($0) / 24) }
    }
}
