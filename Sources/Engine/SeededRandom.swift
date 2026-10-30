/// Generador pseudoaleatorio sembrado.
///
/// **`tech-stack.md` lo exige desde el primer commit**: «El aleatorio es
/// pseudoaleatorio con semilla … PRNG explícito y sembrado, nunca
/// `Int.random()`». La Pre Spec pone la razón musical: la secuencia tiene que
/// «cambiar, pero no ser caos totalmente impredecible». Probability es su primer
/// usuario.
///
/// **Qué significa repetible aquí.** El generador avanza por Pulse, así que dos
/// vueltas consecutivas del anillo no deciden lo mismo. Lo que se repite es la
/// sesión: resembrarlo con la misma semilla reproduce exactamente la misma
/// secuencia. Precisión documentada con fecha en `tech-stack.md` el 2026-08-29.
///
/// **Por qué no se usa `SystemRandomNumberGenerator` ni `RandomNumberGenerator`
/// de la stdlib.** El protocolo obligaría a pasar el generador como
/// `inout some RandomNumberGenerator`, y usarlo como existencial metería boxing
/// en el hilo del scheduler. Este tipo es un `struct` concreto y trivial: su
/// estado son ocho bytes que se copian sin tocar el conteo de referencias.
///
/// El algoritmo es *xorshift64\**: tres desplazamientos, tres XOR y una
/// multiplicación. Se elige por ser suficiente para decidir omisiones y caber
/// entero en el camino de tiempo real — no es criptográfico y no pretende
/// serlo.
public struct SeededRandom: Equatable, Sendable {

    /// Semilla por defecto del producto.
    ///
    /// Fija a propósito: es lo que hace que pulsar Play dos veces reproduzca la
    /// misma secuencia de omisiones. Un valor sembrado del reloj daría una
    /// sesión distinta cada vez y rompería la reproducibilidad que la Pre Spec
    /// pide.
    public static let defaultSeed: UInt64 = 0x2545_F491_4F6C_DD1D

    /// Estado del generador. Nunca es cero: ver el inicializador.
    private var state: UInt64

    /// - Parameter seed: cualquier valor. El cero se sustituye por una
    ///   constante, porque *xorshift* con estado cero se queda clavado en cero
    ///   para siempre — es el modo de fallo clásico de la familia, y se cierra
    ///   aquí en vez de confiar en que nadie siembre con cero.
    public init(seed: UInt64 = SeededRandom.defaultSeed) {
        state = seed == 0 ? SeededRandom.defaultSeed : seed
    }

    /// El siguiente valor de la secuencia.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Generates the next pseudo-random value in the sequence.
    /// - Returns: The next `UInt64` value.
    public mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }
}

extension SeededRandom {

    /// Un valor aleatorio en −100…100 para el Step absoluto `step`, **sin
    /// estado**: el aleatorio de la onda `random` de la modulación.
    ///
    /// **No avanza ningún generador**, y es la razón de que exista aparte de
    /// `next()`. El consumo de `SeededRandom` es lo que fija las omisiones de
    /// Probability; si la modulación tirara de él, poner `random` en un Cycle
    /// movería los huecos de un patrón que nadie tocó. Sigue siendo
    /// determinista y sembrado, que es lo que pide `RULES.md` §3.
    ///
    /// **Varía por vuelta y se repite por Play**, como Probability: el Step
    /// absoluto crece a lo largo de una pasada y vuelve a empezar al pulsar
    /// Play, y la semilla es fija.
    ///
    /// El mezclador es el finalizador de *SplitMix64* sobre `seed ^ step`:
    /// dos multiplicaciones y tres desplazamientos, sin asignación. El sesgo del
    /// módulo 201 sobre 2⁶⁴ no se oye.
    public static func excursion(seed: UInt64, atStep step: Int) -> Int {
        var z = seed ^ UInt64(bitPattern: Int64(step))
        z &+= 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Int(z % 201) - 100
    }
}
