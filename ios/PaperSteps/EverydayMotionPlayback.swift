import Foundation

/// A single authored movement. Playback never confirms a physical action or
/// advances the learner's session; those are separate, explicit decisions.
struct EverydayMotionPlayback: Equatable {
    private(set) var actionIndex: Int
    private(set) var progress: Double
    private(set) var isPlaying = false
    private(set) var speed: Double = 1

    init(actionIndex: Int = 0, progress: Double = 0) {
        self.actionIndex = max(0, actionIndex)
        self.progress = Self.normalized(progress)
    }

    mutating func select(actionIndex: Int, progress: Double = 0, autoplay: Bool = false) {
        self.actionIndex = max(0, actionIndex)
        self.progress = Self.normalized(progress)
        isPlaying = autoplay && self.progress < 1
    }

    mutating func play() {
        if progress >= 1 { progress = 0 }
        isPlaying = true
    }

    mutating func pause() { isPlaying = false }

    mutating func replay() {
        progress = 0
        isPlaying = true
    }

    mutating func seek(to value: Double) {
        progress = Self.normalized(value)
        isPlaying = false
    }

    mutating func setSlow(_ slow: Bool) { speed = slow ? 0.5 : 1 }

    /// Measured elapsed time gives equal duration at different refresh rates.
    /// The cap avoids a large jump after a stalled frame or interruption.
    mutating func advance(elapsed: TimeInterval, allowed: Bool) {
        guard allowed else { pause(); return }
        guard isPlaying, elapsed.isFinite, elapsed > 0 else { return }
        let candidate = progress + min(elapsed, 0.12) * speed / 4
        if candidate >= 1 - 1e-12 {
            progress = 1
            isPlaying = false
        } else {
            progress = candidate
        }
    }

    private static func normalized(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}
