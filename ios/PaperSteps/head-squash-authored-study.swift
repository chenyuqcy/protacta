import Foundation
import simd

/// Authored broad-head continuation after the Joseph Wu / WWF preparation.
/// This uses an added crown tuck; it is not the diagram's exact V-head squash.
enum ElephantAuthoredHeadStudy {
 static let width=ElephantGeometry.width
 static let stepCount=5
 private struct Patch {var face:PaperFace;var trunk:Bool}
 static func frame(step:Int,progress:Float,input suppliedInput:PaperFrame? = nil)->PaperFrame {
  let input=suppliedInput ?? ElephantShoulderStudy.frame(step:4,progress:1)
  if step==0{return input}
  let h=width/4,s=width-h/tan(Float.pi/8)
  func vertex(_ uv:SIMD2<Float>)->SIMD3<Float>{input.faces.flatMap(\.vertices).min(by:{simd_distance($0.source,uv)<simd_distance($1.source,uv)})!.position}
  let f=vertex([s,-h]), H=vertex([width-h,-h]), t=vertex([width,0]), m=(f+t)/2
  let axis=simd_normalize(f-H), radius=simd_dot(m-H,axis), radial=m-H-radius*axis
  let r=simd_length(radial), xx=radial/r, yy=simd_cross(axis,xx)
  let p=step>1 ? 1:min(1,max(0,progress)), a=Float.pi*p,d=a/2
  let movingM=rotate(m,H,axis,a)
  let normal=simd_normalize(-radius*cos(d)*xx-radius*sin(d)*yy+r*cos(d)*axis)
  let movingT=f-2*normal*simd_dot(f-H,normal)
  let faceNormal=simd_normalize(simd_cross(m-H,f-H))
  let cutNormal=simd_cross(faceNormal,m-H)
  var patches=[Patch]()
  for original in input.faces {
   for front in [false,true] {
    let sideVertices=clip(original.vertices,H,xx,front)
    guard sideVertices.count>2 else{continue}
    if !front {var q=original;q.vertices=sideVertices;q.isMoving=false;if q.area>1e-12{patches.append(Patch(face:q,trunk:false))};continue}
    for lower in [false,true] {
     let v=clip(sideVertices,H,cutNormal,lower)
     guard v.count>2 else{continue}
     var q=original;q.vertices=v
     guard q.area>1e-12 else{continue}
     let near=original.originalSide == -1
     for i in q.vertices.indices {
      let x=q.vertices[i].position
      q.vertices[i].position = lower
        ? rigidMap(x,H,f,m,H,f,near ? movingM:m)
        : rigidMap(x,H,m,t,H,near ? movingM:m,movingT)
      q.vertices[i].separation = .zero
     }
     q.isMoving=near || !lower
     q.outlinedEdges=nil
     patches.append(Patch(face:q,trunk:!lower))
    }
   }
  }
  if step>=2 {
   // Authored variation: fold the small peaked packet inward to a short crown.
   let amount=step>2 ? 1:min(1,max(0,progress))
   let creasePoint=SIMD3<Float>(H.x,H.y,m.z)
   patches=fold(patches,creasePoint,[1,0,0],[0,0,-1],Float.pi*amount)
  }
  if step>=3 {
   // Fold the right head half behind the left along the joined paper spine.
   patches=fold(patches,f,[0,0,1],[1,0,0],Float.pi*(step>3 ? 1:min(1,max(0,progress))))
  }
  var crease:PaperCrease?
  var paths=[[SIMD3<Float>]]()
  if step==1 {
   crease=PaperCrease(start:f,end:H)
   paths=[(0...28).map { sample in
    let d=Float.pi*Float(sample)/56
    let n=simd_normalize(-radius*cos(d)*xx-radius*sin(d)*yy+r*cos(d)*axis)
    return f-2*n*simd_dot(f-H,n)
   }]
  } else if step==2 {
   let left=rotate(m,H,axis,Float.pi),origin=SIMD3<Float>(H.x,H.y,m.z)
   crease=PaperCrease(start:left,end:m)
   paths=[(0...28).map{rotate(H,origin,[1,0,0],Float.pi*Float($0)/28)}]
  } else if step==3 {
   crease=PaperCrease(start:f,end:[H.x,H.y,m.z])
   paths=[(0...28).map{rotate(m,f,[0,0,1],Float.pi*Float($0)/28)}]
  }
  if step>=4 {
   // Both folded H–P–T walls are the trunk packet. They share the real source
   // apex (w,0); the coincident leg point (s,±h) is a different source point.
   let crownUV=SIMD2<Float>(width-sqrt(2)*h,0)
   let pivotUV=SIMD2<Float>((s+width)/2,-h/2)
   let current=patches.map(\.face)
   let crown=point(crownUV,in:current),pivot=point(pivotUV,in:current)
   let hinge=simd_normalize(pivot-crown),amount=min(1,max(0,progress))
   let apex=point([width,0],in:current)
   for i in patches.indices {
    patches[i].face.isMoving=patches[i].trunk
    guard patches[i].trunk else{continue}
    for j in patches[i].face.vertices.indices {
     patches[i].face.vertices[j].position=rotate(patches[i].face.vertices[j].position,crown,hinge,Float.pi*amount)
    }
   }
   crease=PaperCrease(start:crown,end:pivot)
   paths=[(0...28).map{rotate(apex,crown,hinge,Float.pi*Float($0)/28)}]
  }
  // A folded crown tab spans both sides of the trunk hinge. Raise the whole
  // sheet only as needed during that turn, preserving all relative positions.
  let lowest=patches.flatMap{$0.face.vertices}.map{$0.position.y}.min() ?? 0
  let clearance=max(0,0.001-lowest)
  if clearance>0 {
   for i in patches.indices {for j in patches[i].face.vertices.indices {patches[i].face.vertices[j].position.y+=clearance}}
   if let c=crease {crease=PaperCrease(start:c.start+[0,clearance,0],end:c.end+[0,clearance,0])}
   paths=paths.map{$0.map{$0+[0,clearance,0]}}
  }
  return PaperFrame(faces:patches.map(\.face),crease:crease,actionPaths:paths,tableLift:input.tableLift+clearance)
 }
 private static func point(_ source:SIMD2<Float>,in faces:[PaperFace])->SIMD3<Float>{
  func cross(_ a:SIMD2<Float>,_ b:SIMD2<Float>)->Float{a.x*b.y-a.y*b.x}
  for f in faces {
   let a=f.vertices[0]
   for i in 1..<(f.vertices.count-1){let b=f.vertices[i],c=f.vertices[i+1],u=b.source-a.source,v=c.source-a.source,q=source-a.source,d=cross(u,v)
    if abs(d)<1e-12{continue}
    let x=cross(q,v)/d,y=cross(u,q)/d
    if x>=(-0.00001),y>=(-0.00001),x+y<=1.00001{return a.position+x*(b.position-a.position)+y*(c.position-a.position)}
   }
  }
  preconditionFailure("Missing source anchor")
 }
 private static func fold(_ input:[Patch],_ o:SIMD3<Float>,_ axis:SIMD3<Float>,_ normal:SIMD3<Float>,_ angle:Float)->[Patch]{
  input.flatMap {patch in [false,true].compactMap {moving in
   let v=clip(patch.face.vertices,o,normal,moving);guard v.count>2 else{return nil}
   var q=patch.face;q.vertices=v;guard q.area>1e-12 else{return nil}
   if moving{for i in q.vertices.indices{q.vertices[i].position=rotate(q.vertices[i].position,o,axis,angle)}}
   q.isMoving=moving;q.outlinedEdges=nil;return Patch(face:q,trunk:patch.trunk)
  }}
 }
 private static func rotate(_ p:SIMD3<Float>,_ o:SIMD3<Float>,_ a:SIMD3<Float>,_ t:Float)->SIMD3<Float>{let v=p-o;return o+cos(t)*v+sin(t)*simd_cross(a,v)+(1-cos(t))*simd_dot(a,v)*a}
 private static func rigidMap(_ p:SIMD3<Float>,_ a:SIMD3<Float>,_ b:SIMD3<Float>,_ c:SIMD3<Float>,_ aa:SIMD3<Float>,_ bb:SIMD3<Float>,_ cc:SIMD3<Float>)->SIMD3<Float>{
  func basis(_ a:SIMD3<Float>,_ b:SIMD3<Float>,_ c:SIMD3<Float>)->simd_float3x3{let u=simd_normalize(b-a),n=simd_normalize(simd_cross(u,c-a)),v=simd_cross(n,u);return .init(columns:(u,v,n))}
  return aa+basis(aa,bb,cc)*basis(a,b,c).transpose*(p-a)
 }
 private static func clip(_ v:[PaperVertex],_ o:SIMD3<Float>,_ n:SIMD3<Float>,_ pos:Bool)->[PaperVertex]{
  let e:Float=1e-7;var out=[PaperVertex]()
  for i in v.indices{let a=v[i],b=v[(i+1)%v.count],da=simd_dot(a.position-o,n),db=simd_dot(b.position-o,n)
   if pos ? da >= -e : da <= e{out.append(a)}
   if (da < -e && db > e)||(da > e && db < -e){out.append(PaperVertex.interpolate(a,b,da/(da-db)))}
  }
  var clean=[PaperVertex]();for a in out where clean.last.map({simd_distance($0.source,a.source)>e}) ?? true{clean.append(a)}
  if clean.count>2,simd_distance(clean[0].source,clean.last!.source)<e{clean.removeLast()};return clean
 }
}
