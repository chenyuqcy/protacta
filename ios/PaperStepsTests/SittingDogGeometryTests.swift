import XCTest
import simd
@testable import Foliafold

/// Material and annotation regressions; native rendering, paper contact and
/// hands-on foldability remain separate evidence.
final class SittingDogGeometryTests: XCTestCase {
    func testCompleteActionsKeepOneFiniteSourceSquare() {
        XCTAssertTrue(SittingDogGeometry.isComplete)
        XCTAssertEqual(SittingDogGeometry.lastStep,28)
        XCTAssertEqual(SittingDogLessonContent.steps.map(\.id),Array(0...28))
        XCTAssertTrue(SittingDogLessonContent.steps.allSatisfy {!$0.title.isEmpty && !$0.instruction.isEmpty && !$0.explanation.isEmpty})
        for step in 0...28 {for sample in 0...8 {
            let f=SittingDogGeometry.frame(step:step,progress:Float(sample)/8)
            var area:Float=0
            for face in f.faces {
                XCTAssertGreaterThanOrEqual(face.vertices.count,3)
                let a=face.vertices[0].source
                for i in 1..<(face.vertices.count-1) {
                    let b=face.vertices[i].source-a,c=face.vertices[i+1].source-a
                    area += abs(b.x*c.y-b.y*c.x)/2
                }
                for v in face.vertices {
                    XCTAssertTrue(v.position.x.isFinite && v.position.y.isFinite && v.position.z.isFinite)
                    XCTAssertGreaterThanOrEqual(v.position.y,0)
                    XCTAssertGreaterThanOrEqual(min(v.source.x,v.source.y),-0.000001)
                    XCTAssertLessThanOrEqual(max(v.source.x,v.source.y),0.200001)
                }
            }
            XCTAssertEqual(area,0.04,accuracy:0.0000004,"Source material at action \(step)")
        }}
    }

    func testRigidFoldsAndSeparatelyBoundedFinalForming() {
        for step in 0...28 {for sample in 0...8 {
            let f=SittingDogGeometry.frame(step:step,progress:Float(sample)/8)
            let forming=step==SittingDogGeometry.finalFormingStep
            XCTAssertEqual(f.area,0.04,accuracy:forming ? 0.00015:0.0000004)
            for face in f.faces {for a in face.vertices {for b in face.vertices {
                let original=simd_distance(a.source,b.source),actual=simd_distance(a.position,b.position)
                XCTAssertEqual(actual,original,accuracy:forming ? 0.0006:0.00002)
                if forming && original>0.0001 {XCTAssertLessThan(abs(actual-original)/original,0.006)}
            }}}
        }}
    }

    func testSharedMaterialJointsAndActionBoundariesStayConnected() {
        for step in 0...28 {
            for progress:Float in [0,0.5,1] {
                let f=SittingDogGeometry.frame(step:step,progress:progress)
                let vertices=f.faces.flatMap(\.vertices)
                for v in vertices {for face in f.faces {for j in face.vertices.indices {
                    let a=face.vertices[j],b=face.vertices[(j+1)%face.vertices.count]
                    if simd_distance(v.source,a.source)<0.0000001 {
                        XCTAssertLessThan(simd_distance(v.position,a.position),0.00002)
                    }
                    let d=b.source-a.source,l2=simd_length_squared(d)
                    if l2<1e-14 {continue}
                    let t=simd_dot(v.source-a.source,d)/l2
                    if t>0.00001 && t<0.99999 && simd_distance(v.source,a.source+d*t)<0.00000015 {
                        XCTAssertLessThan(simd_distance(v.position,a.position+(b.position-a.position)*t),0.00002,
                                          "A split vertex must remain on its neighbor's material edge")
                    }
                }}}
            }
            if step>0 {
                let previous=SittingDogGeometry.frame(step:step-1,progress:1)
                let next=SittingDogGeometry.frame(step:step,progress:0)
                for v in previous.faces.flatMap(\.vertices) {
                    guard let nextPoint=point(v.source,in:next) else {XCTFail("Missing source material");continue}
                    XCTAssertLessThan(simd_distance(v.position,nextPoint),0.00002,"Action boundary \(step)")
                }
            }
        }
    }

    func testGuidesBelongToMovingPaperAndArrowsShowRealMotion() {
        for step in 1...27 {for progress:Float in [0.25,0.5,0.75] {
            let f=SittingDogGeometry.frame(step:step,progress:progress)
            XCTAssertFalse(f.actionPaths.isEmpty)
            for path in f.actionPaths {
                guard let first=path.first else {XCTFail("Empty action path");continue}
                XCTAssertGreaterThan(path.map {simd_distance($0,first)}.max() ?? 0,0.001,
                                     "Tail-edge arrows must not sit on their stationary hinge tip")
            }
            if let c=f.crease {
                for end in [c.start,c.end] {
                    let p=end-SIMD3<Float>(0,0.001,0)
                    var nearest=Float.greatestFiniteMagnitude
                    for face in f.faces where face.isMoving {for j in face.vertices.indices {
                        let a=face.vertices[j].position,b=face.vertices[(j+1)%face.vertices.count].position
                        let d=b-a,l2=simd_length_squared(d)
                        let t=l2>1e-14 ? min(1,max(0,simd_dot(p-a,d)/l2)):0
                        nearest=min(nearest,simd_distance(p,a+d*t))
                    }}
                    XCTAssertLessThan(nearest,0.00002,"Muzzle crease must not extend across the inactive chest")
                }
            }
        }}
        XCTAssertEqual(SittingDogGeometry.frame(step:21,progress:0.25).actionPaths.count,2)
        for step in 1...6 {
            let a=SittingDogGeometry.frame(step:step,progress:0.25).actionPaths[0]
            let b=SittingDogGeometry.frame(step:step,progress:0.75).actionPaths[0]
            XCTAssertLessThan(simd_distance(a.first!,b.last!),0.00001)
            XCTAssertLessThan(simd_distance(a.last!,b.first!),0.00001)
        }
    }

    func testEveryCountedActionActuallyMovesSourceMaterial() {
        for step in 1...28 {
            let start=SittingDogGeometry.frame(step:step,progress:0)
            var movement:Float=0
            for progress:Float in [0.25,0.5,0.75,1] {
                let f=SittingDogGeometry.frame(step:step,progress:progress)
                for v in f.faces.flatMap(\.vertices) {
                    guard let a=point(v.source,in:start) else {XCTFail("Missing source point");continue}
                    let offset=SIMD3<Float>(0,f.tableLift-start.tableLift,0)
                    movement=max(movement,simd_distance(v.position-offset,a))
                }
            }
            XCTAssertGreaterThan(movement,0.001,"Access-only/no-motion cards must not inflate action count")
        }
    }

    private func point(_ source:SIMD2<Float>,in frame:PaperFrame)->SIMD3<Float>? {
        for vertex in frame.faces.flatMap(\.vertices) where simd_distance(vertex.source,source)<1e-7 {return vertex.position}
        func cross(_ a:SIMD2<Float>,_ b:SIMD2<Float>)->Float {a.x*b.y-a.y*b.x}
        for face in frame.faces {
            let a=face.vertices[0]
            for i in 1..<(face.vertices.count-1) {
                let b=face.vertices[i],c=face.vertices[i+1]
                let u=b.source-a.source,v=c.source-a.source,q=source-a.source,d=cross(u,v)
                if abs(d)<1e-12 {continue}
                let x=cross(q,v)/d,y=cross(u,q)/d
                if x >= -1e-5 && y >= -1e-5 && x+y<=1.00001 {
                    return a.position+x*(b.position-a.position)+y*(c.position-a.position)
                }
            }
        }
        return nil
    }
}
