import Engine
import XCTest

@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre.
private typealias Pattern = Engine.Pattern

/// Tests del LFO asignable en el camino de emisión
/// (`assignable-lfo_20260916`, FR11–FR15, AC 1, AC 2).
///
/// **Lo que se comprueba aquí y no en `Engine`** es que el scheduler llame a los
/// tres puntos de aplicación en el sitio correcto: que `timing` y `delay` muevan
/// de verdad el instante —viven dentro de `shiftNanoseconds`, así que el
/// desplazamiento tiene que calcularse con el Groove **ya modulado**—, que la
/// altura pase por el LFO, y que el Note Repeater se module **antes** de contar
/// sus repeticiones.
///
/// **El LFO no consume aleatoriedad.** La fase sale del índice del Step, así que
/// con `depth` en 0 la secuencia emitida es idéntica a la de un Cycle sin
/// modulación: mismos instantes, mismas velocities y las mismas omisiones de
/// Probability.
final class ModulationTargetInSchedulerTests: XCTestCase {

    private let stepNanoseconds: Int64 = 125_000_000
    private let timeline = MusicalTimeline(
        tempo: Tempo(beatsPerMinute: 120)!,
        division: .sixteenth
    )

    private func pool() -> PitchPool {
        var pool = PitchPool()
        // Do menor, que es el marco por defecto del Cycle: las tres están
        // dentro de la escala, así que el test habla del LFO y no del reencuadre.
        for value in [60, 63, 67] { pool = pool.toggling(Pitch(value)!) }
        return pool
    }

    private func cycle(
        target: TrackParameter,
        depth: Int,
        waveform: Waveform = .triangle,
        repeats: Int = 0,
        probability: Int = 100
    ) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!),
            pool: pool(),
            groove: Groove(
                velocity: Velocity(100)!,
                sustain: .default,
                probability: Probability(percent: probability)!
            ),
            noteRepeater: NoteRepeater(repeats: Repeats(repeats)!),
            modulation: Modulation(
                waveform: waveform, depth: Depth(percent: depth)!, target: target)
        )
    }

    /// Un evento tal y como sale del scheduler: lo que hace falta para
    /// distinguir los nueve destinos.
    private struct Event {
        let step: Int
        let pitch: Int?
        let velocity: Int
        let sustain: Int
        let offset: Int64
    }

    private func emitted(_ cycle: Cycle, rounds: Int = 1) -> [Event] {
        var scheduler = TrackScheduler(timeline: timeline, material: .cycle(cycle))
        var result: [Event] = []
        scheduler.advance(
            toHorizon: Int64(16 * rounds) * stepNanoseconds,
            refreshingFrom: nil
        ) { _, step, pitch, groove, offset in
            result.append(
                Event(
                    step: step,
                    pitch: pitch?.value,
                    velocity: groove.velocity.value,
                    sustain: groove.sustain.percent,
                    offset: offset
                ))
        }
        return result
    }

    /// Las repeticiones que colgaron de cada Pulse, con su altura y su velocity.
    private func repetitions(_ cycle: Cycle) -> [(step: Int, pitch: Int?, velocity: Int)] {
        var scheduler = TrackScheduler(timeline: timeline, material: .cycle(cycle))
        var result: [(Int, Int?, Int)] = []
        scheduler.advance(
            toHorizon: 16 * stepNanoseconds,
            refreshingFrom: nil,
            emitRepetition: { _, step, pitch, velocity, _, _ in
                result.append((step, pitch?.value, velocity.value))
            },
            emit: { _, _, _, _, _ in }
        )
        return result
    }

    // MARK: - AC 2: el neutro, en los nueve destinos

    /// **Con `depth = 0` la secuencia es idéntica sea cual sea el destino**:
    /// mismos Steps, mismas alturas, mismas velocities, mismos instantes. Es la
    /// no regresión de la rebanada, y lo que hace que el camino nuevo no cueste
    /// nada a quien no lo pide.
    func testWithoutDepthEveryTargetEmitsTheSameSequence() {
        let reference = emitted(cycle(target: .velocity, depth: 0))

        for target in TrackParameter.modulationTargets {
            for waveform in Waveform.allCases {
                let events = emitted(cycle(target: target, depth: 0, waveform: waveform))
                XCTAssertEqual(events.map(\.step), reference.map(\.step), "\(target) \(waveform)")
                XCTAssertEqual(events.map(\.pitch), reference.map(\.pitch), "\(target) \(waveform)")
                XCTAssertEqual(
                    events.map(\.velocity), reference.map(\.velocity), "\(target) \(waveform)")
                XCTAssertEqual(
                    events.map(\.offset), reference.map(\.offset), "\(target) \(waveform)")
            }
        }
    }

    /// **Y el consumo de aleatoriedad tampoco cambia.** Con Probability por
    /// debajo de 100, las omisiones de un Cycle con el LFO puesto y `depth` en 0
    /// son exactamente las del mismo Cycle sin modulación.
    func testWithoutDepthTheRandomnessIsConsumedIdentically() {
        let plain = Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!),
            pool: pool(),
            groove: Groove(
                velocity: Velocity(100)!,
                sustain: .default,
                probability: Probability(percent: 50)!
            )
        )

        for target in TrackParameter.modulationTargets {
            let modulated = plain.with(
                modulation: Modulation(waveform: .saw, depth: .default, target: target))
            XCTAssertEqual(
                emitted(modulated, rounds: 4).map(\.step),
                emitted(plain, rounds: 4).map(\.step),
                "\(target)"
            )
        }
    }

    // MARK: - Cada destino mueve lo suyo, y solo lo suyo

    /// Velocity: la de siempre. Con `depth = +100` y `triangle`, el pico del
    /// cuarto de vuelta sube 63 unidades.
    func testVelocityFollowsTheWave() {
        let events = emitted(cycle(target: .velocity, depth: 100))

        XCTAssertEqual(events[0].velocity, 100)
        XCTAssertEqual(events[4].velocity, 127, "el pico recorta contra el techo MIDI")
        XCTAssertEqual(events[8].velocity, 100)
        // Ni las alturas ni los instantes se mueven.
        XCTAssertEqual(
            events.map(\.offset),
            emitted(cycle(target: .velocity, depth: 0)).map(\.offset)
        )
    }

    /// Sustain: cambia el gate y deja la velocity quieta.
    func testSustainFollowsTheWaveAndLeavesTheVelocityAlone() {
        let events = emitted(cycle(target: .sustain, depth: 100))

        XCTAssertEqual(events[0].sustain, 100)
        XCTAssertEqual(events[4].sustain, 199, "100 + el halfRange de Sustain, que es 99")
        XCTAssertTrue(events.allSatisfy { $0.velocity == 100 })
    }

    /// **`timing` mueve el instante** (FR12), y esa es la comprobación que solo
    /// se puede hacer aquí: Timing vive dentro de `shiftNanoseconds`, así que si
    /// el desplazamiento se calculara con el Groove sin modular, este test
    /// saldría igual que el neutro.
    func testTimingMovesTheInstant() {
        let modulated = emitted(cycle(target: .timing, depth: 100)).map(\.offset)
        let neutral = emitted(cycle(target: .timing, depth: 0)).map(\.offset)

        XCTAssertNotEqual(modulated, neutral, "el LFO de Timing no movió ningún instante")
        // El Step 0 no se mueve: la triangular vale 0 en el arranque.
        XCTAssertEqual(modulated[0], neutral[0])

        // **Se mira un Step impar, y no el pico.** El swing de Timing solo
        // desplaza los Steps impares —es lo que hace que sea swing y no un
        // retardo— y el pico de la triangular cae en el Step 4, que es par. Con
        // el pico no se vería nada y el test mentiría sobre el parámetro.
        XCTAssertNotEqual(modulated[3], neutral[3])
        XCTAssertNotEqual(modulated[5], neutral[5])
    }

    /// `delay` es el otro que mueve instantes, y con más recorrido: su
    /// `halfRange` es 100 contra los 12 de Timing.
    func testDelayMovesTheInstant() {
        let modulated = emitted(cycle(target: .delay, depth: 100)).map(\.offset)
        let neutral = emitted(cycle(target: .delay, depth: 0)).map(\.offset)

        XCTAssertNotEqual(modulated, neutral)
        XCTAssertEqual(modulated[0], neutral[0])
        XCTAssertGreaterThan(modulated[4], neutral[4], "el pico atrasa el evento")
    }

    /// **`pitch` cambia la altura emitida** y nada más.
    func testPitchChangesTheEmittedNote() {
        let modulated = emitted(cycle(target: .pitch, depth: 100))
        let neutral = emitted(cycle(target: .pitch, depth: 0))

        XCTAssertNotEqual(modulated.map(\.pitch), neutral.map(\.pitch))
        XCTAssertEqual(modulated[0].pitch, neutral[0].pitch, "la triangular vale 0 en el arranque")
        XCTAssertNotEqual(modulated[4].pitch, neutral[4].pitch)
        // Ni la velocity ni los instantes se mueven.
        XCTAssertEqual(modulated.map(\.velocity), neutral.map(\.velocity))
        XCTAssertEqual(modulated.map(\.offset), neutral.map(\.offset))
    }

    /// Toda altura emitida sigue dentro de 0–127 y dentro de la escala, también
    /// con el LFO al máximo (AC 6 visto desde el camino de emisión).
    func testEveryModulatedPitchStaysInsideTheFrame() {
        for depth in [-100, -50, 50, 100] {
            let cycle = self.cycle(target: .pitch, depth: depth)
            for event in emitted(cycle, rounds: 2) {
                guard let value = event.pitch else { continue }
                XCTAssertTrue(Pitch.validRange.contains(value), "depth \(depth)")
                XCTAssertTrue(cycle.frame.allows(Pitch(value)!), "depth \(depth), fuera de escala")
            }
        }
    }

    // MARK: - El Note Repeater (FR11)

    /// **`repeats` a 0 y el LFO puesto: las repeticiones aparecen donde la onda
    /// sube.** Es la comprobación de que el Note Repeater se modula **antes** de
    /// contar: preguntar primero por el valor base habría salido por el `guard`
    /// y no habría repetido nunca.
    func testRepeatsAtZeroStillRepeatsWhereTheWaveRises() {
        let repetitions = self.repetitions(
            cycle(target: .repeats, depth: 100, waveform: .pulse))

        XCTAssertFalse(repetitions.isEmpty, "el LFO de Repeats no generó ninguna repetición")
        // `pulse` está arriba la primera media vuelta y abajo la segunda.
        XCTAssertTrue(repetitions.allSatisfy { $0.step < 8 })
    }

    /// Con `depth = 0` y `repeats = 0` no cuelga ninguna repetición, que es la
    /// salida barata de siempre.
    func testWithoutDepthRepeatsAtZeroStillRepeatsNothing() {
        XCTAssertTrue(repetitions(cycle(target: .repeats, depth: 0)).isEmpty)
    }

    /// Las repeticiones heredan la altura del Pulse, LFO de pitch incluido.
    func testRepetitionsInheritTheModulatedPitch() {
        let cycle = self.cycle(target: .pitch, depth: 100, repeats: 2)
        let events = emitted(cycle)
        let repetitions = self.repetitions(cycle)

        for repetition in repetitions {
            let pulse = events.first { $0.step == repetition.step }
            XCTAssertEqual(repetition.pitch, pulse?.pitch, "step \(repetition.step)")
        }
    }

    // MARK: - La fase (FR15)

    /// **El LFO corre sobre los Steps que no disparan.** Dos Cycles con el mismo
    /// `depth` y distinto reparto euclidiano acentúan en la misma fase: la
    /// posición del ciclo depende del índice del Step y nunca de si hubo nota.
    func testThePhaseDoesNotDependOnWhichStepsFire() {
        let dense = cycle(target: .velocity, depth: 60)
        let sparse = Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!),
            pool: pool(),
            groove: Groove(velocity: Velocity(100)!, sustain: .default, probability: .default),
            modulation: Modulation(
                waveform: .triangle, depth: Depth(percent: 60)!, target: .velocity)
        )

        let denseEvents = emitted(dense)
        for event in emitted(sparse) {
            let sameStep = denseEvents.first { $0.step == event.step }
            XCTAssertEqual(
                event.velocity, sameStep?.velocity,
                "el Step \(event.step) acentúa distinto con otro reparto"
            )
        }
    }
}
