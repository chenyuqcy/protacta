import Foundation
import XCTest
@testable import Protacta

final class EverydayMotionPlaybackTests: XCTestCase {
    func testInitializationAndSelectionNormalizeInputsWithoutStartingPlayback() {
        for invalid in [Double.nan, .infinity, -.infinity, -4] {
            let playback = EverydayMotionPlayback(actionIndex: -8, progress: invalid)
            XCTAssertEqual(playback.actionIndex, 0)
            XCTAssertEqual(playback.progress, 0)
            XCTAssertFalse(playback.isPlaying)
        }
        var playback = EverydayMotionPlayback(actionIndex: 3, progress: 4)
        XCTAssertEqual(playback.progress, 1)
        playback.select(actionIndex: 5, progress: 0.35)
        XCTAssertEqual(playback.actionIndex, 5)
        XCTAssertEqual(playback.progress, 0.35)
        XCTAssertFalse(playback.isPlaying)
        playback.select(actionIndex: -1, progress: .nan, autoplay: true)
        XCTAssertEqual(playback.actionIndex, 0)
        XCTAssertEqual(playback.progress, 0)
        XCTAssertTrue(playback.isPlaying)
        playback.select(actionIndex: 2, progress: 1, autoplay: true)
        XCTAssertEqual(playback.progress, 1)
        XCTAssertFalse(playback.isPlaying)
    }

    func testEqualElapsedTimeProducesEqualPoseAtDifferentFrameRates() {
        var at25 = EverydayMotionPlayback()
        var at50 = EverydayMotionPlayback()
        at25.play(); at50.play()
        for _ in 0..<50 { at25.advance(elapsed: 0.04, allowed: true) }
        for _ in 0..<100 { at50.advance(elapsed: 0.02, allowed: true) }
        XCTAssertEqual(at25.progress, 0.5, accuracy: 1e-12)
        XCTAssertEqual(at50.progress, at25.progress, accuracy: 1e-12)
        XCTAssertTrue(at25.isPlaying)
    }

    func testSlowPlaybackDoublesDurationAndSpeedDoesNotChangeThePose() {
        var playback = EverydayMotionPlayback(actionIndex: 4, progress: 0.25)
        playback.setSlow(true)
        XCTAssertEqual(playback.speed, 0.5)
        XCTAssertEqual(playback.progress, 0.25)
        playback.play()
        for _ in 0..<50 { playback.advance(elapsed: 0.04, allowed: true) }
        XCTAssertEqual(playback.progress, 0.5, accuracy: 1e-12)
        playback.setSlow(false)
        XCTAssertEqual(playback.speed, 1)
        XCTAssertEqual(playback.progress, 0.5, accuracy: 1e-12)
        for _ in 0..<50 { playback.advance(elapsed: 0.04, allowed: true) }
        XCTAssertEqual(playback.progress, 1)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.actionIndex, 4)
    }

    func testLargeElapsedTimeIsCappedAndInvalidTimeCannotMoveTheModel() {
        var playback = EverydayMotionPlayback()
        playback.play()
        playback.advance(elapsed: 8, allowed: true)
        XCTAssertEqual(playback.progress, 0.03, accuracy: 1e-12)
        let validPose = playback
        for invalid in [Double.nan, .infinity, -.infinity, 0, -0.3] {
            playback.advance(elapsed: invalid, allowed: true)
            XCTAssertEqual(playback, validPose)
        }
    }

    func testPauseAndLifecycleGateKeepThePoseUntilExplicitResume() {
        var playback = EverydayMotionPlayback(actionIndex: 2, progress: 0.45)
        playback.play()
        playback.advance(elapsed: 0.08, allowed: false)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.progress, 0.45)
        playback.advance(elapsed: 0.08, allowed: true)
        XCTAssertEqual(playback.progress, 0.45)
        playback.play()
        playback.advance(elapsed: 0.08, allowed: true)
        XCTAssertEqual(playback.progress, 0.47, accuracy: 1e-12)
        playback.pause()
        playback.advance(elapsed: 0.08, allowed: true)
        XCTAssertEqual(playback.progress, 0.47, accuracy: 1e-12)
        XCTAssertEqual(playback.actionIndex, 2)
    }

    func testExactEndStopsWithoutAdvancingAndReplayKeepsTheSameAction() {
        var playback = EverydayMotionPlayback(actionIndex: 6, progress: 0.99)
        playback.play()
        playback.advance(elapsed: 0.04, allowed: true)
        XCTAssertEqual(playback.progress, 1)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.actionIndex, 6)
        playback.advance(elapsed: 0.1, allowed: true)
        XCTAssertEqual(playback.progress, 1)
        playback.replay()
        XCTAssertEqual(playback.progress, 0)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(playback.actionIndex, 6)
        playback.seek(to: 1)
        playback.play()
        XCTAssertEqual(playback.progress, 0)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(playback.actionIndex, 6)
    }

    func testSeekPausesAndAutoplaySelectionPreservesUserSpeed() {
        var playback = EverydayMotionPlayback(actionIndex: 1)
        playback.setSlow(true)
        playback.play()
        playback.seek(to: 0.65)
        XCTAssertEqual(playback.progress, 0.65)
        XCTAssertFalse(playback.isPlaying)
        playback.select(actionIndex: 2, autoplay: true)
        XCTAssertEqual(playback.progress, 0)
        XCTAssertEqual(playback.actionIndex, 2)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(playback.speed, 0.5)
        playback.seek(to: 99)
        XCTAssertEqual(playback.progress, 1)
        XCTAssertFalse(playback.isPlaying)
    }
}
