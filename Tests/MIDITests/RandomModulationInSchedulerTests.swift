import Engine
import XCTest

@testable import MIDI

/// `random` en el scheduler (Random Modulation, FR7–FR9, AC 3–6, AC 9).
///
/// **El scheduler pasa el Step absoluto y la semilla del Track.** El Step
/// absoluto es el de la rejilla —cuenta desde Play, y cada Play construye un
/// scheduler nuevo desde 0—, así que el resultado varía por vuelta y se repite
/// por Play sin que `TrackScheduler` gane un solo campo mutable.
final class RandomModulationInSchedulerTests: XCTestCase {

    private let stepNanoseconds: Int64 = 125_000_000
    private let timeline = MusicalTimeline(
        tempo: Tempo(beatsPerMinute: 120)!,
        division: .sixteenth
    )

    private let targets: [TrackParameter] = [
        .velocity, .sustain, .timing, .delay, .repeats, .repeatTime, .ramp, .pace, .pitch,
    ]

    private func pool() -> PitchPool {
        var pool = PitchPool()
        for value in [60, 63, 67] { pool = pool.toggling(Pitch(value)!) }
        return pool
    }

    private func cycle(
        target: TrackParameter, depth: Int, repeats: Int = 0, probability: Int = 100
    ) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!),
            pool: pool(),
            groove: Groove(
                velocity: Velocity(64)!,
                sustain: Sustain(percent: 50)!,
                probability: Probability(percent: probability)!
            ),
            noteRepeater: NoteRepeater(repeats: Repeats(repeats)!),
            modulation: Modulation(
                waveform: .random, depth: Depth(percent: depth)!, target: target)
        )
    }

    private struct Event: Equatable {
        let step: Int
        let pitch: Int?
        let velocity: Int
        let sustain: Int
        let offset: Int64
    }

    private func emitted(
        _ cycle: Cycle, rounds: Int = 1, seed: UInt64 = SeededRandom.defaultSeed
    ) -> [Event] {
        var scheduler = TrackScheduler(timeline: timeline, material: .cycle(cycle), seed: seed)
        var result: [Event] = []
        scheduler.advance(
            toHorizon: Int64(16 * rounds) * stepNanoseconds,
            refreshingFrom: nil
        ) { _, step, pitch, groove, offset in
            result.append(
                Event(
                    step: step, pitch: pitch?.value, velocity: groove.velocity.value,
                    sustain: groove.sustain.percent, offset: offset))
        }
        return result
    }

    private func repetitionCounts(_ cycle: Cycle, rounds: Int) -> [Int: Int] {
        var scheduler = TrackScheduler(timeline: timeline, material: .cycle(cycle))
        var counts: [Int: Int] = [:]
        scheduler.advance(
            toHorizon: Int64(16 * rounds) * stepNanoseconds,
            refreshingFrom: nil,
            emitRepetition: { _, step, _, _, _, _ in counts[step, default: 0] += 1 },
            emit: { _, _, _, _, _ in }
        )
        return counts
    }

    // MARK: - El valor que suena es el del Step absoluto

    /// La velocity del Step absoluto `s` es la base desplazada por la excursión
    /// de `(semilla del Track, s)` — no por la de la posición en la vuelta.
    func testVelocityFollowsTheExcursionOfTheAbsoluteStep() {
        let seed: UInt64 = 0xBEEF
        let events = emitted(cycle(target: .velocity, depth: 100), rounds: 3, seed: seed)
        XCTAssertEqual(events.count, 48)
        for event in events {
            let excursion = SeededRandom.excursion(seed: seed, atStep: event.step)
            XCTAssertEqual(
                event.velocity, Velocity(64)!.advanced(by: excursion * 100 * 63 / 10000).value,
                "step \(event.step)")
        }
    }

    // MARK: - AC 3 y AC 4: repetible por Play, distinto por vuelta

    /// Dos Plays con la misma semilla emiten exactamente lo mismo, en los nueve
    /// destinos (AC 3).
    func testTwoPlaysWithTheSameSeedEmitTheSame() {
        for target in targets {
            let modulated = cycle(target: target, depth: 100, repeats: 2)
            XCTAssertEqual(emitted(modulated, rounds: 4), emitted(modulated, rounds: 4), "\(target)")
        }
    }

    /// Dos vueltas seguidas del mismo Cycle no dan las mismas velocities (AC 4).
    func testConsecutiveLapsDiffer() {
        let events = emitted(cycle(target: .velocity, depth: 100), rounds: 2)
        let first = events.filter { $0.step < 16 }.map(\.velocity)
        let second = events.filter { $0.step >= 16 }.map(\.velocity)
        XCTAssertEqual(first.count, 16)
        XCTAssertNotEqual(first, second)
    }

    /// `repeats` modulado: el número de repeticiones por Step también cambia de
    /// vuelta en vuelta — `NoteRepeater.modulated` recibe el Step absoluto.
    func testRepeatCountsDifferAcrossLaps() {
        let counts = repetitionCounts(cycle(target: .repeats, depth: 100), rounds: 2)
        let first = (0..<16).map { counts[$0, default: 0] }
        let second = (16..<32).map { counts[$0, default: 0] }
        XCTAssertNotEqual(first, second)
    }

    // MARK: - AC 5: Probability no se mueve

    /// **`random` no consume el PRNG.** Con Probability al 50%, los Pulses que
    /// suenan son los mismos con `depth = 100` que con `depth = 0`, en todos los
    /// destinos salvo `repeats` (AC 5, enmienda del 2026-10-30): modular
    /// `repeats` cambia cuántas repeticiones se tiran, como con el LFO.
    func testProbabilityOmissionsDoNotMove() {
        for target in targets where target != .repeats {
            let neutral = emitted(cycle(target: target, depth: 0, probability: 50), rounds: 4)
            let modulated = emitted(cycle(target: target, depth: 100, probability: 50), rounds: 4)
            XCTAssertLessThan(neutral.count, 64, "\(target): Probability no omite nada")
            XCTAssertEqual(modulated.map(\.step), neutral.map(\.step), "\(target)")
        }
    }

    // MARK: - AC 6: Tracks distintos

    /// Dos Tracks con el mismo Cycle reciben semillas distintas del
    /// `PatternScheduler`, y suenan distinto (AC 6).
    func testTwoTracksEmitDifferentSequences() {
        let modulated = cycle(target: .velocity, depth: 100)
        let first = emitted(
            modulated, seed: PatternScheduler.seed(SeededRandom.defaultSeed, forTrack: 0))
        let second = emitted(
            modulated, seed: PatternScheduler.seed(SeededRandom.defaultSeed, forTrack: 1))
        XCTAssertNotEqual(first.map(\.velocity), second.map(\.velocity))
    }

    // MARK: - AC 9: recorte y frenos

    /// `pitch` con `random` a tope: ninguna altura fuera de 0–127 ni fuera de la
    /// escala del Cycle, en ocho vueltas.
    func testRandomPitchStaysInTheScale() {
        for depth in [100, -100] {
            let modulated = cycle(target: .pitch, depth: depth)
            let events = emitted(modulated, rounds: 8)
            XCTAssertEqual(events.count, 128)
            for event in events {
                let pitch = Pitch(event.pitch!)!
                XCTAssertNotNil(modulated.frame.degree(of: pitch), "\(depth): \(event.pitch!)")
            }
            XCTAssertGreaterThan(Set(events.compactMap(\.pitch)).count, 3, "\(depth): no se mueve")
        }
    }

    /// `repeats = 0` con `depth = +100`: la mitad negativa se recorta en 0 y no
    /// envuelve; nunca hay más repeticiones que el tope.
    func testRandomRepeatsAreClippedAtZero() {
        let counts = repetitionCounts(cycle(target: .repeats, depth: 100), rounds: 8)
        XCTAssertTrue(counts.values.allSatisfy { (0...Repeats.validRange.upperBound).contains($0) })
        let silent = (0..<128).filter { counts[$0, default: 0] == 0 }
        XCTAssertFalse(silent.isEmpty, "la mitad negativa tendría que recortarse en 0")
    }
}
