import XCTest

@testable import Engine

/// Tests del destino del LFO: qué parámetros admite, cuánto vale `depth` sobre
/// cada uno y cómo viaja el `target` dentro del `Cycle`
/// (`assignable-lfo_20260916`, FR1, FR2, FR6–FR9).
///
/// **Los nueve destinos son los parámetros de evento.** Lo que se decide en
/// cada evento y no define la vuelta. Los seis que quedan fuera lo hacen cada
/// uno por su razón, y esta suite las fija para que añadir un `TrackParameter`
/// sin clasificarlo rompa la compilación en vez de colarse.
///
/// **`depth` es un porcentaje del rango del destino, no unidades.** De ahí que
/// `halfRange` salga de `displacementRange` y no de una tabla escrita aparte:
/// una segunda fuente de verdad se olvidaría al añadir un destino.
final class ModulationTargetTests: XCTestCase {

    // MARK: - Qué parámetros son destino (FR2)

    /// Los nueve, y ninguno más. Test exhaustivo sobre `allCases`, como el de
    /// `isNoteRepeater`: un `TrackParameter` nuevo sin clasificar rompe el
    /// `switch` y, si alguien lo clasificara mal, rompe este test.
    func testTheNineEventParametersAreTargets() {
        let targets = TrackParameter.allCases.filter(\.isModulationTarget)
        XCTAssertEqual(
            Set(targets),
            Set([
                .velocity, .sustain, .timing, .delay,
                .repeats, .repeatTime, .ramp, .pace,
                .pitch,
            ])
        )
        XCTAssertEqual(targets.count, 9)
    }

    /// **`probability` queda fuera por decisión de producto**, y no por una
    /// restricción técnica: nada impediría modularla.
    func testProbabilityIsNotATarget() {
        XCTAssertFalse(TrackParameter.probability.isModulationTarget)
    }

    /// **`steps` y `division` son circulares.** La fase del LFO se calcula
    /// `p = step / stepCount`, así que `steps` *es* el divisor. `division`
    /// además define cuánto dura un Step, y eso mueve instantes.
    func testTheParametersThatDefineTheTurnAreNotTargets() {
        XCTAssertFalse(TrackParameter.steps.isModulationTarget)
        XCTAssertFalse(TrackParameter.division.isModulationTarget)
    }

    /// **`pulses` y `rotate` exigirían reconstruir un `Shape` por Step** en el
    /// hilo del scheduler, y eso asigna. Es la restricción de tiempo real, no
    /// una decisión musical.
    func testTheParametersThatWouldRebuildAShapeAreNotTargets() {
        XCTAssertFalse(TrackParameter.pulses.isModulationTarget)
        XCTAssertFalse(TrackParameter.rotate.isModulationTarget)
    }

    /// **`harmony` no tiene posición**: es estado con historia, round robin con
    /// histéresis. Una onda periódica sobre él no da un resultado repetible,
    /// que es la premisa del producto.
    func testHarmonyIsNotATarget() {
        XCTAssertFalse(TrackParameter.harmony.isModulationTarget)
    }

    /// El orden de `modulationTargets` es el que dibuja la rejilla 3×3 de la
    /// pantalla (FR16), así que es contrato y no un detalle del compilador —
    /// igual que el de `Waveform.allCases`.
    func testTheTargetListKeepsTheOrderTheGridDraws() {
        XCTAssertEqual(
            TrackParameter.modulationTargets,
            [
                .velocity, .sustain, .timing,
                .delay, .repeats, .repeatTime,
                .ramp, .pace, .pitch,
            ]
        )
    }

    /// La lista y la propiedad dicen lo mismo. Son dos vías —una ordenada para
    /// la rejilla, otra para preguntar por uno— y discrepar sería un fallo
    /// silencioso.
    func testTheListAndThePropertyAgree() {
        for parameter in TrackParameter.allCases {
            XCTAssertEqual(
                parameter.isModulationTarget,
                TrackParameter.modulationTargets.contains(parameter),
                "\(parameter) no coincide entre la lista y la propiedad"
            )
        }
    }

    // MARK: - Cuánto vale `depth` sobre cada destino (FR6, FR7)

    /// **`halfRange` sale del rango que el propio parámetro declara** (AC 4).
    /// No se escribe una tabla nueva: se deriva, y este test comprueba que la
    /// derivación es la que se espera destino a destino.
    func testHalfRangeComesFromTheParametersOwnRange() {
        // **`pitch` queda fuera del barrido**: su excursión depende de la escala
        // del Cycle y la decide `Cycle.modulationHalfRange`. Ver el test de
        // abajo.
        for target in TrackParameter.modulationTargets where target != .pitch {
            guard let range = target.displacementRange else {
                return XCTFail("\(target) es destino y no declara rango")
            }
            XCTAssertEqual(
                target.modulationHalfRange,
                (range.upperBound - range.lowerBound) / 2,
                "\(target)"
            )
        }
    }

    /// La tabla concreta, escrita para que un cambio de rango en cualquier tipo
    /// se vea aquí y no se descubra tocando.
    func testTheHalfRangeOfEveryTarget() {
        XCTAssertEqual(TrackParameter.velocity.modulationHalfRange, 63)
        XCTAssertEqual(TrackParameter.sustain.modulationHalfRange, 99)
        XCTAssertEqual(TrackParameter.timing.modulationHalfRange, 12)
        XCTAssertEqual(TrackParameter.delay.modulationHalfRange, 100)
        XCTAssertEqual(TrackParameter.repeats.modulationHalfRange, 4)
        XCTAssertEqual(TrackParameter.repeatTime.modulationHalfRange, 4)
        XCTAssertEqual(TrackParameter.ramp.modulationHalfRange, 100)
        XCTAssertEqual(TrackParameter.pace.modulationHalfRange, 100)
    }

    /// **`pitch` devuelve 0 aquí a propósito** (enmienda del 2026-09-16). Su
    /// `displacementRange` es ±28 grados —cuatro octavas, el recorrido del knob
    /// de transposición— y aplicarlo como profundidad de LFO daba saltos
    /// inservibles. La excursión real es una octava de la escala y la decide el
    /// Cycle, que es quien conoce el marco.
    ///
    /// Devolver 0 y no un número plausible hace que usar esta propiedad para
    /// pitch **apague** la modulación en vez de aplicar una profundidad
    /// equivocada en silencio.
    func testPitchHasNoHalfRangeOfItsOwnHere() {
        XCTAssertEqual(TrackParameter.pitch.modulationHalfRange, 0)
    }

    /// La excursión de pitch es **una octava de la escala del Cycle**: siete
    /// grados en las heptatónicas, cinco en pentatónica y hirajoshi.
    func testThePitchExcursionIsOneOctaveOfTheScale() {
        let shape = Shape(steps: Steps(16)!, pulses: Pulses(1)!)
        for scale in Scale.allCases {
            let cycle = Cycle(shape: shape, frame: TonalFrame(scale: scale, root: .c))
                .with(modulation: Modulation(depth: Depth(percent: 100)!, target: .pitch))
            XCTAssertEqual(cycle.modulationHalfRange, scale.degrees.count, "\(scale)")
        }
    }

    /// Los otros ocho delegan en el `TrackParameter` sin cambios.
    func testTheOtherTargetsDelegateTheirHalfRange() {
        let shape = Shape(steps: Steps(16)!, pulses: Pulses(1)!)
        for target in TrackParameter.modulationTargets where target != .pitch {
            let cycle = Cycle(shape: shape)
                .with(modulation: Modulation(depth: Depth(percent: 50)!, target: target))
            XCTAssertEqual(cycle.modulationHalfRange, target.modulationHalfRange, "\(target)")
        }
    }

    /// **El 63 de velocity no es un número nuevo: es el que la fórmula vieja
    /// llevaba escrito.** Generalizar no puede cambiarlo, y de eso depende AC 1.
    func testVelocityKeepsTheSixtyThreeTheOldFormulaHadWrittenIn() {
        XCTAssertEqual(TrackParameter.velocity.modulationHalfRange, 63)
    }

    /// Los que no son destino no tienen media excursión que ofrecer. Devuelven
    /// 0, que es lo que apaga la modulación — no un valor plausible que hiciera
    /// sonar algo por accidente.
    func testNonTargetsHaveNoHalfRange() {
        for parameter in TrackParameter.allCases where !parameter.isModulationTarget {
            XCTAssertEqual(parameter.modulationHalfRange, 0, "\(parameter)")
        }
    }

    // MARK: - No regresión sobre velocity (AC 1)

    /// **La fórmula vieja como oráculo.** Con `target = .velocity`, el offset
    /// generalizado tiene que devolver exactamente lo que devolvía
    /// `wave · depth · 63 / 10000`, para las cuatro ondas, todo el rango de
    /// `depth` y toda vuelta de 1 a 64 Steps.
    ///
    /// Es el test que sostiene la rebanada: si generalizar hubiera movido un
    /// número, el destino ya entregado sonaría distinto.
    func testOnVelocityTheGeneralisedFormulaMatchesTheOldOneExactly() {
        for waveform in Waveform.allCases {
            for percent in stride(from: -100, through: 100, by: 1) {
                let modulation = Modulation(
                    waveform: waveform,
                    depth: Depth(percent: percent)!,
                    target: .velocity
                )
                for stepCount in 1...64 {
                    for step in 0..<stepCount {
                        let expected =
                            percent == 0
                            ? 0
                            : waveform.value(atStep: step, of: stepCount) * percent * 63 / 10000
                        XCTAssertEqual(
                            modulation.offset(atStep: step, of: stepCount),
                            expected,
                            "\(waveform) depth \(percent) step \(step)/\(stepCount)"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Simetría del signo (AC 3)

    /// Para todo destino y todo Step, el offset con `+n` es el complemento
    /// exacto del de `−n`. Lo garantiza que la división trunque hacia cero.
    func testTheSignIsSymmetricOnEveryTarget() {
        for target in TrackParameter.modulationTargets {
            for waveform in Waveform.allCases {
                for percent in stride(from: 1, through: 100, by: 7) {
                    let up = Modulation(
                        waveform: waveform, depth: Depth(percent: percent)!, target: target)
                    let down = Modulation(
                        waveform: waveform, depth: Depth(percent: -percent)!, target: target)
                    for step in 0..<16 {
                        XCTAssertEqual(
                            up.offset(atStep: step, of: 16),
                            -down.offset(atStep: step, of: 16),
                            "\(target) \(waveform) depth \(percent) step \(step)"
                        )
                    }
                }
            }
        }
    }

    // MARK: - El neutro (AC 2)

    /// Con `depth = 0` el offset es 0 en los nueve destinos, sin pasar por la
    /// onda. Es la no regresión de la rebanada y lo que hace que el camino
    /// nuevo no cueste nada a quien no lo pide.
    func testWithoutDepthThereIsNoOffsetOnAnyTarget() {
        for target in TrackParameter.modulationTargets {
            for waveform in Waveform.allCases {
                let modulation = Modulation(waveform: waveform, depth: .default, target: target)
                for step in 0..<16 {
                    XCTAssertEqual(modulation.offset(atStep: step, of: 16), 0, "\(target)")
                }
            }
        }
    }

    // MARK: - El `target` dentro de `Modulation` (FR1, FR9)

    /// El default apunta a velocity, que es el destino que la rebanada anterior
    /// entregó: un `Cycle` construido sin decir nada suena como antes.
    func testTheTargetDefaultsToVelocity() {
        XCTAssertEqual(Modulation.default.target, .velocity)
        XCTAssertEqual(Modulation().target, .velocity)
    }

    /// **Cambiar de destino conserva `depth`** (AC 7). El número mide
    /// intensidad relativa, así que significa lo mismo en los nueve y el slider
    /// no se mueve al cambiar de destino.
    func testChangingTheTargetKeepsTheDepthAndTheWaveform() {
        let modulation = Modulation(waveform: .pulse, depth: Depth(percent: 40)!, target: .velocity)
        let moved = modulation.with(target: .pitch)

        XCTAssertEqual(moved.target, .pitch)
        XCTAssertEqual(moved.depth.percent, 40)
        XCTAssertEqual(moved.waveform, .pulse)
    }

    /// Y al revés: mover `depth` o la onda no mueve el destino.
    func testChangingTheDepthOrTheWaveformKeepsTheTarget() {
        let modulation = Modulation(waveform: .saw, depth: Depth(percent: 10)!, target: .sustain)

        XCTAssertEqual(modulation.with(depth: Depth(percent: -60)!).target, .sustain)
        XCTAssertEqual(modulation.with(waveform: .sine).target, .sustain)
    }

    /// **Un parámetro que no es destino cae en `.velocity`** (FR2). Puede
    /// llegar de un fichero de otra versión, y un Bank no se queda sin abrir por
    /// un byte malo.
    func testAParameterThatIsNotATargetFallsBackToVelocity() {
        XCTAssertEqual(Modulation(target: .probability).target, .velocity)
        XCTAssertEqual(Modulation(target: .harmony).target, .velocity)
        XCTAssertEqual(Modulation(target: .steps).target, .velocity)
        XCTAssertEqual(Modulation.default.with(target: .rotate).target, .velocity)
    }

    /// Los nueve sobreviven a la ida y vuelta por el campo almacenado. Es un
    /// byte, y un byte mal mapeado cambiaría de destino en silencio.
    func testEveryTargetSurvivesBeingStored() {
        for target in TrackParameter.modulationTargets {
            XCTAssertEqual(Modulation(target: target).target, target, "\(target)")
        }
    }

    /// La igualdad distingue dos modulaciones que solo difieren en el destino.
    /// Sin esto, un `Cycle` editado no se vería como cambiado.
    func testEqualityDistinguishesTheTarget() {
        let depth = Depth(percent: 30)!
        XCTAssertNotEqual(
            Modulation(waveform: .sine, depth: depth, target: .velocity),
            Modulation(waveform: .sine, depth: depth, target: .timing)
        )
    }

    // MARK: - El `target` dentro del `Cycle` (FR1, AC 13)

    /// El `Cycle` sigue siendo POD con el campo nuevo: el snapshot cruza al
    /// hilo del scheduler y de ello depende que copiarlo sea trivial.
    func testTheCycleIsStillPOD() {
        XCTAssertTrue(_isPOD(Cycle.self), "el Cycle dejó de ser trivial")
    }

    /// Editar cualquier otra cosa del `Cycle` conserva el destino. Es la regla
    /// de `with(...)`: lo que no se nombra no se pierde.
    func testEditingTheCycleKeepsTheTarget() {
        let cycle = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!)).with(
            modulation: Modulation(waveform: .saw, depth: Depth(percent: 20)!, target: .delay))

        XCTAssertEqual(cycle.with(channel: Channel(5)!).modulation.target, TrackParameter.delay)
        XCTAssertEqual(
            cycle.applying(1, to: TrackParameter.velocity).modulation.target,
            TrackParameter.delay)
        XCTAssertEqual(
            cycle.applying(-2, to: TrackParameter.steps).modulation.target,
            TrackParameter.delay)
    }

    // MARK: - El destino decide qué se modula (FR11)

    /// **Un destino que no es de Groove deja el Groove intacto.** Los otros
    /// cinco los cubren `NoteRepeater.modulated` y `Cycle.modulationPitchShift`;
    /// lo que este método no puede hacer es seguir modulando la velocity cuando
    /// el destino es otro, que sería modular lo que no se pidió.
    ///
    /// > **Sustituye a un test de la fase anterior.** Entonces `Groove.modulated`
    /// > solo aplicaba velocity y este test comprobaba que `sustain` salía
    /// > intacto. Ya no: `sustain`, `timing` y `delay` son destinos suyos, y el
    /// > detalle de cada uno vive en `ModulationAppliesTests`.
    func testAGrooveIsUntouchedWhenTheTargetIsNotItsOwn() {
        let groove = Groove.default
        let modulation = Modulation(
            waveform: .triangle, depth: Depth(percent: 100)!, target: .repeats)

        for step in 0..<16 {
            XCTAssertEqual(groove.modulated(by: modulation, atStep: step, of: 16), groove)
        }
    }

    /// Y con velocity sigue modulando exactamente como antes del track.
    func testAGrooveIsStillModulatedWhenTheTargetIsVelocity() {
        let groove = Groove.default
        let modulation = Modulation(
            waveform: .triangle, depth: Depth(percent: 100)!, target: .velocity)
        let peak = groove.modulated(by: modulation, atStep: 4, of: 16)

        XCTAssertEqual(
            peak.velocity.value,
            groove.velocity.advanced(by: 63).value
        )
    }
}
