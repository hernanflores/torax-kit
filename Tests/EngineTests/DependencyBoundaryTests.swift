import XCTest

/// Guarda la pureza del paquete `Engine`.
///
/// `conductor/tech-stack.md` exige que el motor generativo no dependa de nada
/// más allá de la stdlib de Swift: es lo que permite testearlo sin simulador y
/// lo que impide que la lógica musical se enrede con CoreMIDI o SwiftUI.
///
/// Este test escanea el código fuente en lugar de confiar en la disciplina.
final class DependencyBoundaryTests: XCTestCase {

    /// Módulos que `Engine` no puede importar.
    ///
    /// Foundation está incluido a propósito: la regla es *stdlib*, no
    /// "stdlib y un poco de Foundation". El motor es determinista y no
    /// necesita fechas, locales ni formateadores.
    private static let forbiddenModules = [
        "AppKit",
        "AVFoundation",
        "CoreAudio",
        "CoreGraphics",
        "CoreMIDI",
        "Combine",
        "Foundation",
        "SwiftUI",
        "UIKit",
    ]

    private var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // EngineTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // la raíz del kit
            .appendingPathComponent("Sources/Engine")
    }

    func testEngineSourcesImportNothingBeyondStdlib() throws {
        let files = try swiftFiles(in: sourcesDirectory)
        XCTAssertFalse(files.isEmpty, "No se encontró código fuente en \(sourcesDirectory.path)")

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
            {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("import ") else { continue }

                let module =
                    trimmed
                    .dropFirst("import ".count)
                    .trimmingCharacters(in: .whitespaces)
                    .split(separator: ".").first
                    .map(String.init) ?? ""

                XCTAssertFalse(
                    Self.forbiddenModules.contains(module),
                    """
                    \(file.lastPathComponent):\(index + 1) importa '\(module)'.
                    Engine debe depender solo de la stdlib de Swift \
                    (conductor/tech-stack.md).
                    """
                )
            }
        }
    }

    /// El target `Engine` no declara dependencias.
    ///
    /// **Cambió de forma al mudarse al kit, no de intención.** Antes había un
    /// `Package.swift` por paquete y bastaba con que el de `Engine` no tuviera
    /// ningún `.package(`. Ahora el manifiesto es uno solo y compartido, así que
    /// lo que hay que vigilar es su línea: `.target(name: "Engine")`, a secas.
    /// Si alguien le cuelga un `dependencies:`, esto falla.
    func testEngineTargetDeclaresNoDependencies() throws {
        let manifest =
            sourcesDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Package.swift")

        let source = try String(contentsOf: manifest, encoding: .utf8)
        XCTAssertTrue(
            source.contains(#".target(name: "Engine")"#),
            """
            El target 'Engine' del manifiesto declara dependencias, o cambió de \
            forma. Engine debe depender solo de la stdlib de Swift \
            (conductor/tech-stack.md).
            """
        )
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil
            )
        else { return [] }

        return
            enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
    }
}
