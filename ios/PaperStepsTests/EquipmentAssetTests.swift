import XCTest
import RealityKit
import CryptoKit
@testable import Protacta

@MainActor
final class EquipmentAssetTests: XCTestCase {
    func testBundledCoursesHaveCompleteMappingsAndPackagedLicenseNotices() throws {
        for id in EquipmentTutorialID.allCases {
            let course = try id.load()
            XCTAssertEqual(course.steps.count, id == .gearmotor ? 5 : 6)
            XCTAssertEqual(course.parts.count, id == .gearmotor ? 7 : 11)
            XCTAssertEqual(course.sourceURL?.scheme, "https")
            XCTAssertFalse(course.scope.isEmpty)
            XCTAssertNotNil(course.licenseURL)
            let notice = try XCTUnwrap(course.noticeResource)
            let url = try XCTUnwrap(Bundle.main.url(forResource: notice, withExtension: "txt"))
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(text.contains("Innerscene Corp"))
            XCTAssertTrue(text.contains("Copyright (c) 2026 Dmitry Kulikov"))
            XCTAssertTrue(text.contains("Permission is hereby granted"))
        }
    }

    func testMotorLoadsAllSourceMeshesInMetresAndRetainsTextures() async throws {
        let course = try EquipmentTutorialID.gearmotor.load()
        let entity = try await asset(course, sha256: "cec0d2ec83cbaea70f9aedd62428366d4ad2fd24840c2043d668b0ca9ed54891")
        let extent = entity.visualBounds(relativeTo: nil).extents
        XCTAssertEqual(extent.x, 0.502, accuracy: 0.00001)
        XCTAssertEqual(extent.y, 0.2622, accuracy: 0.00001)
        XCTAssertEqual(extent.z, 0.1999702, accuracy: 0.00001)
        let models = descendants(entity).compactMap { $0 as? ModelEntity }
        XCTAssertEqual(models.count, 20)
        let materials = models.flatMap { $0.model?.materials ?? [] }.compactMap { $0 as? PhysicallyBasedMaterial }
        XCTAssertGreaterThan(materials.filter { $0.baseColor.texture != nil }.count, 0)
        XCTAssertGreaterThan(materials.filter { $0.normal.texture != nil }.count, 0)
        try exercise(course, entity: entity)
    }

    func testTurbofanLoadsElevenIndependentModulesAtSourceScale() async throws {
        let course = try EquipmentTutorialID.turbofan.load()
        let entity = try await asset(course, sha256: "30bf7afdad2ea8370fb011af59a7581d6d24a2c46621b001b31a5dd19385a6bf")
        let extent = entity.visualBounds(relativeTo: nil).extents
        XCTAssertEqual(extent.x, 5, accuracy: 0.0001)
        XCTAssertEqual(extent.z, 2.44, accuracy: 0.0001)
        XCTAssertEqual(descendants(entity).filter { $0 is ModelEntity }.count, 36)
        try exercise(course, entity: entity)
    }

    private func asset(_ course: AssemblyTutorial, sha256: String) async throws -> Entity {
        let url = try XCTUnwrap(Bundle.main.url(forResource: course.assetName, withExtension: "usdz"))
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), sha256)
        let start = ProcessInfo.processInfo.systemUptime
        let entity = try await ProductAsset.load(from: url)
        let time = XCTAttachment(string: "\(course.assetName) Simulator load seconds: \(ProcessInfo.processInfo.systemUptime - start). Not a physical-device performance result.")
        time.name = "\(course.assetName)_simulator_load"; time.lifetime = .keepAlways; add(time)
        return entity
    }

    private func exercise(_ course: AssemblyTutorial, entity: Entity) throws {
        let originalModels = descendants(entity).compactMap { $0 as? ModelEntity }
        let originalMaterialTypes = originalModels.map { model in
            (model.model?.materials ?? []).map { String(reflecting: type(of: $0)) }
        }
        let controller = AssemblySceneController(tutorial: course)
        try controller.bind(entity)
        let origins = try course.parts.map { part -> (Entity, SIMD3<Float>) in
            let node = try XCTUnwrap(entity.findEntity(named: part.entityName))
            return (node, node.position(relativeTo: nil))
        }
        for index in course.steps.indices {
            controller.setStep(index)
            for frame in 0...12 { controller.setProgress(Double(frame) / 12) }
        }
        for (node, origin) in origins {
            XCTAssertLessThan(simd_distance(node.position(relativeTo: nil), origin), 0.00001,
                              "Final reassembly must restore the source pose")
        }
        controller.setExploded(true); controller.setExploded(false)
        controller.select(nil)
        for (index, model) in originalModels.enumerated() {
            XCTAssertEqual((model.model?.materials ?? []).map { String(reflecting: type(of: $0)) }, originalMaterialTypes[index])
        }
        controller.shutdown()
    }

    private func descendants(_ entity: Entity) -> [Entity] { [entity] + entity.children.flatMap { descendants($0) } }
}
