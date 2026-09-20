import XCTest

@testable import Engine

/// Tests de los tres puntos donde el LFO se aplica
/// (`assignable-lfo_20260916`, FR10–FR14).
///
/// **Tres métodos y no uno.** `Groove`, `NoteRepeater` y el desplazamiento de
/// pitch, cada uno con salida temprana si el destino no es suyo. Un
/// `Cycle.modulated(atStep:of:)` único se leería mejor y **construiría un Cycle
/// por Step** en el hilo del scheduler, que es lo que NFR1 prohíbe.
///
/// **La base es el valor actual y se recorta en los extremos** (FR10). El LFO
/// desplaza alrededor de lo que el knob tiene puesto; no recentra nada, porque
/// eso destruiría el ajuste del knob. Varios destinos tienen su neutro en un
/// extremo —`repeats` empieza en 0, `sustain` en 1— y ahí media onda se recorta
/// entera: es correcto, y el panel de la pantalla lo enseña.
final class ModulationAppliesTests: XCTestCase {

    private let shape = Shape(steps: Steps(16)!, pulses: Pulses(5)!)

    /// `triangle` con `depth` al máximo: el pico cae en el Step 4 de dieciséis
    /// (un cuarto de vuelta) y el valle en el 12.
    private func fullDepth(on target: TrackParameter) -> Modulation {
        Modulation(waveform: .triangle, depth: Depth(percent: 100)!, target: target)
    }

    // MARK: - Groove (FR11)

    /// Con el destino en velocity, el pico desplaza `halfRange` unidades — 63 —
    /// y los otros cuatro campos salen intactos.
    func testVelocityMovesAtThePeakAndLeavesTheRestAlone() {
        let groove = Groove.default
        let peak = groove.modulated(by: fullDepth(on: .velocity), atStep: 4, of: 16)

        XCTAssertEqual(peak.velocity, groove.velocity.advanced(by: 63))
        XCTAssertEqual(peak.sustain, groove.sustain)
        XCTAssertEqual(peak.probability, groove.probability)
        XCTAssertEqual(peak.timing, groove.timing)
        XCTAssertEqual(peak.delay, groove.delay)
    }

    /// Sustain con su propio `halfRange`, que es 99: `Sustain.validRange` es
    /// 1…200.
    func testSustainMovesAtThePeakAndLeavesTheRestAlone() {
        let groove = Groove.default
        let peak = groove.modulated(by: fullDepth(on: .sustain), atStep: 4, of: 16)

        XCTAssertEqual(peak.sustain, groove.sustain.advanced(by: 99))
        XCTAssertEqual(peak.velocity, groove.velocity)
        XCTAssertEqual(peak.probability, groove.probability)
    }

    /// **Timing sí mueve instantes, y es lo que Timing hace** (FR12). Su rango
    /// es estrecho —50…75— así que su `halfRange` es 12, y el LFO no puede
    /// producir ningún desplazamiento que el knob no pudiera producir.
    func testTimingMovesAtThePeakAndLeavesTheRestAlone() {
        let groove = Groove.default
        let peak = groove.modulated(by: fullDepth(on: .timing), atStep: 4, of: 16)

        XCTAssertEqual(peak.timing, groove.timing.advanced(by: 12))
        XCTAssertEqual(peak.velocity, groove.velocity)
        XCTAssertEqual(peak.delay, groove.delay)
    }

    /// Delay, el otro que mueve instantes. Bipolar, `halfRange` 100.
    func testDelayMovesAtThePeakAndLeavesTheRestAlone() {
        let groove = Groove.default
        let peak = groove.modulated(by: fullDepth(on: .delay), atStep: 4, of: 16)

        XCTAssertEqual(peak.delay, groove.delay.advanced(by: 100))
        XCTAssertEqual(peak.velocity, groove.velocity)
        XCTAssertEqual(peak.timing, groove.timing)
    }

    /// **`probability` no es destino y nunca se modula.** Aunque alguien
    /// construyera la `Modulation` apuntándola, el destino cae en `.velocity`.
    func testProbabilityIsNeverModulated() {
        let groove = Groove.default
        for step in 0..<16 {
            let modulated = groove.modulated(by: fullDepth(on: .probability), atStep: step, of: 16)
            XCTAssertEqual(modulated.probability, groove.probability, "step \(step)")
        }
    }

    /// Con un destino que no es de Groove, devuelve `self` sin construir nada.
    func testAGrooveComesBackUntouchedWhenTheTargetIsNotItsOwn() {
        let groove = Groove.default
        for target in [TrackParameter.repeats, .repeatTime, .ramp, .pace, .pitch] {
            for step in 0..<16 {
                XCTAssertEqual(
                    groove.modulated(by: fullDepth(on: target), atStep: step, of: 16),
                    groove,
                    "\(target) step \(step)"
                )
            }
        }
    }

    /// **El recorte en el extremo bajo** (FR10, AC 5). Con `sustain = 1` —el
    /// mínimo— la mitad baja de la onda no tiene a dónde ir y se queda en 1. No
    /// envuelve al máximo, que sería el cambio más brutal que el parámetro
    /// admite.
    func testSustainAtItsFloorClipsInsteadOfWrapping() {
        let groove = Groove(
            velocity: .default, sustain: Sustain(percent: 1)!, probability: .default)
        let modulation = Modulation(
            waveform: .triangle, depth: Depth(percent: -100)!, target: .sustain)

        for step in 0..<16 {
            let value = groove.modulated(by: modulation, atStep: step, of: 16).sustain.percent
            XCTAssertGreaterThanOrEqual(value, Sustain.validRange.lowerBound, "step \(step)")
            XCTAssertLessThanOrEqual(value, Sustain.validRange.upperBound, "step \(step)")
        }
        // En el valle de una onda invertida —el pico de la subida— se queda en
        // el suelo en vez de dar la vuelta.
        XCTAssertEqual(groove.modulated(by: modulation, atStep: 4, of: 16).sustain.percent, 1)
    }

    // MARK: - Note Repeater (FR11, FR14)

    /// Los cuatro mueven lo suyo y dejan los otros tres intactos.
    func testEachNoteRepeaterTargetMovesOnlyItself() {
        let repeater = NoteRepeater(
            repeats: Repeats(4)!, time: .default, ramp: .default, pace: .default)

        let repeats = repeater.modulated(by: fullDepth(on: .repeats), atStep: 4, of: 16)
        XCTAssertEqual(repeats.repeats, repeater.repeats.advanced(by: 4))
        XCTAssertEqual(repeats.time, repeater.time)
        XCTAssertEqual(repeats.ramp, repeater.ramp)
        XCTAssertEqual(repeats.pace, repeater.pace)

        let ramp = repeater.modulated(by: fullDepth(on: .ramp), atStep: 4, of: 16)
        XCTAssertEqual(ramp.ramp, repeater.ramp.advanced(by: 100))
        XCTAssertEqual(ramp.repeats, repeater.repeats)

        let pace = repeater.modulated(by: fullDepth(on: .pace), atStep: 4, of: 16)
        XCTAssertEqual(pace.pace, repeater.pace.advanced(by: 100))
        XCTAssertEqual(pace.repeats, repeater.repeats)
    }

    /// **`repeatTime` se mueve por posiciones de `RepeatTime.ordered`** (FR14),
    /// como hace el knob. Nunca produce una fracción que no esté en la lista.
    func testRepeatTimeMovesThroughItsOwnList() {
        let repeater = NoteRepeater(repeats: Repeats(2)!, time: .default)
        let modulation = Modulation(
            waveform: .triangle, depth: Depth(percent: 100)!, target: .repeatTime)

        for step in 0..<16 {
            let time = repeater.modulated(by: modulation, atStep: step, of: 16).time
            XCTAssertTrue(RepeatTime.ordered.contains(time), "step \(step)")
        }
        XCTAssertEqual(
            repeater.modulated(by: modulation, atStep: 4, of: 16).time,
            repeater.time.advanced(by: 4)
        )
    }

    /// **El recorte con `repeats = 0` y una onda de dos valores** (AC 5). Media
    /// vuelta sube al tope y media se queda en 0, sin salir del rango.
    func testRepeatsAtZeroClipsTheLowerHalfOfAPulse() {
        let repeater = NoteRepeater()
        let modulation = Modulation(
            waveform: .pulse, depth: Depth(percent: 100)!, target: .repeats)

        for step in 0..<8 {
            XCTAssertEqual(
                repeater.modulated(by: modulation, atStep: step, of: 16).repeats.count,
                4,
                "la mitad alta sube al tope de la excursión: step \(step)"
            )
        }
        for step in 8..<16 {
            XCTAssertEqual(
                repeater.modulated(by: modulation, atStep: step, of: 16).repeats.count,
                0,
                "la mitad baja se recorta en 0 y no envuelve: step \(step)"
            )
        }
    }

    /// Con un destino que no es del Note Repeater, devuelve `self`.
    func testANoteRepeaterComesBackUntouchedWhenTheTargetIsNotItsOwn() {
        let repeater = NoteRepeater(repeats: Repeats(3)!)
        for target in [TrackParameter.velocity, .sustain, .timing, .delay, .pitch] {
            for step in 0..<16 {
                XCTAssertEqual(
                    repeater.modulated(by: fullDepth(on: target), atStep: step, of: 16),
                    repeater,
                    "\(target) step \(step)"
                )
            }
        }
    }

    // MARK: - El neutro (AC 2)

    /// Con `depth = 0` los dos devuelven `self` en los nueve destinos, sin pasar
    /// por la onda. Es lo que hace que el camino nuevo no cueste nada a quien no
    /// lo pide.
    func testWithoutDepthNothingIsModulatedOnAnyTarget() {
        let groove = Groove.default
        let repeater = NoteRepeater(repeats: Repeats(3)!)

        for target in TrackParameter.modulationTargets {
            let modulation = Modulation(waveform: .saw, depth: .default, target: target)
            for step in 0..<16 {
                XCTAssertEqual(groove.modulated(by: modulation, atStep: step, of: 16), groove)
                XCTAssertEqual(repeater.modulated(by: modulation, atStep: step, of: 16), repeater)
            }
        }
    }

    // MARK: - Pitch (FR13, AC 6)

    private func tonalCycle(
        pool: [Int], pitchOffset: PitchOffset = .zero, modulation: Modulation = .default
    ) -> Cycle {
        var pitches = PitchPool()
        for value in pool { pitches = pitches.inserting(Pitch(value)!) }
        return Cycle(shape: shape, pool: pitches)
            .with(modulation: modulation, pitchOffset: pitchOffset)
    }

    /// El LFO transpone la altura del Step en grados de la escala, por la misma
    /// vía que el knob.
    func testPitchIsTransposedInDegreesOfTheScale() {
        let cycle = tonalCycle(
            pool: [60, 64, 67],
            modulation: Modulation(
                waveform: .triangle, depth: Depth(percent: 100)!, target: .pitch)
        )

        // En el pico la excursión es **una octava de la escala**: el marco por
        // defecto es Do menor, que tiene siete grados.
        XCTAssertEqual(cycle.modulationPitchShift(atStep: 4, of: 16), 7)
        // En el arranque la triangular vale 0: no desplaza.
        XCTAssertEqual(cycle.modulationPitchShift(atStep: 0, of: 16), 0)
    }

    /// **Respeta el freno atómico de `pitch-harmony_20260912`** (AC 6). Con un
    /// pool pegado al techo del marco, el LFO se frena donde el knob se
    /// frenaría: ninguna altura sale de 0–127.
    func testPitchStopsWhereTheKnobWouldStop() {
        let cycle = tonalCycle(
            pool: [120, 123, 127],
            modulation: Modulation(
                waveform: .triangle, depth: Depth(percent: 100)!, target: .pitch)
        )

        for step in 0..<16 {
            let shift = cycle.modulationPitchShift(atStep: step, of: 16)
            // El oráculo: el mismo desplazamiento pedido al knob, con la
            // excursión de una octava que el Cycle decide.
            let excursion =
                cycle.modulation.waveform.value(atStep: step, of: 16)
                * cycle.modulation.depth.percent * cycle.modulationHalfRange / 10000
            XCTAssertEqual(
                shift,
                cycle.pitchOffset(movedBy: excursion).degrees - cycle.pitchOffset.degrees,
                "el LFO y el knob discrepan en el step \(step)"
            )
            let pitch = cycle.modulatedPitch(atStep: step, of: 16)
            if let pitch {
                XCTAssertTrue(Pitch.validRange.contains(pitch.value), "step \(step)")
                XCTAssertTrue(cycle.frame.allows(pitch), "fuera de la escala: step \(step)")
            }
        }
    }

    /// Con el pool vacío no hay altura que mover, y el desplazamiento se mueve
    /// libre dentro de ±28 sin reventar.
    func testPitchWithAnEmptyPoolDoesNotBreak() {
        let cycle = tonalCycle(
            pool: [],
            modulation: Modulation(
                waveform: .triangle, depth: Depth(percent: 100)!, target: .pitch)
        )

        XCTAssertNil(cycle.modulatedPitch(atStep: 4, of: 16))
        XCTAssertEqual(cycle.modulationPitchShift(atStep: 4, of: 16), 7)
    }

    /// **El LFO no toca Harmony.** Son dos ejes distintos: Pitch transpone el
    /// pool entero y Harmony mueve una voz. Modular uno no puede mover el otro.
    func testTheLFODoesNotTouchHarmony() {
        let cycle = tonalCycle(
            pool: [60, 64, 67],
            modulation: Modulation(
                waveform: .saw, depth: Depth(percent: 80)!, target: .pitch)
        )

        for step in 0..<16 {
            _ = cycle.modulatedPitch(atStep: step, of: 16)
        }
        XCTAssertEqual(cycle.harmony, .clean)
    }

    /// **El desplazamiento del LFO no se persiste**: es del Step, no del Cycle.
    /// Tras recorrer la vuelta entera, `pitchOffset` sigue siendo el que puso el
    /// knob. Si se escribiera, el LFO dejaría de ser un LFO y sería un knob que
    /// gira solo.
    func testThePitchShiftIsNotWrittenBackIntoTheCycle() {
        let cycle = tonalCycle(
            pool: [60, 64, 67],
            pitchOffset: PitchOffset(3)!,
            modulation: Modulation(
                waveform: .triangle, depth: Depth(percent: 100)!, target: .pitch)
        )

        for step in 0..<16 {
            _ = cycle.modulatedPitch(atStep: step, of: 16)
        }
        XCTAssertEqual(cycle.pitchOffset.degrees, 3)
    }

    /// **El LFO no mueve una altura más de una octava** (enmienda del
    /// 2026-09-16). Es la regresión del defecto que encontró la verificación en
    /// dispositivo: con la regla general —media excursión de
    /// `displacementRange`— el pico saltaba hasta veintiocho grados, que son
    /// cuatro octavas, y sonaba como un error aunque la nota estuviera dentro de
    /// la escala.
    ///
    /// Se barren las ocho escalas, los doce roots y los dos signos de `depth`,
    /// porque el defecto se veía con los negativos y era igual de cierto con los
    /// positivos — sólo que ahí el freno del pool lo tapaba a veces.
    func testTheLFONeverMovesAPitchMoreThanOneOctave() {
        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                let frame = TonalFrame(scale: scale, root: Root(rootValue)!)
                var pool = PitchPool()
                for value in [60, 63, 67] { pool = pool.inserting(Pitch(value)!) }

                for depth in [-100, -50, 50, 100] {
                    let cycle = Cycle(shape: shape, pool: pool, frame: frame)
                        .with(
                            modulation: Modulation(
                                waveform: .triangle,
                                depth: Depth(percent: depth)!,
                                target: .pitch))

                    for step in 0..<16 {
                        let shift = cycle.modulationPitchShift(atStep: step, of: 16)
                        XCTAssertLessThanOrEqual(
                            abs(shift), frame.degreesPerOctave,
                            "\(scale) root \(rootValue) depth \(depth) step \(step)"
                        )
                    }
                }
            }
        }
    }

    /// **Y ninguna altura que el LFO mueve sale de la escala.** Estaba ya
    /// garantizado —`frame.pitch(atDegree:)` solo devuelve alturas del marco—
    /// pero es lo que la verificación en dispositivo creyó estar viendo, así que
    /// queda atado: lo que se oía como «fuera de la escala» era la distancia, no
    /// la altura.
    func testNoPitchTheLFOMovesLeavesTheScale() {
        for scale in Scale.allCases {
            for rootValue in 0..<12 {
                let frame = TonalFrame(scale: scale, root: Root(rootValue)!)
                var pool = PitchPool()
                for value in [60, 64, 67] { pool = pool.inserting(Pitch(value)!) }

                for depth in [-100, 100] {
                    let cycle = Cycle(shape: shape, pool: pool, frame: frame)
                        .with(
                            modulation: Modulation(
                                waveform: .triangle,
                                depth: Depth(percent: depth)!,
                                target: .pitch))

                    for step in 0..<16 {
                        guard cycle.modulationPitchShift(atStep: step, of: 16) != 0,
                            let pitch = cycle.modulatedPitch(atStep: step, of: 16)
                        else { continue }
                        XCTAssertTrue(
                            frame.allows(pitch),
                            "\(scale) root \(rootValue) depth \(depth) step \(step): \(pitch.value)"
                        )
                        XCTAssertTrue(Pitch.validRange.contains(pitch.value))
                    }
                }
            }
        }
    }

    /// Con otro destino, la altura es la de siempre: `modulatedPitch` devuelve
    /// exactamente lo que devuelve `pitch(atStep:)`.
    func testThePitchIsUntouchedWhenTheTargetIsNotPitch() {
        for target in [TrackParameter.velocity, .sustain, .repeats, .ramp] {
            let cycle = tonalCycle(pool: [60, 64, 67], modulation: fullDepth(on: target))
            for step in 0..<16 {
                XCTAssertEqual(
                    cycle.modulatedPitch(atStep: step, of: 16),
                    cycle.pitch(atStep: step),
                    "\(target) step \(step)"
                )
                XCTAssertEqual(cycle.modulationPitchShift(atStep: step, of: 16), 0)
            }
        }
    }

    /// Y con `depth = 0` tampoco, aunque el destino sea pitch: es AC 2 sobre el
    /// destino más caro de los nueve.
    func testThePitchIsUntouchedWithoutDepth() {
        let cycle = tonalCycle(
            pool: [60, 64, 67],
            modulation: Modulation(waveform: .triangle, depth: .default, target: .pitch)
        )
        for step in 0..<16 {
            XCTAssertEqual(cycle.modulatedPitch(atStep: step, of: 16), cycle.pitch(atStep: step))
        }
    }
}
