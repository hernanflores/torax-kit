// swift-tools-version: 6.1
import PackageDescription

/// Torax Kit — el motor de Torax H-0, sin pantalla.
///
/// **Un repositorio y un manifiesto porque SPM no sabe hacer otra cosa.** Un
/// paquete que vive en un subdirectorio de un repo git no se puede consumir por
/// URL, así que los cuatro comparten raíz y versión. La consecuencia hay que
/// saberla: **tocar `Session` sube el número que ve quien solo usa `Engine`.**
/// Se acepta mientras los consumidores se cuenten con una mano.
///
/// **El reparto no cambia por mudarse**, y es lo que hace que esto sea un kit y
/// no una carpeta:
///
/// - `Engine` — motor generativo puro. **Solo stdlib**, ni Foundation.
///   `DependencyBoundaryTests` lo vigila leyendo el código fuente, no confiando
///   en la disciplina.
/// - `MIDI` — el reloj, el scheduler y CoreMIDI. El camino crítico de timing.
/// - `Persistence` — el disco, con el sistema de ficheros inyectable.
/// - `Session` — el aparato de una sesión: los dos extremos de CoreMIDI y el
///   árbol de Banks. Sin SwiftUI y sin estado observable; eso es de cada app.
///
/// Quien construya una app encima escribe sus pantallas y su capa observable, y
/// no vuelve a escribir nada de esto.
///
/// **La cobertura va por pieza, y no por accidente.** `Engine` ≥90% —puro y
/// determinista, sin excusa—, `MIDI` ≥80% —la entrega real de CoreMIDI se
/// valida con el arnés de jitter, no con tests—, `Persistence` ≥90% porque es
/// lo único capaz de perder el trabajo del usuario, y dentro de `Session` el
/// reparto es desigual a propósito: `ProjectSession` se mide como
/// `Persistence`, y **`MIDISession` no se mide todavía**. Abre los puertos de
/// CoreMIDI en su `init`, así que un test que la construya abre un cliente
/// real, que es el camino del flake documentado en los tests de `MIDI`.
/// Medirla pide un seam sobre `CoreMIDIOutput` y `CoreMIDIInput`; es una
/// decisión tomada el 2026-09-20, no un descuido.
let package = Package(
    name: "ToraxKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Engine", targets: ["Engine"]),
        .library(name: "MIDI", targets: ["MIDI"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Session", targets: ["Session"]),
    ],
    targets: [
        // **`Engine` no lleva `dependencies` y no es un olvido.** Es la regla que
        // permite testearlo sin simulador y lo que impide que la lógica musical
        // se enrede con CoreMIDI o SwiftUI. Hay un test que falla si alguien se
        // la salta.
        .target(name: "Engine"),

        // Atómicos sin lock. Target C propio, no una dependencia externa:
        // iPadOS 17 no ofrece alternativa sin recurrir a terceros.
        .target(name: "CToraxAtomics"),

        .target(name: "MIDI", dependencies: ["Engine", "CToraxAtomics"]),
        .target(name: "Persistence", dependencies: ["Engine"]),
        .target(name: "Session", dependencies: ["MIDI", "Persistence"]),

        .testTarget(name: "EngineTests", dependencies: ["Engine"]),
        .testTarget(name: "MIDITests", dependencies: ["MIDI"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
        .testTarget(name: "SessionTests", dependencies: ["Session"]),
    ]
)
