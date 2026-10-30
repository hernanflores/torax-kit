import XCTest

@testable import Engine

/// El panel con `random`: la banda alcanzable por Step (FR12, FR13, AC 10).
///
/// **Con una onda periódica el panel sabe lo que va a sonar; con `random`, no.**
/// El valor siguiente sale del Step absoluto, que el panel no tiene, así que
/// dibujar una vuelta concreta sería dibujar algo que nadie oye. Lo que sí se
/// sabe es entre qué dos valores va a caer, recorte incluido.
final class RandomResponseTests: XCTestCase {

    private func cycle(target: TrackParameter, depth: Int, waveform: Waveform) -> Cycle {
        var pool = PitchPool()
        for value in [60, 63, 67] { pool = pool.toggling(Pitch(value)!) }
        return Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(9)!),
            pool: pool,
            groove: Groove(
                velocity: Velocity(64)!, sustain: Sustain(percent: 50)!, probability: .default),
            noteRepeater: NoteRepeater(repeats: Repeats(4)!),
            modulation: Modulation(
                waveform: waveform, depth: Depth(percent: depth)!, target: target)
        )
    }

    /// Lo que el scheduler emitiría en el Step absoluto `absolute`, por los
    /// mismos métodos de aplicación que usa la emisión.
    private func emitted(_ cycle: Cycle, absolute: Int, seed: UInt64) -> Int {
        let step = absolute % 16
        let modulation = cycle.modulation
        let groove = cycle.groove.modulated(
            by: modulation, atStep: step, of: 16, absoluteStep: absolute, seed: seed)
        let repeater = cycle.noteRepeater.modulated(
            by: modulation, atStep: step, of: 16, absoluteStep: absolute, seed: seed)
        switch modulation.target {
        case .velocity: return groove.velocity.value
        case .sustain: return groove.sustain.percent
        case .timing: return groove.timing.percent
        case .delay: return groove.delay.percent
        case .repeats: return repeater.repeats.count
        case .repeatTime: return RepeatTime.ordered.firstIndex(of: repeater.time)!
        case .ramp: return repeater.ramp.percent
        case .pace: return repeater.pace.percent
        case .pitch:
            return cycle.pitchOffset.degrees
                + cycle.modulationPitchShift(
                    atStep: step, of: 16, absoluteStep: absolute, seed: seed)
        default: fatalError("no es destino")
        }
    }

    /// **Con las cuatro periódicas no cambia nada**: la banda es un punto, el
    /// valor de hoy (AC 10).
    func testPeriodicWaveformsHaveABandOfOnePoint() {
        for waveform in Waveform.periodic {
            for target in TrackParameter.modulationTargets {
                for depth in [-100, 0, 55] {
                    for entry in cycle(target: target, depth: depth, waveform: waveform)
                        .modulationResponse
                    {
                        XCTAssertEqual(entry.lowest, entry.value, "\(waveform) \(target) \(depth)")
                        XCTAssertEqual(entry.highest, entry.value, "\(waveform) \(target) \(depth)")
                    }
                }
            }
        }
    }

    /// **La banda contiene todo lo que suena.** Ocho vueltas, dos semillas, los
    /// nueve destinos y cuatro profundidades: cada valor emitido en el Step *i*
    /// cae dentro de la banda *i* (AC 10).
    func testTheBandContainsEverythingThatSounds() {
        for target in TrackParameter.modulationTargets {
            for depth in [-100, -40, 40, 100] {
                let cycle = cycle(target: target, depth: depth, waveform: .random)
                let response = cycle.modulationResponse
                for seed in [SeededRandom.defaultSeed, 0xBEEF] {
                    for absolute in 0..<128 {
                        let entry = response[absolute % 16]
                        let value = emitted(cycle, absolute: absolute, seed: seed)
                        XCTAssertTrue(
                            (entry.lowest...entry.highest).contains(value),
                            "\(target) \(depth) step \(absolute): \(value) fuera de \(entry.lowest)...\(entry.highest)"
                        )
                    }
                }
            }
        }
    }

    /// **Y no es más ancha de lo que hace falta**: con `depth = ±100` los dos
    /// bordes se alcanzan en alguna vuelta.
    func testTheBandIsReachedAtFullDepth() {
        for target in TrackParameter.modulationTargets {
            let cycle = cycle(target: target, depth: 100, waveform: .random)
            let entry = cycle.modulationResponse[0]
            let values = Set((0..<2000).map { emitted(cycle, absolute: $0 * 16, seed: 7) })
            XCTAssertTrue(values.contains(entry.lowest), "\(target): \(entry.lowest) nunca suena")
            XCTAssertTrue(values.contains(entry.highest), "\(target): \(entry.highest) nunca suena")
        }
    }

    /// Con `random`, `value` es la base: lo que suena con `depth = 0`.
    func testRandomValueIsTheBase() {
        for target in TrackParameter.modulationTargets {
            let random = cycle(target: target, depth: 70, waveform: .random).modulationResponse
            let neutral = cycle(target: target, depth: 0, waveform: .random).modulationResponse
            XCTAssertEqual(random.map(\.value), neutral.map(\.value), "\(target)")
            XCTAssertEqual(random.map(\.triggers), neutral.map(\.triggers), "\(target)")
        }
    }

    /// Velocity 64 con `depth = 100`: la banda es el recorrido entero, 1…127,
    /// en todos los Steps — el recorte en los dos extremos.
    func testFullDepthVelocitySpansTheWholeRange() {
        let response = cycle(target: .velocity, depth: 100, waveform: .random).modulationResponse
        XCTAssertTrue(response.allSatisfy { $0.lowest == 1 && $0.highest == 127 })
    }

    /// `repeats = 4` con `depth = 100`: de 0 a 8, recortado en los dos extremos.
    func testFullDepthRepeatsSpansZeroToTheTop() {
        let response = cycle(target: .repeats, depth: 100, waveform: .random).modulationResponse
        XCTAssertTrue(response.allSatisfy { $0.lowest == 0 && $0.highest == 8 })
    }
}
