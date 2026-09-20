import XCTest

@testable import Engine

/// Tests del dato que dibuja el panel de la pantalla `modulation`
/// (`assignable-lfo_20260916`, FR20, FR21, AC 8).
///
/// **El panel no puede discrepar de lo que suena.** Cada entrada sale del mismo
/// método de aplicación que usa el camino de emisión; una segunda fórmula aquí
/// sería capaz de dibujar una onda que nadie oye, y ése es el fallo que esta
/// suite existe para impedir.
///
/// **El dato vive en `Engine` y no en la vista** (NFR6): se prueba con números
/// en vez de mirándolo, que es lo que `workflow.md` pide cuando algo en `App`
/// merecería un test.
final class ModulationResponseTests: XCTestCase {

    private func cycle(target: TrackParameter, depth: Int, waveform: Waveform = .triangle) -> Cycle
    {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!),
            noteRepeater: NoteRepeater(repeats: Repeats(4)!),
            modulation: Modulation(
                waveform: waveform, depth: Depth(percent: depth)!, target: target)
        )
    }

    // MARK: - AC 8: el panel dibuja lo que se emite

    /// **Para los nueve destinos, la entrada *i* es el valor que el parámetro
    /// tendría en el Step *i*.** Se compara contra los métodos de aplicación,
    /// que son los que el scheduler llama.
    func testTheResponseMatchesWhatTheApplicationPathProduces() {
        for target in TrackParameter.modulationTargets {
            let cycle = self.cycle(target: target, depth: 80)
            let response = cycle.modulationResponse

            XCTAssertEqual(response.count, 16, "\(target)")

            for (step, entry) in response.enumerated() {
                let groove = cycle.groove.modulated(
                    by: cycle.modulation, atStep: step, of: 16)
                let repeater = cycle.noteRepeater.modulated(
                    by: cycle.modulation, atStep: step, of: 16)

                let expected: Int
                switch target {
                case .velocity: expected = groove.velocity.value
                case .sustain: expected = groove.sustain.percent
                case .timing: expected = groove.timing.percent
                case .delay: expected = groove.delay.percent
                case .repeats: expected = repeater.repeats.count
                case .repeatTime:
                    expected = RepeatTime.ordered.firstIndex(of: repeater.time) ?? 0
                case .ramp: expected = repeater.ramp.percent
                case .pace: expected = repeater.pace.percent
                case .pitch:
                    expected =
                        cycle.pitchOffset.degrees
                        + cycle.modulationPitchShift(atStep: step, of: 16)
                default: expected = groove.velocity.value
                }

                XCTAssertEqual(entry.value, expected, "\(target) step \(step)")
            }
        }
    }

    /// **El valor cae siempre dentro del rango del destino**, porque el acotado
    /// lo hace el `advanced(by:)` del tipo. Es lo que permite que la vista
    /// normalice contra ese rango sin comprobar nada.
    func testEveryValueStaysInsideTheTargetRange() {
        for target in TrackParameter.modulationTargets {
            for depth in [-100, -40, 40, 100] {
                let cycle = self.cycle(target: target, depth: depth)
                let range = cycle.modulationResponseRange
                for entry in cycle.modulationResponse {
                    XCTAssertTrue(
                        range.contains(entry.value),
                        "\(target) depth \(depth): \(entry.value) fuera de \(range)"
                    )
                }
            }
        }
    }

    // MARK: - El rango y el título (FR20, FR21)

    /// El rango de normalización es el que el destino declara.
    func testTheRangeComesFromTheTarget() {
        for target in TrackParameter.modulationTargets where target != .pitch {
            XCTAssertEqual(
                cycle(target: target, depth: 0).modulationResponseRange,
                target.displacementRange,
                "\(target)"
            )
        }
    }

    /// **Pitch se normaliza contra lo que el LFO alcanza, no contra ±28**
    /// (enmienda del 2026-09-16). Su `displacementRange` es el recorrido del
    /// knob —cuatro octavas— y la excursión del LFO es una octava: dibujar la
    /// onda dentro del rango del knob la dejaría en una banda plana en el centro
    /// del panel, que no enseña nada.
    func testThePitchRangeIsWhatTheLFOReaches() {
        let cycle = self.cycle(target: .pitch, depth: 100)
        let reach = cycle.modulationHalfRange

        XCTAssertEqual(cycle.modulationResponseRange, -reach...reach)
        XCTAssertTrue(PitchOffset.validRange.contains(cycle.modulationResponseRange.lowerBound))
        XCTAssertTrue(PitchOffset.validRange.contains(cycle.modulationResponseRange.upperBound))
    }

    /// **El título lo da el motor, no la vista** (NFR6), y usa el término de la
    /// Pre Spec en minúscula (NFR7).
    func testTheTitleNamesTheTargetInLowercase() {
        XCTAssertEqual(
            cycle(target: .velocity, depth: 0).modulationResponseTitle, "velocity response")
        XCTAssertEqual(cycle(target: .pitch, depth: 0).modulationResponseTitle, "pitch response")
        XCTAssertEqual(
            cycle(target: .repeatTime, depth: 0).modulationResponseTitle, "time response")
    }

    /// Los nueve tienen título propio: dos destinos que se rotularan igual
    /// harían imposible saber qué se está mirando.
    func testEveryTargetHasItsOwnTitle() {
        let titles = TrackParameter.modulationTargets.map {
            cycle(target: $0, depth: 0).modulationResponseTitle
        }
        XCTAssertEqual(Set(titles).count, 9)
    }

    // MARK: - La fase (FR20)

    /// **Los Steps que no disparan llevan su valor igualmente.** El LFO corre
    /// sobre ellos (FR15), así que omitirlos mentiría sobre la fase.
    func testTheStepsThatDoNotTriggerStillCarryTheirValue() {
        let cycle = Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!),
            modulation: Modulation(
                waveform: .triangle, depth: Depth(percent: 100)!, target: .sustain)
        )
        let response = cycle.modulationResponse

        XCTAssertTrue(response.contains { !$0.triggers })
        for (step, entry) in response.enumerated() {
            XCTAssertEqual(entry.triggers, cycle.triggers(atStep: step), "step \(step)")
        }
        // El pico está donde está la onda, no donde están los pulsos.
        XCTAssertEqual(response[4].value, 199)
    }

    /// Con `depth` en 0 el panel es una línea recta en el valor base, sea cual
    /// sea el destino: es lo que suena.
    func testWithoutDepthTheResponseIsFlatOnEveryTarget() {
        for target in TrackParameter.modulationTargets {
            let values = cycle(target: target, depth: 0).modulationResponse.map(\.value)
            XCTAssertEqual(Set(values).count, 1, "\(target)")
        }
    }

    /// Tantas entradas como Steps tenga el Cycle, no dieciséis.
    func testTheResponseHasOneEntryPerStep() {
        for stepCount in [1, 9, 16] {
            let cycle = Cycle(
                shape: Shape(steps: Steps(stepCount)!, pulses: Pulses(1)!),
                modulation: Modulation(depth: Depth(percent: 50)!, target: .delay)
            )
            XCTAssertEqual(cycle.modulationResponse.count, stepCount, "\(stepCount) Steps")
        }
    }
}
