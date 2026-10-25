import CoreGraphics
import Foundation

/// A short-lived registration of the visible sheet, not a judgment of a fold.
/// Teaching progress and saved lesson state deliberately live elsewhere.
struct PaperGuideSession {
    enum Status: String, Equatable {
        case searching
        case needsDirection
        case aligned
        case reacquiring
        case unsupported
    }

    static let maximumObservationAge: TimeInterval = 0.35

    private(set) var quadrilateral: PaperQuadrilateral?
    private(set) var registration: PaperRegistration?
    private(set) var directionConfirmed = false
    private(set) var status: Status = .searching
    private(set) var sessionGeneration = 0

    private var active = false
    private var supported = true
    private var hasSeenPaper = false
    private var lastEventTimestamp: TimeInterval?
    private var lastObservationTimestamp: TimeInterval?

    init() {}

    mutating func start(generation: Int) {
        sessionGeneration = generation
        active = true
        hasSeenPaper = false
        lastEventTimestamp = nil
        lastObservationTimestamp = nil
        quadrilateral = nil
        registration = nil
        directionConfirmed = false
        status = supported ? .searching : .unsupported
    }

    /// Observations and `now` use the same monotonic clock as ARFrame.timestamp.
    /// Old callbacks cannot clear or revive a newer camera session.
    mutating func receive(quad: PaperQuadrilateral?, timestamp: TimeInterval,
                          generation: Int, now: TimeInterval) {
        guard active, generation == sessionGeneration, supported else { return }
        guard timestamp.isFinite, now.isFinite, timestamp >= 0, now >= 0 else {
            hideForLoss()
            return
        }
        // Even a delayed callback must not keep an older cue alive past its TTL.
        expire(at: now)
        if let previousEvent = lastEventTimestamp, timestamp <= previousEvent {
            // An out-of-order result says nothing about the latest observation.
            return
        }
        guard timestamp <= now, now - timestamp <= Self.maximumObservationAge else {
            hideForLoss()
            return
        }

        let previousTimestamp = lastObservationTimestamp
        lastEventTimestamp = timestamp
        guard let detected = quad, detected.isValid else {
            hideForLoss()
            return
        }

        if let previousTimestamp,
           timestamp - previousTimestamp > Self.maximumObservationAge {
            // Do not transfer a direction through an unobserved interval.
            hideForLoss()
        }

        let tracked: PaperQuadrilateral
        if let previous = quadrilateral {
            if let match = Self.continuousMatch(detected, previous: previous) {
                tracked = match
            } else {
                // A different rectangle, abrupt change or uncertain identity
                // needs a fresh human direction check before showing a cue.
                directionConfirmed = false
                registration = nil
                tracked = detected
            }
        } else {
            directionConfirmed = false
            registration = nil
            tracked = detected
        }

        quadrilateral = tracked
        lastObservationTimestamp = timestamp
        hasSeenPaper = true
        updateRegistration()
    }

    /// A direction choice is only meaningful while the underlying image is fresh.
    @discardableResult
    mutating func confirmDirection(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        expire(at: now)
        guard active, supported, quadrilateral != nil, status == .needsDirection else { return false }
        directionConfirmed = true
        updateRegistration()
        return registration != nil
    }

    /// Rotate the tutorial's corner identities, not the camera image or sheet.
    mutating func rotateDirection(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        expire(at: now)
        guard active, supported, let current = quadrilateral else { return }
        quadrilateral = current.rotated(by: 1)
        updateRegistration()
    }

    /// Ends this camera session. Recovery requires start(generation:).
    mutating func invalidate() {
        active = false
        hideForLoss()
    }

    /// Call on a lightweight UI timer as well as on incoming camera frames.
    mutating func expire(at now: TimeInterval) {
        guard active, supported, let timestamp = lastObservationTimestamp else { return }
        guard now.isFinite, now >= timestamp,
              now - timestamp <= Self.maximumObservationAge else {
            hideForLoss()
            return
        }
    }

    mutating func setSupported(_ isSupported: Bool) {
        guard supported != isSupported else { return }
        supported = isSupported
        hideForLoss()
    }

    private mutating func updateRegistration() {
        guard supported else {
            registration = nil
            status = .unsupported
            return
        }
        guard let quadrilateral else {
            registration = nil
            status = hasSeenPaper ? .reacquiring : .searching
            return
        }
        guard directionConfirmed,
              let candidate = PaperRegistration(quadrilateral: quadrilateral) else {
            registration = nil
            directionConfirmed = false
            status = .needsDirection
            return
        }
        registration = candidate
        status = .aligned
    }

    private mutating func hideForLoss() {
        quadrilateral = nil
        registration = nil
        directionConfirmed = false
        lastObservationTimestamp = nil
        status = supported ? (hasSeenPaper ? .reacquiring : .searching) : .unsupported
    }

    /// Match identities by the smallest cyclic displacement. These conservative
    /// image-space limits prevent visible jumps from inheriting a direction.
    /// They cannot identify indistinguishable sheets or assess hidden creases.
    private static func continuousMatch(_ detected: PaperQuadrilateral,
                                        previous: PaperQuadrilateral) -> PaperQuadrilateral? {
        let previousPoints = previous.points
        let diagonal = max(distance(previousPoints[0], previousPoints[2]),
                           distance(previousPoints[1], previousPoints[3]))
        guard diagonal.isFinite, diagonal > 0.0001 else { return nil }

        let candidates = (0..<4).map { detected.rotated(by: $0) }
        guard let closest = candidates.min(by: {
            squaredDisplacement($0.points, previousPoints) < squaredDisplacement($1.points, previousPoints)
        }) else { return nil }
        let points = closest.points
        let rms = sqrt(squaredDisplacement(points, previousPoints) / 4)
        guard rms / diagonal <= 0.10 else { return nil }

        for index in 0..<4 {
            guard distance(points[index], previousPoints[index]) / diagonal <= 0.16 else { return nil }
            let next = (index + 1) % 4
            let oldLength = distance(previousPoints[index], previousPoints[next])
            let newLength = distance(points[index], points[next])
            guard oldLength > 0.0001, abs(newLength / oldLength - 1) <= 0.20 else { return nil }
        }
        return closest
    }

    private static func squaredDisplacement(_ first: [CGPoint], _ second: [CGPoint]) -> CGFloat {
        zip(first, second).reduce(0) { total, pair in
            let dx = pair.0.x - pair.1.x, dy = pair.0.y - pair.1.y
            return total + dx * dx + dy * dy
        }
    }

    private static func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }
}
