import Foundation
import simd

/// Shared by the live teaching models and their offline catalog portraits.
/// A quiet matte finish keeps fold silhouettes readable in both contexts.
enum EverydaySurfaceStyle {
    static let roughness: Float = 0.94

    static func color(index: Int) -> SIMD3<Float> {
        let palette: [SIMD3<Float>] = [
            [0.91, 0.91, 0.91], // White towel fallback
            [0.20, 0.46, 0.69], // Shirt / first rope
            [0.82, 0.37, 0.17], // Second rope
            [0.91, 0.91, 0.91], // White bed linen
            [0.16, 0.23, 0.29]  // Necktie
        ]
        return palette[min(palette.count - 1, max(0, index))]
    }
}
