import XCTest
import simd
@testable import Protacta

/// Source continuity and action regression checks. The final body opening is
/// a bounded flexible forming model; it is deliberately not checked as rigid.
final class ElephantCompleteGeometryTests: XCTestCase {
    func testFullSequencePreservesFiniteSourceSquare() {
        XCTAssertEqual(ElephantAssemblyGeometry.lastStep,40)
        XCTAssertEqual(ElephantFinalContent.steps.map(\.id),Array(0...40))
        for step in 0...40 { for sample in 0...8 {
            let frame=ElephantAssemblyGeometry.frame(step:step,progress:Float(sample)/8)
            var sourceArea:Float=0
            for face in frame.faces {
                XCTAssertGreaterThanOrEqual(face.vertices.count,3)
                let origin=face.vertices[0].source
                for i in 1..<(face.vertices.count-1) {
                    let b=face.vertices[i].source-origin,c=face.vertices[i+1].source-origin
                    sourceArea+=abs(b.x*c.y-b.y*c.x)/2
                }
                for a in face.vertices {
                    XCTAssertTrue(a.position.x.isFinite && a.position.y.isFinite && a.position.z.isFinite)
                    XCTAssertGreaterThanOrEqual(a.position.y,-0.000001)
                    XCTAssertTrue(a.source.x >= -0.000001 && a.source.x <= 0.200001)
                    XCTAssertTrue(abs(a.source.y) <= 0.100001)
                    for b in face.vertices {
                        let length=simd_distance(a.source,b.source),actual=simd_distance(a.position,b.position)
                        if step == 40 {
                            if length>0.0001 {XCTAssertLessThan(abs(actual-length)/length,0.011)}
                        } else {XCTAssertEqual(actual,length,accuracy:0.00002)}
                    }
                }
            }
            XCTAssertEqual(sourceArea,0.04,accuracy:0.0000004)
            XCTAssertEqual(frame.area,0.04,accuracy:step == 40 ? 0.0004:0.0000004)
        }}
    }
    func testSharedMaterialAndSplitEdgesRemainJoined() {
        for step in 0...40 {for progress:Float in [0,0.5,1] {
            let frame=ElephantAssemblyGeometry.frame(step:step,progress:progress)
            for v in frame.faces.flatMap(\.vertices) {for face in frame.faces {for j in face.vertices.indices {
                let a=face.vertices[j],b=face.vertices[(j+1)%face.vertices.count]
                if simd_distance(v.source,a.source)<1e-7 {XCTAssertLessThan(simd_distance(v.position,a.position),0.00002)}
                let d=b.source-a.source,l2=simd_length_squared(d)
                if l2<1e-14 {continue}
                let t=simd_dot(v.source-a.source,d)/l2
                if t>0.00001 && t<0.99999 && simd_distance(v.source,a.source+d*t)<0.00000015 {
                    XCTAssertLessThan(simd_distance(v.position,a.position+(b.position-a.position)*t),0.00002,"Split edge at action \(step)")
                }
            }}}
        }}
    }
    func testActionBoundariesKeepTheSamePaper() {
        for step in 1...40 {
            let previous=ElephantAssemblyGeometry.frame(step:step-1,progress:1)
            let next=ElephantAssemblyGeometry.frame(step:step,progress:0)
            for v in previous.faces.flatMap(\.vertices) {
                guard let position=point(v.source,in:next) else {XCTFail("Missing source material at action \(step)");continue}
                XCTAssertLessThan(simd_distance(v.position,position),0.00002,"Boundary \(step)")
            }
        }
    }
    func testTrunkArrowsMoveAndCompletedAnimalStandsAboveTable() {
        for step in 33...39 {for progress:Float in [0.25,0.5,0.75] {
            let frame=ElephantAssemblyGeometry.frame(step:step,progress:progress)
            XCTAssertFalse(frame.actionPaths.isEmpty,"Action \(step)")
            for path in frame.actionPaths {
                guard let first=path.first else {XCTFail("Empty path");continue}
                XCTAssertGreaterThan(path.map {simd_distance($0,first)}.max() ?? 0,0.001)
                XCTAssertTrue(path.allSatisfy {$0.x.isFinite && $0.y.isFinite && $0.z.isFinite})
            }
        }}
        let frame=ElephantAssemblyGeometry.frame(step:40,progress:1)
        let size=frame.bounds.maximum-frame.bounds.minimum
        // The 20 cm sheet folds down to a roughly 7.3 × 6.0 cm animal.
        XCTAssertGreaterThan(size.x,0.06);XCTAssertGreaterThan(size.y,0.05);XCTAssertGreaterThan(size.z,0.01)
    }
    func testSurfaceDisplayNeverChangesPhysicalPaperOrCues() {
        for step in [0,9,20,27,28,30,32,33,36,37,39,40] {for p:Float in [0,0.5,1] {
            let a=ElephantAssemblyGeometry.frame(step:step,progress:p),b=ElephantRenderSurface.apply(to:a)
            XCTAssertEqual(a.area,b.area);XCTAssertEqual(a.actionPaths,b.actionPaths)
            XCTAssertEqual(a.faces.count,b.faces.count)
            for (f,g) in zip(a.faces,b.faces) {for (v,w) in zip(f.vertices,g.vertices) {
                XCTAssertEqual(v.source,w.source);XCTAssertEqual(v.position,w.position)
                XCTAssertLessThanOrEqual(simd_length(w.separation),0.00066)
            }}
        }}
    }
    private func point(_ source:SIMD2<Float>,in frame:PaperFrame)->SIMD3<Float>? {
        func cross(_ a:SIMD2<Float>,_ b:SIMD2<Float>)->Float {a.x*b.y-a.y*b.x}
        for face in frame.faces {
            let a=face.vertices[0]
            for i in 1..<(face.vertices.count-1) {
                let b=face.vertices[i],c=face.vertices[i+1],u=b.source-a.source,v=c.source-a.source,q=source-a.source,d=cross(u,v)
                if abs(d)<1e-12 {continue}
                let x=cross(q,v)/d,y=cross(u,q)/d
                if x >= -1e-5 && y >= -1e-5 && x+y <= 1.00001 {return a.position+x*(b.position-a.position)+y*(c.position-a.position)}
            }
        }
        return nil
    }
}
