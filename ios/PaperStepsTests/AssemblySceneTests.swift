import XCTest
import RealityKit
@testable import Protacta

@MainActor
final class AssemblySceneTests: XCTestCase {
    func testExporterRotationUsesStudioOffsetsAndReplayDoesNotAccumulate() throws {
        let asset = fixture()
        let cover = try XCTUnwrap(asset.findEntity(named: "Rear_Cover"))
        let filter = try XCTUnwrap(asset.findEntity(named: "Filter_Cartridge"))
        let coverOrigin = cover.position(relativeTo: nil)
        let filterOrigin = filter.position(relativeTo: nil)
        let controller = AssemblySceneController(tutorial: .aeris)
        try controller.bind(asset)
        controller.setProgress(1)
        assertClose(cover.position(relativeTo: nil), coverOrigin + [0, 0, -0.43])
        let end = cover.transform
        controller.setStep(1)
        assertClose(cover.transform.translation, end.translation)
        assertClose(filter.position(relativeTo: nil), filterOrigin)
        controller.setProgress(1)
        assertClose(filter.position(relativeTo: nil), filterOrigin + [0, 0, -0.24])
        controller.setProgress(0.4)
        let poseBeforeInspection = filter.transform
        controller.setExploded(true)
        XCTAssertEqual(controller.progress, 0.4)
        controller.setExploded(false)
        assertClose(filter.transform.translation, poseBeforeInspection.translation)
        for _ in 0..<8 { controller.setProgress(0); controller.setProgress(1) }
        assertClose(filter.position(relativeTo: nil), filterOrigin + [0, 0, -0.24])
        controller.setStep(2); controller.setProgress(1)
        assertClose(cover.position(relativeTo: nil), coverOrigin)
        assertClose(filter.position(relativeTo: nil), filterOrigin)
        controller.setProgress(.nan); XCTAssertEqual(controller.progress, 0)
        controller.setProgress(.infinity); XCTAssertEqual(controller.progress, 0)
        controller.shutdown()
    }

    func testSelectingDescendantFramesOnlyItsPartWithoutChangingMaterials() throws {
        let asset = fixture()
        let cover = try XCTUnwrap(asset.findEntity(named: "Rear_Cover") as? ModelEntity)
        let filter = try XCTUnwrap(asset.findEntity(named: "Filter_Cartridge") as? ModelEntity)
        let originalCover = try XCTUnwrap(cover.model?.materials.first as? SimpleMaterial).color.tint
        let originalFilter = try XCTUnwrap(filter.model?.materials.first as? SimpleMaterial).color.tint
        let controller = AssemblySceneController(tutorial: .aeris)
        try controller.bind(asset)
        let child = Entity(); filter.addChild(child)
        controller.select(entity: child)
        XCTAssertEqual(controller.selectedPartID, "filter")
        XCTAssertEqual((cover.model?.materials.first as? SimpleMaterial)?.color.tint, originalCover)
        XCTAssertEqual((filter.model?.materials.first as? SimpleMaterial)?.color.tint, originalFilter)
        XCTAssertEqual(filter.findEntity(named: "__ProtactaPartHighlight")?.children.count, 12)
        XCTAssertNil(cover.findEntity(named: "__ProtactaPartHighlight"))
        let overviewRadius = controller.framing.radius
        controller.focusSelectedPart()
        XCTAssertTrue(controller.isPartFocused)
        XCTAssertLessThan(controller.framing.radius, overviewRadius)
        controller.resetCameraView()
        XCTAssertEqual(controller.framing.radius, overviewRadius)
        controller.select(nil)
        XCTAssertNil(controller.selectedPartID)
        XCTAssertNil(filter.findEntity(named: "__ProtactaPartHighlight"))
        XCTAssertEqual((filter.model?.materials.first as? SimpleMaterial)?.color.tint, originalFilter)
        controller.select("unknown")
        XCTAssertNil(controller.selectedPartID)
        controller.shutdown()
    }

    func testMissingAmbiguousNestedAndEmptyPartsRejectBeforeReplacingWorkingModel() throws {
        let controller = AssemblySceneController(tutorial: .aeris)
        let valid = fixture(); try controller.bind(valid)
        let duplicate = fixture()
        let extra = Entity(); extra.name = "Rear_Cover"; duplicate.addChild(extra)
        XCTAssertThrowsError(try controller.bind(duplicate))
        XCTAssertTrue(valid.parent === controller.root)
        let nested = fixture()
        let cover = try XCTUnwrap(nested.findEntity(named: "Rear_Cover"))
        cover.addChild(try XCTUnwrap(nested.findEntity(named: "Filter_Cartridge")))
        XCTAssertThrowsError(try controller.bind(nested))
        let missing = fixture()
        missing.findEntity(named: "Base_Assembly")?.removeFromParent()
        XCTAssertThrowsError(try controller.bind(missing))
        let empty = fixture()
        (empty.findEntity(named: "Top_Assembly") as? ModelEntity)?.model = nil
        XCTAssertThrowsError(try controller.bind(empty))
        XCTAssertTrue(valid.parent === controller.root)
        controller.shutdown()
    }

    func testInvalidAuthoringDataRejectsUnknownPartAndNonfiniteMotion() {
        let base = AssemblyTutorial.aeris
        for offsets: [String: SIMD3<Float>] in [["missing": [0, 0, 1]], ["cover": [.nan, 0, 0]]] {
            let bad = AssemblyTutorial(title: base.title, assetName: base.assetName, attribution: base.attribution,
                parts: base.parts, steps: [.init(id: "invalid", title: "Invalid", instruction: "", focusID: "cover", offsets: offsets)])
            XCTAssertThrowsError(try bad.validate())
        }
    }

    func testBorrowedRendererSurvivesLayoutChangesAndCanReturnToProductModule() throws {
        let original = ProductSceneController()
        let borrowed = original.makeView()
        original.shutdown()
        let controller = AssemblySceneController(tutorial: .aeris, sharedView: borrowed)
        try controller.bind(fixture())
        XCTAssertTrue(controller.makeView() === borrowed)
        let container = AssemblyViewportContainer(renderer: controller.renderer, view: borrowed)
        for size in [CGSize(width: 390, height: 240), CGSize(width: 390, height: 650)] {
            container.frame.size = size; container.setNeedsLayout(); container.layoutIfNeeded()
            XCTAssertEqual(borrowed.bounds.size, size)
            XCTAssertEqual(borrowed.scene.anchors.count, 1)
        }
        XCTAssertTrue(original.makeView() === borrowed)
        let restoredGestures = (borrowed.gestureRecognizers ?? []).map(ObjectIdentifier.init)
        controller.shutdown()
        XCTAssertEqual((borrowed.gestureRecognizers ?? []).map(ObjectIdentifier.init), restoredGestures,
                       "Late explorer cleanup must not remove the product module's replacement gestures")
        XCTAssertEqual(borrowed.scene.anchors.count, 1)
        original.shutdown()
    }

    func testBundledUSDZHasIndependentPartsAndCanUseSharedStudio() async throws {
        let controller = AssemblySceneController(tutorial: .aeris)
        await controller.load()
        XCTAssertTrue(controller.isLoaded, controller.failure ?? "No load error reported")
        XCTAssertNil(controller.failure)
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 500)
        controller.renderer.updateLayout()
        XCTAssertEqual(view.scene.anchors.count, 1)
        for index in AssemblyTutorial.aeris.steps.indices {
            controller.setStep(index)
            for frame in 0...10 { controller.setProgress(Double(frame) / 10) }
        }
        controller.setExploded(true); controller.setExploded(false)
        controller.renderer.setActive(false)
        XCTAssertEqual(view.scene.anchors.count, 0)
        controller.renderer.setActive(true)
        XCTAssertEqual(view.scene.anchors.count, 1)
        controller.shutdown()
        XCTAssertNil(controller.renderer.view)
        XCTAssertTrue(controller.root.children.isEmpty)
    }

    private func fixture() -> Entity {
        let asset = Entity()
        let conversion = Entity()
        conversion.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        conversion.scale = [0.7, 0.7, 0.7]
        asset.addChild(conversion)
        for (index, part) in AssemblyTutorial.aeris.parts.enumerated() {
            let entity = ModelEntity(mesh: .generateBox(size: 0.1), materials: [SimpleMaterial(color: .blue, isMetallic: false)])
            entity.name = part.entityName
            entity.position = [Float(index) * 0.12, 0, 0]
            conversion.addChild(entity)
        }
        return asset
    }

    private func assertClose(_ a: SIMD3<Float>, _ b: SIMD3<Float>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(simd_distance(a, b), 0.00001, file: file, line: line)
    }
}
