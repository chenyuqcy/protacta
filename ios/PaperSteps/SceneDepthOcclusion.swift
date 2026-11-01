import ARKit
import Foundation
import RealityKit
import UIKit

/// Camera-calibrated LiDAR surfaces for non-person objects. Native RealityKit
/// matting owns hands; its current region and margin are excluded from this mesh.
/// No color is drawn, and old meshes cannot reclaim a newly recognised hand.
@MainActor
final class SceneDepthOcclusion {
    enum Profile: Sendable { case rawPaper, stablePaper, stableEquipment }
    /// Runtime state of the depth surface, not a claim that its pixels have
    /// visibly occluded the paper. That still needs a real-camera check.
    struct Diagnostics {
        let status: String
        let triangleCount: Int
        let depthWidth: Int
        let depthHeight: Int
        let buildMilliseconds: Double
        let meshAgeMilliseconds: Double?
        let isAnchored: Bool
        let isActive: Bool
        let hasScene: Bool
        /// Frames accepted for display; this does not measure visible coverage.
        let displayedFrames: Int
        let expiredBuilds: Int
        let expiredDisplays: Int
        let emptyForegroundBuilds: Int
        let rejectedSamples: Int
        let rejectedDiscontinuities: Int
        let rejectedSupportTriangles: Int
        let depthSource: String
        let sourceWidth: Int
        let sourceHeight: Int
        let pixelStep: Int
        let cropX: Int
        let cropY: Int
        let samplingReason: String
        let projectedTargetArea: Int
        let nativePersonExclusion: Bool
        let excludedPersonPixels: Int
        let appliedFrameTimestamp: TimeInterval?
    }

    private let anchor = AnchorEntity(world: .zero)
    private let surface = ModelEntity()
    private weak var view: ARView?
    private var buildTask: Task<Void, Never>?
    private var expirationTimer: Timer?
    private var generation: UInt64 = 0
    private var lastScheduledTimestamp: TimeInterval = -.infinity
    private var latestFrameTimestamp: TimeInterval = 0
    private var displayedTimestamp: TimeInterval?
    private var displayedReceiptTime: TimeInterval = 0
    private var displayedFrames = 0
    private var expiredBuilds = 0
    private var expiredDisplays = 0
    private var emptyForegroundBuilds = 0
    private var rejectedSamples = 0
    private var rejectedDiscontinuities = 0
    private var rejectedSupportTriangles = 0
    private let profile: Profile
    private var stabilizer = EquipmentDepthStabilizer()
    private var depthSource = "None"
    private var sampling = SceneDepthSampling()
    private var sourceSize = SIMD2<Int>.zero
    private var samplingStep = 2
    private var cropOrigin = SIMD2<Int>.zero
    private var samplingReason = "Not active"
    private var projectedTargetArea = 0
    private(set) var lastAcceptedDepthTimestamp: TimeInterval?
    /// A fresh completed upload or reliable clear observation, not receipt alone.
    private(set) var lastAppliedDepthTimestamp: TimeInterval?
    private var excludingNativePeople = false
    private var latestPersonExclusion: [Bool]?
    private var latestPersonFrame: SceneDepthSnapshot?
    private var displayedSurface: SceneDepthSurface?
    private var displayedCameraTransform = matrix_identity_float4x4
    private var excludedPersonPixels = 0

    private(set) var triangleCount = 0
    private(set) var status = "Not active"
    private(set) var lastBuildMilliseconds: Double = 0
    private(set) var depthSize = SIMD2<Int>.zero

    var diagnostics: Diagnostics {
        expireIfNeeded()
        let age = displayedTimestamp.map { timestamp in
            let latest = max(latestFrameTimestamp, view?.session.currentFrame?.timestamp ?? latestFrameTimestamp)
            let receiptAge = ProcessInfo.processInfo.systemUptime - displayedReceiptTime
            return max(0, max(latest - timestamp, receiptAge)) * 1000
        }
        return Diagnostics(status: status, triangleCount: triangleCount,
                           depthWidth: depthSize.x, depthHeight: depthSize.y,
                           buildMilliseconds: lastBuildMilliseconds, meshAgeMilliseconds: age,
                           isAnchored: anchor.isAnchored, isActive: surface.isActive,
                           hasScene: anchor.scene != nil && surface.scene != nil,
                           displayedFrames: displayedFrames, expiredBuilds: expiredBuilds,
                           expiredDisplays: expiredDisplays, emptyForegroundBuilds: emptyForegroundBuilds,
                           rejectedSamples: rejectedSamples, rejectedDiscontinuities: rejectedDiscontinuities,
                           rejectedSupportTriangles: rejectedSupportTriangles, depthSource: depthSource,
                           sourceWidth: sourceSize.x, sourceHeight: sourceSize.y, pixelStep: samplingStep,
                           cropX: cropOrigin.x, cropY: cropOrigin.y,
                           samplingReason: samplingReason, projectedTargetArea: projectedTargetArea,
                           nativePersonExclusion: excludingNativePeople, excludedPersonPixels: excludedPersonPixels,
                           appliedFrameTimestamp: lastAppliedDepthTimestamp)
    }

    init(profile: Profile = .rawPaper) {
        self.profile = profile
        anchor.name = "Current real-world depth"
        surface.name = "Live depth occluder"
        anchor.synchronization = nil
        surface.synchronization = nil
        surface.isEnabled = false
        anchor.addChild(surface)
    }

    deinit { buildTask?.cancel(); expirationTimer?.invalidate() }

    func configure(in view: ARView, excludingNativePeople: Bool = false) {
        if self.view !== view { reset(); self.view = view }
        self.excludingNativePeople = excludingNativePeople
        ensureSceneAttachment(in: view)
        if expirationTimer == nil {
            let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.expireIfNeeded() }
            }
            RunLoop.main.add(timer, forMode: .common)
            expirationTimer = timer
        }
        if displayedTimestamp == nil {
            status = profile == .rawPaper ? "Waiting for raw scene depth" : "Waiting for smoothed hand depth"
        }
    }

    private func ensureSceneAttachment(in view: ARView) {
        if surface.parent !== anchor { anchor.addChild(surface) }
        // A session reset or caller clearing the scene must not leave a live
        // mesh detached. Do not repeatedly reanchor while ARKit is still
        // establishing tracking; only restore a missing scene attachment.
        if !view.scene.anchors.contains(where: { $0 === anchor }) {
            anchor.removeFromParent()
            view.scene.addAnchor(anchor)
        }
    }

    /// Call for every ARFrame before any UI/tracking-status throttling. Pass the
    /// actual supporting table's world Y, not a paper-model animation height.
    func update(frame: ARFrame, supportPlaneY: Float? = nil, target: Entity? = nil,
                localBounds: (minimum: SIMD3<Float>, maximum: SIMD3<Float>)? = nil) {
        guard let view else { return }
        ensureSceneAttachment(in: view)
        latestFrameTimestamp = frame.timestamp
        guard case .normal = frame.camera.trackingState else {
            invalidateMesh(reason: "Tracking unavailable"); return
        }
        // Stabilized profiles explicitly consume smoothed depth and check
        // current raw motion; the legacy raw-paper profile keeps its source.
        let useSmoothed = profile != .rawPaper && frame.smoothedSceneDepth?.confidenceMap != nil
        let selectedDepth = useSmoothed ? frame.smoothedSceneDepth : frame.sceneDepth
        guard let depth = selectedDepth else {
            if excludingNativePeople { latestPersonExclusion = nil; latestPersonFrame = nil }
            // A missing depth exposure cannot prove current native coverage.
            // Retaining a custom mesh here could cut a newly recognised hand.
            invalidateMesh(reason: "Raw scene depth unavailable", retainingFreshDisplay: !excludingNativePeople); return
        }
        expireIfNeeded()
        // Refresh native coverage on EVERY camera frame, even while a mesh is
        // being built. A past mesh must not clip a newly recognised hand.
        let fullWidth = CVPixelBufferGetWidth(depth.depthMap), fullHeight = CVPixelBufferGetHeight(depth.depthMap)
        var personExclusion: [Bool]?
        if excludingNativePeople {
            guard let person = Self.personMask(frame: frame),
                  let mask = person.exclusionMask(depthWidth: fullWidth, depthHeight: fullHeight) else {
                latestPersonExclusion = nil
                invalidateMesh(reason: "Waiting for native hand coverage"); return
            }
            guard let required = person.exclusionMask(depthWidth: fullWidth, depthHeight: fullHeight, radius: 2) else {
                invalidateMesh(reason: "Native hand coverage unavailable"); return
            }
            let currentFrame = Self.metadata(frame: frame, width: fullWidth, height: fullHeight)
            latestPersonExclusion = required; latestPersonFrame = currentFrame; personExclusion = mask
            if let displayedSurface,
               !SceneDepthPersonCoverage.isDisjoint(surface: displayedSurface,
                                                   sourceCameraTransform: displayedCameraTransform,
                                                   current: currentFrame, personMask: required) {
                hide(reason: "Native hand boundary updated")
            }
        }
        guard buildTask == nil, frame.timestamp - lastScheduledTimestamp >= 1.0 / 30.0 else { return }
        guard let snapshot = Self.snapshot(frame: frame, depth: depth) else {
            invalidateMesh(reason: "Depth confidence unavailable", retainingFreshDisplay: true); return
        }
        let currentRaw = useSmoothed ? frame.sceneDepth.flatMap { Self.snapshot(frame: frame, depth: $0) } : nil
        depthSource = useSmoothed ? "Smoothed scene depth" : "Raw scene depth"
        if currentRaw != nil { depthSource += " + current raw motion check" }
        // Project the eight oriented corners. Re-expanding a rotated object
        // into a world-axis box can cross the camera near plane and force the
        // entire session back to a coarse full-image mesh.
        let worldCorners = target.map { target in
            let bounds = target.visualBounds(relativeTo: target)
            return SceneDepthRegion.corners(minimum: localBounds?.minimum ?? bounds.min,
                                            maximum: localBounds?.maximum ?? bounds.max)
                .map { target.convert(position: $0, to: nil) }
        }
        let plan = profile == .rawPaper
            ? SceneDepthSampling.Plan(region: .full(snapshot), pixelStep: 2)
            : sampling.plan(for: snapshot, worldCorners: worldCorners)
        lastAcceptedDepthTimestamp = snapshot.timestamp
        let receiptTime = ProcessInfo.processInfo.systemUptime
        let token = generation
        let previousFilter = stabilizer
        let capturedExclusion = personExclusion
        let profile = self.profile
        lastScheduledTimestamp = snapshot.timestamp
        sourceSize = [snapshot.width, snapshot.height]
        depthSize = [plan.region.width, plan.region.height]
        cropOrigin = [plan.region.x, plan.region.y]; samplingStep = plan.pixelStep
        samplingReason = plan.reason; projectedTargetArea = plan.projectedArea
        buildTask = Task { [weak self] in
            let start = ProcessInfo.processInfo.systemUptime
            let result = await Task.detached(priority: .userInitiated) { () -> (SceneDepthSurface, EquipmentDepthStabilizer, Int, Int) in
                var filter = previousFilter
                let local = plan.region.crop(snapshot)
                let raw = currentRaw.map { plan.region.crop($0) }
                var localExclusion: [Bool]?
                if let mask = capturedExclusion {
                    var cropped: [Bool] = []; cropped.reserveCapacity(plan.region.area)
                    for y in 0..<plan.region.height {
                        let start = (plan.region.y + y) * snapshot.width + plan.region.x
                        cropped.append(contentsOf: mask[start..<(start + plan.region.width)])
                    }
                    localExclusion = cropped
                }
                var filtered = profile != .rawPaper ? filter.filter(local, current: raw, pixelStep: plan.pixelStep,
                                                                    excluding: localExclusion) : local
                // Defend the ownership boundary after ALL spatial/temporal work.
                // Masking only before filtering could fill the hand back in.
                if let localExclusion {
                    for index in localExclusion.indices where localExclusion[index] {
                        filtered.depths[index] = 0; filtered.confidence[index] = 0
                    }
                }
                let mesh = SceneDepthMesher.build(filtered, supportPlaneY: supportPlaneY,
                                                 pixelStep: plan.pixelStep,
                                                 policy: profile == .stableEquipment ? .stableEquipment : .paper)
                let observation: SceneDepthSnapshot
                if let raw, raw.width == local.width, raw.height == local.height,
                   raw.depths.count == local.depths.count, raw.confidence.count == local.confidence.count,
                   raw.calibration == local.calibration { observation = raw }
                else { observation = local }
                var excludedCount = 0, reliableNonPersonCount = 0
                for index in observation.depths.indices {
                    if localExclusion?[index] == true { excludedCount += 1 }
                    else if observation.depths[index].isFinite, (0.12...3).contains(observation.depths[index]),
                            (1...2).contains(observation.confidence[index]) { reliableNonPersonCount += 1 }
                }
                return (mesh, filter, excludedCount, reliableNonPersonCount)
            }.value
            // A cancelled generation must never clear a newer generation's
            // in-flight task or replace its surface/diagnostics.
            guard let self, self.generation == token, !Task.isCancelled else { return }
            self.buildTask = nil
            let mesh = result.0
            self.lastBuildMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
            self.rejectedSamples = mesh.rejectedSamples
            self.rejectedDiscontinuities = mesh.rejectedDiscontinuities
            self.rejectedSupportTriangles = mesh.rejectedSupportTriangles
            guard self.isCurrent(timestamp: snapshot.timestamp, receivedAt: receiptTime) else {
                self.expiredBuilds += 1
                self.rejectBuild(reason: "Depth frame expired"); return
            }
            if capturedExclusion != nil {
                guard let current = self.latestPersonFrame, let required = self.latestPersonExclusion,
                      SceneDepthPersonCoverage.isDisjoint(surface: mesh, sourceCameraTransform: snapshot.cameraTransform,
                                                          current: current, personMask: required) else {
                    self.hide(reason: "Native hand boundary changed during depth work"); return
                }
            }
            self.stabilizer = result.1
            self.excludedPersonPixels = result.2
            guard !mesh.triangles.isEmpty else {
                self.emptyForegroundBuilds += 1
                // A fresh view of only the support plane/person exclusion is a
                // valid clear observation. An all-invalid depth map is not.
                if SceneDepthClearObservation.isReliableEmpty(surface: mesh, pixelCount: plan.region.area,
                                                             excludedPixels: result.2,
                                                             reliableNonPersonPixels: result.3) {
                    self.lastAppliedDepthTimestamp = snapshot.timestamp
                }
                if profile != .rawPaper {
                    // A current clear observation must not retain the previous
                    // hand until the stale-frame timer expires.
                    self.hide(reason: "No reliable foreground surface")
                } else { self.rejectBuild(reason: "No reliable foreground surface") }
                return
            }
            var descriptor = MeshDescriptor(name: "Camera-calibrated live scene depth")
            descriptor.positions = MeshBuffers.Positions(mesh.positions)
            descriptor.primitives = .triangles(mesh.triangles)
            do {
                let resource = try MeshResource.generate(from: [descriptor])
                self.lastBuildMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
                guard self.isCurrent(timestamp: snapshot.timestamp, receivedAt: receiptTime) else {
                    self.expiredBuilds += 1
                    self.rejectBuild(reason: "Depth frame expired during mesh upload"); return
                }
                if let view = self.view { self.ensureSceneAttachment(in: view) }
                var material = OcclusionMaterial(receivesDynamicLighting: false)
                if #available(iOS 18.0, *) { material.faceCulling = .none; material.readsDepth = true }
                self.surface.model = ModelComponent(mesh: resource, materials: [material])
                // Freeze the depth exposure at its own camera pose. Attaching a
                // past depth buffer to the current camera would produce sliding.
                self.surface.transform = Transform(matrix: snapshot.cameraTransform)
                self.surface.isEnabled = true
                self.displayedTimestamp = snapshot.timestamp
                self.lastAppliedDepthTimestamp = snapshot.timestamp
                self.displayedSurface = capturedExclusion == nil ? nil : mesh
                self.displayedCameraTransform = snapshot.cameraTransform
                self.displayedReceiptTime = receiptTime
                self.triangleCount = mesh.triangles.count / 3
                self.displayedFrames += 1
                self.status = "Fresh depth mesh attached"
            } catch {
                self.lastBuildMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
                self.rejectBuild(reason: "Depth mesh unavailable")
            }
        }
    }

    /// Call on leaving AR, backgrounding, interruption and a new placement/session.
    func reset() {
        generation &+= 1
        buildTask?.cancel(); buildTask = nil
        expirationTimer?.invalidate(); expirationTimer = nil
        hide(reason: "Not active")
        surface.model = nil
        anchor.removeFromParent()
        view = nil
        lastScheduledTimestamp = -.infinity
        latestFrameTimestamp = 0
        depthSize = .zero
        lastBuildMilliseconds = 0
        displayedFrames = 0
        expiredBuilds = 0
        expiredDisplays = 0; emptyForegroundBuilds = 0
        rejectedSamples = 0
        rejectedDiscontinuities = 0
        rejectedSupportTriangles = 0
        stabilizer.reset(); depthSource = "None"; lastAcceptedDepthTimestamp = nil; lastAppliedDepthTimestamp = nil
        excludingNativePeople = false; latestPersonExclusion = nil; latestPersonFrame = nil
        displayedSurface = nil; displayedCameraTransform = matrix_identity_float4x4; excludedPersonPixels = 0
        sampling.reset(); sourceSize = .zero; samplingStep = 2; cropOrigin = .zero
        samplingReason = "Not active"; projectedTargetArea = 0
    }

    private func invalidateMesh(reason: String, retainingFreshDisplay: Bool = false) {
        generation &+= 1
        buildTask?.cancel(); buildTask = nil
        if !retainingFreshDisplay { stabilizer.reset(); sampling.reset() }
        if retainingFreshDisplay { rejectBuild(reason: reason) }
        else { hide(reason: reason) }
    }

    private func rejectBuild(reason: String) {
        // Rejecting a new frame must not erase a still-current display. Its
        // original timestamp/receipt remain unchanged, so the timer and live
        // frame checks still remove it at the same 120 ms deadline.
        if let timestamp = displayedTimestamp,
           isCurrent(timestamp: timestamp, receivedAt: displayedReceiptTime) {
            status = "Fresh depth mesh retained; \(reason.lowercased())"
        } else {
            hide(reason: reason)
        }
    }

    private func hide(reason: String) {
        surface.isEnabled = false
        displayedSurface = nil
        displayedTimestamp = nil
        displayedReceiptTime = 0
        triangleCount = 0
        status = reason
    }

    private func expireIfNeeded() {
        guard let timestamp = displayedTimestamp else { return }
        if !isCurrent(timestamp: timestamp, receivedAt: displayedReceiptTime) {
            expiredDisplays += 1
            hide(reason: "Depth frame expired")
        }
    }

    private func isCurrent(timestamp: TimeInterval, receivedAt: TimeInterval) -> Bool {
        // Read the live session as well as delegate state: a busy main thread
        // must not make an old queued callback look like the latest camera frame.
        guard let frame = view?.session.currentFrame, case .normal = frame.camera.trackingState else { return false }
        return SceneDepthMesher.isFresh(timestamp: timestamp,
                                        latestFrameTimestamp: max(latestFrameTimestamp, frame.timestamp),
                                        secondsSinceReceived: ProcessInfo.processInfo.systemUptime - receivedAt)
    }

    private static func metadata(frame: ARFrame, width: Int, height: Int) -> SceneDepthSnapshot {
        let resolution = frame.camera.imageResolution, k = frame.camera.intrinsics
        let sx = Float(width) / Float(resolution.width), sy = Float(height) / Float(resolution.height)
        return SceneDepthSnapshot(width: width, height: height, depths: [], confidence: [],
                                  calibration: [k[0][0] * sx, k[1][1] * sy, k[2][0] * sx, k[2][1] * sy],
                                  cameraTransform: frame.camera.transform, timestamp: frame.timestamp)
    }

    private static func personMask(frame: ARFrame) -> SceneDepthPersonMask? {
        guard let buffer = frame.segmentationBuffer,
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8 else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0, width <= 4096, height <= 4096,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let address = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var values: [UInt8] = []; values.reserveCapacity(width * height)
        for y in 0..<height {
            values.append(contentsOf: UnsafeBufferPointer(start: address.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self), count: width))
        }
        return SceneDepthPersonMask(width: width, height: height, values: values)
    }

    private static func snapshot(frame: ARFrame, depth: ARDepthData) -> SceneDepthSnapshot? {
        let buffer = depth.depthMap
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DepthFloat32,
              let confidence = depth.confidenceMap,
              CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8 else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard width > 1, height > 1, CVPixelBufferGetWidth(confidence) == width,
              CVPixelBufferGetHeight(confidence) == height,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferLockBaseAddress(confidence, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
        guard let depthAddress = CVPixelBufferGetBaseAddress(buffer),
              let confidenceAddress = CVPixelBufferGetBaseAddress(confidence) else { return nil }
        let depthStride = CVPixelBufferGetBytesPerRow(buffer), confidenceStride = CVPixelBufferGetBytesPerRow(confidence)
        var depths = [Float](), confidences = [UInt8]()
        depths.reserveCapacity(width * height); confidences.reserveCapacity(width * height)
        for row in 0..<height {
            depths.append(contentsOf: UnsafeBufferPointer(start: depthAddress.advanced(by: row * depthStride).assumingMemoryBound(to: Float.self), count: width))
            confidences.append(contentsOf: UnsafeBufferPointer(start: confidenceAddress.advanced(by: row * confidenceStride).assumingMemoryBound(to: UInt8.self), count: width))
        }
        let resolution = frame.camera.imageResolution, intrinsics = frame.camera.intrinsics
        guard resolution.width > 0, resolution.height > 0 else { return nil }
        let sx = Float(width) / Float(resolution.width), sy = Float(height) / Float(resolution.height)
        return SceneDepthSnapshot(width: width, height: height, depths: depths, confidence: confidences,
                                  calibration: [intrinsics[0][0] * sx, intrinsics[1][1] * sy,
                                                intrinsics[2][0] * sx, intrinsics[2][1] * sy],
                                  cameraTransform: frame.camera.transform, timestamp: frame.timestamp)
    }
}
