import ARKit
import Foundation
import RealityKit
import UIKit

/// Camera-calibrated LiDAR surfaces for hands and nearby objects. Paper may
/// augment native occlusion; equipment uses one depth owner. No color is drawn.
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
        let rejectedSamples: Int
        let rejectedDiscontinuities: Int
        let rejectedSupportTriangles: Int
        let depthSource: String
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
    private var rejectedSamples = 0
    private var rejectedDiscontinuities = 0
    private var rejectedSupportTriangles = 0
    private let profile: Profile
    private var stabilizer = EquipmentDepthStabilizer()
    private var depthSource = "None"
    private(set) var lastAcceptedDepthTimestamp: TimeInterval?

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
                           rejectedSamples: rejectedSamples, rejectedDiscontinuities: rejectedDiscontinuities,
                           rejectedSupportTriangles: rejectedSupportTriangles, depthSource: depthSource)
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

    func configure(in view: ARView) {
        if self.view !== view { reset(); self.view = view }
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
    func update(frame: ARFrame, supportPlaneY: Float? = nil) {
        guard let view else { return }
        ensureSceneAttachment(in: view)
        latestFrameTimestamp = frame.timestamp
        guard case .normal = frame.camera.trackingState else {
            invalidateMesh(reason: "Tracking unavailable"); return
        }
        // Paper retains raw depth; equipment explicitly consumes smoothed depth
        // instead of assuming RealityKit's native person compositor uses it.
        let useSmoothed = profile != .rawPaper && frame.smoothedSceneDepth?.confidenceMap != nil
        let selectedDepth = useSmoothed ? frame.smoothedSceneDepth : frame.sceneDepth
        guard let depth = selectedDepth else {
            invalidateMesh(reason: "Raw scene depth unavailable", retainingFreshDisplay: true); return
        }
        depthSource = useSmoothed ? "Smoothed scene depth" : "Raw scene depth"
        expireIfNeeded()
        guard buildTask == nil, frame.timestamp - lastScheduledTimestamp >= 1.0 / 30.0 else { return }
        guard let snapshot = Self.snapshot(frame: frame, depth: depth) else {
            invalidateMesh(reason: "Depth confidence unavailable", retainingFreshDisplay: true); return
        }
        let currentRaw = useSmoothed ? frame.sceneDepth.flatMap { Self.snapshot(frame: frame, depth: $0) } : nil
        if currentRaw != nil { depthSource += " + current raw motion check" }
        lastAcceptedDepthTimestamp = snapshot.timestamp
        let receiptTime = ProcessInfo.processInfo.systemUptime
        let token = generation
        let previousFilter = stabilizer
        let profile = self.profile
        lastScheduledTimestamp = snapshot.timestamp
        depthSize = [snapshot.width, snapshot.height]
        buildTask = Task { [weak self] in
            let start = ProcessInfo.processInfo.systemUptime
            let result = await Task.detached(priority: .userInitiated) {
                var filter = previousFilter
                let filtered = profile != .rawPaper ? filter.filter(snapshot, current: currentRaw, pixelStep: 2) : snapshot
                let mesh = SceneDepthMesher.build(filtered, supportPlaneY: supportPlaneY,
                                                 policy: profile == .stableEquipment ? .stableEquipment : .paper)
                return (mesh, filter)
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
            self.stabilizer = result.1
            guard !mesh.triangles.isEmpty else {
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
        rejectedSamples = 0
        rejectedDiscontinuities = 0
        rejectedSupportTriangles = 0
        stabilizer.reset(); depthSource = "None"; lastAcceptedDepthTimestamp = nil
    }

    private func invalidateMesh(reason: String, retainingFreshDisplay: Bool = false) {
        generation &+= 1
        buildTask?.cancel(); buildTask = nil
        if !retainingFreshDisplay { stabilizer.reset() }
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
        displayedTimestamp = nil
        displayedReceiptTime = 0
        triangleCount = 0
        status = reason
    }

    private func expireIfNeeded() {
        guard let timestamp = displayedTimestamp else { return }
        if !isCurrent(timestamp: timestamp, receivedAt: displayedReceiptTime) {
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
