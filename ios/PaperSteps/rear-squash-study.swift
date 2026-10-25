import Foundation
import simd

/// Isolated source-19 rear pocket. Three moving rigid regions share material;
/// this is not the rejected single cap turn. Main lesson is unchanged.
enum ElephantRearSquashStudy {
    static let width:Float = 0.20
    static let stepCount=3,lastStep=2,isComplete=false
    static let taste:Float=0.45
    private static let e:Float=1e-7

    static func frame(step:Int,progress:Float)->PaperFrame {
        let source=ElephantGeometry.frame(step:26,progress:1)
        let tip=source.faces.flatMap(\.vertices).first {simd_distance($0.source,[width,0])<1e-6}!.position
        let offset=SIMD3<Float>(width-tip.x,-source.tableLift,-tip.z)
        var faces=source.faces.map {face -> PaperFace in
            var f=face;f.isMoving=false
            for j in f.vertices.indices {f.vertices[j].position += offset;f.vertices[j].separation = .zero}
            return f
        }
        for index in 1...2 where step>=index {
            faces=apply(to:faces,side:index==1 ? 1:-1,progress:step>index ? 1:progress,active:step==index)
        }
        let points=faces.flatMap(\.vertices).map(\.position)
        let lo=points.reduce(SIMD3<Float>(repeating:.greatestFiniteMagnitude),simd_min)
        let hi=points.reduce(SIMD3<Float>(repeating:-.greatestFiniteMagnitude),simd_max)
        let lift=max(0,-lo.y)+0.001
        let center=SIMD3<Float>(-(lo.x+hi.x)/2,lift,-(lo.z+hi.z)/2)
        for i in faces.indices {for j in faces[i].vertices.indices {
            faces[i].vertices[j].position += center
            faces[i].vertices[j].separation = faces[i].normal*Float(i%5)*0.00002
        }}
        var crease:PaperCrease?,paths=[[SIMD3<Float>]]()
        if step>0 {
            let guide=guidance(side:step==1 ? 1:-1)
            crease=PaperCrease(start:guide.crease.start+center+[0,0.001,0],end:guide.crease.end+center+[0,0.001,0])
            paths=guide.paths.map {path in
                let shifted=path.map {$0+center}
                let raise=max(0,0.004-(shifted.map(\.y).min() ?? 0))
                return shifted.map {$0+SIMD3<Float>(0,raise,0)}
            }
        }
        return PaperFrame(faces:faces,crease:crease,actionPaths:paths,tableLift:lift)
    }

    /// Input is the source-18 flat checkpoint in uncentered x/z coordinates:
    /// left source edge x=0, head point x=.2, center z=0. Source UV stays intact.
    static func apply(to faces:[PaperFace],side:Int,progress:Float,active:Bool=true)->[PaperFace] {
        let h=width/4,s=width-h/tan(Float.pi/8),r=s/4
        let m=motion(side:side,progress:progress)
        let P=m.P,R=m.R,C=m.C,T=m.T,u=m.u,v=m.v,alpha=m.alpha,beta=m.beta,newR=m.newR,newC=m.newC
        func normal(_ point:SIMD3<Float>)->SIMD3<Float> {
            let a=point-P;var n=SIMD3<Float>(a.z,0,-a.x)
            if simd_dot(C-P,n)<0 {n *= -1};return n
        }
        return faces.flatMap {original -> [PaperFace] in
            guard original.originalSide==side else{return [original]}
            let uv=original.vertices.reduce(SIMD2<Float>.zero){$0+$1.source}/Float(original.vertices.count)
            let beforeX=uv.x<r ? 2*r-uv.x:uv.x
            let z=abs(uv.y),beforeZ=min(z,2*h-z)
            let corner=beforeZ>h-3*r/sqrt(5)+(beforeX-r)/sqrt(5)+e
            guard corner else{return [original]}
            let band=uv.x<r
            let hinge=band ? R:T
            return [false,true].compactMap {positive in
                let vertices=clip(original.vertices,origin:P,normal:normal(hinge),positive:positive)
                guard vertices.count>=3 else{return nil}
                var f=original;f.vertices=vertices
                guard f.area>1e-12 else{return nil}
                for j in f.vertices.indices {
                    let q=f.vertices[j].position
                    if band {
                        f.vertices[j].position=positive ? rigidMap(q,P,R,C,P,newR,newC):rotate(q,P,u,alpha)
                    } else if positive {f.vertices[j].position=rotate(q,P,v,beta)}
                }
                f.isMoving=active && (band || positive)
                return f
            }
        }
    }
    /// Guides use the same solved trajectories as apply(), in uncentered coordinates.
    static func guidance(side:Int)->(crease:PaperCrease,paths:[[SIMD3<Float>]]) {
        let rest=motion(side:side,progress:0)
        let states=(0...32).map {motion(side:side,progress:Float($0)/32)}
        return (PaperCrease(start:rest.P,end:rest.T),[states.map(\.newR),states.map(\.newC)])
    }
    private struct Motion {
        let P:SIMD3<Float>,R:SIMD3<Float>,C:SIMD3<Float>,T:SIMD3<Float>,u:SIMD3<Float>,v:SIMD3<Float>,newR:SIMD3<Float>,newC:SIMD3<Float>
        let alpha:Float,beta:Float
    }
    private static func motion(side:Int,progress:Float)->Motion {
        let p=min(1,max(0,progress)),k=Float(side)
        let h=width/4,s=width-h/tan(Float.pi/8),r=s/4
        let P=SIMD3<Float>(r,0,k*(h-3*r/sqrt(5)))
        let S=SIMD3<Float>(s,0,k*h)
        let C=SIMD3<Float>(2*r,0,k*(h-r*sqrt(5)))
        let B=SIMD3<Float>(8*r/3,0,k*(h-10*r/(3*sqrt(5))))
        let R=C+(B-C)*taste
        func angle(_ v:SIMD3<Float>)->Float {atan2(k*v.z,v.x)}
        let theta=angle(S-P)+angle(C-P)-angle(R-P)
        let axis=SIMD3<Float>(cos(theta),0,k*sin(theta))
        func cross2(_ a:SIMD3<Float>,_ b:SIMD3<Float>)->Float {a.x*b.z-a.z*b.x}
        let t=cross2(P-C,axis)/cross2(S-C,axis)
        let T=C+(S-C)*t
        let u=simd_normalize(S-P),v=simd_normalize(T-P)
        let alpha=k*Float.pi*p
        let newR=rotate(R,P,u,alpha)
        var beta:Float=0
        if p>=1 {beta=k*Float.pi}
        else if p>0 {
            let rm=SIMD3<Double>(newR-P),c=SIMD3<Double>(C-P),rr=SIMD3<Double>(R-P),vv=SIMD3<Double>(v)
            let parallel=vv*simd_dot(vv,c),perp=c-parallel
            let aa=simd_dot(rm,perp),bb=simd_dot(rm,simd_cross(vv,perp))
            let cc=simd_dot(rr,c)-simd_dot(rm,parallel)
            beta=Float(atan2(bb,aa)+Double(k)*acos(min(1,max(-1,cc/max(1e-20,hypot(aa,bb))))))
        }
        let newC=rotate(C,P,v,beta)
        return Motion(P:P,R:R,C:C,T:T,u:u,v:v,newR:newR,newC:newC,alpha:alpha,beta:beta)
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
    private static func clip(_ vertices:[PaperVertex],origin:SIMD3<Float>,normal:SIMD3<Float>,positive:Bool)->[PaperVertex] {
        var out=[PaperVertex]()
        for i in vertices.indices {
            let a=vertices[i],b=vertices[(i+1)%vertices.count]
            let da=simd_dot(a.position-origin,normal),db=simd_dot(b.position-origin,normal)
            if positive ? da>=(-e):da<=e {out.append(a)}
            if da * db < 0 && abs(da-db)>e {out.append(PaperVertex.interpolate(a,b,da/(da-db)))}
        }
        var clean=[PaperVertex]()
        for v in out where clean.last.map({simd_distance($0.source,v.source)>e}) ?? true {clean.append(v)}
        if clean.count>2 && simd_distance(clean[0].source,clean[clean.count-1].source)<e {clean.removeLast()}
        return clean
    }
}
