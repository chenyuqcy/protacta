import Foundation

/// Pure timing policy. A fresh camera exposure and the committed anchor are
/// required even while the fold animation is paused.
enum OrigamiARFrameHealth {
    static let maximumAge: TimeInterval = 0.25

    static func isFresh(timestamp: TimeInterval?, now: TimeInterval) -> Bool {
        guard let timestamp, timestamp.isFinite, now.isFinite, timestamp >= 0 else { return false }
        let age = now - timestamp
        return age >= -0.001 && age <= maximumAge
    }

    static func isUsable(timestamp: TimeInterval?, now: TimeInterval,
                         normal: Bool, anchorPresent: Bool) -> Bool {
        normal && anchorPresent && isFresh(timestamp: timestamp, now: now)
    }
}

/// A receipt is not healthy depth. Only a recently applied mesh or a reliable
/// empty observation may renew this window; neither advances learner progress.
struct OrigamiARDepthHealth {
    private var windowStartedAt: TimeInterval?
    private var lastHealthyAt: TimeInterval?
    private var lastNow: TimeInterval?

    mutating func reset() {
        windowStartedAt = nil; lastHealthyAt = nil; lastNow = nil
    }

    mutating func shouldFallback(now: TimeInterval, frameTimestamp: TimeInterval,
                                  normal: Bool, appliedTimestamp: TimeInterval?) -> Bool {
        guard now.isFinite, now >= 0, normal,
              OrigamiARFrameHealth.isFresh(timestamp: frameTimestamp, now: now) else {
            reset(); return false
        }
        if let lastNow, now < lastNow { reset() }
        lastNow = now
        if windowStartedAt == nil { windowStartedAt = now }
        if let appliedTimestamp, appliedTimestamp.isFinite, appliedTimestamp >= 0 {
            let age = frameTimestamp - appliedTimestamp
            if age >= -0.001 && age < 0.15 {
                lastHealthyAt = now
                return false
            }
        }
        let deadline: TimeInterval = lastHealthyAt == nil ? 2 : 0.75
        return now - (lastHealthyAt ?? windowStartedAt ?? now) >= deadline
    }
}
