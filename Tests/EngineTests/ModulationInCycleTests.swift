import XCTest

@testable import Engine

/// Tests de la `Modulation` dentro del `Cycle` (FR1, NFR2).
///
/// **Vive en el `Cycle` y no fuera** porque el hilo del scheduler necesita la
/// onda y el depth para decidir con cuánta fuerza emite un Step, y lo único que
/// ese hilo lee es el snapshot publicado. De ahí que tenga que ser un valor
/// trivial, y de ahí que `_isPOD(Cycle.self)` siga siendo la red.
///
/// **Cada Cycle lleva el suyo**, que es lo que permite acentuar solo el B de un
/// desarrollo A/B.
///
/// **El riesgo de la rebanada está aquí y no en la matemática.** Las cuatro
/// ondas se prueban con números y se acabó; lo que hay que vigilar es que meter
/// un campo más en un valor que cruza al hilo del scheduler dieciséis veces por
/// Track no rompa `_isPOD` ni engorde el snapshot.
final class ModulationInCycleTests: XCTestCase {

    private let shape = Shape(steps: Steps(16)!, pulses: Pulses(5)!)

    // MARK: - El default

    /// Un Cycle recién creado no modula: `depth = 0` y `waveform = .triangle`
    /// (criterio 1). Es lo que hace que un Pattern existente suene exactamente
    /// igual que antes de la rebanada.
    func testAFreshCycleDoesNotModulate() {
        let cycle = Cycle(shape: shape)
        XCTAssertEqual(cycle.modulation, .default)
        XCTAssertEqual(cycle.modulation.depth.percent, 0)
        XCTAssertEqual(cycle.modulation.waveform, .triangle)
    }

    /// **El campo entra por default en el inicializador**, como entraron Timing,
    /// Delay y el Note Repeater: código que no lo pide sigue compilando y sonando
    /// igual. Es la regla de destructividad de `product-guidelines.md` aplicada
    /// al código.
    func testTheFieldEntersByDefaultSoOlderCallSitesStillCompile() {
        let cycle = Cycle(shape: shape, pool: PitchPool().inserting(Pitch(48)!))
        XCTAssertEqual(cycle.modulation, Modulation.default)
    }

    /// Y los dieciséis Cycles de un Pattern recién creado tampoco modulan.
    func testNoCycleOfAFreshPatternModulates() {
        let pattern = Pattern.initial
        for track in 0..<Pattern.trackCount {
            for index in 0..<Track.cycleCount {
                XCTAssertEqual(
                    pattern.track(at: track)?.cycle(at: index)?.modulation,
                    .default,
                    "track \(track) cycle \(index)"
                )
            }
        }
    }

    // MARK: - Editar

    /// `with(modulation:)` devuelve un valor nuevo y **no toca nada más**.
    func testWithModulationChangesNothingElse() {
        let modulation = Modulation(waveform: .pulse, depth: Depth(percent: -40)!)
        let cycle = Cycle(
            shape: shape,
            pool: PitchPool().inserting(Pitch(48)!),
            groove: Groove(velocity: Velocity(90)!, sustain: .default, probability: .default),
            channel: Channel(5)!,
            frame: TonalFrame(scale: .major, root: Root(2)!),
            noteRepeater: NoteRepeater(repeats: Repeats(3)!),
            padOctaveShift: 2
        )

        let modulated = cycle.with(modulation: modulation)

        XCTAssertEqual(modulated.modulation, modulation)
        XCTAssertEqual(modulated.shape, cycle.shape)
        XCTAssertEqual(modulated.pool, cycle.pool)
        XCTAssertEqual(modulated.groove, cycle.groove)
        XCTAssertEqual(modulated.channel, cycle.channel)
        XCTAssertEqual(modulated.frame, cycle.frame)
        XCTAssertEqual(modulated.noteRepeater, cycle.noteRepeater)
        XCTAssertEqual(modulated.padOctaveShift, cycle.padOctaveShift)
    }

    /// Y a la inversa: cambiar cualquier otra cosa **no pierde la modulación**.
    /// Es el defecto que `Cycle.with(...)` existe para impedir desde el
    /// 2026-08-31.
    func testChangingAnythingElseKeepsTheModulation() {
        let modulation = Modulation(waveform: .saw, depth: Depth(percent: 70)!)
        let cycle = Cycle(shape: shape).with(modulation: modulation)

        XCTAssertEqual(cycle.with(channel: Channel(9)!).modulation, modulation)
        XCTAssertEqual(cycle.with(padOctaveShift: -1).modulation, modulation)
        XCTAssertEqual(
            cycle.with(
                groove: Groove(velocity: Velocity(20)!, sustain: .default, probability: .default)
            )
            .modulation,
            modulation
        )
        XCTAssertEqual(cycle.on(Channel(4)!).modulation, modulation)
    }

    /// **La igualdad distingue dos Cycles que solo difieren en la onda.** Sin
    /// esto, cambiar de forma no publicaría un snapshot nuevo.
    func testEqualityDistinguishesTwoCyclesThatOnlyDifferInTheWaveform() {
        let saw = Cycle(shape: shape).with(modulation: Modulation(waveform: .saw))
        let sine = Cycle(shape: shape).with(modulation: Modulation(waveform: .sine))
        XCTAssertNotEqual(saw, sine)
        XCTAssertEqual(saw, Cycle(shape: shape).with(modulation: Modulation(waveform: .saw)))
    }

    /// Y dos que solo difieren en el depth.
    func testEqualityDistinguishesTwoCyclesThatOnlyDifferInTheDepth() {
        let quiet = Cycle(shape: shape).with(modulation: Modulation(depth: Depth(percent: 10)!))
        let loud = Cycle(shape: shape).with(modulation: Modulation(depth: Depth(percent: 90)!))
        XCTAssertNotEqual(quiet, loud)
    }

    // MARK: - Cada Cycle lleva el suyo

    /// **Cambiar el del Cycle en edición no toca a los otros quince.** Es lo que
    /// permite acentuar solo el B de un desarrollo A/B.
    func testChangingOneCycleLeavesTheOtherFifteenAlone() {
        var track = Track(Cycle(shape: shape)).withActiveCount(Track.cycleCount).withEditing(1)
        let modulation = Modulation(waveform: .pulse, depth: Depth(percent: 100)!)
        track = track.replacingEditing(track.editingCycle.with(modulation: modulation))

        XCTAssertEqual(track.cycle(at: 1)?.modulation, modulation)
        XCTAssertEqual(track.cycle(at: 0)?.modulation, .default)
        for index in 2..<Track.cycleCount {
            XCTAssertEqual(track.cycle(at: index)?.modulation, .default, "Cycle \(index)")
        }
    }

    // MARK: - Sigue siendo trivial

    /// `_isPOD(Cycle.self)` es la red que impide que el snapshot deje de poder
    /// copiarse dentro del hilo del scheduler. No se relaja (NFR2).
    func testTheCycleIsStillTriviallyCopyable() {
        XCTAssertTrue(_isPOD(Waveform.self), "la onda no es trivial")
        XCTAssertTrue(_isPOD(Depth.self), "el depth no es trivial")
        XCTAssertTrue(_isPOD(Modulation.self), "la Modulation no es trivial")
        XCTAssertTrue(_isPOD(Cycle.self), "el Cycle dejó de ser trivial")
        XCTAssertTrue(_isPOD(Track.self), "el Track dejó de ser trivial")
        XCTAssertTrue(_isPOD(Engine.Pattern.self), "el Pattern dejó de ser trivial")
    }

    /// **El coste de la modulación, escrito: tres bytes por Cycle.** Es lo que
    /// obliga a guardar el depth como `Int8` y el destino como `UInt8` en vez de
    /// como sus tipos —un `Depth` envuelve un `Int` y un `TrackParameter` no
    /// tiene `RawValue`— y es el idioma que `NoteRepeater` ya fijó.
    ///
    /// > **Eran dos hasta el 2026-09-16.** `assignable-lfo_20260916` añade el
    /// > `target`, que cuesta el tercero: con doce Tracks por dieciséis Cycles
    /// > son ~192 B sobre los ~37 KB del snapshot. Un `load()` cuesta ~870 ns
    /// > medidos —el 0,0044% de la ventana—, así que este byte no se nota.
    func testTheModulationCostsThreeBytesPerCycle() {
        XCTAssertEqual(MemoryLayout<Modulation>.size, 3)
    }
}
