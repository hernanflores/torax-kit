/// La forma del movimiento que la modulación imprime a la velocity.
///
/// **Cuatro casos y ninguno más**, tal y como los lista la Pre Spec.
///
/// > **Se llama `waveform` y no `Groove`.** La Pre Spec usa *Groove* para dos
/// > cosas —la familia de Velocity, Sustain, Probability, Timing y Delay, y el
/// > knob que escoge la forma del LFO— y el motor ya gastó el término en la
/// > primera: `Groove` es un tipo de este mismo paquete.
/// > `product-guidelines.md` pide un solo término por concepto, así que la
/// > forma toma el nombre con el que el propio handoff de diseño la rotula.
/// > Desviación fechada el 2026-09-08 en `Pre Spec Torax H-0.md`.
///
/// **El orden de `allCases` es el que dibuja la rejilla 2×2 de la pantalla**
/// (FR11), así que es parte del contrato y no un detalle del compilador.
public enum Waveform: CaseIterable, Equatable, Sendable {

    /// Rampa ascendente con un corte: sube, salta al fondo y vuelve a subir.
    case saw

    /// Subida y bajada simétricas. El default.
    case triangle

    /// La misma forma que `triangle`, redondeada. Se resuelve por tabla entera
    /// —ver `Waveform.value(atStep:of:)`—, nunca con `sin()`.
    case sine

    /// Dos valores y nada entre ellos: media vuelta arriba, media abajo.
    case pulse

    /// Default del producto.
    ///
    /// **`triangle` y no `saw`** porque es la forma que sube y baja
    /// simétricamente, que es la lectura menos sorprendente de «modulación» —y
    /// la única de las cuatro que no introduce ni un salto ni una asimetría que
    /// haya que explicar. Con `depth` en 0 da igual cuál sea, porque ninguna
    /// se aplica; importa el día que se sube el slider sin haber elegido forma.
    public static let `default` = Waveform.triangle
}

extension Waveform: CustomStringConvertible {

    /// **El mismo término en minúscula** (FR2, FR20).
    ///
    /// Vive en `Engine` y no en la vista por la razón de siempre: `workflow.md`
    /// dice que si algo en `App` merece un test está en el sitio equivocado, y
    /// un formato es exactamente eso.
    public var description: String {
        switch self {
        case .saw: "saw"
        case .triangle: "triangle"
        case .sine: "sine"
        case .pulse: "pulse"
        }
    }
}

/// Cuánto se desvía la velocity a lo largo de la vuelta, con signo.
///
/// Término de la Pre Spec: «amplitud de variación de velocity alrededor de
/// Velocity base».
///
/// **Bipolar y simétrico, como `Delay`, `Ramp` y `Pace`**: el cero es el centro
/// y se cruza sin caso especial. El signo invierte la forma, así que un
/// `triangle` con depth negativo empieza bajando — es la misma onda leída del
/// otro lado, no una quinta forma.
///
/// **El 0 está dentro del rango y es el default.** No es un extremo incómodo:
/// es el valor que **apaga** la modulación, y de él depende toda la no regresión
/// de la rebanada. Con `depth = 0` la salida es la de antes — instantes,
/// velocities y consumo de aleatoriedad.
///
/// > **No tiene knob**, a diferencia del resto de parámetros de Groove: se
/// > edita con el dedo en la pantalla `modulation`, que cae del lado táctil de
/// > la frontera del 2026-09-06. El coste está escrito y es real — Ctrl All,
/// > Temp y la lectura transitoria grande no lo alcanzan, porque los tres
/// > operan sobre `TrackParameter`. Desviación fechada el 2026-09-08 en
/// > `Pre Spec Torax H-0.md`.
///
/// Valida en el inicializador, como `Velocity` y `Ramp`: un `Depth` que existe
/// es siempre aplicable.
public struct Depth: Equatable, Sendable {

    /// Rango admitido. Simétrico: la excursión entera hacia cada lado.
    public static let validRange: ClosedRange<Int> = -100...100

    /// Default del producto: sin modulación. Con él, la salida es la de antes de
    /// la rebanada.
    public static let `default` = Depth(unchecked: 0)

    public let percent: Int

    /// Devuelve `nil` si el porcentaje cae fuera de `validRange`.
    public init?(percent: Int) {
        guard Self.validRange.contains(percent) else { return nil }
        self.percent = percent
    }

    /// Vía interna para valores ya acotados. Ver `Velocity.init(unchecked:)`.
    init(unchecked percent: Int) {
        self.percent = percent
    }
}

extension Depth: CustomStringConvertible {

    /// Cómo se lee `depth` en pantalla: `+34`, `-12`, `0`.
    ///
    /// **El signo se ve también en el positivo.** Es la convención que `Rotate`
    /// y `Delay` ya siguen para lo bipolar, y aquí es lo que separa «sube 34» de
    /// «el valor es 34»: sin él, la lectura grande de la pantalla no diría hacia
    /// dónde se desvía la velocity.
    ///
    /// **El 0 va sin signo.** No es un valor pequeño hacia ningún lado — es el
    /// que apaga la modulación—, y escribirlo `+0` le inventaría una dirección
    /// que no tiene.
    ///
    /// **Sin `%`.** El rango es −100…100 pero no es un porcentaje de nada
    /// nombrable: lo que desplaza son unidades MIDI, y el factor está en FR6.
    /// Ponerle el signo diría que es un porcentaje de la Velocity base, que es
    /// justo lo que no es.
    ///
    /// **Vive en `Engine` y no en la vista** (NFR6), por la razón de siempre:
    /// `workflow.md` dice que si algo en `App` merece un test está en el sitio
    /// equivocado, y un formato es exactamente eso.
    public var description: String {
        percent > 0 ? "+\(percent)" : "\(percent)"
    }
}

extension Depth {

    /// El depth resultante de mover el slider `delta` unidades.
    ///
    /// **No lo mueve un knob sino un dedo arrastrando** (FR9, FR18), y por eso
    /// el parámetro se llama `delta` igual que en los demás: la aritmética es la
    /// misma aunque el gesto no lo sea.
    ///
    /// **Se detiene en los extremos, no envuelve.** Ver `Sustain.advanced(by:)`.
    /// Aquí pesa más que en los knobs: un arrastre largo del dedo produce deltas
    /// grandes de golpe, y envolver haría que pasarse del acento máximo devolviera
    /// el mínimo — el cambio más brutal que el parámetro admite, justo donde
    /// `product-guidelines.md` pide «un cambio inmediato y proporcional».
    ///
    /// **El cero no es un punto de parada.** Se cruza como cualquier otro valor;
    /// el imantado cerca del centro (FR18) es de la vista, que sabe cuántos
    /// puntos de pantalla son «cerca», y no del tipo.
    ///
    /// Adjusts the depth by the specified amount while keeping it within the valid range.
    /// - Parameter delta: The amount to add to the depth percentage.
    /// - Returns: A percentage clamped between −100 and 100.
    public func advanced(by delta: Int) -> Depth {
        Depth(unchecked: Self.validRange.clamping(percent + delta))
    }
}

extension Waveform {

    /// La excursión de la modulación, muestreada en el Step `step` de una vuelta
    /// de `stepCount` (FR4, FR5). Devuelve −100…100.
    ///
    /// **La fase sale del índice de Step dentro de la vuelta**, `p = step /
    /// stepCount`, y ahí está todo el diseño de la rebanada: un ciclo dura
    /// exactamente una vuelta del anillo porque así se calcula la fase, no
    /// porque nadie lo vigile. No hay reloj de modulación ni estado que
    /// mantener, y cada Track modula a su velocidad porque cada uno tiene sus
    /// Steps y su Division.
    ///
    /// **El índice envuelve sobre la vuelta**, como `Cycle.triggers(atStep:)`.
    ///
    /// **Todo pasa por `t = 400 · step / stepCount`**, la fase en cuartos de
    /// vuelta por cien: 0 en el arranque, 100 en el cuarto, 200 en la mitad, 300
    /// en los tres cuartos. Las cuatro formas son cuatro lecturas de ese mismo
    /// número, que es lo que garantiza que todas tengan el pico en el mismo
    /// sitio — cambiar de forma cambia el recorrido, no dónde cae el acento.
    ///
    /// - `triangle`: `t` mientras sube, `200 − t` mientras baja, `t − 400` en el
    ///   último cuarto. Los tres tramos coinciden en sus fronteras, así que la
    ///   forma es continua sin caso especial.
    /// - `saw`: la misma subida hasta el cuarto, y después **un solo corte** —
    ///   cae al fondo y vuelve a subir a un tercio de la pendiente, porque le
    ///   quedan tres cuartos de vuelta para recorrer lo que la subida hizo en
    ///   uno. El corte va en `p=¼` y no a media vuelta para que su pico coincida
    ///   con el de las otras tres.
    /// - `sine`: `sin(2πp)` **por tabla escrita de un cuarto de onda**, con las
    ///   otras tres cuartas partes por simetría. No se calcula con `sin()`:
    ///   `Engine` no importa nada fuera de la stdlib (NFR5) y esto corre en el
    ///   hilo del scheduler (NFR1).
    /// - `pulse`: arriba mientras la fase no llega a la mitad, abajo después.
    ///   **Con Steps impares el Step del medio cae en la mitad alta** —`t < 200`
    ///   equivale a `2·step < stepCount`— así que acentúa `ceil(steps/2)` de
    ///   `steps`. Es la misma regla, no un caso especial.
    ///
    /// **`pulse` es la excepción a «empieza en el centro» y no puede no serlo:**
    /// una onda de dos valores no pasa por el centro. Empieza arriba, que es lo
    /// que hace la forma útil para lo que sirve — acentuar media vuelta entera.
    ///
    /// Con `stepCount` no positivo devuelve el centro en vez de dividir por
    /// cero. `Steps` valida 1…64 y no puede producirlo, pero esto corre en el
    /// hilo del scheduler y ahí una división por cero es un crash.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await, sin coma flotante.
    ///
    /// Samples the modulation waveform at one step of a turn.
    /// - Parameters:
    ///   - step: The step index; it wraps around the turn.
    ///   - stepCount: How many steps the turn has.
    /// - Returns: The excursion, from −100 to 100.
    public func value(atStep step: Int, of stepCount: Int) -> Int {
        guard stepCount > 0 else { return 0 }

        // El módulo de Swift conserva el signo del dividendo, así que un índice
        // negativo se lleva de vuelta al anillo sumando una vuelta.
        let wrapped = ((step % stepCount) + stepCount) % stepCount
        let t = 400 * wrapped / stepCount

        switch self {
        case .triangle:
            if t <= 100 { return t }
            if t <= 300 { return 200 - t }
            return t - 400

        case .saw:
            if t <= 100 { return t }
            return -100 + (t - 100) / 3

        case .sine:
            if t <= 100 { return Self.quarterSine[t] }
            if t <= 200 { return Self.quarterSine[200 - t] }
            if t <= 300 { return -Self.quarterSine[t - 200] }
            return -Self.quarterSine[400 - t]

        case .pulse:
            return t < 200 ? 100 : -100
        }
    }

    /// Un cuarto de onda de seno, escrito y no calculado (NFR5).
    ///
    /// `quarterSine[i] = round(100 · sin(π·i/200))` para `i` de 0 a 100, que es
    /// el recorrido de la fase de 0 a un cuarto de vuelta. Las otras tres
    /// cuartas partes salen de esta por simetría, así que la tabla cuesta 101
    /// enteros y no 400.
    ///
    /// **La forma es una aproximación entera**, y a 16 Steps o menos —donde el
    /// muestreo pasa por una de cada seis entradas— es indistinguible de la
    /// curva exacta. Es la limitación que la spec del track anota.
    ///
    /// > **Es un global de inicialización perezosa, y eso se lee desde el hilo
    /// > del scheduler.** Leer una entrada no asigna nada, pero la **primera**
    /// > lectura del proceso corre el `swift_once` que construye el array. Es
    /// > exactamente el mismo idioma que `RepeatTime.ordered`, que la rebanada 5
    /// > ya lee desde ese hilo, así que no se inventa aquí un patrón nuevo. Si
    /// > algún día se quiere quitar del todo, la vía es una tupla de tamaño fijo
    /// > leída con `withUnsafePointer` — más barata y bastante menos legible, y
    /// > no se paga hasta que haya un motivo medido para pagarla.
    static let quarterSine: [Int] = [
        0, 2, 3, 5, 6, 8, 9, 11, 13, 14,
        16, 17, 19, 20, 22, 23, 25, 26, 28, 29,
        31, 32, 34, 35, 37, 38, 40, 41, 43, 44,
        45, 47, 48, 50, 51, 52, 54, 55, 56, 58,
        59, 60, 61, 63, 64, 65, 66, 67, 68, 70,
        71, 72, 73, 74, 75, 76, 77, 78, 79, 80,
        81, 82, 83, 84, 84, 85, 86, 87, 88, 88,
        89, 90, 90, 91, 92, 92, 93, 94, 94, 95,
        95, 96, 96, 96, 97, 97, 98, 98, 98, 99,
        99, 99, 99, 99, 100, 100, 100, 100, 100, 100,
        100,
    ]
}

/// Los dos parámetros de la modulación de un Cycle.
///
/// **Vive dentro del `Cycle`**, junto a Shape, Groove, el pool y el Note
/// Repeater, por la misma razón que ellos: el hilo del scheduler necesita los
/// dos para decidir con cuánta fuerza emite un Step, y lo único que ese hilo lee
/// es el snapshot publicado. Cada Cycle tiene el suyo, así que un desarrollo A/B
/// puede acentuar solo en el B.
///
/// **Guarda un `Int8` y no un `Depth`**, que es el idioma que `NoteRepeater` ya
/// fijó: el campo cuesta dos bytes por Cycle —la onda es un `enum` sin carga—
/// contra los dieciséis que costaría almacenar los dos tipos enteros. Con doce
/// Tracks × dieciséis Cycles la diferencia son ~2,7 KB sobre los ~37 KB del
/// snapshot, y NFR2 presupone que este campo no se nota.
///
/// **Con el neutro no cambia nada de lo entregado**: `depth` en 0 devuelve la
/// Velocity base sin tocarla, igual que Repeats en 0 no ejecuta nada del camino
/// del Note Repeater.
public struct Modulation: Equatable, Sendable {

    /// El neutro: sin modulación, sobre `triangle`. Con él, la salida es la de
    /// antes de la rebanada — instantes, velocities y consumo de aleatoriedad.
    public static let `default` = Modulation()

    /// La forma del movimiento.
    public let waveform: Waveform

    private let storedDepth: Int8

    /// El destino, guardado por su posición en `TrackParameter.modulationTargets`.
    ///
    /// **Un byte, como `storedDepth` y `storedTimeIndex`.** Con doce Tracks por
    /// dieciséis Cycles son ~192 B sobre los ~37 KB del snapshot, y NFR2
    /// presupone que este campo no se nota: un `load()` cuesta ~870 ns medidos.
    ///
    /// **Se guarda la posición y no el `TrackParameter`** porque el `enum` no
    /// tiene `RawValue` y su orden es el del flujo del motor, que puede cambiar.
    /// La posición es la de la lista de destinos, que sí es contrato.
    private let storedTarget: UInt8

    public init(
        waveform: Waveform = .default,
        depth: Depth = .default,
        target: TrackParameter = .velocity
    ) {
        self.waveform = waveform
        storedDepth = Int8(depth.percent)
        storedTarget = Self.slot(for: target)
    }

    /// Cuánto se desvía el parámetro de destino, con signo.
    public var depth: Depth { Depth(unchecked: Int(storedDepth)) }

    /// A qué parámetro apunta el LFO (FR1, FR2).
    ///
    /// **Se resuelve con un `switch` y no indexando
    /// `TrackParameter.modulationTargets`.** Esto se lee desde el hilo del
    /// scheduler, y aquella lista es un global de inicialización perezosa: su
    /// primera lectura del proceso corre un `swift_once`. Un `switch` no cuesta
    /// nada y no depende de que nadie haya leído la lista antes.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await, sin coma flotante.
    public var target: TrackParameter {
        switch storedTarget {
        case 1: .sustain
        case 2: .timing
        case 3: .delay
        case 4: .repeats
        case 5: .repeatTime
        case 6: .ramp
        case 7: .pace
        case 8: .pitch
        // **El 0 y cualquier otro byte dan velocity.** Un valor imposible puede
        // llegar de un fichero de otra versión, y un Bank no se queda sin abrir
        // por un byte malo: cae en el destino que la rebanada anterior entregó.
        default: .velocity
        }
    }

    /// La posición que le toca a un destino, o la de velocity si no es destino.
    ///
    /// **Un parámetro que no es destino cae en `.velocity`** (FR2) en vez de
    /// rechazarse: el inicializador no puede fallar sin obligar a todo llamante
    /// a desenvolver un opcional por un caso que la interfaz no puede producir.
    private static func slot(for target: TrackParameter) -> UInt8 {
        switch target {
        case .sustain: 1
        case .timing: 2
        case .delay: 3
        case .repeats: 4
        case .repeatTime: 5
        case .ramp: 6
        case .pace: 7
        case .pitch: 8
        case .velocity: 0
        case .steps, .pulses, .rotate, .division, .probability, .harmony: 0
        }
    }

    /// La misma `Modulation` con lo que se le cambie, y todo lo demás intacto.
    ///
    /// Mismo idioma que `Cycle.with(...)` y `NoteRepeater.with(...)`, y por la
    /// misma razón: reconstruirla a mano pierde en silencio lo que no se nombre.
    ///
    /// **Cambiar el destino conserva `depth`** (FR9). El número es un porcentaje
    /// del rango del destino, así que mide intensidad relativa y significa lo
    /// mismo en los nueve: reajustarlo al cambiar de destino sería pedirle al
    /// usuario que corrigiera algo que no se ha movido.
    public func with(
        waveform: Waveform? = nil,
        depth: Depth? = nil,
        target: TrackParameter? = nil
    ) -> Modulation {
        Modulation(
            waveform: waveform ?? self.waveform,
            depth: depth ?? self.depth,
            target: target ?? self.target
        )
    }
}

extension Modulation {

    /// Cuánto se desvía el parámetro de destino en el Step `step` de una vuelta
    /// de `stepCount`, en las unidades de ese parámetro y con signo (FR6).
    ///
    /// ```
    /// offset = wave(p) · depth · halfRange(target) / 10000   // wave ∈ −100…100
    /// ```
    ///
    /// **`halfRange` es media excursión del rango del destino**, así que
    /// `depth = ±100` sobre el pico de la onda desplaza media escala de lo que
    /// sea que se esté modulando. Sale de `displacementRange` y no de una tabla
    /// escrita aparte — ver `TrackParameter.modulationHalfRange`.
    ///
    /// **Sobre `velocity` da 63, que es el número que esta fórmula llevaba
    /// escrito antes de que el destino fuera asignable.** Generalizar no cambia
    /// un solo desplazamiento del destino ya entregado, y un test lo fija con la
    /// fórmula vieja como oráculo. Con la Velocity en el centro del rango, un
    /// depth al extremo barre prácticamente 1…127 sin recortar; con la Velocity
    /// por defecto —100— recorta arriba, y enseñar ese recorte es justo para lo
    /// que sirve el panel de respuesta (FR12).
    ///
    /// **La división trunca hacia cero, que es lo que hace simétrico el signo.**
    /// Truncar hacia abajo separaría `+n` de `−n` en una unidad sobre la mitad
    /// de los Steps, y el criterio 4 pide que uno sea el complemento exacto del
    /// otro. Multiplicando antes de dividir, como
    /// `Sustain.gateNanoseconds(over:)`.
    ///
    /// El producto no puede desbordar: el `halfRange` mayor es 100 —`delay`,
    /// `ramp` y `pace`—, así que el techo es 100 · 100 · 100, un millón.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await, sin coma flotante.
    ///
    /// Calculates the offset applied to the target parameter at one step of the turn.
    /// - Parameters:
    ///   - step: The step index within the turn; it wraps around it.
    ///   - stepCount: How many steps the turn has.
    /// - Returns: The offset in the target parameter's own units.
    public func offset(atStep step: Int, of stepCount: Int) -> Int {
        guard depth.percent != 0 else { return 0 }
        let excursion = waveform.value(atStep: step, of: stepCount)
        return excursion * depth.percent * target.modulationHalfRange / 10000
    }

    /// La velocity que se emite en el Step `step` de una vuelta de `stepCount`,
    /// partiendo de la del Cycle (FR6, FR7).
    ///
    /// **El acotado a 1…127 lo hace `Velocity.advanced(by:)`**, que ya existe y
    /// ya está cubierto: la modulación lo reutiliza en vez de escribir un
    /// segundo acotado que pudiera discrepar. El extremo inferior sigue
    /// excluyendo el 0 por la razón de siempre — un note-on con velocity 0 es un
    /// note-off, y para no sonar está Probability.
    ///
    /// **Con `depth` en 0 devuelve la base intacta**, sin pasar por la onda ni
    /// por el acotado. Es la no regresión de la rebanada, y es también lo que
    /// hace que el camino nuevo no cueste nada a quien no lo pide.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await, sin coma flotante.
    ///
    /// Calculates the velocity emitted at one step of the turn.
    /// - Parameters:
    ///   - step: The step index within the turn; it wraps around it.
    ///   - stepCount: How many steps the turn has.
    ///   - base: The velocity of the cycle.
    /// - Returns: A velocity clamped to `Velocity.validRange`.
    public func velocity(atStep step: Int, of stepCount: Int, from base: Velocity) -> Velocity {
        guard depth.percent != 0, target == .velocity else { return base }
        return base.advanced(by: offset(atStep: step, of: stepCount))
    }
}

extension NoteRepeater {

    /// El mismo Note Repeater con el parámetro de destino ya desplazado en este
    /// Step de la vuelta (FR10, FR11, FR14).
    ///
    /// **Cubre sus cuatro destinos y devuelve `self` para los otros cinco.** Es
    /// uno de los tres puntos donde el LFO se aplica, y cada uno conoce solo los
    /// suyos: un único `Cycle.modulated(atStep:of:)` se leería mejor y
    /// **construiría un `Cycle` por Step** en el hilo del scheduler, que es lo
    /// que NFR1 prohíbe.
    ///
    /// **La base es el valor que el knob tiene puesto, y se recorta en los
    /// extremos** (FR10). El acotado lo hace el `advanced(by:)` de cada tipo,
    /// que ya existe y ya está cubierto: escribir un segundo acotado aquí sería
    /// tener dos sitios donde discrepar. Con `repeats` en 0 —su neutro, que está
    /// en un extremo— media onda se recorta entera; es correcto, y el panel de
    /// la pantalla lo enseña.
    ///
    /// **`repeatTime` se mueve por posiciones de `RepeatTime.ordered`**, como
    /// hace el knob: su `displacementRange` es el de posiciones y no el de
    /// fracciones, así que nunca produce una que no esté en la lista.
    ///
    /// **Con `depth` en 0, o con un destino ajeno, devuelve `self`** sin
    /// construir nada.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await, sin coma flotante.
    ///
    /// Applies the modulation to the target parameter at one step of the turn.
    /// - Parameters:
    ///   - modulation: The waveform, depth and target of the cycle.
    ///   - step: The step index within the turn.
    ///   - stepCount: How many steps the turn has.
    /// - Returns: The same note repeater with the target parameter of that step.
    public func modulated(by modulation: Modulation, atStep step: Int, of stepCount: Int)
        -> NoteRepeater
    {
        guard modulation.depth.percent != 0 else { return self }

        let offset = modulation.offset(atStep: step, of: stepCount)
        switch modulation.target {
        case .repeats: return with(repeats: repeats.advanced(by: offset))
        case .repeatTime: return with(time: time.advanced(by: offset))
        case .ramp: return with(ramp: ramp.advanced(by: offset))
        case .pace: return with(pace: pace.advanced(by: offset))
        default: return self
        }
    }
}

extension Cycle {

    /// Cuántos grados de la escala desplaza el LFO la altura de este Step
    /// (FR13). Devuelve 0 si el destino no es `pitch` o si `depth` es 0.
    ///
    /// **Pasa por `pitchOffset(movedBy:)`, la misma vía que el knob.** Así
    /// respeta el pool, el marco tonal y el freno atómico que
    /// `pitch-harmony_20260912` entregó: ninguna altura sale de 0–127 ni de la
    /// escala, y el giro se frena en el último valor válido en vez de acotarse
    /// nota a nota. Acotar plano contra `PitchOffset.validRange` sería más
    /// barato y produciría offsets que el knob no dejaría poner — el LFO y el
    /// knob discreparían.
    ///
    /// **Devuelve el desplazamiento y no un `PitchOffset`**, porque lo que se
    /// mueve es la altura de *este* Step y no el estado del Cycle. El offset del
    /// Cycle es el que puso el knob y no se toca: si el LFO lo escribiera,
    /// dejaría de ser un LFO y sería un knob que gira solo.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// `pitchOffsetLimits(harmony:in:)` recorre el pool —ocho entradas como
    /// mucho— con enteros y sin construir nada.
    /// Sin asignaciones, sin locks, sin await, sin coma flotante.
    public func modulationPitchShift(atStep step: Int, of stepCount: Int) -> Int {
        guard modulation.depth.percent != 0, modulation.target == .pitch else { return 0 }

        // **No pasa por `Modulation.offset(atStep:of:)`**: aquella usa el
        // `halfRange` del `TrackParameter`, y el de pitch depende de la escala.
        // Ver `modulationHalfRange`.
        let excursion = modulation.waveform.value(atStep: step, of: stepCount)
        let offset = excursion * modulation.depth.percent * modulationHalfRange / 10000
        return pitchOffset(movedBy: offset).degrees - pitchOffset.degrees
    }

    /// Cuánto desplaza un `depth` de ±100 en el pico de la onda, para el destino
    /// de este Cycle.
    ///
    /// **Existe porque `pitch` no cabe en `TrackParameter.modulationHalfRange`:**
    /// su excursión es **una octava de la escala del Cycle** —siete grados en
    /// las heptatónicas, cinco en pentatónica y hirajoshi— y eso depende del
    /// marco tonal, que un `TrackParameter` no conoce. Los otros ocho destinos
    /// delegan sin cambios.
    ///
    /// > **Enmienda del 2026-09-16, encontrada verificando en el iPad.** Pitch
    /// > usaba la regla general —media excursión de `displacementRange`—, que da
    /// > 28 grados: **cuatro octavas**. Ese rango es el del knob de
    /// > transposición, no el de una modulación. En el pico de la onda producía
    /// > saltos de hasta cuatro octavas; las notas estaban dentro de la escala
    /// > —eso se comprobó sobre 24.576 combinaciones de escala, root, pool y
    /// > depth, con cero fuera— pero tan lejos que suenan como un error. Y el
    /// > control quedaba inservible: con `depth` 25 ya se tenía una octava, así
    /// > que tres cuartos del slider iban de una a cuatro.
    /// >
    /// > **Una octava de la escala** hace que el recorrido entero del slider sea
    /// > tocable y que «una octava» signifique lo mismo en las ocho escalas.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// `Scale.degrees` construye un array — por eso aquí se cuenta la máscara,
    /// que no asigna.
    /// Sin asignaciones, sin locks, sin await, sin coma flotante.
    public var modulationHalfRange: Int {
        guard modulation.target == .pitch else { return modulation.target.modulationHalfRange }
        return frame.degreesPerOctave
    }

    /// La altura que suena en este Step con el LFO de pitch ya aplicado, o `nil`
    /// si el Step no tiene altura — pool vacío, o Step sin pulso.
    ///
    /// **Desplaza la altura que ya sonaba, en vez de recalcular el pool.**
    /// `PitchPool.sounding(pitchOffset:harmony:in:)` suma el mismo offset a
    /// **todos** los grados, así que mover una altura los grados que el LFO pide
    /// da el mismo resultado que reconstruir el pool entero — y aquello está
    /// documentado como código que no es de tiempo real.
    ///
    /// Que sean equivalentes depende del freno de `modulationPitchShift`: dentro
    /// de los offsets que permite, ninguna altura toca el acotado del marco, así
    /// que el pool no encoge por colisión y el desplazamiento es uniforme.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// `TonalFrame.degree(of:)` y `pitch(atDegree:)` son aritmética entera sobre
    /// la máscara de la escala.
    /// Sin asignaciones, sin locks, sin await, sin coma flotante.
    public func modulatedPitch(
        atStep index: Int, of stepCount: Int, traversal: PoolTraversal = .ascending
    ) -> Pitch? {
        guard let base = pitch(atStep: index, traversal: traversal) else { return nil }

        let shift = modulationPitchShift(atStep: index, of: stepCount)
        guard shift != 0 else { return base }

        // **La altura se lleva al marco antes de contar grados**, con el mismo
        // `nearest(to:)` que usa `PitchPool.degree(at:in:)`. El pool base puede
        // traer alturas fuera de la escala —`sounding(...)` las deja pasar tal
        // cual cuando no hay nada que transponer— y `frame.degree(of:)` devuelve
        // `nil` para ellas.
        //
        // > **Se entregó sin esto y el test lo encontró.** El marco por defecto
        // > es Do menor y el pool de prueba traía un E natural: `degree(of:)`
        // > daba `nil`, la nota se quedaba sin modular y el LFO parecía no
        // > hacer nada en ese Step. Transponer el pool ya resolvía este caso por
        // > esta vía; el LFO tenía que resolverlo igual, no de otra forma.
        guard let degree = frame.degree(of: frame.nearest(to: base)) else { return base }
        return frame.pitch(atDegree: degree + shift) ?? base
    }
}

extension Groove {

    /// El mismo Groove con la velocity que le toca a este Step de la vuelta.
    ///
    /// **Es el único punto donde la modulación se aplica**, y por eso vive aquí
    /// y no en el scheduler: `workflow.md` dice que si algo merece un test está
    /// donde se testea, y una velocity mal compuesta se oye como un acento que
    /// no está donde debería.
    ///
    /// **Solo toca el parámetro de destino, y los otros cuatro salen intactos.**
    /// Cubre `velocity`, `sustain`, `timing` y `delay`; con cualquier otro
    /// devuelve `self` sin construir nada. **`probability` no es destino** y no
    /// lo será: quedó fuera por decisión de producto.
    ///
    /// **`timing` y `delay` sí mueven instantes, y es lo que esos parámetros
    /// hacen** (FR12). Lo hacen dentro de los rangos que ya declaran y ya se
    /// usan, así que el LFO no introduce ningún desplazamiento nuevo — solo otra
    /// vía para pedirlo. Es el argumento por el que NFR3 no exige medición.
    ///
    /// **Con `depth` en 0, o con un destino que no es suyo, devuelve `self`**
    /// sin construir nada: es el criterio 1 de la rebanada, y hace que el camino
    /// nuevo no cueste nada a quien no lo pide.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await, sin coma flotante.
    ///
    /// Applies the modulation to this groove's velocity at one step of the turn.
    /// - Parameters:
    ///   - modulation: The waveform and depth of the cycle.
    ///   - step: The step index within the turn.
    ///   - stepCount: How many steps the turn has.
    /// - Returns: The same groove with the velocity of that step.
    public func modulated(by modulation: Modulation, atStep step: Int, of stepCount: Int) -> Groove
    {
        guard modulation.depth.percent != 0 else { return self }

        let offset = modulation.offset(atStep: step, of: stepCount)
        switch modulation.target {
        case .velocity:
            return Groove(
                velocity: velocity.advanced(by: offset),
                sustain: sustain,
                probability: probability,
                timing: timing,
                delay: delay
            )

        case .sustain:
            return Groove(
                velocity: velocity,
                sustain: sustain.advanced(by: offset),
                probability: probability,
                timing: timing,
                delay: delay
            )

        case .timing:
            return Groove(
                velocity: velocity,
                sustain: sustain,
                probability: probability,
                timing: timing.advanced(by: offset),
                delay: delay
            )

        case .delay:
            return Groove(
                velocity: velocity,
                sustain: sustain,
                probability: probability,
                timing: timing,
                delay: delay.advanced(by: offset)
            )

        // Los cinco restantes no son suyos: cuatro los cubre
        // `NoteRepeater.modulated`, `pitch` lo cubre
        // `Cycle.modulationPitchShift`, y `probability` no es destino.
        default:
            return self
        }
    }
}

/// Un Step de la vuelta, tal y como el panel de respuesta lo dibuja (FR20).
///
/// **Lleva el valor final del parámetro de destino, recorte incluido**: no la
/// forma normalizada. Dos ajustes que recortan distinto se tienen que ver
/// distintos, y eso solo es cierto si la altura de la barra es el valor que se
/// va a emitir.
///
/// **Y lleva si el Step dispara** (FR20), porque los que no son pulso euclidiano
/// se dibujan atenuados: el LFO corre sobre ellos igualmente (FR15), así que
/// tienen valor y no suenan. Un panel que los omitiera mentiría sobre la fase.
///
/// > **Se llamaba `VelocityResponseStep` y llevaba una `Velocity`.** Con el
/// > destino asignable el panel dibuja nueve parámetros distintos, así que el
/// > valor pasa a ser un entero en las unidades del destino y la vista lo
/// > normaliza contra el rango que ese destino declara.
public struct ModulationResponseStep: Equatable, Sendable {

    /// El valor que el parámetro de destino tendría en este Step, ya acotado a
    /// su rango, en sus propias unidades.
    public let value: Int

    /// Si el Step es pulso euclidiano.
    public let triggers: Bool
}

extension Cycle {

    /// La vuelta entera, Step a Step, como el panel la dibuja (FR20, FR21).
    ///
    /// **Tantas entradas como Steps tenga el Cycle**, no dieciséis: el panel es
    /// el espejo del anillo, y uno que dijera dieciséis cuando el anillo dice
    /// nueve mentiría sobre lo que suena.
    ///
    /// **El valor sale del mismo camino que suena.** Cada entrada pasa por el
    /// método de aplicación que le toca a su destino —el de `Groove`, el de
    /// `NoteRepeater` o el desplazamiento de pitch—, así que el panel no puede
    /// discrepar de la emisión: una segunda fórmula aquí sería capaz de dibujar
    /// una onda que nadie oye.
    ///
    /// **Vive en `Engine` y no en la vista** (NFR6). Es el dato que el panel
    /// dibuja, así que se prueba con números en vez de mirándolo — que es lo que
    /// `workflow.md` pide cuando algo en `App` merecería un test.
    ///
    /// **No es código de tiempo real.** Asigna un array y lo consulta la
    /// interfaz al redibujar, como `Playhead`. El camino del scheduler no pasa
    /// por aquí.
    ///
    /// Calculates the value of the modulation target at every step of one turn.
    /// - Returns: One entry per step of the cycle, in order.
    public var modulationResponse: [ModulationResponseStep] {
        let stepCount = shape.steps.count
        return (0..<stepCount).map { step in
            ModulationResponseStep(
                value: modulationValue(atStep: step, of: stepCount),
                triggers: triggers(atStep: step)
            )
        }
    }

    /// El valor del parámetro de destino en este Step, en sus propias unidades.
    ///
    /// **Pasa por el método de aplicación que le toca**, no por una fórmula
    /// propia: es lo que garantiza que el panel dibuje lo que se emite.
    private func modulationValue(atStep step: Int, of stepCount: Int) -> Int {
        let target = modulation.target
        let groove = groove.modulated(by: modulation, atStep: step, of: stepCount)
        let repeater = noteRepeater.modulated(by: modulation, atStep: step, of: stepCount)

        switch target {
        case .velocity: return groove.velocity.value
        case .sustain: return groove.sustain.percent
        case .timing: return groove.timing.percent
        case .delay: return groove.delay.percent
        case .repeats: return repeater.repeats.count
        // Como el knob: lo que se mueve es la posición en la lista, así que es
        // la posición lo que el panel dibuja. La fracción no es una escala.
        case .repeatTime:
            return RepeatTime.ordered.firstIndex(of: repeater.time) ?? 0
        case .ramp: return repeater.ramp.percent
        case .pace: return repeater.pace.percent
        case .pitch:
            return pitchOffset.degrees + modulationPitchShift(atStep: step, of: stepCount)
        // Los seis restantes no son destino y `Modulation` no puede apuntarlos.
        default: return groove.velocity.value
        }
    }

    /// El rango contra el que el panel normaliza sus barras, y el nombre que
    /// lleva el título (FR20, FR21).
    ///
    /// **Vive aquí y no en la vista** por la razón de siempre: `workflow.md`
    /// dice que si algo en `App` merece un test está en el sitio equivocado.
    public var modulationResponseRange: ClosedRange<Int> {
        // **Pitch se normaliza contra lo que el LFO alcanza, no contra ±28.**
        // Su `displacementRange` es el recorrido del knob —cuatro octavas— y la
        // excursión del LFO es una octava: dibujar la onda dentro del rango del
        // knob la dejaría en una banda plana en el centro del panel, que no
        // enseña nada. Se acota igualmente al rango del parámetro, porque el
        // freno del pool no deja salir de él.
        if modulation.target == .pitch {
            let reach = modulationHalfRange
            let base = pitchOffset.degrees
            let range = PitchOffset.validRange
            return max(range.lowerBound, base - reach)...min(range.upperBound, base + reach)
        }
        return modulation.target.displacementRange ?? Velocity.validRange
    }

    /// Cómo se rotula el panel: `velocity response`, `pitch response`, …
    ///
    /// **En minúscula, como el resto de la pantalla**, y con el término de la
    /// Pre Spec sin traducir (NFR7).
    public var modulationResponseTitle: String {
        "\(modulation.target.description.lowercased()) response"
    }
}
