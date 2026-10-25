import XCTest
import simd
@testable import Protacta

/// Geometry checks cover material continuity and the explicitly bounded forming
/// approximation. Native rendering and paper follow-along are separate checks.
final class FullRabbitGeometryTests: XCTestCase {
    func testAuthoredRabbitVariationMetadata() {
        XCTAssertTrue(FullRabbitGeometry.isComplete)
        XCTAssertTrue(FullRabbitLessonContent.isComplete)
        XCTAssertEqual(FullRabbitGeometry.plannedActionCount,25)
        XCTAssertEqual(FullRabbitGeometry.stepCount,26)
        XCTAssertEqual(FullRabbitLessonContent.steps.count,26)
        XCTAssertEqual(FullRabbitLessonContent.steps.map(\.id),Array(0..<26))
        XCTAssertTrue(FullRabbitLessonContent.steps.allSatisfy{!$0.title.isEmpty && !$0.instruction.isEmpty && !$0.explanation.isEmpty})
    }

    func testEveryActionPreservesTheOriginalSourceSquareAndSeams() {
        for step in 0..<26 { for sample in 0...16 {
            let frame=FullRabbitGeometry.frame(step:step,progress:Float(sample)/16)
            var area:Float=0,groups=[SIMD2<Int>:[PaperVertex]]()
            for face in frame.faces {
                let first=face.vertices[0].source
                for i in 1..<(face.vertices.count-1) {
                    let u=face.vertices[i].source-first,v=face.vertices[i+1].source-first
                    area += abs(u.x*v.y-u.y*v.x)/2
                }
                XCTAssertEqual(face.outlinedEdges?.count,face.vertices.count)
                for v in face.vertices {
                    XCTAssertTrue(v.position.x.isFinite && v.position.y.isFinite && v.position.z.isFinite)
                    XCTAssertGreaterThanOrEqual(v.position.y,0)
                    let key=SIMD2<Int>(Int((v.source.x*1e7).rounded()),Int((v.source.y*1e7).rounded()))
                    for dx in -1...1 {for dy in -1...1 {
                        for w in groups[key &+ SIMD2<Int>(dx,dy)] ?? [] where simd_distance(v.source,w.source)<1e-7 {
                            XCTAssertLessThan(simd_distance(v.position,w.position),2e-5,"Step \(step), fraction \(sample)/16")
                        }
                    }}
                    groups[key,default:[]].append(v)
                }
            }
            XCTAssertEqual(area,0.0256,accuracy:4e-7)
            XCTAssertEqual(frame.area,0.0256,accuracy:step <= 24 ? 4e-7 : 4e-6)
        }}
    }

    func testRigidFoldsAndLimitedFinalForming() {
        for step in 0..<26 {for p:Float in [0,0.125,0.25,0.5,0.75,0.875,1] {
            for face in FullRabbitGeometry.frame(step:step,progress:p).faces {for v in face.vertices {for w in face.vertices {
                XCTAssertEqual(simd_distance(v.position,w.position),simd_distance(v.source,w.source),accuracy:step <= 24 ? 2e-5 : 0.00045)
            }}}
        }}
    }

    func testNextStepStartsAtThePreviousMaterialPosition() {
        for step in 1..<26 {
            let before=FullRabbitGeometry.frame(step:step-1,progress:1),after=FullRabbitGeometry.frame(step:step,progress:0)
            let vertices=after.faces.flatMap(\.vertices)
            for v in before.faces.flatMap(\.vertices) {
                let matches=vertices.filter{simd_distance($0.source,v.source)<1e-7}
                // A reopened precrease can remove a collinear vertex. In that
                // case evaluate its source point in the next material triangle.
                let position=matches.first?.position ?? interpolate(v.source,in:after)
                XCTAssertNotNil(position,"Missing material at step \(step)")
                if let position {XCTAssertLessThan(simd_distance(v.position,position),2e-5)}
            }
        }
    }

    func testFinishedRabbitHasSeparatedEarsAndSupportWidth() {
        let final=FullRabbitGeometry.frame(step:25,progress:1)
        XCTAssertGreaterThan(final.bounds.maximum.y-final.bounds.minimum.y,0.065)
        XCTAssertGreaterThan(final.bounds.maximum.z-final.bounds.minimum.z,0.02)
        let leftEar=interpolate([-0.08,-0.08],in:final)!
        let rightEar=interpolate([0.08,-0.08],in:final)!
        let innerPoint=interpolate([0,-0.08],in:final)!
        XCTAssertGreaterThan(simd_distance(leftEar,rightEar),0.02)
        XCTAssertGreaterThan(min(leftEar.y,rightEar.y)-innerPoint.y,0.025)
        for sx:Float in [-0.04,0.04] {for sz:Float in [0,0.04] {
            let support=interpolate([sx,sz],in:final)!
            XCTAssertLessThan(support.y,0.0012)
        }}
        for (step,p):(Int,Float) in [(-99,-.infinity),(999,.nan),(1,-3),(8,4)] {
            let frame=FullRabbitGeometry.frame(step:step,progress:p)
            XCTAssertFalse(frame.faces.isEmpty)
            XCTAssertTrue(frame.bounds.minimum.x.isFinite)
        }
    }
    private func interpolate(_ source:SIMD2<Float>,in frame:PaperFrame)->SIMD3<Float>? {
        func cross(_ a:SIMD2<Double>,_ b:SIMD2<Double>)->Double {a.x*b.y-a.y*b.x}
        for face in frame.faces {
            let a=face.vertices[0]
            for i in 1..<(face.vertices.count-1) {
                let b=face.vertices[i],c=face.vertices[i+1]
                let u=SIMD2<Double>(b.source-a.source),v=SIMD2<Double>(c.source-a.source),q=SIMD2<Double>(source-a.source),d=cross(u,v)
                if abs(d)<1e-12 {continue}
                let x=cross(q,v)/d,y=cross(u,q)/d
                if x >= -1e-5 && y >= -1e-5 && x+y <= 1.00001 {return a.position+Float(x)*(b.position-a.position)+Float(y)*(c.position-a.position)}
            }
        }
        return nil
    }

}
