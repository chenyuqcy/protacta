import Foundation
import RealityKit
import UIKit
import XCTest
@testable import Protacta

/// Checks actual generated mesh contents against the cache-disabled renderer.
/// Local timing measures synchronous pose work, not real-camera frame rate or
/// hand-occlusion quality.
@MainActor
final class PaperModelCachingTests: XCTestCase {
    private let movingCases: [(OrigamiLesson, Int)] = [(.dart, 1), (.crane, 12), (.elephant, 24)]

    func testRepeatedNormalizedPoseSkipsWorkAfterFirstSuccessfulRender() {
        let cached = PaperModel()
        let reference = PaperModel(meshReuseEnabled: false)
        XCTAssertGreaterThan(cached.diagnostics.meshGenerationCalls, 0, "Initialization must build the first visible sheet")
        XCTAssertTrue(cached.root.children.contains { $0.isEnabled && ($0 as? ModelEntity)?.model != nil })
        cached.setPose(lesson: .dart, step: 1, progress: 0.4)
        reference.setPose(lesson: .dart, step: 1, progress: 0.4)
        cached.resetDiagnostics()
        for _ in 0..<12 { cached.setPose(lesson: .dart, step: 1, progress: 0.4) }
        XCTAssertEqual(cached.diagnostics.poseEvaluations, 0)
        XCTAssertEqual(cached.diagnostics.meshGenerationCalls, 0)
        XCTAssertEqual(cached.diagnostics.identicalPoseSkips, 12)
        assertEquivalent(cached, reference)

        cached.setPose(lesson: .dart, step: 1, progress: 0)
        reference.setPose(lesson: .dart, step: 1, progress: 0)
        cached.resetDiagnostics()
        for value: Float in [-1, .nan, .infinity, -.infinity] {
            cached.setPose(lesson: .dart, step: 1, progress: value)
        }
        XCTAssertEqual(cached.diagnostics.poseEvaluations, 0)
        XCTAssertEqual(cached.diagnostics.identicalPoseSkips, 4)
        assertEquivalent(cached, reference)
    }

    func testMovingMeshesMatchReferenceThroughReplayAndHintChanges() {
        let cached = PaperModel()
        let reference = PaperModel(meshReuseEnabled: false)
        for (lesson, step) in movingCases {
            // Move forward, scrub back, replay, and reach the end of the fold.
            for progress: Float in [0, 0.2, 0.47, 0.8, 1, 0.47, 0, 1] {
                cached.setPose(lesson: lesson, step: step, progress: progress)
                reference.setPose(lesson: lesson, step: step, progress: progress)
                for hints in [true, false, true] {
                    cached.showHints(hints)
                    reference.showHints(hints)
                    assertEquivalent(cached, reference)
                    XCTAssertLessThanOrEqual(cached.diagnostics.cachedMeshCount, 8)
                }
            }
        }
        XCTAssertGreaterThan(cached.diagnostics.meshReuses, 0)
    }

    func testLessonSwitchesAndFinalHintSuppressionMatchReference() {
        let cached = PaperModel()
        let reference = PaperModel(meshReuseEnabled: false)
        for lesson in OrigamiLesson.allCases {
            for step in [0, lesson.lastStep] {
                for hints in [false, true] {
                    cached.setPose(lesson: lesson, step: step, progress: 1)
                    reference.setPose(lesson: lesson, step: step, progress: 1)
                    cached.showHints(hints)
                    reference.showHints(hints)
                    assertEquivalent(cached, reference)
                    XCTAssertEqual(cached.root.name, lesson.title)
                    XCTAssertLessThanOrEqual(cached.diagnostics.cachedMeshCount, 8)
                }
            }
        }
    }

    func testReusedStaticMeshRestoresAuthoritativeMaterialAndVisibility() throws {
        let cached = PaperModel()
        let reference = PaperModel(meshReuseEnabled: false)
        cached.setPose(lesson: .dart, step: 1, progress: 0.25)
        let front = try XCTUnwrap(cached.root.findEntity(named: "Paper front") as? ModelEntity)
        let originalMesh = try XCTUnwrap(front.model?.mesh)
        front.model = ModelComponent(mesh: originalMesh,
                                     materials: [SimpleMaterial(color: .blue, isMetallic: true)])
        front.isEnabled = false
        cached.resetDiagnostics()
        cached.setPose(lesson: .dart, step: 1, progress: 0.5)
        reference.setPose(lesson: .dart, step: 1, progress: 0.5)
        XCTAssertTrue(front.model?.mesh === originalMesh, "The unchanged sheet region should reuse its mesh resource")
        XCTAssertGreaterThan(cached.diagnostics.meshReuses, 0)
        assertEquivalent(cached, reference)
    }

    func testBenchmarkExactMeshReuseOnSimpleAndComplexMovingFolds() throws {
        var rows: [[String: Any]] = []
        var totalCachedCalls = 0
        var totalReferenceCalls = 0
        for (lesson, step) in movingCases {
            var cachedRuns = [Double](), referenceRuns = [Double]()
            var cachedCalls = 0, referenceCalls = 0, reused = 0
            for round in 0..<3 {
                // Alternate order, exclude initialization/warm-up, and animate
                // distinct progresses so duplicate-pose skipping cannot inflate
                // the moving-fold benchmark.
                for enabled in round.isMultiple(of: 2) ? [false, true] : [true, false] {
                    let model = PaperModel(meshReuseEnabled: enabled)
                    model.setPose(lesson: lesson, step: step, progress: 0)
                    model.resetDiagnostics()
                    let start = ProcessInfo.processInfo.systemUptime
                    for sample in 1...24 {
                        model.setPose(lesson: lesson, step: step, progress: Float(sample) / 25)
                    }
                    let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
                    let counters = model.diagnostics
                    XCTAssertEqual(counters.poseEvaluations, 24)
                    XCTAssertEqual(counters.identicalPoseSkips, 0)
                    XCTAssertLessThanOrEqual(counters.cachedMeshCount, enabled ? 8 : 0)
                    if enabled {
                        cachedRuns.append(milliseconds)
                        cachedCalls += counters.meshGenerationCalls
                        reused += counters.meshReuses
                    } else {
                        referenceRuns.append(milliseconds)
                        referenceCalls += counters.meshGenerationCalls
                    }
                }
            }
            totalCachedCalls += cachedCalls
            totalReferenceCalls += referenceCalls
            rows.append([
                "lesson": lesson.rawValue, "step": step, "distinctPosesPerRun": 24, "runs": 3,
                "cachedRunMilliseconds": cachedRuns, "referenceRunMilliseconds": referenceRuns,
                "cachedMedianMillisecondsPerPose": cachedRuns.sorted()[1] / 24,
                "referenceMedianMillisecondsPerPose": referenceRuns.sorted()[1] / 24,
                "cachedMeshGenerationCalls": cachedCalls, "referenceMeshGenerationCalls": referenceCalls,
                "exactMeshReuses": reused
            ])
        }
        XCTAssertLessThan(totalCachedCalls, totalReferenceCalls, "Moving folds should avoid some unchanged resource generations")
        let report: [String: Any] = [
            "scope": "Local XCTest synchronous pose and mesh-generation work; not GPU frame time or real-camera AR acceptance",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "cases": rows,
            "timingAssertions": "None; recorded timings are observations, not a flaky pass/fail threshold"
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "paper-mesh-reuse-benchmark.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("PAPER_MESH_REUSE_BENCHMARK\n\(String(decoding: data, as: UTF8.self))")
    }

    private func assertEquivalent(_ cached: PaperModel, _ reference: PaperModel,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(cached.root.children.count, reference.root.children.count, file: file, line: line)
        XCTAssertEqual(cached.bounds.minimum, reference.bounds.minimum, file: file, line: line)
        XCTAssertEqual(cached.bounds.maximum, reference.bounds.maximum, file: file, line: line)
        XCTAssertEqual(cached.framingBounds.minimum, reference.framingBounds.minimum, file: file, line: line)
        XCTAssertEqual(cached.framingBounds.maximum, reference.framingBounds.maximum, file: file, line: line)
        for (left, right) in zip(cached.root.children, reference.root.children) {
            XCTAssertEqual(left.name, right.name, file: file, line: line)
            XCTAssertEqual(left.isEnabled, right.isEnabled, left.name, file: file, line: line)
            guard left.isEnabled else { continue }
            guard let leftModel = (left as? ModelEntity)?.model,
                  let rightModel = (right as? ModelEntity)?.model else {
                XCTFail("Missing enabled model: \(left.name)", file: file, line: line); continue
            }
            let leftParts = leftModel.mesh.contents.models.flatMap { Array($0.parts) }
            let rightParts = rightModel.mesh.contents.models.flatMap { Array($0.parts) }
            XCTAssertEqual(leftParts.count, rightParts.count, left.name, file: file, line: line)
            for (a, b) in zip(leftParts, rightParts) {
                XCTAssertEqual(a.positions.elements, b.positions.elements, left.name, file: file, line: line)
                XCTAssertEqual(a.normals?.elements, b.normals?.elements, left.name, file: file, line: line)
                XCTAssertEqual(a.triangleIndices?.elements, b.triangleIndices?.elements, left.name, file: file, line: line)
                XCTAssertEqual(a.materialIndex, b.materialIndex, left.name, file: file, line: line)
            }
            XCTAssertEqual(leftModel.materials.count, rightModel.materials.count, file: file, line: line)
            for (a, b) in zip(leftModel.materials, rightModel.materials) {
                if let a = a as? SimpleMaterial, let b = b as? SimpleMaterial {
                    XCTAssertEqual(a.color.tint, b.color.tint, left.name, file: file, line: line)
                    XCTAssertEqual(a.roughness, b.roughness, left.name, file: file, line: line)
                    XCTAssertEqual(a.metallic, b.metallic, left.name, file: file, line: line)
                } else if let a = a as? UnlitMaterial, let b = b as? UnlitMaterial {
                    XCTAssertEqual(a.color.tint, b.color.tint, left.name, file: file, line: line)
                } else {
                    XCTFail("Changed material type: \(left.name)", file: file, line: line)
                }
            }
        }
    }
}
