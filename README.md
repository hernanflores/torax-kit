# Torax Kit

El motor de [Torax H-0](https://github.com/hernanflores/torax-h0), sin pantalla.

Cuatro productos SPM que una app iOS o macOS puede consumir para tener un
secuenciador MIDI generativo completo —reloj, scheduler, salida, entrada de
control, persistencia— **y escribir solo sus pantallas**.

```swift
.package(url: "https://github.com/hernanflores/torax-kit", from: "1.0.0")
```

## Los cuatro productos

| Producto | Qué es | Depende de |
|---|---|---|
| `Engine` | El motor generativo: Shape, Tonal, Groove, Cycles, modulación. **Solo stdlib** — ni Foundation. | — |
| `MIDI` | El reloj, el scheduler look-ahead y CoreMIDI. El camino crítico de timing. | `Engine` |
| `Persistence` | El disco: JSON, escritura atómica, Autosave, rescate de ficheros ilegibles. | `Engine` |
| `Session` | El aparato de una sesión: los dos extremos de CoreMIDI y el árbol de Banks. | `MIDI`, `Persistence` |

Ninguno importa SwiftUI ni UIKit, y ninguno tiene estado observable. La capa
observable es de cada app.

## La arquitectura de timing, en una línea

El scheduler calcula los eventos de una ventana futura y se los entrega a
CoreMIDI **ya sellados con un timestamp de entrega**, así que el jitter no
depende de cuándo despierta el hilo. Medido en iPad Air (4ª gen): máximo
**0,158 ms** y σ **0,013 ms** contra un umbral de 2 ms / 0,5 ms.

Lo que eso impone al código que corre en el hilo del scheduler: **sin
asignaciones, sin locks, sin `await`, sin logging.** Está documentado en cada
sitio donde importa.

## Las reglas

Tres, y están en [`RULES.md`](RULES.md): el dominio se valida en el tipo, el
camino del scheduler no asigna ni bloquea, y `Engine` es puro. El código las
cita por número donde importan.

## Qué se vigila solo

`Engine` no puede importar Foundation, CoreMIDI, Combine ni SwiftUI:
`DependencyBoundaryTests` lee el código fuente y falla si alguien lo intenta. No
es disciplina, es un test.

## Tests

```
swift test --filter 'VirtualLoopbackTests|JitterHarnessTests|CoreMIDIOutputTests|CoreMIDIInputTests'
swift test --skip VirtualLoopbackTests --skip JitterHarnessTests --skip CoreMIDIOutputTests --skip CoreMIDIInputTests
```

**Dos procesos a propósito.** Los tests que crean endpoints virtuales de
CoreMIDI van primero y solos: la suite arranca hilos de scheduler a prioridad
máxima y esa presión inutiliza la creación de endpoints para el resto del
proceso. Es una mitigación conocida, no un arreglo.

2218 tests. Cobertura: `Engine` 98%, `MIDI` 92%, `Persistence` 90%,
`Session.ProjectSession` 98%. `Session.MIDISession` no se mide todavía —abre
puertos de CoreMIDI en su `init`—, y está escrito por qué en su manifiesto.

## `preset/`

El preset del Arturia BeatStep Pro que mapea los knobs a los parámetros del
motor. **No es documentación:** `PresetFileTests` comprueba que el fichero que
se carga en MIDI Control Center y el mapeo en código dicen lo mismo.
