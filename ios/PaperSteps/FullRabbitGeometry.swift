import Foundation
import simd

/// An authored standing rabbit variation studied from Hadi Tahir. Every region
/// retains its coordinates on one source square. Actions 1–24 use rigid folds;
/// action 25 is a small, explicitly measured source-continuous forming motion.
enum FullRabbitGeometry {
    static let width:Float=0.16
    static let plannedActionCount=25
    static let stepCount=26
    static let isComplete=true
    private static let a=width/2
    private static let b=width/4
    private static let k=tan(Float.pi/8)
    private static let epsilon:Float=0.00000012
    private struct Patch {var face:PaperFace;var part:Int}

    static func frame(step requestedStep:Int,progress requestedProgress:Float)->PaperFrame {
        let step=min(stepCount-1,max(0,requestedStep))
        let p=requestedProgress.isFinite ? min(1,max(0,requestedProgress)) : 0
        func amount(_ index:Int)->Float {step>index ? 1 : step == index ? p : 0}
        var patches=[Patch]()
        var crease:PaperCrease?,paths=[[SIMD3<Float>]]()
        if step < 7 {
            patches=[makePatch([[-a,-a],[a,-a],[a,a],[-a,a]],part:0)]
            if step == 1 || step == 2 {
                let vertical=step == 2, axis=SIMD3<Float>(vertical ? 0:1,0,vertical ? 1:0)
                fold(&patches,origin:.zero,axis:axis,normal:vertical ? [-1,0,0]:[0,0,1],angle:(vertical ? 1:-1) * .pi * sin(.pi*p),select:{_ in true},active:true)
                crease=PaperCrease(start:vertical ? [0,0,-a]:[-a,0,0],end:vertical ? [0,0,a]:[a,0,0])
                paths=[arc(vertical ? [-a,0,0]:[0,0,a],.zero,axis,vertical ? .pi : -.pi)]
            }
            for side in [-1,1] {
                let index=side == -1 ? 3:4,x=Float(side)
                guard step>=index else {continue}
                let origin=SIMD3<Float>(x*b,0,0)
                fold(&patches,origin:origin,axis:[0,0,1],normal:[x,0,0],angle:x * .pi * amount(index),select:{_ in true},active:step == index,movingPart:side)
                if step == index {crease=PaperCrease(start:[x*b,0,-a],end:[x*b,0,a]);paths=[arc([x*a,0,0],origin,[0,0,1],x * .pi)]}
            }
            for end in [-1,1] {
                let index=end == -1 ? 5:6,z=Float(end)
                guard step == index else {continue}
                let origin=SIMD3<Float>(0,0,z*b)
                fold(&patches,origin:origin,axis:[1,0,0],normal:[0,0,z],angle:-z * .pi * sin(.pi*p),select:{_ in true},active:true)
                crease=PaperCrease(start:[-b,0,z*b],end:[b,0,z*b]);paths=[arc([0,0,z*a],origin,[1,0,0],-z * .pi)]
            }
        } else {
            patches=doubleBoat(top:amount(7),bottom:amount(8))
            if step == 7 || step == 8 {
                let z:Float=step == 7 ? -1:1
                crease=PaperCrease(start:[-b,0,z*b],end:[b,0,z*b])
                paths=[arc([0,0,z*a],[0,0,z*b],[1,0,0],-z * .pi)]
                for i in patches.indices where (patches[i].part == (step == 7 ? 10:20)) {patches[i].face.isMoving=true}
            }
            for end in [-1,1] {
                let index=end == -1 ? 9:10,z=Float(end),origin=SIMD3<Float>(0,0,z*b)
                guard step>=index else {continue}
                turn(&patches,origin:origin,axis:[1,0,0],angle:z * .pi * amount(index),select:{$0.part == (end == -1 ? 10:20)},active:step == index)
                if step == index {crease=PaperCrease(start:[-b,0,z*b],end:[b,0,z*b]);paths=[arc(.zero,origin,[1,0,0],z * .pi)]}
            }
            for side in [-1,1] {
                let index=side == -1 ? 11:12,x=Float(side),origin=SIMD3<Float>(x*b,0,0),axis=SIMD3<Float>(-x*k,0,-1)
                guard step>=index else {continue}
                fold(&patches,origin:origin,axis:axis,normal:[x,0,-k],angle:x * .pi * amount(index),select:{_ in true},active:step == index)
                if step == index {crease=PaperCrease(start:origin,end:[x*b*(1-k*1.7071068),0,-b*1.7071068]);paths=[arc([x*b,0,-b],origin,axis,x * .pi)]}
            }
            if step>=13 {
                closeNeck(&patches,progress:amount(13),active:step == 13)
                crease=PaperCrease(start:[-b,0,0],end:[0,0,-k*b])
                paths=[]
            }
        }
        if step>=14 {
            let pivot=SIMD3<Float>(0,0,b/sqrt(2)),slope=1-1/sqrt(Float(2))
            let t=amount(14),first=min(1,2*t),second=max(0,2*t-1)
            fold(&patches,origin:pivot,axis:[1,0,0],normal:[0,0,1],angle:.pi*first,select:{$0.part != 100},active:step == 14,movingPart:40)
            fold(&patches,origin:pivot,axis:[1,0,-slope],normal:[-slope,0,-1],angle:-.pi*second,select:{$0.part == 40},active:step == 14,movingPart:41)
            if step == 14 {crease=PaperCrease(start:pivot,end:[b,0,b/sqrt(2)]);paths=[arc([0,0,a],pivot,[1,0,0],.pi)]}
        }
        // Independently authored broader-body variation: two loose caps
        // become matching haunches. The center backing layers form the tail.
        let d=SIMD3<Float>(b,0,b*(sqrt(2)-1))
        let u=SIMD3<Float>(0.15801717*b,0,0.9537178*b)
        let tail=SIMD3<Float>(0.6975215*b,0,1.7957006*b)
        func looseCap(_ patch:Patch,_ side:Int)->Bool {
            patch.face.originalSide == side*3 && patch.face.vertices.allSatisfy{$0.source.y>=b-1e-6}
        }
        for side in [1,-1] {
            let index=side == 1 ? 15:16,tag=side == 1 ? 60:64
            if step>=index {
                turn(&patches,origin:d,axis:u-d,angle:Float(side) * .pi*amount(index),select:{looseCap($0,side)},active:step == index)
                for i in patches.indices where looseCap(patches[i],side) {patches[i].part=tag}
                if step == index {crease=PaperCrease(start:d,end:u);paths=[arc(tail,d,u-d,Float(side) * .pi)]}
            }
        }
        if step>=17 {
            let point=u+0.40*(tail-u),axis=point-d,normal=SIMD3<Float>(axis.z,0,-axis.x)
            fold(&patches,origin:d,axis:axis,normal:normal,angle:-.pi*amount(17),select:{$0.part != 60 && $0.part != 64 && $0.part != 100},active:step == 17,movingPart:61)
            if step == 17 {crease=PaperCrease(start:d,end:point);paths=[arc(tail,d,axis,-.pi)]}
        }
        for side in [1,-1] {
            let index=side == 1 ? 18:19,tag=side == 1 ? 60:64,result=side == 1 ? 62:66
            if step>=index {
                let point=u+0.06*(rotate(tail,d,u-d,.pi)-u),axis=point-d,normal=SIMD3<Float>(-axis.z,0,axis.x)
                fold(&patches,origin:d,axis:axis,normal:normal,angle:-Float(side) * .pi*amount(index),select:{$0.part == tag},active:step == index,movingPart:result)
                if step == index {crease=PaperCrease(start:d,end:point);paths=[arc(rotate(tail,d,u-d,.pi),d,axis,-Float(side) * .pi)]}
            }
        }
        for side in [1,-1] {
            let index=side == 1 ? 20:21,tag=side == 1 ? 62:66,result=side == 1 ? 63:67
            if step>=index {
                let pivot=SIMD3<Float>(0,0,1.25*b)
                fold(&patches,origin:pivot,axis:[1,0,0],normal:[0,0,1],angle:Float(side) * .pi*amount(index),select:{$0.part == tag},active:step == index,movingPart:result)
                if step == index {crease=PaperCrease(start:[0.45*b,0,1.25*b],end:[1.15*b,0,1.25*b]);paths=[]}
            }
        }
        if step>=22 {
            let pivot=SIMD3<Float>(0,0,0.23*b)
            fold(&patches,origin:pivot,axis:[1,0,0],normal:[0,0,1],angle:.pi*amount(22),select:{$0.part == 100},active:step == 22,movingPart:70)
            if step == 22 {crease=PaperCrease(start:[-0.90*b,0,0.23*b],end:[0.15*b,0,0.23*b]);paths=[]}
        }
        if step>=23 {
            let pivot=SIMD3<Float>(0,0,-0.33*b)
            fold(&patches,origin:pivot,axis:[1,0,0],normal:[0,0,-1],angle:-.pi*amount(23),select:{$0.part != 70},active:step == 23,movingPart:71)
            if step == 23 {crease=PaperCrease(start:[-0.12*b,0,-0.33*b],end:[0.3*b,0,-0.33*b]);paths=[]}
        }
        if step>=24 {
            let pivot=SIMD3<Float>(-0.62*b,0,0)
            fold(&patches,origin:pivot,axis:[0,0,1],normal:[-1,0,0],angle:.pi*amount(24),select:{abs($0.face.originalSide) == 2},active:step == 24,movingPart:72)
            if step == 24 {crease=PaperCrease(start:[-0.62*b,0,-0.32*b],end:[-0.62*b,0,0.4*b]);paths=[]}
        }
        if step>=25 {
            // Source-continuous forming, measured separately from the rigid
            // folds. This opens the four cupboard panels while gently flexing
            // the already-shaped neck/tail; no point or paper layer is replaced.
            let angle=Float.pi/22*amount(25),cosine=cos(angle),sine=sin(angle)
            for i in patches.indices {
                for j in patches[i].face.vertices.indices {
                    patches[i].face.vertices[j].position.x *= cosine
                    patches[i].face.vertices[j].position.y += patches[i].face.vertices[j].source.x*sine
                }
                patches[i].face.isMoving=true
            }
            crease=nil;paths=[]
        }
        // Stand the side profile up as the body closes. This is only a rigid
        // presentation transform; all subsequent folds are authored in its plane.
        if step>=13 {
            let target=simd_float3x3(columns:([0,-1,0],[0,0,-1],[1,0,0]))
            let rotation=simd_slerp(simd_quatf(angle:0,axis:[1,0,0]),simd_quatf(target),amount(13))
            for i in patches.indices {for j in patches[i].face.vertices.indices {patches[i].face.vertices[j].position=rotation.act(patches[i].face.vertices[j].position)}}
            if let c=crease {crease=PaperCrease(start:rotation.act(c.start),end:rotation.act(c.end))}
            paths=paths.map{$0.map{rotation.act($0)}}
        }
        var faces=patches.map(\.face)
        let lift=max(0,-(faces.flatMap(\.vertices).map(\.position.y).min() ?? 0))+0.001
        for i in faces.indices {
            faces[i].outlinedEdges=faces[i].vertices.indices.map {j in
                let v=faces[i].vertices[j].source,w=faces[i].vertices[(j+1)%faces[i].vertices.count].source
                func line(_ n:SIMD2<Float>,_ value:Float)->Bool {abs(simd_dot(v,n)-value)<1e-6 && abs(simd_dot(w,n)-value)<1e-6}
                if step<7 {return line([1,0],a)||line([1,0],-a)||line([0,1],a)||line([0,1],-a)||(step>=1 && line([0,1],0))||(step>=2 && line([1,0],0))||(step>=3 && line([1,0],-b))||(step>=4 && line([1,0],b))||(step>=5 && line([0,1],-b))||(step>=6 && line([0,1],b))}
                return true
            }
            if step>=7 {faces[i].outlinedEdges=nil}
            let owner=patches[i].face.originalSide
            var rank:Float=owner == 3 ? 3:owner == 2 ? 1:owner == -2 ? -1:owner == -3 ? -3:0
            if patches[i].part == 62 {rank=4};if patches[i].part == 63 {rank=3.7}
            if patches[i].part == 66 {rank = -4};if patches[i].part == 67 {rank = -3.7}
            let depth=rank*0.00010+Float(i)*0.0000012
            let spacing:SIMD3<Float>=step>=13 ? [0,0,depth]:[0,depth,0]
            for j in faces[i].vertices.indices {faces[i].vertices[j].position.y += lift;faces[i].vertices[j].separation=spacing}
        }
        if let c=crease {crease=PaperCrease(start:c.start+[0,lift,0],end:c.end+[0,lift,0])}
        paths=paths.map{$0.map{$0+[0,lift+0.001,0]}}
        return PaperFrame(faces:removingFlatSeamOutlines(from:faces),crease:crease,actionPaths:paths,tableLift:lift)
    }

    private static func removingFlatSeamOutlines(from faces: [PaperFace]) -> [PaperFace] {
        struct Segment {
            let face: Int
            let a: PaperVertex
            let b: PaperVertex
        }
        let tolerance: Float = 0.0000005
        let positionTolerance: Float = 0.000002
        let half = width / 2
        let normals = faces.map(\.normal)
        let centers = faces.map { face in
            face.vertices.reduce(SIMD2<Float>.zero) { $0 + $1.source } / Float(max(1, face.vertices.count))
        }
        let segments = faces.enumerated().flatMap { index, face in
            face.vertices.indices.map { Segment(face: index, a: face.vertices[$0], b: face.vertices[($0 + 1) % face.vertices.count]) }
        }
        func cross2(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }
        return faces.enumerated().map { index, face in
            guard face.outlinedEdges == nil else { return face }
            var result = face
            result.outlinedEdges = face.vertices.indices.map { edgeIndex in
                let a = face.vertices[edgeIndex], b = face.vertices[(edgeIndex + 1) % face.vertices.count]
                for axis in 0..<2 {
                    if abs(abs(a.source[axis]) - half) < tolerance && abs(a.source[axis] - b.source[axis]) < tolerance { return true }
                }
                let delta = b.source - a.source
                let length = simd_length(delta)
                guard length > tolerance else { return true }
                let direction = delta / length
                let ownSide = cross2(direction, centers[index] - a.source)
                var coveredIntervals = [(Float, Float)]()
                for other in segments where other.face != index {
                    guard faces[other.face].isMoving == face.isMoving,
                          simd_dot(normals[index], normals[other.face]) > 0.9999,
                          ownSide * cross2(direction, centers[other.face] - a.source) < 0,
                          abs(cross2(direction, other.a.source - a.source)) <= tolerance,
                          abs(cross2(direction, other.b.source - a.source)) <= tolerance else { continue }
                    let start = simd_dot(other.a.source - a.source, direction)
                    let end = simd_dot(other.b.source - a.source, direction)
                    let low = max(0, min(start, end)), high = min(length, max(start, end))
                    guard high - low > tolerance, abs(end - start) > tolerance else { continue }
                    var contiguous = true
                    for distance in [low, high] {
                        let p = a.position + (b.position - a.position) * (distance / length)
                        let q = other.a.position + (other.b.position - other.a.position) * ((distance - start) / (end - start))
                        if simd_distance(p, q) > positionTolerance { contiguous = false; break }
                    }
                    if contiguous { coveredIntervals.append((low, high)) }
                }
                // A long edge may meet several short edges after later folds.
                // Require their union to cover the full edge, including ends.
                var covered: Float = 0
                for interval in coveredIntervals.sorted(by: { $0.0 < $1.0 }) {
                    if interval.0 > covered + tolerance { return true }
                    covered = max(covered, interval.1)
                }
                return covered < length - tolerance
            }
            return result
        }
    }

    private static func makePatch(_ source:[SIMD2<Float>],part:Int)->Patch {
        var vertices=source.map{PaperVertex(position:[$0.x,0,$0.y],source:$0)}
        let u=source[1]-source[0],v=source[2]-source[0]
        if u.x*v.y-u.y*v.x>0 {vertices.reverse()}
        return Patch(face:PaperFace(vertices:vertices,originalSide:part),part:part)
    }

    /// Four linked triangles squash each cupboard corner. The moving free edge
    /// follows the horizontal hinge; the shared folded corner is trilaterated.
    private static func doubleBoat(top:Float,bottom:Float)->[Patch] {
        var result=[Patch]()
        for end:Float in [-1,1] {for mirror:Float in [-1,1] {
            let p=end == -1 ? top:bottom
            let o=SIMD3<Float>(-b,0,-b),c=SIMD3<Float>(0,0,-2*b),m=SIMD3<Float>(0,0,-b)
            let d=rotate(c,o,[1,0,0],.pi*p)
            let movingB:SIMD3<Float>
            if p<=0 {movingB=[-b,0,-2*b]}
            else if p>=1 {movingB=m}
            else {movingB=corner(o,c,d,b,b,b)}
            let sources:[SIMD2<Float>]=[[-b,-b],[-b,-2*b],[0,-2*b],[0,-b],[0,0],[-b,0]]
            func add(_ ids:[Int],door:Bool,poses:[SIMD3<Float>],part:Int) {
                var vertices=ids.map {id->PaperVertex in
                    let s=sources[id],q=poses[id]
                    let source=SIMD2<Float>((door ? -2*b-s.x:s.x)*mirror,-end*s.y)
                    return PaperVertex(position:[q.x*mirror,q.y,-end*q.z],source:source)
                }
                let u=vertices[1].source-vertices[0].source,v=vertices[2].source-vertices[0].source
                if u.x*v.y-u.y*v.x>0 {vertices.reverse()}
                result.append(Patch(face:PaperFace(vertices:vertices,originalSide:door ? Int(mirror)*3:Int(mirror)*2),part:part))
            }
            let back=[o,movingB,c,m,SIMD3<Float>.zero,[-b,0,0]]
            let door=[o,movingB,d,m,SIMD3<Float>.zero,[-b,0,0]]
            add([0,1,2],door:false,poses:back,part:0);add([0,2,3],door:false,poses:back,part:0)
            add([0,3,4,5],door:false,poses:back,part:0)
            add([0,1,2],door:true,poses:door,part:end == -1 ? 10:20);add([0,2,3],door:true,poses:door,part:end == -1 ? 10:20)
            add([0,3,4,5],door:true,poses:door,part:0)
        }}
        return result
    }

    private static func closeNeck(_ patches:inout [Patch],progress p:Float,active:Bool) {
        let c=SIMD3<Float>(0,0,-k*b),left=SIMD3<Float>(-b,0,0),right=SIMD3<Float>(b,0,0),tip=SIMD3<Float>(0,0,-a)
        let angle=Float.pi*p,s=sin(angle/2),cc=cos(angle/2),den=k*k+s*s
        let direction=SIMD3<Float>(-2*k*s*s/den,2*k*s*cc/den,(s*s-k*k)/den)
        let movingTip=c+simd_distance(tip,c)*direction
        let movingLeft=rotate(left,.zero,[0,0,1],angle)
        var result=[Patch]()
        for patch in patches {for side in [-1,1] {
            let x=Float(side),half=clip(patch.face.vertices,origin:.zero,normal:[x,0,0],positive:true)
            guard half.count>=3 else {continue}
            for head in [false,true] {
                let vertices=clip(half,origin:c,normal:[k*x,0,-1],positive:head)
                guard vertices.count>=3 else {continue}
                var q=patch;q.face.vertices=vertices;guard q.face.area>1e-12 else {continue}
                q.face.vertices=vertices.map {vertex in
                    var v=vertex
                    if head {v.position=rigidMap(v.position,c,side == -1 ? left:right,tip,c,side == -1 ? movingLeft:right,movingTip)}
                    else if side == -1 {v.position=rotate(v.position,.zero,[0,0,1],angle)}
                    return v
                }
                q.face.isMoving=active;if head {q.part=100};result.append(q)
            }
        }}
        patches=result
    }

    private static func corner(_ a:SIMD3<Float>,_ b:SIMD3<Float>,_ c:SIMD3<Float>,_ ra:Float,_ rb:Float,_ rc:Float)->SIMD3<Float> {
        let a=SIMD3<Double>(a),b=SIMD3<Double>(b),c=SIMD3<Double>(c),ra=Double(ra),rb=Double(rb),rc=Double(rc)
        let ex=simd_normalize(b-a),d=simd_length(b-a),i=simd_dot(ex,c-a),ey=simd_normalize(c-a-i*ex),ez=simd_cross(ex,ey),j=simd_dot(ey,c-a)
        let x=(ra*ra-rb*rb+d*d)/(2*d),y=(ra*ra-rc*rc+i*i+j*j-2*i*x)/(2*j),z=sqrt(max(0,ra*ra-x*x-y*y))
        let first=a+x*ex+y*ey+z*ez,second=a+x*ex+y*ey-z*ez
        return SIMD3<Float>(first.x<second.x ? first:second)
    }
    private static func rigidMap(_ p:SIMD3<Float>,_ a:SIMD3<Float>,_ b:SIMD3<Float>,_ c:SIMD3<Float>,_ aa:SIMD3<Float>,_ bb:SIMD3<Float>,_ cc:SIMD3<Float>)->SIMD3<Float> {
        func basis(_ a:SIMD3<Float>,_ b:SIMD3<Float>,_ c:SIMD3<Float>)->simd_float3x3 {
            let u=simd_normalize(b-a),n=simd_normalize(simd_cross(u,c-a)),v=simd_cross(n,u)
            return simd_float3x3(columns:(u,v,n))
        }
        return aa+basis(aa,bb,cc)*basis(a,b,c).transpose*(p-a)
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
