import XCTest
import RealityKit
@testable import Protacta

final class EverydayFabricMaterialsTests: XCTestCase {
    @MainActor
    func testBundledScansLoadWithDataSemanticsMipmapsAndPhysicalScale() throws {
        for fabric in EverydayFabricStyle.allCases {
            let material = try EverydayFabricMaterials.load(fabric)
            let color = try XCTUnwrap(material.baseColor.texture)
            let normal = try XCTUnwrap(material.normal.texture)
            let roughness = try XCTUnwrap(material.roughness.texture)
            XCTAssertEqual(color.resource.semantic, .color)
            XCTAssertEqual(normal.resource.semantic, .normal)
            XCTAssertEqual(roughness.resource.semantic, .scalar)
            for texture in [color, normal, roughness] {
                XCTAssertEqual(texture.resource.width, color.resource.width)
                XCTAssertEqual(texture.resource.height, color.resource.height)
                XCTAssertTrue((1000...1100).contains(texture.resource.width))
                XCTAssertTrue((1000...1100).contains(texture.resource.height))
                XCTAssertGreaterThan(texture.resource.mipmapLevelCount, 1,
                                     "Distance filtering avoids shimmering fine fibres")
                texture.sampler.access { sampler in
                    XCTAssertEqual(sampler.sAddressMode, .repeat)
                    XCTAssertEqual(sampler.tAddressMode, .repeat)
                    XCTAssertEqual(sampler.mipFilter, .linear)
                }
            }
            XCTAssertEqual(material.textureCoordinateTransform.scale,
                           SIMD2<Float>(repeating: 1) / fabric.tileSizeMetres)
            XCTAssertEqual(material.roughness.scale, 1)
        }
    }

    @MainActor
    func testFabricSelectionDoesNotPutClothOnRopesWithTheSamePaletteIndex() throws {
        for fabric in EverydayFabricStyle.allCases {
            XCTAssertNotNil(EverydayFabricMaterials.material(for: fabric)?.baseColor.texture)
        }
        for id in [EverydayTutorialID.towel, .tShirt, .flatBedsheet] {
            for part in EverydayMeshGeometry.parts(courseID: id, actionIndex: 0, progress: 0) {
                XCTAssertNotNil(EverydayFabricStyle.fabric(forPartID: part.id))
            }
        }
        for part in EverydayMeshGeometry.parts(courseID: .squareKnot, actionIndex: 0, progress: 0) {
            XCTAssertNil(EverydayFabricStyle.fabric(forPartID: part.id))
        }
    }

    func testWovenTieRetainsTeachingColorsAndStableMaterialCoordinates() throws {
        let start = EverydayMeshGeometry.parts(courseID: .fourInHand, actionIndex: 0, progress: 0)
        for action in 0..<7 {
            for progress in [0.0, 0.35, 0.7, 1.0] {
                let parts = EverydayMeshGeometry.parts(courseID: .fourInHand, actionIndex: action, progress: progress)
                for part in parts where !part.id.hasPrefix("tie-collar-") {
                    XCTAssertEqual(EverydayFabricStyle.fabric(forPartID: part.id), .linen)
                    XCTAssertEqual(EverydayFabricStyle.tint(forPartID: part.id, colorIndex: part.colorIndex),
                                   EverydaySurfaceStyle.color(index: part.colorIndex))
                    let uvs = try XCTUnwrap(part.fabricUVs)
                    XCTAssertEqual(uvs.count, part.positions.count)
                    XCTAssertTrue(uvs.allSatisfy { $0.x.isFinite && $0.y.isFinite })
                    XCTAssertGreaterThan(Set(uvs.map { "\($0.x),\($0.y)" }).count, 20)
                    XCTAssertEqual(uvs, start.first { $0.id == part.id }?.fabricUVs,
                                   "Weave must stay attached when a ribbon tightens or the timeline reverses")
                }
            }
        }
        for (id, index) in [("towel_soft_body", 0), ("shirt_body", 1), ("sheet_linen", 3)] {
            XCTAssertEqual(EverydayFabricStyle.tint(forPartID: id, colorIndex: index), SIMD3(repeating: 1))
        }
    }
}
