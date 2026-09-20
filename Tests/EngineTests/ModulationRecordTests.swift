import XCTest

@testable import Engine

/// Tests de la modulación en disco.
///
/// **Entra por una enmienda del 2026-09-08.** La spec de la rebanada listaba la
/// persistencia entre lo que no existe —se escribió el 2026-09-06, cuando la
/// rebanada 4 estaba por planificar— y `ProjectRecord.swift` ya dejaba dicho lo
/// que pasaría: «las rebanadas 5 y 6 —Note Repeater y Modulation— añaden campos,
/// y el test que enumera las claves esperadas es lo que impide que uno se pierda
/// en silencio». Sin estas dos claves, guardar un Bank perdería `waveform` y
/// `depth` sin decir nada.
///
/// **`schemaVersion` se queda en 1.** `ProjectRecord.validated()` exige igualdad
/// exacta, así que subirla sin migrador dejaría ilegibles los ficheros ya
/// escritos. Un fichero sin las claves nuevas se lee como el estado de antes de
/// la rebanada, que es el criterio 1 aplicado al disco.
final class ModulationRecordTests: XCTestCase {

    private let shape = Shape(steps: Steps(16)!, pulses: Pulses(5)!)

    private func dictionary(from record: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(record)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Las dos claves

    func testTheCycleJSONCarriesTheThreeModulationKeys() throws {
        let cycle = Cycle(shape: shape).with(
            modulation: Modulation(
                waveform: .pulse, depth: Depth(percent: -70)!, target: .sustain))
        let json = try dictionary(from: CycleRecord(cycle))

        XCTAssertEqual(json["waveform"] as? String, "pulse")
        XCTAssertEqual(json["depth"] as? Int, -70)
        XCTAssertEqual(json["target"] as? String, "sustain")
    }

    /// **La clave vieja no se escribe nunca más** (FR31). Se conserva solo para
    /// leer los ficheros de antes del renombrado.
    func testTheOldAccentKeyIsNeverWritten() throws {
        let cycle = Cycle(shape: shape).with(
            modulation: Modulation(waveform: .saw, depth: Depth(percent: 42)!))
        let json = try dictionary(from: CycleRecord(cycle))

        XCTAssertNil(json["accent"])
    }

    /// El neutro también se escribe: un `0` explícito dice «sin modulación»,
    /// mientras que una clave ausente solo dice «esto lo escribió otra versión».
    func testTheNeutralModulationIsWrittenToo() throws {
        let json = try dictionary(from: CycleRecord(Cycle(shape: shape)))

        XCTAssertEqual(json["waveform"] as? String, "triangle")
        XCTAssertEqual(json["depth"] as? Int, 0)
        XCTAssertEqual(json["target"] as? String, "velocity")
    }

    /// **`waveform` se guarda por clave y no por su posición en el `enum`.** El
    /// orden de `allCases` lo manda la rejilla 2×2 de la pantalla (FR11) y puede
    /// querer cambiarse; atar el fichero al índice haría que reordenar la rejilla
    /// cambiara la onda de un Bank ya guardado. Es el criterio de `scale`.
    func testEveryWaveformHasItsOwnStableKey() throws {
        var keys: Set<String> = []
        for waveform in Waveform.allCases {
            let cycle = Cycle(shape: shape).with(modulation: Modulation(waveform: waveform))
            let key = try XCTUnwrap(dictionary(from: CycleRecord(cycle))["waveform"] as? String)
            keys.insert(key)
        }
        XCTAssertEqual(keys, ["saw", "triangle", "sine", "pulse"])
    }

    // MARK: - Vuelve entera

    func testTheModulationSurvivesTheRoundTrip() throws {
        for waveform in Waveform.allCases {
            for percent in [-100, -1, 0, 1, 100] {
                let modulation = Modulation(waveform: waveform, depth: Depth(percent: percent)!)
                let cycle = Cycle(shape: shape).with(modulation: modulation)

                let data = try JSONEncoder().encode(CycleRecord(cycle))
                let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

                XCTAssertEqual(
                    decoded.cycle.modulation, modulation, "\(waveform) depth \(percent)")
            }
        }
    }

    /// Y el Cycle entero vuelve igual: la modulación no se lleva por delante
    /// ninguna de las otras claves.
    func testTheWholeCycleStillSurvivesTheRoundTrip() throws {
        let cycle = Cycle(
            shape: shape,
            pool: PitchPool().inserting(Pitch(48)!).inserting(Pitch(55)!),
            groove: Groove(velocity: Velocity(90)!, sustain: .default, probability: .default),
            channel: Channel(7)!,
            frame: TonalFrame(scale: .lydian, root: Root(5)!),
            noteRepeater: NoteRepeater(repeats: Repeats(4)!),
            modulation: Modulation(waveform: .sine, depth: Depth(percent: 55)!),
            padOctaveShift: -1
        )

        let data = try JSONEncoder().encode(CycleRecord(cycle))
        let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

        XCTAssertEqual(decoded.cycle, cycle)
    }

    // MARK: - Los ficheros de antes de la rebanada

    /// **Un fichero sin las dos claves se lee como el neutro**, que es
    /// exactamente el estado que ese fichero describía. Es lo que hace que un
    /// Bank guardado antes de la rebanada siga abriendo y sonando igual.
    func testAFileWithoutTheKeysReadsAsTheNeutralModulation() throws {
        var json = try dictionary(from: CycleRecord(Cycle(shape: shape)))
        json.removeValue(forKey: "waveform")
        json.removeValue(forKey: "depth")
        json.removeValue(forKey: "target")

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

        XCTAssertEqual(decoded.cycle.modulation, .default)
    }

    /// Y no sube la versión del esquema: `validated()` exige igualdad exacta, y
    /// subirla sin migrador dejaría sin abrir los Banks ya escritos.
    func testTheSchemaVersionDoesNotMove() {
        XCTAssertEqual(ProjectRecord.currentSchemaVersion, 1)
    }

    // MARK: - Valores que no deberían existir

    /// Una onda desconocida —un fichero de una versión futura, o tocado a mano—
    /// cae en el default en vez de dejar el Bank sin abrir. Mismo criterio que
    /// `scale`.
    func testAnUnknownWaveformFallsBackToTheDefault() throws {
        var json = try dictionary(from: CycleRecord(Cycle(shape: shape)))
        json["waveform"] = "square"

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

        XCTAssertEqual(decoded.cycle.modulation.waveform, .default)
    }

    /// Y un depth fuera de rango también, como el resto de las claves: un byte
    /// malo no es razón para perder un Bank.
    func testAnOutOfRangeDepthFallsBackToTheDefault() throws {
        var json = try dictionary(from: CycleRecord(Cycle(shape: shape)))
        json["depth"] = 900

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

        XCTAssertEqual(decoded.cycle.modulation.depth, .default)
    }

    // MARK: - El renombrado no pierde lo guardado (FR31, AC 10)

    /// **Un fichero escrito antes del 2026-09-16 trae `accent` y se lee con su
    /// modulación intacta.** Es el criterio de aceptación del renombrado: sin
    /// esto, cambiar el nombre del parámetro habría apagado la modulación de
    /// todo lo guardado.
    ///
    /// El JSON se escribe a mano —quitando `depth` y poniendo `accent`— porque
    /// eso es exactamente lo que hay en el disco de quien abrió la app antes.
    func testAFileWrittenWithTheOldKeyKeepsItsModulation() throws {
        var json = try dictionary(from: CycleRecord(Cycle(shape: shape)))
        json.removeValue(forKey: "depth")
        json.removeValue(forKey: "target")
        json["waveform"] = "pulse"
        json["accent"] = -70

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

        XCTAssertEqual(decoded.cycle.modulation.waveform, .pulse)
        XCTAssertEqual(decoded.cycle.modulation.depth.percent, -70)
        XCTAssertEqual(
            decoded.cycle.modulation.target, .velocity,
            "un fichero sin destino apunta a velocity, que es lo que entonces modulaba")
    }

    /// Con las dos claves presentes manda `depth`. No debería pasar —nadie
    /// escribe las dos— pero un fichero tocado a mano puede traerlas, y la
    /// regla tiene que estar escrita en algún sitio.
    func testDepthWinsOverTheOldKey() throws {
        var json = try dictionary(from: CycleRecord(Cycle(shape: shape)))
        json["depth"] = 20
        json["accent"] = -70

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

        XCTAssertEqual(decoded.cycle.modulation.depth.percent, 20)
    }

    // MARK: - El destino en disco (FR32, FR33, AC 11, AC 12)

    /// **Los nueve destinos sobreviven a la ida y vuelta** (AC 11), cada uno con
    /// su clave estable.
    func testEveryTargetSurvivesTheRoundTrip() throws {
        var keys: Set<String> = []
        for target in TrackParameter.modulationTargets {
            let cycle = Cycle(shape: shape).with(
                modulation: Modulation(
                    waveform: .sine, depth: Depth(percent: 33)!, target: target))
            let record = CycleRecord(cycle)
            let data = try JSONEncoder().encode(record)
            let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

            XCTAssertEqual(decoded.cycle.modulation.target, target)
            keys.insert(try XCTUnwrap(dictionary(from: record)["target"] as? String))
        }
        XCTAssertEqual(keys.count, 9, "dos destinos comparten clave en disco")
    }

    /// **`repeatTime` se guarda como `time`**, que es como se lee en todas
    /// partes: el prefijo del `enum` es desambiguación de Swift frente a
    /// `MusicalTime`, no un término del vocabulario (NFR7).
    func testRepeatTimeIsWrittenAsTime() throws {
        let cycle = Cycle(shape: shape).with(
            modulation: Modulation(depth: Depth(percent: 10)!, target: .repeatTime))

        XCTAssertEqual(try dictionary(from: CycleRecord(cycle))["target"] as? String, "time")
    }

    /// **Un destino desconocido cae en `.velocity` y el Bank abre** (AC 12).
    func testAnUnknownTargetFallsBackToVelocity() throws {
        var json = try dictionary(from: CycleRecord(Cycle(shape: shape)))
        json["target"] = "voicing"

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

        XCTAssertEqual(decoded.cycle.modulation.target, .velocity)
    }

    /// **Y el de un parámetro que existe pero no es destino, también.** Un
    /// fichero de una versión que modulara `probability` no puede imponerlo
    /// aquí.
    func testATargetThatIsNotAModulationTargetFallsBackToVelocity() throws {
        for key in ["probability", "harmony", "steps", "division"] {
            var json = try dictionary(from: CycleRecord(Cycle(shape: shape)))
            json["target"] = key

            let data = try JSONSerialization.data(withJSONObject: json)
            let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

            XCTAssertEqual(decoded.cycle.modulation.target, .velocity, key)
        }
    }
}
