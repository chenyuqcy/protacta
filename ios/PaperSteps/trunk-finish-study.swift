import Foundation
import simd

/// Independently authored three-bend finish of the broad-head elephant variation.
/// The completed head's material tag is captured before any animation flags change.
/// These are packet folds, not a claim to reproduce Wu's inside-reverse topology.
enum ElephantTrunkFinishStudy {
 static let width=ElephantGeometry.width
 static let stepCount=4
 static let lastStep=3
 static let isComplete=false
 private struct Patch {var face:PaperFace;var trunk:Bool}
 struct Result {var faces:[PaperFace];var crease:PaperCrease?;var actionPaths:[[SIMD3<Float>]]}
 static func frame(step:Int,progress:Float,input supplied:PaperFrame?=nil)->PaperFrame {
  let input=supplied ?? ElephantAuthoredHeadStudy.frame(step:4,progress:1)
  if step==0{return input}
  let result=apply(to:input.faces,step:step,progress:progress)
  var faces=result.faces, crease=result.crease,paths=result.actionPaths
  let low=faces.flatMap(\.vertices).map(\.position.y).min() ?? 0
  let lift=max(0,0.001-low)
  if lift>0 {
   for i in faces.indices{for j in faces[i].vertices.indices{faces[i].vertices[j].position.y+=lift}}
   if let c=crease{crease=PaperCrease(start:c.start+[0,lift,0],end:c.end+[0,lift,0])}
   paths=paths.map{$0.map{$0+[0,lift,0]}}
  }
  return PaperFrame(faces:faces,crease:crease,actionPaths:paths,tableLift:input.tableLift+lift)
 }
 /// Input must be the completed action-4 head, with its original `isMoving`
 /// trunk membership untouched. Coordinates are preserved; no floor lift here.
 static func apply(to input:[PaperFace],step:Int,progress:Float)->Result {
  precondition((0...lastStep).contains(step))
  if step==0{return Result(faces:input,crease:nil,actionPaths:[])}
  var patches=input.map{Patch(face:$0,trunk:$0.isMoving)}
  // The head API preserves the flat XZ construction frame, including when
  // supplied with rear feet. Only translation and uniform floor lift vary.
  let root=point([(width-width/4/tan(Float.pi/8)+width)/2,-width/8],in:input)
  let x=SIMD3<Float>(1,0,0),z=SIMD3<Float>(0,0,1)
  var crease:PaperCrease?, paths=[[SIMD3<Float>]]()
  for action in 1...step {
   let amount=action<step ? Float(1):min(1,max(0,progress))
   let faces=patches.map(\.face),apex=point([width,0],in:faces)
   let hingeOrigin:SIMD3<Float>,axis:SIMD3<Float>,angle:Float
   var normal:SIMD3<Float>
   if action==1 {
    hingeOrigin=root
    axis=simd_normalize(cos(Float.pi*18.75/180)*x+sin(Float.pi*18.75/180)*z)
    normal=simd_normalize(sin(Float.pi*18.75/180)*x-cos(Float.pi*18.75/180)*z)
    angle = .pi
   } else if action==2 {
    // A second, small diagonal at the lower trunk gives a gentle forward bend.
    hingeOrigin=root+0.67*(apex-root)
    axis=simd_normalize(cos(Float.pi*40/180)*x+sin(Float.pi*40/180)*z)
    normal=simd_normalize(simd_cross([0,1,0],axis))
    if simd_dot(apex-hingeOrigin,normal)<0 { normal = -normal }
    angle = -.pi
   } else {
    // The terminal cap folds upward. Only the selected distal packet moves.
    hingeOrigin=apex-0.008*(cos(Float.pi/9)*x+sin(Float.pi/9)*z)
    axis=cos(-Float.pi/9)*x+sin(-Float.pi/9)*z
    normal=simd_normalize(simd_cross([0,1,0],axis))
    if simd_dot(apex-hingeOrigin,normal)<0 {normal = -normal}
    angle = -.pi
   }
   let event=fold(patches,origin:hingeOrigin,axis:axis,normal:normal,angle:angle*amount)
   patches=event.patches
   if action==step {
    crease=event.crease
    paths=[(0...28).map{rotate(apex,hingeOrigin,axis,angle*Float($0)/28)}]
   }
  }
  return Result(faces:patches.map(\.face),crease:crease,actionPaths:paths)
 }
 private static func fold(_ input:[Patch],origin:SIMD3<Float>,axis:SIMD3<Float>,normal:SIMD3<Float>,angle:Float)->(patches:[Patch],crease:PaperCrease?) {
  var output=[Patch](),hinge=[SIMD3<Float>]()
  for patch in input {
   if !patch.trunk {var q=patch;q.face.isMoving=false;output.append(q);continue}
   for moving in [false,true] {
    let vertices=clip(patch.face.vertices,origin,normal,moving)
    guard vertices.count>2 else{continue}
    var face=patch.face;face.vertices=vertices
    guard face.area>1e-12 else{continue}
    for v in vertices where abs(simd_dot(v.position-origin,normal))<2e-7 {hinge.append(v.position)}
    if moving {for i in face.vertices.indices{face.vertices[i].position=rotate(face.vertices[i].position,origin,axis,angle)}}
    face.isMoving=moving;face.outlinedEdges=nil
    output.append(Patch(face:face,trunk:true))
   }
  }
  let sorted=hinge.sorted{simd_dot($0-origin,axis)<simd_dot($1-origin,axis)}
  let crease=sorted.count>1 ? PaperCrease(start:sorted.first!,end:sorted.last!):nil
  return(output,crease)
 }
 private static func point(_ source:SIMD2<Float>,in faces:[PaperFace])->SIMD3<Float> {
  func cross(_ a:SIMD2<Float>,_ b:SIMD2<Float>)->Float{a.x*b.y-a.y*b.x}
  for face in faces {let a=face.vertices[0];for i in 1..<(face.vertices.count-1){let b=face.vertices[i],c=face.vertices[i+1],u=b.source-a.source,v=c.source-a.source,q=source-a.source,d=cross(u,v);if abs(d)<1e-12{continue};let x=cross(q,v)/d,y=cross(u,q)/d;if x>=(-1e-5),y>=(-1e-5),x+y<=1.00001{return a.position+x*(b.position-a.position)+y*(c.position-a.position)}}}
  preconditionFailure("Missing elephant source anchor")
 }
 private static func rotate(_ p:SIMD3<Float>,_ o:SIMD3<Float>,_ a:SIMD3<Float>,_ t:Float)->SIMD3<Float>{let v=p-o;return o+cos(t)*v+sin(t)*simd_cross(a,v)+(1-cos(t))*simd_dot(a,v)*a}
 private static func clip(_ vertices:[PaperVertex],_ o:SIMD3<Float>,_ n:SIMD3<Float>,_ positive:Bool)->[PaperVertex] {
  let epsilon:Float=1e-7;var out=[PaperVertex]()
  for i in vertices.indices {let a=vertices[i],b=vertices[(i+1)%vertices.count],da=simd_dot(a.position-o,n),db=simd_dot(b.position-o,n)
   if positive ? da >= -epsilon:da <= epsilon {out.append(a)}
   if (da < -epsilon && db > epsilon)||(da > epsilon && db < -epsilon){out.append(PaperVertex.interpolate(a,b,da/(da-db)))}
  }
  var clean=[PaperVertex]();for v in out where clean.last.map({simd_distance($0.source,v.source)>epsilon}) ?? true{clean.append(v)}
  if clean.count>2,simd_distance(clean[0].source,clean.last!.source)<epsilon{clean.removeLast()};return clean
 }
}
