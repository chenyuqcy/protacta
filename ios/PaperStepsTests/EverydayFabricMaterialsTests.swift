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
        for id in [EverydayTutorialID.squareKnot, .fourInHand] {
            for part in EverydayMeshGeometry.parts(courseID: id, actionIndex: 0, progress: 0) {
                XCTAssertNil(EverydayFabricStyle.fabric(forPartID: part.id))
            }
        }
    }
}
