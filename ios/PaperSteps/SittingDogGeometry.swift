import Foundation
import simd

/// Isolated, independently authored development model. Every rendered point
/// belongs to the same source square; there is no imported or replacement dog.
/// Fish-base linkage adapted from this project's independently solved fox base.
/// Broad-paw variation: the source's optional leg-margin and shoulder tucks
/// are omitted. Native rendering and hands-on foldability are not yet accepted.
enum SittingDogGeometry {
    static let size: Float = 0.20
    static let plannedActionCount = 28
    static let implementedActionCount = 28
    static let stepCount = implementedActionCount + 1
    static let lastStep = stepCount - 1
    /// The authored sequence is complete; this flag does not certify native AR or paper follow-along.
    static let isComplete = true
    static let finalFormingStep = 28
    private static let root2: Float = sqrt(2)
    private static let halfDiagonal = size / sqrt(Float(2))
    private static let earWidth = size * (sqrt(Float(2)) - 1) / sqrt(Float(2))
    private static let epsilon: Float = 0.0000002

    private struct Fold {
        var origin: SIMD3<Float>
        var axis: SIMD3<Float>
        var outward: SIMD3<Float>
        var angle: Float
        var arrow: SIMD3<Float>
        var layers: Set<Int>? = nil
        var resultFamily: Int? = nil
        var seed: SIMD2<Float>? = nil
        var outerTailHalf: Int? = nil
    }

    static func frame(step requestedStep: Int, progress requestedProgress: Float) -> PaperFrame {
        let neckRootFactor: Float = -0.15
        let crimpFraction: SIMD2<Float> = [0.45, 0.51]
        let step = min(lastStep,max(0,requestedStep))
        let p = requestedProgress.isFinite ? min(1,max(0,requestedProgress)) : 0
        func amount(_ i:Int)->Float {step < i ? 0 : step == i ? p : 1}
        var faces = fishBase(left:amount(7),right:amount(8))
        var crease:PaperCrease?
        var paths=[[SIMD3<Float>]]()
        func perform(_ fold:Fold,_ fraction:Float,_ active:Bool,_ reverseArrow:Bool = false) {
            if active {
                if crease == nil { crease=clippedCrease(fold,faces:faces) }
                var annotated=fold
                let axis=simd_normalize(fold.axis)
                if simd_length(simd_cross(fold.arrow-fold.origin,axis))<epsilon {
                    let unmarked=faces.map {face -> PaperFace in var copy=face;copy.isMoving=false;return copy}
                    let flap=apply(fold,to:unmarked,fraction:0,active:true).filter(\.isMoving)
                    // A narrowing hinge passes through the tail tip. Put its
                    // arrow on the moving outer edge, not that stationary tip.
                    if let point=flap.flatMap(\.vertices).map(\.position).max(by:{
                        simd_length_squared(simd_cross($0-fold.origin,axis)) < simd_length_squared(simd_cross($1-fold.origin,axis))
                    }) {annotated.arrow=point}
                }
                let path=arrowPath(annotated)
                paths.append(reverseArrow ? Array(path.reversed()):path)
            }
            faces=apply(fold,to:faces,fraction:fraction,active:active)
        }
        func at(_ fold:Fold,_ i:Int) {
            guard step >= i else{return}
            perform(fold,amount(i),step==i)
        }
        func sourcePoint(_ uv:SIMD2<Float>)->SIMD3<Float> {
            faces.flatMap(\.vertices).min {simd_distance_squared($0.source,uv*size)<simd_distance_squared($1.source,uv*size)}!.position
        }
        func along(_ origin:SIMD3<Float>,_ axis:SIMD3<Float>,_ tip:SIMD3<Float>,_ angle:Float,
                   layers:Set<Int>?=nil,family:Int?=nil)->Fold {
            var n=SIMD3<Float>(axis.z,0,-axis.x)
            if simd_dot(tip-origin,n)<0 {n *= -1}
            return Fold(origin:origin,axis:axis,outward:n,angle:angle,arrow:tip,layers:layers,resultFamily:family)
        }
        if step == 1 || step == 2 {
            let axis:SIMD3<Float> = step == 1 ? [1,0,0] : [0,0,1]
            let normal:SIMD3<Float> = step == 1 ? [0,0,1] : [-1,0,0]
            let tip:SIMD3<Float> = step == 1 ? [0,0,halfDiagonal] : [-halfDiagonal,0,0]
            perform(Fold(origin:.zero,axis:axis,outward:normal,angle: -.pi,arrow:tip),sin(.pi*p),true,p>0.5)
        }
        if (3...6).contains(step) {
            let s:Float=1/sqrt(2),t:Float=1-s
            let origin=sheet(step < 5 ? [1,1]:[0,0])
            let mirror=step%2==0
            let hinge=sheet(mirror ? [t,s]:[s,t])
            let tip=sheet(mirror ? [0,1]:[1,0])
            let axis=simd_normalize(hinge-origin)
            var normal=SIMD3<Float>(axis.z,0,-axis.x)
            if simd_dot(tip-origin,normal)<0 {normal *= -1}
            let sign:Float=simd_cross(axis,tip-origin).y>0 ? 1:-1
            perform(Fold(origin:origin,axis:axis,outward:normal,angle:sign * .pi,arrow:tip),sin(.pi*p),true,p>0.5)
        }
        if step == 7 || step == 8 {
            let side=step == 7 ? 11:12
            for i in faces.indices where faces[i].originalSide==side {faces[i].isMoving=true}
            let mirror=step==8
            paths=[(0...28).map { i in
                var v=earNodes(amount:Float(i)/28)["B"]!
                if mirror {v.z *= -1}
                return v
            }]
        }
        for (index,layer) in [(9,11),(10,12)] {
            at(Fold(origin:.zero,axis:[0,0,1],outward:[1,0,0],angle: -.pi,
                    arrow:[earWidth,0,0],layers:[layer]),index)
        }
        at(Fold(origin:.zero,axis:[1,0,0],outward:[0,0,1],angle: -.pi,
                arrow:[0,0,earWidth],layers:[2,12]),11)

        // Outside-reverse endpoints are represented by the same material turn.
        // Physical layer opening/contact is a separate visible aid, not a claim
        // of collision simulation. The hinge goes through the broad rear corner.
        let rear=SIMD3<Float>(0,0,-earWidth)
        let slope:Float=1
        at(Fold(origin:rear,axis:[slope,0,1],outward:[1,0,-slope],angle:.pi,
                arrow:[halfDiagonal,0,0],resultFamily:20),12)
        let tailTip=rotated([halfDiagonal,0,0],origin:rear,axis:[slope,0,1],angle:.pi)
        at(Fold(origin:[0,0,earWidth*0.22],axis:[1,0,0],outward:[0,0,1],angle: -.pi,
                arrow:tailTip,layers:[21,22],resultFamily:70),13)

        // The short crimp is drawn as two opposed hinges across the tail's
        // protruding section. Both original halves participate at the seam.
        if step >= 14 {
            let tip=sourcePoint([1,1])
            let firstOrigin=SIMD3<Float>(0,0,-earWidth*0.16)
            let first=along(firstOrigin,[1,0,0],tip,.pi,layers:[71,72],family:60)
            let f=amount(14)
            perform(first,min(1,f*2),step==14 && f<0.5)
            let secondOrigin=firstOrigin+SIMD3<Float>(0,0,earWidth*0.07)
            let foldedTip=rotated(tip,origin:firstOrigin,axis:[1,0,0],angle:.pi)
            perform(along(secondOrigin,[1,0,0],foldedTip,-.pi,layers:[61,62],family:70),max(0,f*2-1),step==14 && f>=0.5)
        }
        for (index,half) in [(15,1),(16,2)] where step >= index {
            let tip=sourcePoint([1,1])
            var fold=along(tip,[-0.18,0,1],tip+SIMD3<Float>(0.02,0,0),half==1 ? .pi:-.pi,
                           layers:Set(faces.map(\.originalSide).filter {$0%10==half}))
            fold.seed=[size,size]
            fold.outerTailHalf=half
            at(fold,index)
        }
        if step >= 17 {
            let tip=sourcePoint([1,1])
            var fold=along([earWidth*0.86,0,-earWidth*0.09],[1,0,-0.75],tip,.pi,layers:[71,72,61,62])
            fold.seed=[size,size]
            at(fold,17)
        }


        // The front flap really hinges about its material attachment O-I.
        // Its opening is released again while the neck is being raised.
        if step >= 18 {
            let open=step==18 ? p:step==19 ? 1-p:0
            perform(Fold(origin:.zero,axis:[0,0,1],outward:[-1,0,0],angle: -.pi*0.22,
                         arrow:[-earWidth,0,0],layers:[12]),open,step==18)
        }
        let neckRoot=SIMD3<Float>(earWidth*neckRootFactor,0,0)
        let neckAxis=SIMD3<Float>(-tan(Float.pi*3/16),0,-1)
        at(along(neckRoot,neckAxis,[-halfDiagonal,0,0],-.pi,layers:[1,2],family:30),19)
        var headUpper=SIMD3<Float>.zero,headLower=SIMD3<Float>.zero
        if step >= 20 {
            let tip=sourcePoint([0,0])
            let candidates=faces.filter {[31,32].contains($0.originalSide)}.flatMap(\.vertices).map(\.position)
            // The two crimp creases meet on the short edge, as in the source:
            // first from the broad base corner; second across the upper point.
            let shortBase=candidates.filter {simd_distance($0,tip)>0.01 && simd_distance($0,neckRoot)>0.01}
                .min {simd_distance($0,tip)<simd_distance($1,tip)}!
            let junction=tip+(neckRoot-tip)*crimpFraction.x
            let upperEdge=tip+(shortBase-tip)*crimpFraction.y
            let first=along(shortBase,junction-shortBase,tip,.pi,layers:[31,32],family:40)
            let f=amount(20)
            perform(first,min(1,f*2),step==20 && f<0.5)
            let turnedTip=rotated(tip,origin:shortBase,axis:junction-shortBase,angle:.pi)
            let turnedEdge=rotated(upperEdge,origin:shortBase,axis:junction-shortBase,angle:.pi)
            headUpper=junction;headLower=turnedEdge
            perform(along(junction,turnedEdge-junction,turnedTip,-.pi,layers:[41,42],family:50),
                    max(0,f*2-1),step==20 && f>=0.5)
        }

        if step >= 21 {
            let nr=neckRoot
            let slope=tan(Float.pi*3/16)
            let edgeT=(halfDiagonal+nr.x)/(halfDiagonal+slope*earWidth)
            let ss:Float=1/sqrt(2),uv=SIMD2<Float>(ss,1-ss)*edgeT*size
            let shortBase=sheet(uv/size)
            let tip=rotated([-halfDiagonal,0,0],origin:nr,axis:[-slope,0,-1],angle: -.pi)
            let junction=tip+(nr-tip)*crimpFraction.x,upperEdge=tip+(shortBase-tip)*crimpFraction.y
            let headLower=rotated(upperEdge,origin:shortBase,axis:junction-shortBase,angle:.pi)
            let origin=shortBase+(headLower-shortBase)*0.45
            for (seed,angle) in [(uv,Float.pi),(SIMD2<Float>(uv.y,uv.x),-Float.pi)] {
                var fold=along(origin,nr-origin,shortBase,angle,family:110)
                fold.seed=seed
                at(fold,21)
            }
        }

        var muzzleRoot=SIMD3<Float>.zero
        if step >= 22 {
            let tip=sourcePoint([0,0])
            let junction=tip+(headUpper-tip)*0.83
            let firstEdge=tip+(headLower-tip)*0.78
            let secondEdge=tip+(headLower-tip)*0.75
            muzzleRoot=junction
            let first=along(junction,firstEdge-junction,tip,.pi,layers:[51,52],family:90)
            let f=amount(22)
            perform(first,min(1,f*2),step==22 && f<0.5)
            let movedTip=rotated(tip,origin:junction,axis:firstEdge-junction,angle:.pi)
            let movedEdge=rotated(secondEdge,origin:junction,axis:firstEdge-junction,angle:.pi)
            perform(along(junction,movedEdge-junction,movedTip,-.pi,layers:[91,92],family:100),max(0,f*2-1),step==22 && f>=0.5)
        }
        if step >= 23 {
            let a=headUpper+(muzzleRoot-headUpper)*0.45
            let b=headUpper+(headLower-headUpper)*0.16
            var fold=along(a,b-a,headUpper,.pi,family:120)
            // This corner is shared by the collar and head; its connected
            // supporting layers turn together instead of detaching the corner.
            let source=faces.flatMap(\.vertices).min {simd_distance_squared($0.position,headUpper)<simd_distance_squared($1.position,headUpper)}!.source
            fold.seed=source
            at(fold,23)
        }
        if step >= 24 {
            let tip=sourcePoint([0,0]),direction=simd_normalize(headLower-tip)
            let origin=tip+(headLower-tip)*0.47,axis=SIMD3<Float>(-direction.z,0,direction.x)
            var first=along(origin,axis,tip,.pi,family:130);first.seed=[0,0]
            let f=amount(24)
            perform(first,min(1,f*2),step==24 && f<0.5)
            let movedTip=rotated(tip,origin:origin,axis:axis,angle:.pi)
            let secondOrigin=origin+direction*size*0.009
            perform(along(secondOrigin,axis,movedTip,-.pi,layers:[131,132],family:140),max(0,f*2-1),step==24 && f>=0.5)
        }
        if step >= 25 {
            let tip=sourcePoint([0,0]),direction=simd_normalize(headLower-tip)
            let noseCross=tip+(headLower-tip)*0.22
            var fold=along(noseCross,[-direction.z,0,direction.x],tip,.pi,family:150)
            fold.seed=[0,0]
            at(fold,25)
        }
        for (index,layer) in [(26,11),(27,12)] where step >= index {
            at(Fold(origin:[-earWidth*0.73,0,0],axis:[0,0,1],outward:[-1,0,0],angle:layer==11 ? .pi:-.pi,arrow:[-earWidth,0,0],layers:[layer],resultFamily:170),index)
        }
        if step >= 28 {
            let amount=amount(28)
            // A small source-continuous opening separates the two body sides.
            // Its maximum added slope is measured as forming, not rigid folding.
            let all=faces.flatMap(\.vertices).map(\.position)
            var supportAngle:Float=0,bestSpan:Float=0
            for a in all where a.x<0 {for b in all where b.x>0.015 {
                let span=b.x-a.x
                if span<bestSpan || span<0.04 {continue}
                let slope=(b.z-a.z)/span
                if abs(slope)>0.5 {continue}
                if all.allSatisfy({$0.z<=a.z+slope*($0.x-a.x)+0.000002}) {bestSpan=span;supportAngle=atan(slope)}
            }}
            func stand(_ point:SIMD3<Float>,_ source:SIMD2<Float>)->SIMD3<Float> {
                var v=point
                v.y += 0.05*(source.x-source.y)*amount
                v=rotated(v,origin:.zero,axis:[0,1,0],angle:supportAngle*amount)
                return rotated(v,origin:.zero,axis:[1,0,0],angle:Float.pi/2*amount)
            }
            for i in faces.indices {for j in faces[i].vertices.indices {let v=faces[i].vertices[j];faces[i].vertices[j].position=stand(v.position,v.source)}}
            crease=nil;paths=[]
        }

        let minY=faces.flatMap(\.vertices).map(\.position.y).min() ?? 0
        let lift=max(0,-minY)+0.0015
        for i in faces.indices {
            // Submillimeter display spacing only; source seam/area checks use
            // unseparated positions. It prevents coincident flat layers flickering.
            let normal=faces[i].normal
            let sourceCenter=faces[i].vertices.reduce(SIMD2<Float>.zero) {$0+$1.source}/Float(faces[i].vertices.count)
            let offset=normal*0.00003+SIMD3<Float>(0,Float(faces[i].originalSide%10)*0.000015+(sourceCenter.x+sourceCenter.y)*0.00003,0)
            for j in faces[i].vertices.indices {
                faces[i].vertices[j].position.y += lift
                faces[i].vertices[j].separation=offset
            }
        }
        if var c=crease {c.start.y += lift+0.001;c.end.y += lift+0.001;crease=c}
        paths=paths.map {path in
            let offset=max(lift,0.005-(path.map(\.y).min() ?? 0))
            return path.map {$0+SIMD3<Float>(0,offset,0)}
        }
        return PaperFrame(faces:faces,crease:crease,actionPaths:paths,tableLift:lift)
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

    private static func fishBase(left:Float,right:Float)->[PaperFace]{
        let s:Float=1/sqrt(2),t:Float=1-s
        let uv:[String:SIMD2<Float>] = ["A":[0,0],"B":[1,0],"C":[1,1],"I":[s,t],"R":[s,0],"Q":[1,t]]
        
        let triangles:[([String],Bool)] = [(["C","A","I"],false),(["A","R","I"],false),
                                          (["R","B","I"],true),(["B","Q","I"],true),(["Q","C","I"],false)]
        return [false,true].flatMap { mirror in
            let positions=earNodes(amount:mirror ? right:left)
            return triangles.map { names,ear in
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

    private static func apply(_ fold:Fold,to faces:[PaperFace],fraction:Float,active:Bool)->[PaperFace]{
        var result=[PaperFace]()
        var candidates=[Int]()
        for face in faces {
            if let half=fold.outerTailHalf {
                var uv=face.vertices.reduce(SIMD2<Float>.zero) {$0+$1.source}/(Float(face.vertices.count)*size)
                if half==2 {uv=[uv.y,uv.x]}
                let ss:Float=1/sqrt(2),tt:Float=1-ss
                let belongs=uv.x>=ss-1e-6 && uv.y>=tt-1e-6 && uv.y<=tt+(uv.x-ss)*(1-tt)/(1-ss)+1e-6
                if !belongs {result.append(face);continue}
            }
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
            if let family=fold.resultFamily {result[index].originalSide=family+result[index].originalSide%10}
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
        // The guide belongs to the same connected source flap as the motion.
        // A world-space hinge may cross unrelated layers of the folded body.
        let unmarked=faces.map {face -> PaperFace in var copy=face;copy.isMoving=false;return copy}
        let moving=apply(fold,to:unmarked,fraction:0,active:true).filter(\.isMoving)
        var intersections=[SIMD3<Float>]()
        for face in moving {
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
