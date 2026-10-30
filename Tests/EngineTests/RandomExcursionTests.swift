import XCTest

@testable import Engine

/// Tests del aleatorio sin estado de la modulación (FR2, AC 7).
///
/// **No es un segundo consumidor de `SeededRandom`.** Es una función pura de
/// `(semilla, Step absoluto)`: no avanza nada, así que no puede mover las
/// omisiones de Probability. Que varíe por vuelta sale de que el Step absoluto
/// crece; que se repita por Play, de que la semilla es fija.
final class RandomExcursionTests: XCTestCase {

    private let seed = SeededRandom.defaultSeed

    /// Misma entrada, mismo valor: es lo que hace repetible la sesión (AC 3).
    func testTheSameSeedAndStepAlwaysGiveTheSameValue() {
        for step in 0..<512 {
            XCTAssertEqual(
                SeededRandom.excursion(seed: seed, atStep: step),
                SeededRandom.excursion(seed: seed, atStep: step),
                "step \(step)")
        }
    }

    /// Todo cae en −100…100, el recorrido de las otras cuatro ondas.
    func testEveryValueIsWithinTheWaveformRange() {
        for step in 0..<10_000 {
            let value = SeededRandom.excursion(seed: seed, atStep: step)
            XCTAssertTrue((-100...100).contains(value), "step \(step): \(value)")
        }
    }

    /// Los dos extremos se alcanzan: con `depth = ±100` el destino llega a su
    /// media excursión entera, como con las ondas periódicas.
    func testBothExtremesAreReached() {
        let values = Set((0..<10_000).map { SeededRandom.excursion(seed: seed, atStep: $0) })
        XCTAssertTrue(values.contains(-100))
        XCTAssertTrue(values.contains(100))
    }

    /// **Reparto plano.** Sobre 10.000 Steps cada decil del recorrido recibe
    /// 1.000 ± 10%. Determinista: la semilla es fija, así que esto no es un test
    /// probabilístico que pueda fallar un día sí y otro no (AC 7).
    func testTheValuesAreSpreadEvenlyAcrossTheRange() {
        var deciles = [Int](repeating: 0, count: 10)
        for step in 0..<10_000 {
            let value = SeededRandom.excursion(seed: seed, atStep: step)
            deciles[(value + 100) * 10 / 201] += 1
        }
        for (index, count) in deciles.enumerated() {
            XCTAssertTrue((900...1100).contains(count), "decil \(index): \(count)")
        }
    }

    /// Dos vueltas seguidas de dieciséis Steps no dan la misma secuencia (AC 4).
    func testConsecutiveLapsDiffer() {
        let first = (0..<16).map { SeededRandom.excursion(seed: seed, atStep: $0) }
        let second = (16..<32).map { SeededRandom.excursion(seed: seed, atStep: $0) }
        XCTAssertNotEqual(first, second)
    }

    /// Dos semillas, dos secuencias: es lo que hace que dos Tracks no suenen
    /// igual (AC 6).
    func testDifferentSeedsGiveDifferentSequences() {
        let first = (0..<16).map { SeededRandom.excursion(seed: 1, atStep: $0) }
        let second = (0..<16).map { SeededRandom.excursion(seed: 2, atStep: $0) }
        XCTAssertNotEqual(first, second)
    }

    /// No hay estado: un `SeededRandom` que se usa en medio no cambia nada.
    /// Es la propiedad que protege a Probability (FR8).
    func testDrawingFromAGeneratorDoesNotChangeTheExcursion() {
        let before = (0..<16).map { SeededRandom.excursion(seed: seed, atStep: $0) }
        var generator = SeededRandom(seed: seed)
        for _ in 0..<100 { _ = generator.next() }
        let after = (0..<16).map { SeededRandom.excursion(seed: seed, atStep: $0) }
        XCTAssertEqual(before, after)
    }

    /// Un Step negativo no puede ocurrir en el scheduler, pero la función corre
    /// en su hilo: devuelve un valor en rango y no revienta.
    func testANegativeStepStillGivesAValueInRange() {
        for step in [-1, -16, Int.min] {
            let value = SeededRandom.excursion(seed: seed, atStep: step)
            XCTAssertTrue((-100...100).contains(value), "step \(step): \(value)")
        }
    }
}
