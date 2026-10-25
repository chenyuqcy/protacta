import XCTest
import simd
@testable import Foliafold

/// Tests the authored long-tail variation's retained square, strict hinge
/// geometry and display metadata. Does not establish layer collision, physical
/// balance, instructor acceptance or exact reproduction of Witte's diagram.
final class FullFoxGeometryTests: XCTestCase {
    private func frame(_ step:Int,_ progress:Float)->PaperFrame {
        FullFoxReverseGeometry.frame(step:step,progress:progress)
    }
    private let materialSamples=(0..<9).flatMap{x in (0..<9).map{y in
        SIMD2<Float>((Float(x)+0.37)/9,(Float(y)+0.43)/9)*FullFoxGeometry.size
    }}

    func testAuthoredLessonStatesAndAttributionMatch() {
        XCTAssertEqual(FullFoxLessonContent.steps.count,25)
        XCTAssertEqual(FullFoxGeometry.stepCount,25)
        XCTAssertEqual(FullFoxLessonContent.steps.map(\.id),Array(0...24))
        XCTAssertEqual(FullFoxLessonContent.sourcePanels,[0,1,2,3,5,6,8,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27])
        XCTAssertTrue(FullFoxLessonContent.sourceName.contains("Adapted"))
        XCTAssertTrue(FullFoxLessonContent.steps[12].instruction.contains("one fifth"))
        XCTAssertEqual(FullFoxLessonContent.steps[5].title,"Fold the broad corners inward")
        for step in FullFoxLessonContent.steps {XCTAssertFalse(step.title.isEmpty);XCTAssertFalse(step.instruction.isEmpty)}
    }

    func testEveryPoseRetainsFiniteRigidSquareAndGuidePaths() throws {
        let expected=FullFoxGeometry.size*FullFoxGeometry.size
        for step in 0...24 {for sample in 0...16 {
            let f=frame(step,Float(sample)/16),context="state\(step),sample\(sample)"
            XCTAssertFalse(f.faces.isEmpty,context)
            XCTAssertLessThan(abs(Self.area(f)-expected),expected*0.0001,context)
            for face in f.faces {
                XCTAssertGreaterThanOrEqual(face.vertices.count,3,context)
                XCTAssertEqual(face.outlinedEdges?.count,face.vertices.count,context)
                for i in face.vertices.indices {
                    let v=face.vertices[i]
                    XCTAssertTrue(v.position.x.isFinite && v.position.y.isFinite && v.position.z.isFinite,context)
                    XCTAssertGreaterThanOrEqual(v.position.y,-0.00001,context)
                    XCTAssertEqual(v.separation,.zero,context)
                    // Include diagonals, so a warped polygon cannot pass by
                    // retaining only its perimeter lengths.
                    for j in face.vertices.indices where j>i {
                        let w=face.vertices[j]
                        XCTAssertLessThan(abs(simd_distance(v.position,w.position)-simd_distance(v.source,w.source)),0.00001,context)
                    }
                }
            }
            for source in materialSamples {XCTAssertNotNil(Self.point(source,f),context)}
            for path in f.actionPaths {
                XCTAssertGreaterThan(path.count,1,context)
                for p in path {
                    XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite,context)
                    XCTAssertLessThan(simd_length(p),FullFoxGeometry.size*4,context)
                }
            }
            if let c=f.crease {for p in [c.start,c.end] {XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite,context)}}
        }}
    }

    func testSharedMaterialAndPartialEdgeJointsStayClosed() {
        for step in 0...24 {for progress:Float in [0,0.375,1] {
            let f=frame(step,progress)
            XCTAssertLessThan(Self.jointGap(f),0.000005,"step\(step):\(progress)")
            XCTAssertLessThan(Self.edgeJointGap(f),0.000005,"step\(step):\(progress)")
        }}
    }

    func testEveryLessonBoundaryKeepsOriginalMaterialInPlace() throws {
        for step in 0..<24 {
            let a=frame(step,1),b=frame(step+1,0)
            for source in materialSamples {
                let p=try XCTUnwrap(Self.point(source,a)),q=try XCTUnwrap(Self.point(source,b))
                XCTAssertLessThan(simd_distance(p,q),0.00005,"boundary\(step)")
            }
        }
    }

    func testOnlyGeneratedTailCurlSeamsAreHidden() {
        XCTAssertTrue(FullFoxGeometry.renderFrame(step:23,progress:1).formingSeams.isEmpty)
        for progress:Float in [0,0.25,0.5,0.75,1] {
            let data=FullFoxGeometry.renderFrame(step:24,progress:progress)
            let before=FullFoxOutlineGeometry.outline(data.frame)
            let after=FullFoxOutlineGeometry.outline(data.frame,suppressing:data.formingSeams)
            XCTAssertFalse(data.formingSeams.isEmpty)
            var hidden=0,retained=0
            XCTAssertEqual(before.faces.count,after.faces.count)
            for i in before.faces.indices {
                let a=before.faces[i],b=after.faces[i]
                XCTAssertEqual(a.vertices.count,b.vertices.count)
                for j in a.vertices.indices {
                    XCTAssertEqual(a.vertices[j].position,b.vertices[j].position)
                    XCTAssertEqual(a.vertices[j].source,b.vertices[j].source)
                    if b.outlinedEdges?[j]==true {retained += 1}
                    if a.outlinedEdges?[j] != b.outlinedEdges?[j] {
                        hidden += 1
                        XCTAssertEqual(a.outlinedEdges?[j],true);XCTAssertEqual(b.outlinedEdges?[j],false)
                        let p=a.vertices[j].source,q=a.vertices[(j+1)%a.vertices.count].source
                        XCTAssertTrue(data.formingSeams.contains{$0.covers(p,q)})
                        let size=FullFoxGeometry.size
                        let sourcePerimeter=(abs(p.x)<1e-7 && abs(q.x)<1e-7)||(abs(p.y)<1e-7 && abs(q.y)<1e-7) ||
                            (abs(p.x-size)<1e-7 && abs(q.x-size)<1e-7)||(abs(p.y-size)<1e-7 && abs(q.y-size)<1e-7)
                        XCTAssertFalse(sourcePerimeter,"Never hide the original square perimeter as a curl seam")
                    }
                }
            }
            XCTAssertGreaterThan(retained,10)
            if progress>0 {XCTAssertGreaterThan(hidden,10)}
        }
    }

    func testFinalOpeningHasBoundedThreeDimensionalExtent() {
        let final=frame(24,1),span=final.bounds.maximum-final.bounds.minimum
        XCTAssertGreaterThan(span.y,0.035);XCTAssertLessThan(span.y,0.09)
        XCTAssertGreaterThan(span.x,0.06);XCTAssertLessThan(span.x,0.13)
        XCTAssertGreaterThan(span.z,0.008);XCTAssertLessThan(span.z,0.03)
        // These bounds catch a closed, exploded or rescaled final pose. The
        // rigid tests remain strict during forming; no elastic exception.
    }
    static func cross(_ a:SIMD2<Float>,_ b:SIMD2<Float>)->Float {a.x*b.y-a.y*b.x}
    static func area(_ frame:PaperFrame)->Float {frame.faces.reduce(0) {sum,face in
        let a=face.vertices[0].source
        return sum+(1..<(face.vertices.count-1)).reduce(Float(0)) {$0+abs(cross(face.vertices[$1].source-a,face.vertices[$1+1].source-a))/2}
    }}
    static func point(_ source:SIMD2<Float>,_ frame:PaperFrame)->SIMD3<Float>? {
        for face in frame.faces {
            let a=face.vertices[0]
            for i in 1..<(face.vertices.count-1) {
                let b=face.vertices[i],c=face.vertices[i+1],u=b.source-a.source,v=c.source-a.source,w=source-a.source
                let d=cross(u,v);if abs(d)<1e-14 {continue}
                let x=cross(w,v)/d,y=cross(u,w)/d
                if x >= -0.00001 && y >= -0.00001 && x+y<=1.00001 {
                    return a.position+a.separation+(b.position+b.separation-a.position-a.separation)*x+(c.position+c.separation-a.position-a.separation)*y
                }
            }
        }
        return nil
    }
    static func jointGap(_ frame:PaperFrame)->Float {
        var buckets=[SIMD2<Int>:[PaperVertex]](),maximum:Float=0
        for v in frame.faces.flatMap(\.vertices) {
            let key=SIMD2<Int>(Int(floor(v.source.x/0.0000002)),Int(floor(v.source.y/0.0000002)))
            for x in -1...1 {for y in -1...1 {for u in buckets[key &+ SIMD2<Int>(x,y)] ?? [] {
                if simd_distance(v.source,u.source)<0.0000001 {maximum=max(maximum,simd_distance(v.position+v.separation,u.position+u.separation))}
            }}}
            buckets[key,default:[]].append(v)
        }
        return maximum
    }
    static func edgeJointGap(_ frame:PaperFrame)->Float {
        let vertices=frame.faces.flatMap(\.vertices)
        var maximum:Float=0
        for face in frame.faces {for i in face.vertices.indices {
            let a=face.vertices[i],b=face.vertices[(i+1)%face.vertices.count],edge=b.source-a.source
            let length=simd_length(edge)
            if length<0.0000002 {continue}
            for v in vertices {
                let delta=v.source-a.source,t=simd_dot(delta,edge)/(length*length)
                if t < -0.000001 || t > 1.000001 || abs(cross(delta,edge))/length>0.0000001 {continue}
                maximum=max(maximum,simd_distance(v.position,a.position+(b.position-a.position)*t))
            }
        }}
        return maximum
    }
}
