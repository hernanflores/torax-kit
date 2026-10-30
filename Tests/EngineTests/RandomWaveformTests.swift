import XCTest

@testable import Engine

/// Tests de la onda `random` (Random Modulation, FR1–FR4).
///
/// **Es la única onda que no sale de la posición en la vuelta.** Las cuatro
/// periódicas son funciones de `(step, stepCount)`; `random` es una función de
/// `(Step absoluto, semilla)`, un valor nuevo por Step. Las cuatro reciben los
/// mismos argumentos y los ignoran, así que no cambian ni un número.
final class RandomWaveformTests: XCTestCase {

    private let seed: UInt64 = 0xC0FFEE

    /// `random` es exactamente el aleatorio sin estado del Step absoluto.
    func testRandomIsTheExcursionOfTheAbsoluteStep() {
        for absolute in 0..<64 {
            XCTAssertEqual(
                Waveform.random.value(atStep: absolute % 16, of: 16, absoluteStep: absolute, seed: seed),
                SeededRandom.excursion(seed: seed, atStep: absolute),
                "absolute \(absolute)")
        }
    }

    /// **Mismo Step de la vuelta, otra vuelta, otro valor.** Lo que decide es el
    /// Step absoluto, no la posición en el anillo (AC 4).
    func testTheSameRingPositionDiffersAcrossLaps() {
        let laps = (0..<4).map { lap in
            (0..<16).map { step in
                Waveform.random.value(atStep: step, of: 16, absoluteStep: lap * 16 + step, seed: seed)
            }
        }
        XCTAssertEqual(Set(laps.map { $0.description }).count, 4)
    }

    /// Sin Step absoluto, `random` usa la posición de la vuelta. Es lo que
    /// reciben las llamadas que no tienen reloj —el panel, los tests de las
    /// periódicas— y sigue siendo determinista.
    func testWithoutAnAbsoluteStepRandomUsesTheRingPosition() {
        for step in 0..<16 {
            XCTAssertEqual(
                Waveform.random.value(atStep: step, of: 16),
                SeededRandom.excursion(seed: SeededRandom.defaultSeed, atStep: step))
        }
    }

    /// **Las cuatro periódicas ignoran el Step absoluto y la semilla** (FR4,
    /// AC 1): dan, para todo `(step, stepCount)`, lo mismo que sin ellos.
    func testPeriodicWaveformsIgnoreTheAbsoluteStepAndTheSeed() {
        for waveform in Waveform.periodic {
            for stepCount in [1, 7, 16, 64] {
                for step in 0..<stepCount {
                    let plain = waveform.value(atStep: step, of: stepCount)
                    for (absolute, seed) in [(0, UInt64(1)), (999, 42), (step + 160, .max)] {
                        XCTAssertEqual(
                            waveform.value(
                                atStep: step, of: stepCount, absoluteStep: absolute, seed: seed),
                            plain, "\(waveform) \(step)/\(stepCount)")
                    }
                }
            }
        }
    }

    /// Un `stepCount` no positivo no revienta tampoco con `random`: devuelve un
    /// valor en rango. No puede ocurrir —`Steps` valida 1…64—, pero esto corre
    /// en el hilo del scheduler.
    func testRandomWithANonPositiveStepCountStaysInRange() {
        for stepCount in [0, -4] {
            let value = Waveform.random.value(atStep: 3, of: stepCount, absoluteStep: 3, seed: seed)
            XCTAssertTrue((-100...100).contains(value))
        }
    }

    /// `Waveform` sigue cabiendo en un byte y `Cycle` sigue siendo trivial:
    /// el snapshot no crece (NFR2, AC 12).
    func testAddingRandomKeepsTheSnapshotTrivial() {
        XCTAssertEqual(MemoryLayout<Waveform>.size, 1)
        XCTAssertTrue(_isPOD(Cycle.self))
        XCTAssertTrue(_isPOD(Modulation.self))
    }
}
