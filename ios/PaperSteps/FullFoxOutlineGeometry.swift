import Foundation
import simd

/// Disposable visual experiment: retain the boundary of the coplanar physical
/// stack, plus exposed source-paper edges. It does not alter paper positions.
enum FullFoxOutlineGeometry {
    static let size=FullFoxGeometry.size
    static let stepCount=FullFoxGeometry.stepCount
    static let lastStep=FullFoxGeometry.lastStep
    static func frame(step:Int,progress:Float)->PaperFrame {
        let rendered=FullFoxGeometry.renderFrame(step:step,progress:progress)
        return outline(rendered.frame,suppressing:rendered.formingSeams)
    }
    static func outline(_ input:PaperFrame,suppressing seams:[FullFoxGeometry.SourceSegment]=[])->PaperFrame {
        var frame=input
        let originals=frame.faces
        func inside(_ p:SIMD3<Float>,_ face:PaperFace)->Bool {
            let n=face.normal,a=face.vertices[0].position
            if abs(simd_dot(p-a,n))>0.000001{return false}
            for i in 1..<(face.vertices.count-1){
                let b=face.vertices[i].position,c=face.vertices[i+1].position
                let v=b-a,w=c-a,d=p-a,denom=simd_dot(simd_cross(v,w),n)
                if abs(denom)<1e-13{continue}
                let x=simd_dot(simd_cross(d,w),n)/denom,y=simd_dot(simd_cross(v,d),n)/denom
                if x>=(-0.00001) && y>=(-0.00001) && x+y<=1.00001{return true}
            }
            return false
        }
        for f in frame.faces.indices {
            let face=originals[f],n=face.normal,base=face.vertices[0].position
            let coplanar=originals.filter{abs(simd_dot($0.normal,n))>0.999999 && abs(simd_dot($0.vertices[0].position-base,n))<0.000001}
            var vertices:[PaperVertex]=[],mask:[Bool]=[]
            for i in face.vertices.indices {
                let first=face.vertices[i],last=face.vertices[(i+1)%face.vertices.count]
                let a=first.position,b=last.position,e=b-a,length=simd_length(e)
                if length<0.0000005{continue}
                var times:[Float]=[0,1]
                for other in coplanar {for j in other.vertices.indices {
                    let c=other.vertices[j].position,d=other.vertices[(j+1)%other.vertices.count].position,v=d-c
                    let denominator=simd_dot(simd_cross(e,v),n),delta=c-a
                    if abs(denominator)>length*simd_length(v)*0.000001 {
                        let t=simd_dot(simd_cross(delta,v),n)/denominator,u=simd_dot(simd_cross(delta,e),n)/denominator
                        if t>0 && t<1 && u>=(-0.00001) && u<=1.00001{times.append(t)}
                    } else if simd_length(simd_cross(delta,e))/length<0.0000005 {
                        for point in [c,d] {let t=simd_dot(point-a,e)/(length*length);if t>0 && t<1{times.append(t)}}
                    }
                }}
                times.sort();var split:[Float]=[]
                for t in times {if split.last.map({(t-$0)*length>0.0000002}) ?? true{split.append(t)}}
                if split.last!<1{split[split.count-1]=1}
                let across=simd_normalize(simd_cross(n,e))*min(0.000002,length*0.01)
                for j in 0..<(split.count-1) {
                    let p=a+e*((split[j]+split[j+1])/2)
                    let one=coplanar.contains{inside(p+across,$0)},two=coplanar.contains{inside(p-across,$0)}
                    let start=PaperVertex.interpolate(first,last,split[j])
                    let end=PaperVertex.interpolate(first,last,split[j+1])
                    let isFormingSeam=seams.contains{$0.covers(start.source,end.source)}
                    vertices.append(start);mask.append(one != two && !isFormingSeam)
                }
            }
            if vertices.count>=3 {frame.faces[f].vertices=vertices;frame.faces[f].outlinedEdges=mask}
        }
        return frame
    }
}
