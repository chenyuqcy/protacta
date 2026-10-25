import Foundation
import simd

/// Experimental source-continuous first inside reverse. The body opens fully so
/// the two original halves can take the opposite tail-fold branch without an
/// in-place cap flip. This expands source panel 10 into visible access/closure.
enum FullFoxReverseGeometry {
    static let size=FullFoxGeometry.size
    static let sourceActionCount=FullFoxGeometry.sourceActionCount
    static let implementedActionCount=FullFoxGeometry.implementedActionCount
    static let stepCount=FullFoxGeometry.stepCount
    static let lastStep=FullFoxGeometry.lastStep
    static func frame(step:Int,progress:Float)->PaperFrame {
        let p=progress.isFinite ? min(1,max(0,progress)):0
        guard step==7 else{
            let rendered=FullFoxGeometry.renderFrame(step:step,progress:p)
            return FullFoxOutlineGeometry.outline(rendered.frame,suppressing:rendered.formingSeams)
        }
        let original=FullFoxGeometry.frame(step:6,progress:1)
        let width=size*(1-1/sqrt(Float(2))),root=SIMD3<Float>(width,0,0)
        let h=simd_normalize(SIMD3<Float>(tan(.pi/8),0,1)),out=SIMD3<Float>(1,0,-tan(.pi/8))
        func eased(_ t:Float)->Float {let x=min(1,max(0,t));return x*x*(3-2*x)}
        func rotate(_ v:SIMD3<Float>,_ axis:SIMD3<Float>,_ angle:Float)->SIMD3<Float> {
            let n=simd_normalize(axis)
            return v*cos(angle)+simd_cross(n,v)*sin(angle)+n*simd_dot(n,v)*(1-cos(angle))
        }
        func pose(_ progress:Float)->(Float,SIMD3<Float>,SIMD3<Float>){
            let opening:Float=progress<0.3 ? eased(progress/0.3):1-eased((progress-0.3)/0.7)
            let angle=Float.pi*opening,carried=rotate(h,[1,0,0],angle)
            let sum=h+carried
            let tip:SIMD3<Float> = progress<0.3 ? [1,0,0] : sum*(4*h.x/max(1e-10,simd_length_squared(sum)))-SIMD3<Float>(1,0,0)
            return (angle,carried,tip)
        }
        let (opening,carried,tip)=pose(p)
        func turnAngle(_ axis:SIMD3<Float>)->Float{
            let from=SIMD3<Float>(1,0,0)-axis*axis.x,to=tip-axis*simd_dot(tip,axis)
            return atan2(simd_dot(axis,simd_cross(from,to)),simd_dot(from,to))
        }
        func clip(_ vertices:[PaperVertex],positive:Bool)->[PaperVertex]{
            var result:[PaperVertex]=[]
            for i in vertices.indices {
                let a=vertices[i],b=vertices[(i+1)%vertices.count]
                let da=simd_dot(a.position-root,out),db=simd_dot(b.position-root,out)
                let inside=positive ? da>=0:da<=0
                if inside {result.append(a)}
                if (da<0 && db>0)||(da>0 && db<0) {result.append(PaperVertex.interpolate(a,b,da/(da-db)))}
            }
            var clean:[PaperVertex]=[]
            for v in result {if clean.last.map({simd_distance($0.source,v.source)>0.0000001}) ?? true {clean.append(v)}}
            if clean.count>1 && simd_distance(clean[0].source,clean.last!.source)<0.0000001 {clean.removeLast()}
            return clean
        }
        var faces:[PaperFace]=[]
        for f in original.faces {
            let isUpper=[1,11].contains(f.originalSide)
            let rest=f.vertices.map{v -> PaperVertex in var a=v;a.position.y -= original.tableLift;return a}
            for positive in [false,true] {
                let polygon=clip(rest,positive:positive)
                guard polygon.count>=3 else{continue}
                var face=PaperFace(vertices:polygon,originalSide:f.originalSide,isMoving:isUpper || positive)
                guard face.area>1e-13 else{continue}
                for j in face.vertices.indices {
                    var point=face.vertices[j].position
                    if isUpper {point=rotate(point,[1,0,0],opening)}
                    if positive && p>=0.3 {
                        point=root+rotate(point-root,isUpper ? carried:h,turnAngle(isUpper ? carried:h))
                    }
                    face.vertices[j].position=point
                }
                faces.append(face)
            }
        }
        let low=faces.flatMap(\.vertices).map(\.position.y).min() ?? 0,lift=max(0,-low)+0.001
        for i in faces.indices {for j in faces[i].vertices.indices {faces[i].vertices[j].position.y += lift}}
        let radius=size/sqrt(Float(2))-width
        let path=(0...48).map{i -> SIMD3<Float> in let (_,_,d)=pose(0.3+0.7*Float(i)/48);return root+d*radius+SIMD3<Float>(0,lift+0.001,0)}
        return FullFoxOutlineGeometry.outline(PaperFrame(faces:faces,crease:nil,actionPaths:[path],tableLift:lift))
    }
}
