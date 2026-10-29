import Foundation
import Testing
@testable import TomoCore

/// A clock the tests move forward by hand.
final class FakeClock {
    var date = Date(timeIntervalSince1970: 0)
    func advance(_ seconds: TimeInterval) { date += seconds }
}

private func makeEngine(_ config: TimerConfig = TimerConfig(focus: 60, shortBreak: 10, longBreak: 30, roundsBeforeLongBreak: 2))
    -> (TimerEngine, FakeClock)
{
    let clock = FakeClock()
    let engine = TimerEngine(config: config, now: { clock.date })
    return (engine, clock)
}

@Test func startsIdleInFocus() {
    let (engine, _) = makeEngine()
    #expect(engine.phase == .focus)
    #expect(engine.state == .idle)
    #expect(engine.remaining == 60)
}

@Test func countsDownFromEndDate() {
    let (engine, clock) = makeEngine()
    engine.start()
    clock.advance(15)
    engine.tick()
    #expect(engine.remaining == 45)
    #expect(engine.progress == 0.25)
}

@Test func pauseKeepsTimeLeft() {
    let (engine, clock) = makeEngine()
    engine.start()
    clock.advance(20)
    engine.pause()
    #expect(engine.state == .paused)
    #expect(engine.remaining == 40)

    clock.advance(100) // Time passes while paused.
    engine.tick()
    #expect(engine.remaining == 40)

    engine.start()
    clock.advance(10)
    engine.tick()
    #expect(engine.remaining == 30)
}

@Test func longBreakAfterConfiguredRounds() {
    let (engine, clock) = makeEngine()
    var ended: [(Phase, Phase)] = []
    engine.onPhaseEnded = { ended.append(($0, $1)) }

    func finishPhase() {
        engine.start()
        clock.advance(engine.remaining + 1)
        engine.tick()
    }

    finishPhase()
    #expect(engine.phase == .shortBreak)
    finishPhase()
    #expect(engine.phase == .focus)
    finishPhase()
    #expect(engine.phase == .longBreak)
    #expect(engine.completedFocusRounds == 2)
    finishPhase()
    #expect(engine.phase == .focus)

    #expect(ended.map(\.0) == [.focus, .shortBreak, .focus, .longBreak])
}

@Test func waitsForClickAfterPhaseEnds() {
    let (engine, clock) = makeEngine()
    engine.start()
    clock.advance(61)
    engine.tick()
    #expect(engine.state == .idle)
    #expect(engine.remaining == 10)
}

@Test func autoStartNextKeepsRunning() {
    var config = TimerConfig(focus: 60, shortBreak: 10, longBreak: 30, roundsBeforeLongBreak: 2)
    config.autoStartNext = true
    let (engine, clock) = makeEngine(config)
    engine.start()
    clock.advance(60)
    engine.tick()
    #expect(engine.phase == .shortBreak)
    #expect(engine.state == .running)
}

@Test func skipDoesNotCountRoundOrNotify() {
    let (engine, _) = makeEngine()
    var notified = false
    engine.onPhaseEnded = { _, _ in notified = true }
    engine.skip()
    #expect(engine.phase == .shortBreak)
    #expect(engine.completedFocusRounds == 0)
    #expect(!notified)
}

@Test func resetGoesBackToFirstFocus() {
    let (engine, clock) = makeEngine()
    engine.start()
    clock.advance(61)
    engine.tick()
    engine.reset()
    #expect(engine.phase == .focus)
    #expect(engine.state == .idle)
    #expect(engine.completedFocusRounds == 0)
    #expect(engine.remaining == 60)
}

@Test func configChangeUpdatesIdleTimer() {
    let (engine, _) = makeEngine()
    engine.config.focus = 120
    #expect(engine.remaining == 120)
}
