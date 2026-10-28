import Foundation
import RealityKit
import UIKit
import simd

/// One mesh renderer is used unchanged in the studio and the AR scene. The
/// controller drives progress; replay never substitutes a static model or image.
@MainActor
final class PaperModel {
    struct Diagnostics {
        let poseEvaluations: Int
        let identicalPoseSkips: Int
        let meshGenerationCalls: Int
        let meshReuses: Int
        let cachedMeshCount: Int
        let lastPoseMilliseconds: Double
    }

    let root = Entity()
    private let front = ModelEntity()
    private let back = ModelEntity()
    private let activeFront = ModelEntity()
    private let activeBack = ModelEntity()
    private let edges = ModelEntity()
    private let activeEdges = ModelEntity()
    private let crease = ModelEntity()
    private let arrow = ModelEntity()
    private(set) var hintVisibility = true
    private(set) var frame = PaperGeometry.frame(step: 0, progress: 0)
    private var currentStep = 0
    private var currentProgress: Float = 0
    private var currentLesson: OrigamiLesson = .dart
    private let meshReuseEnabled: Bool
    private var lastPoseRenderedSuccessfully = false
    private struct CachedMesh {
        let payload: PaperMeshBuilder
        let resource: MeshResource
    }
    // Exactly one last payload per existing render entity, never a history of
    // lesson poses. A changing payload replaces the previous entry.
    private var meshCache: [ObjectIdentifier: CachedMesh] = [:]
    private var poseEvaluations = 0
    private var identicalPoseSkips = 0
    private var meshGenerationCalls = 0
    private var meshReuses = 0
    private var lastPoseMilliseconds: Double = 0

    var diagnostics: Diagnostics {
        Diagnostics(poseEvaluations: poseEvaluations, identicalPoseSkips: identicalPoseSkips,
                    meshGenerationCalls: meshGenerationCalls, meshReuses: meshReuses,
                    cachedMeshCount: meshCache.count, lastPoseMilliseconds: lastPoseMilliseconds)
    }

    /// Resets measurements without flushing the small, warm mesh cache.
    func resetDiagnostics() {
        poseEvaluations = 0; identicalPoseSkips = 0
        meshGenerationCalls = 0; meshReuses = 0; lastPoseMilliseconds = 0
    }

    /// Paper-only bounds used for the AR gesture hit target.
    var bounds: (minimum: SIMD3<Float>, maximum: SIMD3<Float>) { frame.bounds }
    var framingBounds: (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        var result = frame.bounds
        let span = simd_length(result.maximum - result.minimum)
        let scale = min(Float(1), max(Float(0.12), span / 0.25))
        func include(_ point: SIMD3<Float>, padding: Float) {
            guard point.x.isFinite && point.y.isFinite && point.z.isFinite else { return }
            result.minimum = simd_min(result.minimum, point - SIMD3(repeating: padding))
            result.maximum = simd_max(result.maximum, point + SIMD3(repeating: padding))
        }
        for face in frame.faces {
            for vertex in face.vertices {
                include(vertex.position + vertex.separation, padding: max(0.00002, 0.00042 * scale))
            }
        }
        if hintVisibility && !(currentStep == currentLesson.lastStep && currentProgress >= 0.999) {
            if let crease = frame.crease {
                include(crease.start, padding: 0.00068 * scale)
                include(crease.end, padding: 0.00068 * scale)
            }
            for path in frame.actionPaths where path.count > 1 {
                let headIndex = max(1, path.count - 7)
                for point in path.prefix(headIndex + 1) { include(point, padding: 0.001 * scale) }
                let delta = path[headIndex] - path[headIndex - 1]
                if simd_length_squared(delta) > 1e-14 {
                    let direction = simd_normalize(delta)
                    include(path[headIndex] - direction * (0.003 * scale), padding: 0.0052 * scale)
                    include(path[headIndex] + direction * (0.010 * scale), padding: 0)
                }
            }
        }
        return result
    }

    private let white = SimpleMaterial(color: UIColor(red: 0.99, green: 0.985, blue: 0.967, alpha: 1),
                                       roughness: 0.83, isMetallic: false)
    private let ivory = SimpleMaterial(color: UIColor(red: 0.91, green: 0.90, blue: 0.85, alpha: 1),
                                       roughness: 0.90, isMetallic: false)
    private let blushFront = SimpleMaterial(color: UIColor(red: 1, green: 0.86, blue: 0.82, alpha: 1),
                                            roughness: 0.83, isMetallic: false)
    private let blushBack = SimpleMaterial(color: UIColor(red: 0.96, green: 0.77, blue: 0.71, alpha: 1),
                                           roughness: 0.90, isMetallic: false)
    private let edgeMaterial = UnlitMaterial(color: UIColor(red: 0.48, green: 0.49, blue: 0.45, alpha: 1))
    private let teal = UnlitMaterial(color: UIColor(red: 0.02, green: 0.49, blue: 0.46, alpha: 1))
    private let red = UnlitMaterial(color: UIColor(red: 0.95, green: 0.22, blue: 0.19, alpha: 1))

    /// Disabling reuse is an internal reference path for equivalence tests and
    /// local benchmarks, not a user setting or a different animation model.
    init(meshReuseEnabled: Bool = true) {
        self.meshReuseEnabled = meshReuseEnabled
        root.name = "Folded A4 Paper"
        // This is a local lesson. Dynamic paper meshes do not participate in
        // peer synchronization or its queued asset-sharing lifecycle.
        root.synchronization = nil
        for (name, entity) in [("Paper front", front), ("Paper reverse", back),
                               ("Moving flap front", activeFront), ("Moving flap reverse", activeBack),
                               ("Paper edges", edges), ("Moving flap outline", activeEdges),
                               ("Crease guide", crease), ("Fold direction", arrow)] {
            entity.name = name
            entity.synchronization = nil
            root.addChild(entity)
        }
        setPose(step: 0, progress: 0)
        setGroundingShadowsEnabled(true)
        if #available(iOS 18.0, *) {
            // Guides are annotations, so they must not cast artificial shadows
            // onto the paper or the physical table beneath it.
            for entity in [edges, activeEdges, crease, arrow] {
                entity.components.set(GroundingShadowComponent(castsShadow: false, receivesShadow: false))
            }
        }
    }

    /// Studio lighting gives the folds depth; camera AR must not darken real
    /// objects where the teaching model intersects them. This changes lighting
    /// participation only, preserving the current pose and cached mesh resources.
    func setGroundingShadowsEnabled(_ enabled: Bool) {
        if #available(iOS 18.0, *) {
            for entity in [front, back, activeFront, activeBack] {
                entity.components.set(GroundingShadowComponent(castsShadow: enabled, receivesShadow: enabled,
                                                                 fadeBehaviorNearPhysicalObjects: .constant))
            }
        }
    }

    func setPose(lesson: OrigamiLesson = .dart, step: Int, progress: Float) {
        let normalizedStep = max(0, min(lesson.lastStep, step))
        let normalizedProgress = progress.isFinite ? max(0, min(1, progress)) : 0
        if meshReuseEnabled, lastPoseRenderedSuccessfully,
           lesson == currentLesson, normalizedStep == currentStep, normalizedProgress == currentProgress {
            identicalPoseSkips += 1
            return
        }
        let start = ProcessInfo.processInfo.systemUptime
        currentLesson = lesson
        root.name = lesson.title
        currentStep = normalizedStep
        currentProgress = normalizedProgress
        poseEvaluations += 1
        frame = lesson.frame(step: currentStep, progress: currentProgress)
        rebuild()
        lastPoseMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
    }

    func showHints(_ visible: Bool) {
        guard hintVisibility != visible else { return }
        hintVisibility = visible
        rebuild()
    }

    private func rebuild() {
        lastPoseRenderedSuccessfully = true
        var frontMesh = PaperMeshBuilder(), backMesh = PaperMeshBuilder()
        var movingFront = PaperMeshBuilder(), movingBack = PaperMeshBuilder()
        var edgeMesh = PaperMeshBuilder(), movingEdgeMesh = PaperMeshBuilder()
        let visibleHints = hintVisibility && !(currentStep == currentLesson.lastStep && currentProgress >= 0.999)
        // The star's contact-aware surface joins at an ideal zero-thickness
        // rim. Extruding both sides there would intersect adjacent layers.
        let thickness: Float = (currentLesson == .star || currentLesson == .fullFox) ? 0 : 0.00002
        let span = simd_length(frame.bounds.maximum - frame.bounds.minimum)
        let guideScale = min(Float(1), max(Float(0.12), span / 0.25))
        let sourcePoints = frame.faces.flatMap { $0.vertices.map(\.source) }
        let sourceMin = sourcePoints.reduce(SIMD2<Float>(repeating: .greatestFiniteMagnitude), simd_min)
        let sourceMax = sourcePoints.reduce(SIMD2<Float>(repeating: -.greatestFiniteMagnitude), simd_max)

        let smoothNormals = currentLesson == .star
            ? StarGeometry.smoothPinchNormals(for: frame, step: currentStep, progress: currentProgress) : nil
        for (faceIndex, face) in frame.faces.enumerated() {
            let normal = face.normal
            let cornerNormals = smoothNormals?[faceIndex]
            let reverseNormals = cornerNormals.map { $0.reversed().map { -$0 } }
            let positive = face.vertices.map { $0.position + $0.separation + normal * thickness }
            let negative = face.vertices.map { $0.position + $0.separation - normal * thickness }
            let moving = face.isMoving && visibleHints
            if moving {
                movingFront.polygon(positive, normal: normal, vertexNormals: cornerNormals)
                movingBack.polygon(Array(negative.reversed()), normal: -normal, vertexNormals: reverseNormals)
            } else {
                frontMesh.polygon(positive, normal: normal, vertexNormals: cornerNormals)
                backMesh.polygon(Array(negative.reversed()), normal: -normal, vertexNormals: reverseNormals)
            }

            for i in positive.indices {
                if let mask = face.outlinedEdges, i < mask.count, !mask[i] { continue }
                let j = (i + 1) % positive.count
                let a = (positive[i] + negative[i]) / 2
                let b = (positive[j] + negative[j]) / 2
                // A freshly prepared sheet has an outline, without exposing the
                // triangle network used to animate later squash/pinch motions.
                if currentStep == 0 && face.outlinedEdges == nil {
                    let p = face.vertices[i].source, q = face.vertices[j].source
                    var onBoundary = false
                    for axis in 0..<2 {
                        let atMinimum = abs(p[axis] - sourceMin[axis]) < Float(0.000001)
                            && abs(q[axis] - sourceMin[axis]) < Float(0.000001)
                        let atMaximum = abs(p[axis] - sourceMax[axis]) < Float(0.000001)
                            && abs(q[axis] - sourceMax[axis]) < Float(0.000001)
                        onBoundary = onBoundary || atMinimum || atMaximum
                    }
                    if !onBoundary { continue }
                }
                if moving { movingEdgeMesh.tube(from: a, to: b, radius: 0.00042 * guideScale) }
                else { edgeMesh.tube(from: a, to: b, radius: 0.00013 * guideScale) }
            }
        }

        update(front, with: frontMesh, material: white)
        // The lucky-star lesson starts from a white strip on both sides.
        update(back, with: backMesh, material: (currentLesson == .star || currentLesson == .fullFox) ? white : ivory)
        update(activeFront, with: movingFront, material: blushFront)
        update(activeBack, with: movingBack, material: (currentLesson == .star || currentLesson == .fullFox) ? blushFront : blushBack)
        update(edges, with: edgeMesh, material: edgeMaterial)
        update(activeEdges, with: movingEdgeMesh, material: red)

        var creaseMesh = PaperMeshBuilder(), arrowMesh = PaperMeshBuilder()
        if visibleHints {
            if let c = frame.crease {
                let direction = c.end - c.start
                let length = simd_length(direction)
                if length > 0.00001 {
                    let d = direction / length
                    var distance: Float = 0
                    while distance < length {
                        creaseMesh.tube(from: c.start + d * distance,
                                        to: c.start + d * min(length, distance + 0.005 * guideScale), radius: 0.00068 * guideScale)
                        distance += 0.0085 * guideScale
                    }
                }
            }
            for path in frame.actionPaths where path.count > 1 {
                // Stop before the arc points almost straight into the table.
                // The old end-on cone vanished in Top view; this wider closed
                // head retains a readable triangular silhouette from above.
                let headIndex = max(1, path.count - 7)
                arrowMesh.tubePath(Array(path.prefix(headIndex + 1)), radius: 0.0010 * guideScale)
                let end = path[headIndex]
                let direction = simd_normalize(end - path[headIndex - 1])
                arrowMesh.cone(base: end - direction * (0.003 * guideScale),
                               tip: end + direction * (0.010 * guideScale), radius: 0.0052 * guideScale)
            }
        }
        update(crease, with: creaseMesh, material: teal)
        update(arrow, with: arrowMesh, material: red)
    }

    private func update(_ entity: ModelEntity, with builder: PaperMeshBuilder, material: any Material) {
        let key = ObjectIdentifier(entity)
        guard !builder.isEmpty else {
            entity.isEnabled = false
            meshCache.removeValue(forKey: key)
            return
        }
        if meshReuseEnabled, let cached = meshCache[key], cached.payload == builder {
            entity.isEnabled = true
            // Geometry equality does not imply material equality: a lesson or
            // hint change can choose a different front/back material.
            entity.model = ModelComponent(mesh: cached.resource, materials: [material])
            meshReuses += 1
            return
        }
        meshGenerationCalls += 1
        guard let mesh = builder.resource() else {
            entity.isEnabled = false
            meshCache.removeValue(forKey: key)
            // An identical subsequent pose must retry a failed generation.
            lastPoseRenderedSuccessfully = false
            return
        }
        entity.isEnabled = true
        entity.model = ModelComponent(mesh: mesh, materials: [material])
        if meshReuseEnabled { meshCache[key] = CachedMesh(payload: builder, resource: mesh) }
    }
}

/// Batches all faces or all annotation segments into one RealityKit mesh. This
/// avoids creating hundreds of separate entities while the hinge is animating.
private struct PaperMeshBuilder: Equatable {
    private var positions = [SIMD3<Float>]()
    private var normals = [SIMD3<Float>]()
    private var triangles = [UInt32]()

    var isEmpty: Bool { triangles.isEmpty }

    /// Shared rings avoid cracks between independently oriented tube segments.
    mutating func tubePath(_ points: [SIMD3<Float>], radius: Float) {
        guard points.count > 1 else { return }
        let sides = 8
        let base = UInt32(positions.count)
        var previousU: SIMD3<Float>?
        for i in points.indices {
            let delta = points[min(i + 1, points.count - 1)] - points[max(0, i - 1)]
            guard simd_length_squared(delta) > 1e-14 else { return }
            let tangent = simd_normalize(delta)
            var u: SIMD3<Float>
            if let previousU {
                let projected = previousU - tangent * simd_dot(previousU, tangent)
                let reference: SIMD3<Float> = abs(tangent.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
                u = simd_length_squared(projected) > 1e-10 ? simd_normalize(projected) : simd_normalize(simd_cross(tangent, reference))
            } else {
                let reference: SIMD3<Float> = abs(tangent.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
                u = simd_normalize(simd_cross(tangent, reference))
            }
            previousU = u
            let v = simd_cross(tangent, u)
            for side in 0..<sides {
                let angle = Float(side) * 2 * .pi / Float(sides)
                let normal = u * cos(angle) + v * sin(angle)
                positions.append(points[i] + normal * radius); normals.append(normal)
            }
        }
        for ring in 0..<(points.count - 1) {
            for side in 0..<sides {
                let a = base + UInt32(ring * sides + side)
                let b = base + UInt32(ring * sides + (side + 1) % sides)
                let c = a + UInt32(sides), d = b + UInt32(sides)
                triangles += [a, b, c, b, d, c]
            }
        }
    }

    mutating func polygon(_ points: [SIMD3<Float>], normal: SIMD3<Float>, vertexNormals: [SIMD3<Float>]? = nil) {
        guard points.count > 2 else { return }
        let base = UInt32(positions.count)
        positions += points
        if let vertexNormals, vertexNormals.count == points.count { normals += vertexNormals }
        else { normals += Array(repeating: normal, count: points.count) }
        for i in 1..<(points.count - 1) { triangles += [base, base + UInt32(i), base + UInt32(i + 1)] }
    }

    mutating func tube(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: Float) {
        let delta = b - a
        guard simd_length_squared(delta) > 1e-14 else { return }
        let d = simd_normalize(delta)
        let reference: SIMD3<Float> = abs(d.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        let u = simd_normalize(simd_cross(d, reference))
        let v = simd_cross(d, u)
        let sides = 6
        let base = UInt32(positions.count)
        for point in [a, b] {
            for i in 0..<sides {
                let angle = Float(i) / Float(sides) * 2 * .pi
                let n = u * cos(angle) + v * sin(angle)
                positions.append(point + n * radius)
                normals.append(n)
            }
        }
        for i in 0..<sides {
            let j = (i + 1) % sides
            let ai = base + UInt32(i), aj = base + UInt32(j)
            let bi = ai + UInt32(sides), bj = aj + UInt32(sides)
            triangles += [ai, aj, bi, aj, bj, bi]
        }
    }

    mutating func cone(base: SIMD3<Float>, tip: SIMD3<Float>, radius: Float) {
        let d = simd_normalize(tip - base)
        let reference: SIMD3<Float> = abs(d.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        let u = simd_normalize(simd_cross(d, reference)), v = simd_cross(d, u)
        for i in 0..<10 {
            let a = Float(i) / 10 * 2 * .pi, b = Float(i + 1) / 10 * 2 * .pi
            let p = base + (u * cos(a) + v * sin(a)) * radius
            let q = base + (u * cos(b) + v * sin(b)) * radius
            let normal = simd_normalize(simd_cross(q - p, tip - p))
            polygon([p, q, tip], normal: normal)
            polygon([base, q, p], normal: -d)
        }
    }

    func resource() -> MeshResource? {
        guard !triangles.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: "Animated paper geometry")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(triangles)
        return try? MeshResource.generate(from: [descriptor])
    }
}
