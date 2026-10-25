import Foundation
import simd

/// Private research prototype of Caleb Witte's full-body fox. Each face retains
/// coordinates in the same uncut square. This file is not in the app target.
/// The coupled fish-base linkage is rigid; later reverse/sink illustrations are
/// authored explanations whose physical layer ordering needs separate review.
enum FullFoxGeometry {
    static let size: Float = 0.15
    static let sourceActionCount = 24
    static let implementedActionCount = 24
    static let stepCount = implementedActionCount + 1
    static let lastStep = stepCount - 1
    private static let epsilon: Float = 0.0000002
    private static let root2: Float = sqrt(2)
    private static let halfDiagonal = size / sqrt(Float(2))
    private static let earWidth = size * (sqrt(Float(2)) - 1) / sqrt(Float(2))

    private struct Fold {
        var origin: SIMD3<Float>
        var axis: SIMD3<Float>
        var outward: SIMD3<Float>
        var angle: Float
        var arrow: SIMD3<Float>
        var layers: Set<Int>? = nil
        var seed: SIMD2<Float>? = nil
    }

    struct SourceSegment {
        let a: SIMD2<Float>
        let b: SIMD2<Float>
        func covers(_ p: SIMD2<Float>, _ q: SIMD2<Float>) -> Bool {
            let edge=b-a,length=simd_length(edge)
            guard length>0.0000001 else {return false}
            let axis=edge/length
            func contains(_ point: SIMD2<Float>) -> Bool {
                let delta=point-a,t=simd_dot(delta,axis)
                return abs(delta.x*axis.y-delta.y*axis.x)<0.00000015 && t >= -0.00000015 && t <= length+0.00000015
            }
            return contains(p) && contains(q)
        }
    }
    static func frame(step: Int, progress: Float) -> PaperFrame {
        renderFrame(step:step,progress:progress).frame
    }
    /// Extra source-coordinate metadata describes display-only forming seams.
    /// The physical positions and topology are identical to candidate C.
    static func renderFrame(step requestedStep: Int, progress requestedProgress: Float) -> (frame:PaperFrame, formingSeams:[SourceSegment]) {
        var formingSeams:[SourceSegment]=[]
        let step = min(lastStep, max(0, requestedStep))
        let p = requestedProgress.isFinite ? min(1, max(0, requestedProgress)) : 0
        var faces = fishBase(amount: step < 3 ? 0 : (step == 3 ? p : 1))
        var crease: PaperCrease?
        var paths = [[SIMD3<Float>]]()
        func perform(_ fold: Fold, fraction: Float, active: Bool) {
            if active { crease = clippedCrease(fold, faces: faces); paths = [arrowPath(fold)] }
            faces = apply(fold, to: faces, fraction: fraction, active: active)
        }
        func at(_ fold: Fold, _ index: Int) {
            if step >= index { perform(fold, fraction: step == index ? p : 1, active: step == index) }
        }
        func pair(_ first: Fold, _ second: Fold, _ index: Int, unfold: Bool = false) {
            guard step >= index else { return }
            if unfold && step != index { return }
            let value = step == index ? p : 1
            let a = min(1, value * 2), b = max(0, value * 2 - 1)
            func phase(_ x: Float) -> Float { unfold ? (x <= 0.5 ? x * 2 : (1 - x) * 2) : x }
            perform(first, fraction: phase(a), active: step == index && value < 0.5)
            perform(second, fraction: phase(b), active: step == index && value >= 0.5)
        }
        if step == 1 || step == 2 {
            let s = 1 / sqrt(Float(2)), t = 1-s
            let origin = sheet(step == 1 ? [1,1] : [0,0])
            let i = sheet([s,t]), j = sheet([t,s])
            let tip: SIMD2<Float> = step == 1 ? [1,0] : [0,1]
            func precrease(_ point: SIMD3<Float>, arrow: SIMD3<Float>) -> Fold {
                let axis = simd_normalize(point-origin)
                var normal = SIMD3<Float>(axis.z,0,-axis.x)
                if simd_dot(arrow-origin,normal) < 0 { normal *= -1 }
                let sign: Float = simd_cross(axis, arrow-origin).y > 0 ? 1 : -1
                return Fold(origin: origin, axis: axis, outward: normal, angle: sign * .pi,
                            arrow: arrow)
            }
            pair(precrease(i,arrow:sheet(tip)),precrease(j,arrow:sheet([tip.y,tip.x])),step,unfold:true)
        }
        if step == 3 {
            for i in faces.indices where [11,12].contains(faces[i].originalSide) { faces[i].isMoving = true }
            paths = [-1,Float(1)].map { sign in
                (0...24).map { i in
                    let nodes = earNodes(amount: Float(i)/24)
                    let p = nodes["B"]!
                    return [p.x,p.y,sign*p.z]
                }
            }
        }
        let q = earWidth / 2
        let upper = Fold(origin:[0,0,-q],axis:[1,0,0],outward:[0,0,-1],angle:.pi,
                         arrow:[0,0,-earWidth*0.93])
        let lower = Fold(origin:[0,0,q],axis:[1,0,0],outward:[0,0,1],angle:-.pi,
                         arrow:[0,0,earWidth*0.93])
        pair(upper,lower,4,unfold:true)
        if step >= 5 {
            // The sink endpoints invert both precreased corners. This private
            // geometry illustrates the continuous turn; layer-opening technique
            // and contact order are separate validation work before integration.
            var a=upper,b=lower;a.angle *= -1;b.angle *= -1
            pair(a,b,5)
        }
        at(Fold(origin:.zero,axis:[1,0,0],outward:[0,0,-1],angle:-.pi,
                arrow:[0,0,-q*0.9]),6)
        let tailRoot = SIMD3<Float>(earWidth,0,0)
        let tailAxis = simd_normalize(SIMD3<Float>(tan(.pi/8),0,1))
        at(Fold(origin:tailRoot,axis:tailAxis,outward:[1,0,-tan(.pi/8)],angle:.pi,
                arrow:[halfDiagonal*0.96,0,0]),7)
        pair(Fold(origin:.zero,axis:[0,0,1],outward:[1,0,0],angle:.pi,
                  arrow:[earWidth*0.88,0,q*0.2],layers:[11]),
             Fold(origin:.zero,axis:[0,0,1],outward:[1,0,0],angle:-.pi,
                  arrow:[earWidth*0.88,0,q*0.2],layers:[12]),8)

        // Source panel 12 opens only the front half of the reversed point.
        // Its boundary on the original square's diagonal lies on this hinge.
        let diagonal = SIMD3<Float>(-1,0,1)
        at(Fold(origin:tailRoot,axis:diagonal,outward:[1,0,1],angle:.pi,
                arrow:[halfDiagonal/2,0,q],layers:[2,12]),9)
        let shoulder = SIMD3<Float>(q,0,-(halfDiagonal/2-earWidth))
        at(Fold(origin:shoulder,axis:[1,0,1],outward:[-1,0,1],angle:-.pi,
                arrow:[0,0,earWidth],seed:[size,size]),10)
        at(Fold(origin:tailRoot,axis:diagonal,outward:[1,0,1],angle:-.pi,
                arrow:[halfDiagonal/2,0,q],layers:[1,11]),11)
        let slope = tan(Float.pi/8)
        // Authored long-tail variation: the two hinges meet 20% along the
        // free tail edge, shallower than the diagram-estimated 40%. The lower
        // root guide lies 55% down the root; both stay on this same sheet.
        let tailLow=SIMD3<Float>(q,0,q),tailHigh=shoulder,tailTip=SIMD3<Float>(0.075,0,-earWidth/root2)
        let meeting=tailLow+(tailTip-tailLow)*0.20
        let lowerStart=tailHigh+(tailLow-tailHigh)*0.55
        let firstAxisTail=simd_normalize(meeting-tailHigh)
        let secondAxisTail=simd_normalize(meeting-lowerStart)
        func tailNormal(_ origin:SIMD3<Float>,_ axis:SIMD3<Float>,_ tip:SIMD3<Float>)->SIMD3<Float>{
            let n=SIMD3<Float>(axis.z,0,-axis.x)
            return simd_dot(tip-origin,n)>=0 ? n:-n
        }
        let foldedTip=rotated(tailTip,origin:tailHigh,axis:firstAxisTail,angle:.pi)
        pair(Fold(origin:tailHigh,axis:firstAxisTail,outward:tailNormal(tailHigh,firstAxisTail,tailTip),angle:.pi,
                  arrow:tailTip,seed:[size,size]),
             Fold(origin:lowerStart,axis:secondAxisTail,outward:tailNormal(lowerStart,secondAxisTail,foldedTip),angle:-.pi,
                  arrow:foldedTip,seed:[size,size]),12)
        at(Fold(origin:[q,0,0],axis:[0,0,1],outward:[-1,0,0],angle:-.pi,
                arrow:[size*(1-sqrt(2)/2)*0.3,0,-(halfDiagonal-earWidth)/2],seed:[size,size]),13)
        pair(Fold(origin:.zero,axis:[0,0,1],outward:[-1,0,0],angle:-.pi,
                  arrow:[-earWidth,0,0],layers:[11]),
             Fold(origin:.zero,axis:[0,0,1],outward:[-1,0,0],angle:.pi,
                  arrow:[-earWidth,0,0],layers:[12]),14)
        pair(Fold(origin:.zero,axis:[1,0,slope],outward:[slope,0,-1],angle:-.pi,
                  arrow:[earWidth,0,0],layers:[11]),
             Fold(origin:.zero,axis:[1,0,slope],outward:[slope,0,-1],angle:.pi,
                  arrow:[earWidth,0,0],layers:[12]),15)
        let d=earWidth/root2
        pair(Fold(origin:[d*0.875,0,d*1.09],axis:[0.72,0,1],outward:[1,0,-0.72],angle:.pi,
                  arrow:[d,0,d],layers:[11]),
             Fold(origin:[d*0.875,0,d*1.09],axis:[0.72,0,1],outward:[1,0,-0.72],angle:-.pi,
                  arrow:[d,0,d],layers:[12]),16)
        pair(Fold(origin:.zero,axis:[1,0,1.25],outward:[1.25,0,-1],angle:-.pi,
                  arrow:[d*0.4,0,d*0.4],layers:[11]),
             Fold(origin:.zero,axis:[1,0,1.25],outward:[1.25,0,-1],angle:.pi,
                  arrow:[d*0.4,0,d*0.4],layers:[12]),17)
        // The original A corner supplies the entire neck, ears and muzzle.
        // Source-space selection follows that flap through overlapping layers.
        let neckRoot=SIMD3<Float>(0,0,q)
        at(Fold(origin:neckRoot,axis:[1,0,1],outward:[-1,0,1],angle:.pi,
                arrow:[-halfDiagonal,0,0],seed:.zero),18)
        let forehead=SIMD3<Float>(-q,0,0)
        let headAxis=SIMD3<Float>(1,0,-1)
        let headOne=SIMD3<Float>(-q,0,-halfDiagonal+q)
        at(Fold(origin:forehead,axis:headAxis,outward:[-1,0,-1],angle:-.pi,
                arrow:headOne,seed:.zero),19)
        let headTwo=rotated(headOne,origin:forehead,axis:headAxis,angle:.pi)
        at(Fold(origin:.zero,axis:[0,0,1],outward:[1,0,0],angle:.pi,
                arrow:headTwo,seed:.zero),20)
        let headThree=SIMD3<Float>(-headTwo.x,0,headTwo.z)
        at(Fold(origin:forehead,axis:headAxis,outward:[-1,0,-1],angle:.pi,
                arrow:headThree,seed:.zero),21)
        let headFour=rotated(headThree,origin:forehead,axis:headAxis,angle:.pi)
        let earTip=SIMD3<Float>(0,0,-q)
        let crimpOne=headFour*0.1+forehead*0.9
        let firstEnd=headFour*0.57+earTip*0.43
        let secondStart=headFour*0.32+forehead*0.68
        let secondEnd=headFour*0.62+earTip*0.38
        let firstAxis=simd_normalize(firstEnd-crimpOne)
        func toward(_ origin:SIMD3<Float>,_ axis:SIMD3<Float>,_ point:SIMD3<Float>)->SIMD3<Float>{
            let n=SIMD3<Float>(axis.z,0,-axis.x)
            return simd_dot(point-origin,n)>=0 ? n:-n
        }
        let crimpTwo=rotated(secondStart,origin:crimpOne,axis:firstAxis,angle:.pi)
        let secondAxis=rotated(simd_normalize(secondEnd-secondStart),origin:.zero,axis:firstAxis,angle:.pi)
        let firstNose=rotated(headFour,origin:crimpOne,axis:firstAxis,angle:.pi)
        pair(Fold(origin:crimpOne,axis:firstAxis,outward:toward(crimpOne,firstAxis,headFour),angle:.pi,
                  arrow:headFour,seed:.zero),
             Fold(origin:crimpTwo,axis:secondAxis,outward:toward(crimpTwo,secondAxis,firstNose),angle:-.pi,
                  arrow:firstNose,seed:.zero),22)
        let nose=rotated(firstNose,origin:crimpTwo,axis:secondAxis,angle:.pi)
        let noseBase=rotated(secondEnd,origin:crimpOne,axis:firstAxis,angle:.pi)
        let muzzleDirection=simd_normalize(nose-noseBase)
        let muzzleAxis=simd_cross(SIMD3<Float>(0,1,0),muzzleDirection)
        pair(Fold(origin:nose-muzzleDirection*0.0015,axis:muzzleAxis,outward:muzzleDirection,angle:.pi,
                  arrow:nose,seed:.zero),
             Fold(origin:nose-muzzleDirection*0.0045,axis:muzzleAxis,outward:muzzleDirection,angle:.pi,
                  arrow:nose-muzzleDirection*0.003,seed:.zero),23)
        if step>=24 {
            let amount=step==24 ? p:1
            for side in [1,2] {
                let uv:SIMD2<Float> = side==1 ? [0.39644661,0.18933983]:[0.18933983,0.39644661]
                let bend=Fold(origin:[0,0,-q*0.64],axis:[1,0,0],outward:[0,0,-1],
                              angle:side==1 ? 0.13:-0.13,arrow:earTip,layers:[side],seed:uv*size)
                perform(bend,fraction:amount,active:false)
            }
            // Curve across the full outside-reversed tail packet instead of
            // placing three sharp bends only at the visible distal tip.
            faces=curvedTail(faces,amount:amount,rootX:q,seams:&formingSeams)
            // The two fish-base ear patches are now the legs. Their original
            // attachment remains the same z-axis, so opening them cannot tear
            // the root even after their smaller toe folds.
            for i in faces.indices where [11,12].contains(faces[i].originalSide) {
                let angle:Float=(faces[i].originalSide==11 ? -0.09:0.09)*amount
                for j in faces[i].vertices.indices {
                    faces[i].vertices[j].position=rotated(faces[i].vertices[j].position,origin:.zero,axis:[0,0,1],angle:angle)
                }
            }
        }

        // Presentation orientation is separate from any material fold. The
        // oblique 60-degree tabletop view keeps the later sitting profile clear.
        if step>=14 {
            let turn:Float = -.pi/3 * (step==14 ? p:1)
            for i in faces.indices {for j in faces[i].vertices.indices {
                faces[i].vertices[j].position=rotated(faces[i].vertices[j].position,origin:.zero,axis:[0,1,0],angle:turn)
            }}
            paths=paths.map{$0.map{rotated($0,origin:.zero,axis:[0,1,0],angle:turn)}}
            if var c=crease {c.start=rotated(c.start,origin:.zero,axis:[0,1,0],angle:turn);c.end=rotated(c.end,origin:.zero,axis:[0,1,0],angle:turn);crease=c}
        }
        if step>=24 {
            let rise=Float.pi/2 * p
            for i in faces.indices {for j in faces[i].vertices.indices {
                faces[i].vertices[j].position=rotated(faces[i].vertices[j].position,origin:.zero,axis:[1,0,0],angle:rise)
            }}
            paths=paths.map{$0.map{rotated($0,origin:.zero,axis:[1,0,0],angle:rise)}}
            if var c=crease {c.start=rotated(c.start,origin:.zero,axis:[1,0,0],angle:rise);c.end=rotated(c.end,origin:.zero,axis:[1,0,0],angle:rise);crease=c}
        }

        // The sheet is mathematically thin. No independent per-face offsets are
        // introduced here because they can tear shared source-material joints.
        let minY = faces.flatMap(\.vertices).map { $0.position.y }.min() ?? 0
        let lift = max(0,-minY)+0.001
        for i in faces.indices {
            // Original paper edges may be drawn; clipping/tessellation edges
            // are not an outline network. The active crease has its own guide.
            faces[i].outlinedEdges=faces[i].vertices.indices.map { j in
                let a=faces[i].vertices[j].source,b=faces[i].vertices[(j+1)%faces[i].vertices.count].source
                return (abs(a.x)<epsilon && abs(b.x)<epsilon) || (abs(a.y)<epsilon && abs(b.y)<epsilon) ||
                    (abs(a.x-size)<epsilon && abs(b.x-size)<epsilon) || (abs(a.y-size)<epsilon && abs(b.y-size)<epsilon)
            }
            for j in faces[i].vertices.indices {faces[i].vertices[j].position.y += lift}
        }
        if var c=crease {c.start.y += lift+0.001;c.end.y += lift+0.001;crease=c}
        paths = paths.map { path in
            let arrowLift=max(lift,0.006-(path.map(\.y).min() ?? 0))
            return path.map {$0+SIMD3<Float>(0,arrowLift,0)}
        }
        return (PaperFrame(faces:faces,crease:crease,actionPaths:paths,tableLift:lift),formingSeams)
    }

    private static func sheet(_ uv: SIMD2<Float>) -> SIMD3<Float> {
        [(uv.x+uv.y-1)*size/root2,0,(uv.y-uv.x)*size/root2]
    }

    /// One degree-of-freedom, four-crease rabbit ear. B and R rotate about AI;
    /// Q rotates about CI with a solved angle that preserves BQ. Every triangle
    /// retains its edge lengths, including the connecting B-Q-I triangle.
    private static func earNodes(amount: Float) -> [String: SIMD3<Float>] {
        let s: Float=1/sqrt(2),t:Float=1-s
        let uv:[String:SIMD2<Float>] = ["A":[0,0],"B":[1,0],"C":[1,1],"I":[s,t],"R":[s,0],"Q":[1,t]]
        var result=uv.mapValues(sheet)
        guard amount>0 else{return result}
        if amount>=1 {result["B"]=sheet([s,s]);result["R"]=sheet([0.5,0.5]);result["Q"]=sheet([0.5,0.5]);return result}
        let a=SIMD3<Double>(result["A"]!),b=SIMD3<Double>(result["B"]!),c=SIMD3<Double>(result["C"]!)
        let i=SIMD3<Double>(result["I"]!),q=SIMD3<Double>(result["Q"]!),r=SIMD3<Double>(result["R"]!)
        let ua=simd_normalize(a-i),uc=simd_normalize(c-i),alpha = -Double.pi*Double(amount)
        func rotate(_ p:SIMD3<Double>,_ axis:SIMD3<Double>,_ angle:Double)->SIMD3<Double>{
            p*cos(angle)+simd_cross(axis,p)*sin(angle)+axis*simd_dot(axis,p)*(1-cos(angle))
        }
        let movingB=rotate(b-i,ua,alpha)
        let parallel=uc*simd_dot(uc,q-i),perpendicular=q-i-parallel
        let aa=simd_dot(movingB,perpendicular),bb=simd_dot(movingB,simd_cross(uc,perpendicular))
        let cc=simd_dot(b-i,q-i)-simd_dot(movingB,parallel)
        let beta=atan2(bb,aa)+acos(min(1,max(-1,cc/max(1e-18,hypot(aa,bb)))))
        result["B"]=SIMD3<Float>(i+movingB)
        result["R"]=SIMD3<Float>(i+rotate(r-i,ua,alpha))
        result["Q"]=SIMD3<Float>(i+rotate(q-i,uc,beta))
        return result
    }

    private static func fishBase(amount:Float)->[PaperFace]{
        let s:Float=1/sqrt(2),t:Float=1-s
        let uv:[String:SIMD2<Float>] = ["A":[0,0],"B":[1,0],"C":[1,1],"I":[s,t],"R":[s,0],"Q":[1,t]]
        let positions=earNodes(amount:amount)
        let triangles:[([String],Bool)] = [(["C","A","I"],false),(["A","R","I"],false),
                                          (["R","B","I"],true),(["B","Q","I"],true),(["Q","C","I"],false)]
        return [false,true].flatMap { mirror in triangles.map { names,ear in
            var vertices=names.map { key -> PaperVertex in
                var source=uv[key]!,point=positions[key]!
                if mirror {source=[source.y,source.x];point.z *= -1}
                return PaperVertex(position:point,source:source*size)
            }
            // All source faces share the original sheet's upward winding.
            let a=vertices[1].source-vertices[0].source,b=vertices[2].source-vertices[0].source
            if a.x*b.y-a.y*b.x>0 {vertices.reverse()}
            return PaperFace(vertices:vertices,originalSide:ear ? (mirror ? 12:11):(mirror ? 2:1))
        }}
    }

    /// Closely spaced parallel hinges approximate an isometric paper curl.
    /// The original tail-root material line stays fixed; no offset shell is used.
    private static func curvedTail(_ input:[PaperFace],amount:Float,rootX:Float,seams:inout [SourceSegment])->[PaperFace] {
        let select=Fold(origin:[rootX,0,0],axis:[0,0,1],outward:[1,0,0],angle:0,arrow:[0,0,0],seed:[size,size])
        let split=apply(select,to:input,fraction:0,active:true)
        let upper=split.filter(\.isMoving).flatMap(\.vertices).map(\.position.x).max() ?? rootX
        let width=max(0.00001,upper-rootX),count=20,interval=width/Float(count)
        func bent(_ point:SIMD3<Float>)->SIMD3<Float>{
            let u=max(0,min(width,point.x-rootX))
            var x=rootX,y:Float=0
            for i in 0..<count {
                let length=min(interval,max(0,u-Float(i)*interval))
                if length<=0{break}
                let theta=Float(i+1)/Float(count)*0.78*amount
                x += length*cos(theta);y += length*sin(theta)
            }
            return [x,point.y+y,point.z]
        }
        var result:[PaperFace]=[]
        for f in split {
            guard f.isMoving else{result.append(f);continue}
            for i in 0..<count {
                let a=Fold(origin:[rootX+Float(i)*interval,0,0],axis:[0,0,1],outward:[1,0,0],angle:0,arrow:.zero)
                let b=Fold(origin:[rootX+Float(i+1)*interval,0,0],axis:[0,0,1],outward:[1,0,0],angle:0,arrow:.zero)
                let polygon=clip(clip(f.vertices,fold:a,positive:true),fold:b,positive:false)
                guard polygon.count>=3 else{continue}
                var face=PaperFace(vertices:polygon,originalSide:f.originalSide,isMoving:amount<1)
                guard face.area>1e-13 else{continue}
                for j in polygon.indices {
                    let v=polygon[j],w=polygon[(j+1)%polygon.count]
                    let onCut = (i>0 && abs(v.position.x-a.origin.x)<epsilon && abs(w.position.x-a.origin.x)<epsilon) ||
                        (i<count-1 && abs(v.position.x-b.origin.x)<epsilon && abs(w.position.x-b.origin.x)<epsilon)
                    guard onCut else{continue}
                    let onOriginal=f.vertices.indices.contains { k in
                        SourceSegment(a:f.vertices[k].source,b:f.vertices[(k+1)%f.vertices.count].source).covers(v.source,w.source)
                    }
                    if !onOriginal {seams.append(SourceSegment(a:v.source,b:w.source))}
                }
                for j in face.vertices.indices {face.vertices[j].position=bent(face.vertices[j].position)}
                result.append(face)
            }
        }
        return result
    }

    private static func apply(_ fold:Fold,to faces:[PaperFace],fraction:Float,active:Bool)->[PaperFace]{
        var result=[PaperFace]()
        var candidates=[Int]()
        for face in faces {
            guard fold.layers == nil || fold.layers!.contains(face.originalSide) else {result.append(face);continue}
            for positive in [false,true] {
                let vertices=clip(face.vertices,fold:fold,positive:positive)
                guard vertices.count>=3 else{continue}
                let fragment=PaperFace(vertices:vertices,originalSide:face.originalSide,isMoving:face.isMoving)
                guard fragment.area>1e-13 else{continue}
                if positive {
                    candidates.append(result.count)
                }
                result.append(fragment)
            }
        }
        var moving=Set(candidates)
        if let seed=fold.seed {
            moving=Set(candidates.filter { result[$0].vertices.contains { simd_distance($0.source,seed)<epsilon } })
            var pending=Array(moving)
            while let index=pending.popLast() {
                for other in candidates where !moving.contains(other) && sourceAdjacent(result[index],result[other],fold:fold) {
                    moving.insert(other);pending.append(other)
                }
            }
        }
        for index in moving {
            result[index].vertices=result[index].vertices.map {original in
                var vertex=original
                vertex.position=rotated(vertex.position,origin:fold.origin,axis:fold.axis,angle:fold.angle*fraction)
                return vertex
            }
            if active {result[index].isMoving=true}
        }
        return result
    }

    /// Source adjacency selects a connected flap after the moving half-plane is
    /// cut. Layers merely touching in space cannot join this material component.
    private static func sourceAdjacent(_ a:PaperFace,_ b:PaperFace,fold:Fold)->Bool {
        for i in a.vertices.indices {
            if abs(simd_dot(a.vertices[i].position-fold.origin,fold.outward))<epsilon &&
                abs(simd_dot(a.vertices[(i+1)%a.vertices.count].position-fold.origin,fold.outward))<epsilon {continue}
            let p=a.vertices[i].source,q=a.vertices[(i+1)%a.vertices.count].source
            let edge=q-p,length=simd_length(edge)
            guard length>epsilon else{continue}
            let axis=edge/length
            for j in b.vertices.indices {
                let r=b.vertices[j].source,s=b.vertices[(j+1)%b.vertices.count].source
                func cross(_ x:SIMD2<Float>)->Float {axis.x*x.y-axis.y*x.x}
                if abs(cross(r-p))>epsilon || abs(cross(s-p))>epsilon {continue}
                let lo=min(simd_dot(r-p,axis),simd_dot(s-p,axis)),hi=max(simd_dot(r-p,axis),simd_dot(s-p,axis))
                if min(length,hi)-max(0,lo)>epsilon {return true}
            }
        }
        return false
    }

    private static func clip(_ polygon:[PaperVertex],fold:Fold,positive:Bool)->[PaperVertex]{
        var result=[PaperVertex]()
        guard !polygon.isEmpty else{return result}
        for i in polygon.indices {
            let a=polygon[i],b=polygon[(i+1)%polygon.count]
            let da=simd_dot(a.position-fold.origin,fold.outward),db=simd_dot(b.position-fold.origin,fold.outward)
            let insideA=positive ? da>=0:da<=0,insideB=positive ? db>=0:db<=0
            if insideA {result.append(a)}
            if insideA != insideB && abs(da-db)>1e-12 {result.append(.interpolate(a,b,min(1,max(0,da/(da-db)))))}
        }
        var clean=[PaperVertex]()
        for p in result where clean.last.map({simd_distance($0.source,p.source)>epsilon}) ?? true {clean.append(p)}
        if clean.count>1 && simd_distance(clean[0].source,clean[clean.count-1].source)<epsilon {clean.removeLast()}
        return clean
    }

    private static func rotated(_ point:SIMD3<Float>,origin:SIMD3<Float>,axis:SIMD3<Float>,angle:Float)->SIMD3<Float>{
        let n=simd_normalize(axis),v=point-origin
        return origin+v*cos(angle)+simd_cross(n,v)*sin(angle)+n*simd_dot(n,v)*(1-cos(angle))
    }
    private static func arrowPath(_ fold:Fold)->[SIMD3<Float>]{
        (0...24).map{rotated(fold.arrow,origin:fold.origin,axis:fold.axis,angle:fold.angle*Float($0)/24)}
    }
    private static func clippedCrease(_ fold:Fold,faces:[PaperFace])->PaperCrease?{
        var intersections=[SIMD3<Float>]()
        for face in faces where fold.layers == nil || fold.layers!.contains(face.originalSide) {
            for i in face.vertices.indices {
                let a=face.vertices[i].position,b=face.vertices[(i+1)%face.vertices.count].position
                let da=simd_dot(a-fold.origin,fold.outward),db=simd_dot(b-fold.origin,fold.outward)
                if abs(da)<epsilon {intersections.append(a)}
                if da*db<0 {intersections.append(a+(b-a)*(da/(da-db)))}
            }
        }
        let sorted=intersections.sorted {simd_dot($0-fold.origin,fold.axis)<simd_dot($1-fold.origin,fold.axis)}
        guard let a=sorted.first,let b=sorted.last,simd_distance(a,b)>epsilon else{return nil}
        return PaperCrease(start:a,end:b)
    }
}
