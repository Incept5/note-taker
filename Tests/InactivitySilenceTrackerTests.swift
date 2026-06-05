import XCTest
// InactivitySilenceTracker is compiled directly into this bundle (see project.yml),
// so no import of the app module — and no host app — is required.

final class InactivitySilenceTrackerTests: XCTestCase {
    // Mirrors AppState.silenceLevelThreshold (0..1 scale).
    private let threshold: Float = 0.005

    private func makeTracker(minutes: Int) -> InactivitySilenceTracker {
        InactivitySilenceTracker(timeoutMinutes: minutes, silenceLevelThreshold: threshold)
    }

    func testDisabledWhenTimeoutZero() {
        var tracker = makeTracker(minutes: 0)
        XCTAssertFalse(tracker.isEnabled)
        // Even after many silent seconds, a disabled tracker never fires.
        for _ in 0..<10_000 {
            XCTAssertFalse(tracker.registerSecond(level: 0.0))
        }
    }

    func testFiresAfterExactTimeoutOfSilence() {
        var tracker = makeTracker(minutes: 5)
        let timeout = 5 * 60 // 300 seconds

        // The first (timeout - 1) silent seconds must NOT trigger a stop.
        for second in 1..<timeout {
            XCTAssertFalse(tracker.registerSecond(level: 0.0),
                           "should not stop at \(second)s of silence")
        }
        // The 300th consecutive silent second triggers the stop.
        XCTAssertTrue(tracker.registerSecond(level: 0.0),
                      "should stop at exactly \(timeout)s of silence")
    }

    func testAudioResetsTheSilenceCounter() {
        var tracker = makeTracker(minutes: 5)
        let timeout = 5 * 60

        // Nearly reach the timeout...
        for _ in 1..<timeout {
            XCTAssertFalse(tracker.registerSecond(level: 0.0))
        }
        // ...then a single audible second resets the count.
        XCTAssertFalse(tracker.registerSecond(level: 0.5))
        XCTAssertEqual(tracker.consecutiveSilentSeconds, 0)

        // It must now take another full timeout of silence to fire.
        for second in 1..<timeout {
            XCTAssertFalse(tracker.registerSecond(level: 0.0),
                           "should not stop \(second)s after reset")
        }
        XCTAssertTrue(tracker.registerSecond(level: 0.0))
    }

    func testLevelAtThresholdIsTreatedAsAudible() {
        var tracker = makeTracker(minutes: 1)
        // A level exactly at the threshold is NOT below it, so it counts as audible.
        XCTAssertFalse(tracker.registerSecond(level: threshold))
        XCTAssertEqual(tracker.consecutiveSilentSeconds, 0)
        // Just below the threshold counts as silence.
        XCTAssertFalse(tracker.registerSecond(level: threshold - 0.0001))
        XCTAssertEqual(tracker.consecutiveSilentSeconds, 1)
    }

    func testIntermittentAudioNeverAccumulatesToTimeout() {
        var tracker = makeTracker(minutes: 5)
        // Alternating silence/audio: the counter never reaches the timeout.
        for i in 0..<10_000 {
            let level: Float = (i % 2 == 0) ? 0.0 : 0.5
            XCTAssertFalse(tracker.registerSecond(level: level))
        }
    }

    func testResetClearsCounter() {
        var tracker = makeTracker(minutes: 5)
        _ = tracker.registerSecond(level: 0.0)
        _ = tracker.registerSecond(level: 0.0)
        XCTAssertEqual(tracker.consecutiveSilentSeconds, 2)
        tracker.reset()
        XCTAssertEqual(tracker.consecutiveSilentSeconds, 0)
    }
}
