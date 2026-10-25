import Foundation
import simd

/// Isolated source-20 study, starting from the existing source-18 checkpoint.
/// This does not stand in for the still missing rear-pocket squash in source 19.
/// The long front first folds over the shoulder; a coupled book closure then
/// reverses the inner shoulder creases and raises the front. No replacement mesh.
enum ElephantShoulderStudy {
    static let width = ElephantGeometry.width
    static let stepCount = 5
    static let lastStep = 4
    static let isComplete = false
    static let sourceCheckpointStep = 26
    private struct Patch { var face: PaperFace; var front: Bool }
    private static let e: Float = 1e-7

    static func frame(step: Int, progress: Float, withRearFeet: Bool = false) -> PaperFrame {
        let s = width-width/4/tan(Float.pi/8), h = width/4
        let source = ElephantGeometry.frame(step: sourceCheckpointStep, progress: 1)
        let sourceOffset = SIMD3<Float>((s/4+width)/2, -source.tableLift, 0)
        var prepared = source.faces.map { face -> PaperFace in
            var f = face
            for i in f.vertices.indices { f.vertices[i].position += sourceOffset; f.vertices[i].separation = .zero }
            return f
        }
        if withRearFeet {
            prepared = ElephantRearSquashStudy.apply(to: prepared, side: 1, progress: 1, active: false)
            prepared = ElephantRearSquashStudy.apply(to: prepared, side: -1, progress: 1, active: false)
        }
        var patches = prepared.map { Patch(face: $0, front: false) }
        let p = min(1,max(0,progress))
        var crease: PaperCrease?
        var paths = [[SIMD3<Float>]]()
        if step == 1 {
            crease = PaperCrease(start:[s,0,-h],end:[s,0,h])
            paths = [(0...28).map { rotate([width,0,0],[s,0,0],[0,0,1],.pi * Float($0)/28) }]
        }
        if step >= 1 {
            let angle = Float.pi*(step > 1 ? 1:p)
            patches = patches.flatMap { patch -> [Patch] in
                [false,true].compactMap { front in
                    let v = clip(patch.face.vertices, origin:[s,0,0], normal:[1,0,0], positive:front)
                    guard v.count >= 3 else { return nil }
                    var f = patch.face; f.vertices = v
                    guard f.area > 1e-12 else { return nil }
                    if front { for j in f.vertices.indices { f.vertices[j].position = rotate(f.vertices[j].position,[s,0,0],[0,0,1],angle) } }
                    f.isMoving = step == 1 && front
                    return Patch(face:f, front:front)
                }
            }
        }
        if step >= 2 {
            // Solve in the same local crosswise frame as a four-crease neck.
            func local(_ v: SIMD3<Float>) -> SIMD3<Float> { [v.z,v.y,v.x-s] }
            func world(_ v: SIMD3<Float>) -> SIMD3<Float> { [v.z+s,v.y,v.x] }
            let k = tan(Float.pi/8), c = SIMD3<Float>(0,0,-k*h)
            let left = SIMD3<Float>(-h,0,0), right = SIMD3<Float>(h,0,0), tip = SIMD3<Float>(0,0,s-width)
            let a = Float.pi*(step > 2 ? 1:p), sn = sin(a/2), cs = cos(a/2), den = k*k+sn*sn
            let direction = SIMD3<Float>(-2*k*sn*sn/den,2*k*sn*cs/den,(sn*sn-k*k)/den)
            let newTip = c+simd_distance(c,tip)*direction
            let newLeft = rotate(left,.zero,[0,0,1],a)
            if step == 2 {
                crease = PaperCrease(start:[s/4,0,0],end:world(c))
                paths = [(0...28).map { sample in
                    let angle = Float.pi * Float(sample)/28
                    let sn = sin(angle/2), cs = cos(angle/2), den = k*k+sn*sn
                    let d = SIMD3<Float>(-2*k*sn*sn/den,2*k*sn*cs/den,(sn*sn-k*k)/den)
                    return world(c+simd_distance(c,tip)*d)
                }]
            }
            patches = patches.flatMap { patch -> [Patch] in
                var original = patch.face
                for i in original.vertices.indices { original.vertices[i].position = local(original.vertices[i].position) }
                var result = [Patch]()
                for side in [-1,1] {
                    let half = clip(original.vertices,origin:.zero,normal:[Float(side),0,0],positive:true)
                    guard half.count >= 3 else { continue }
                    for head in patch.front ? [false,true] : [false] {
                        let v = patch.front ? clip(half,origin:c,normal:[k*Float(side),0,-1],positive:head) : half
                        guard v.count >= 3 else { continue }
                        var f = original; f.vertices = v
                        guard f.area > 1e-12 else { continue }
                        for i in f.vertices.indices {
                            let q = f.vertices[i].position
                            let moved = head ? rigidMap(q,c,side == -1 ? left:right,tip,c,side == -1 ? newLeft:right,newTip)
                                : side == -1 ? rotate(q,.zero,[0,0,1],a) : q
                            f.vertices[i].position = world(moved)
                        }
                        f.isMoving = step == 2 && (head || side == -1)
                        result.append(Patch(face:f,front:patch.front))
                    }
                }
                return result
            }
        }
        for index in 3...4 where step >= index {
            let side = index == 3 ? -1 : 1
            let t = step > index ? 1:p
            if step == index {
                crease = PaperCrease(start:[s,0,-tan(.pi/8)*h],end:[s,0,h])
                paths = [(0...28).map { rotate([s-tan(.pi/8)*h,0,0],[s,0,0],[0,0,1],Float(side) * .pi * Float($0)/28) }]
            }
            patches = patches.flatMap { patch -> [Patch] in
                let outer = patch.face.vertices.allSatisfy { abs($0.source.y) >= h-e }
                guard patch.front, outer, patch.face.originalSide == side else { return [patch] }
                return [false,true].compactMap { moving in
                    let v = clip(patch.face.vertices,origin:[s,0,0],normal:[-1,0,0],positive:moving)
                    guard v.count >= 3 else { return nil }
                    var f = patch.face; f.vertices = v
                    guard f.area > 1e-12 else { return nil }
                    if moving { for j in f.vertices.indices {
                        f.vertices[j].position = rotate(f.vertices[j].position,[s,0,0],[0,0,1],Float(side) * .pi*t)
                    } }
                    f.isMoving = step == index && moving
                    return Patch(face:f,front:patch.front)
                }
            }
        }
        var faces = patches.map(\.face)
        let points = faces.flatMap { $0.vertices.map(\.position) }
        let lo = points.reduce(SIMD3<Float>(repeating:.greatestFiniteMagnitude),simd_min)
        let hi = points.reduce(SIMD3<Float>(repeating:-.greatestFiniteMagnitude),simd_max)
        let lift = max(0,-lo.y)+0.001
        let offset = SIMD3<Float>(-(lo.x+hi.x)/2,lift,-(lo.z+hi.z)/2)
        for i in faces.indices { for j in faces[i].vertices.indices {
            faces[i].vertices[j].position += offset
            faces[i].vertices[j].separation = faces[i].normal*Float(i%5)*0.000025
        } }
        if let c = crease { crease = PaperCrease(start:c.start+offset+[0,0.002,0],end:c.end+offset+[0,0.002,0]) }
        paths = paths.map { path in
            let shifted = path.map { $0+offset }
            let extra = max(0,0.004-(shifted.map(\.y).min() ?? 0))
            return shifted.map { $0+SIMD3<Float>(0,extra,0) }
        }
        return PaperFrame(faces:faces,crease:crease,actionPaths:paths,tableLift:lift)
    }

    private static func rotate(_ q:SIMD3<Float>,_ o:SIMD3<Float>,_ axis:SIMD3<Float>,_ a:Float)->SIMD3<Float> {
        let v=q-o,n=simd_normalize(axis),c=abs(cos(a))<1e-6 ? 0:cos(a),s=abs(sin(a))<1e-6 ? 0:sin(a)
        return o+v*c+simd_cross(n,v)*s+n*simd_dot(n,v)*(1-c)
    }
    private static func rigidMap(_ p:SIMD3<Float>,_ a:SIMD3<Float>,_ b:SIMD3<Float>,_ c:SIMD3<Float>,_ aa:SIMD3<Float>,_ bb:SIMD3<Float>,_ cc:SIMD3<Float>)->SIMD3<Float> {
        func basis(_ a:SIMD3<Float>,_ b:SIMD3<Float>,_ c:SIMD3<Float>)->simd_float3x3 {
            let u=simd_normalize(b-a),n=simd_normalize(simd_cross(u,c-a)),v=simd_cross(n,u)
            return simd_float3x3(columns:(u,v,n))
        }
        return aa+basis(aa,bb,cc)*basis(a,b,c).transpose*(p-a)
    }
    private static func clip(_ v:[PaperVertex],origin:SIMD3<Float>,normal:SIMD3<Float>,positive:Bool)->[PaperVertex] {
        guard !v.isEmpty else {return []}
        var out=[PaperVertex]()
        for i in v.indices {
            let a=v[i],b=v[(i+1)%v.count],da=simd_dot(a.position-origin,normal),db=simd_dot(b.position-origin,normal)
            if positive ? da >= -e : da <= e {out.append(a)}
            if (da < -e && db > e)||(da > e && db < -e) {out.append(PaperVertex.interpolate(a,b,da/(da-db)))}
        }
        var clean=[PaperVertex]()
        for a in out where clean.last.map({simd_distance($0.source,a.source)>e}) ?? true {clean.append(a)}
        if clean.count>2,simd_distance(clean[0].source,clean.last!.source)<e {clean.removeLast()}
        return clean
    }
}
