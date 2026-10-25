import XCTest
import simd
@testable import Foliafold

final class FrogGeometryTests: XCTestCase {
    func testLessonHasTwentyTwoRealActionsAndEnglishInstructions() {
        XCTAssertEqual(FrogGeometry.stepCount,23)
        XCTAssertEqual(FrogLessonContent.steps.count,FrogGeometry.stepCount)
        XCTAssertEqual(FrogLessonContent.steps.map(\.id),Array(0..<FrogGeometry.stepCount))
        XCTAssertEqual(FrogGeometry.height,FrogGeometry.width*2)
        XCTAssertEqual(FrogLessonContent.sourceURL.absoluteString,"https://origami.me/jumping-frog/")
        for step in FrogLessonContent.steps {
            for text in [step.title,step.instruction,step.cue,step.explanation] {
                XCTAssertFalse(text.isEmpty)
                XCTAssertFalse(text.unicodeScalars.contains { (0x4e00...0x9fff).contains($0.value) })
            }
        }
    }

    func testDenseFoldsPreservePaperAreaRigidPanelsAndSharedSeams() {
        let area=FrogGeometry.width*FrogGeometry.height
        var maxArea:Float=0,maxLength:Float=0,maxSeam:Float=0
        for step in 0..<FrogGeometry.stepCount {for sample in 0...40 {
            let f=FrogGeometry.frame(step:step,progress:Float(sample)/40),vertices=f.faces.flatMap(\.vertices)
            maxArea=max(maxArea,abs(f.area-area))
            for face in f.faces {for a in face.vertices {
                XCTAssertTrue(a.position.x.isFinite && a.position.y.isFinite && a.position.z.isFinite)
                XCTAssertGreaterThanOrEqual(a.position.y,0)
                for b in face.vertices {maxLength=max(maxLength,abs(simd_distance(a.position,b.position)-simd_distance(a.source,b.source)))}
                for b in vertices where simd_distance(a.source,b.source)<0.0000005 {maxSeam=max(maxSeam,simd_distance(a.position,b.position))}
            }}
        }}
        XCTAssertLessThan(maxArea,0.0000002)
        XCTAssertLessThan(maxLength,0.00002)
        XCTAssertLessThan(maxSeam,0.00002)
    }

    func testEveryStepBeginsAtThePreviousMaterialPose() throws {
        for step in 1..<FrogGeometry.stepCount {
            let before=FrogGeometry.frame(step:step-1,progress:1),after=FrogGeometry.frame(step:step,progress:0)
            let sources=before.faces.flatMap(\.vertices).map(\.source)+after.faces.flatMap(\.vertices).map(\.source)
            for source in sources {
                let a=try XCTUnwrap(materialPosition(source,in:before)),b=try XCTUnwrap(materialPosition(source,in:after))
                XCTAssertLessThan(simd_distance(a,b),0.00002,"Paper jumps at step \(step), source \(source)")
            }
        }
    }

    func testPocketsOpenInThreeDimensionsAndFinishWithFourFeet() throws {
        for step in [5,15] {
            let mid=FrogGeometry.frame(step:step,progress:0.5)
            XCTAssertGreaterThan(mid.bounds.maximum.y-mid.bounds.minimum.y,0.01)
        }
        let f=FrogGeometry.frame(step:22,progress:1),w=FrogGeometry.width/2
        let sources:[SIMD2<Float>]=[[-w,-2*w],[w,-2*w],[-w,w],[w,w]]
        let feet=try sources.map {try XCTUnwrap(materialPosition($0,in:f))}
        XCTAssertGreaterThan(simd_distance(feet[0],feet[1]),0.025)
        XCTAssertGreaterThan(simd_distance(feet[2],feet[3]),0.045)
        XCTAssertLessThan(feet[0].z,0);XCTAssertLessThan(feet[1].z,0)
        XCTAssertGreaterThan(feet[2].z,0);XCTAssertGreaterThan(feet[3].z,0)
        XCTAssertGreaterThan(f.bounds.maximum.y-f.bounds.minimum.y,0.005)
        XCTAssertLessThan(abs(feet[0].y-feet[2].y),0.002)
    }

    func testClampingAndNearEndpointPocketSolutionsStayFinite() {
        for (step,p):(Int,Float) in [(-20,-.infinity),(999,.nan),(5,-2),(15,3),(5,0.00001),(5,0.99999),(15,0.00001),(15,0.99999)] {
            let f=FrogGeometry.frame(step:step,progress:p)
            XCTAssertFalse(f.faces.isEmpty)
            XCTAssertEqual(f.area,FrogGeometry.width*FrogGeometry.height,accuracy:0.0000002)
            XCTAssertTrue(f.bounds.minimum.x.isFinite && f.bounds.maximum.y.isFinite)
        }
    }

    func testRearPrecreaseArrowsReverseWhenThePaperReopens() throws {
        for step in [12, 13] {
            let closing = try XCTUnwrap(FrogGeometry.frame(step: step, progress: 0.25).actionPaths.first)
            let opening = try XCTUnwrap(FrogGeometry.frame(step: step, progress: 0.75).actionPaths.first)
            XCTAssertEqual(closing.count, opening.count)
            for (a, b) in zip(closing, opening.reversed()) {
                XCTAssertLessThan(simd_distance(a, b), 0.000001, "The arrow must point along the actual unfolding motion")
            }
        }
    }

    func testRearDiagonalTracesRemainOnEveryFoldedLayerDuringReopening() throws {
        let w = FrogGeometry.width / 2, q = w / 2
        for step in [12, 13, 14] {
            let samples: [Float] = step == 12 ? [1] : [0, 0.25, 0.5, 0.75, 1]
            for p in samples {
                let frame = FrogGeometry.frame(step: step, progress: p)
                let signs: [Float] = step == 12 ? [-1] : [-1, 1]
                for sign in signs {
                    // Each rear diagonal crosses an inner strip, its folded-in
                    // outer strip, and both copies in the genuinely doubled hem.
                    let base: [(SIMD2<Float>, SIMD2<Float>)] = [
                        ([sign*q, q], [0, w]), ([sign*w, w], [sign*q, q])
                    ]
                    for hem in [false, true] {
                        for (start, end) in base {
                            let a = SIMD2<Float>(start.x, hem ? 2*w-start.y : start.y)
                            let b = SIMD2<Float>(end.x, hem ? 2*w-end.y : end.y)
                            for t: Float in [0.2, 0.5, 0.8] {
                                let source = a + (b-a)*t
                                let paper = try XCTUnwrap(materialPosition(source, in: frame))
                                let trace = try XCTUnwrap(outlinedEdgePosition(source, in: frame),
                                    "Lost rear diagonal at step \(step), progress \(p), source \(source)")
                                XCTAssertLessThan(simd_distance(trace, paper), 0.000001,
                                                  "The guide must travel on its own material layer")
                            }
                        }
                    }
                }
            }
        }
    }

    private func outlinedEdgePosition(_ source: SIMD2<Float>, in frame: PaperFrame) -> SIMD3<Float>? {
        for face in frame.faces {
            for i in face.vertices.indices where face.outlinedEdges?[i] ?? true {
                let a = face.vertices[i], b = face.vertices[(i+1) % face.vertices.count]
                let edge = b.source-a.source, lengthSquared = simd_length_squared(edge)
                guard lengthSquared > 1e-12 else { continue }
                let t = simd_dot(source-a.source, edge) / lengthSquared
                if t >= -0.000001 && t <= 1.000001 && simd_distance(source, a.source+edge*t) < 0.0000001 {
                    return a.position+(b.position-a.position)*t
                }
            }
        }
        return nil
    }

    private func materialPosition(_ source:SIMD2<Float>,in frame:PaperFrame)->SIMD3<Float>? {
        func cross(_ a:SIMD2<Float>,_ b:SIMD2<Float>)->Float {a.x*b.y-a.y*b.x}
        for f in frame.faces where f.vertices.count>2 {
            let a=f.vertices[0]
            for i in 1..<(f.vertices.count-1) {
                let b=f.vertices[i],c=f.vertices[i+1],u=b.source-a.source,v=c.source-a.source,p=source-a.source,d=cross(u,v)
                if abs(d)<1e-12 {continue}
                let x=cross(p,v)/d,y=cross(u,p)/d
                if x >= -0.0001 && y >= -0.0001 && x+y <= 1.0001 {return a.position+x*(b.position-a.position)+y*(c.position-a.position)}
            }
        }
        return nil
    }
}
