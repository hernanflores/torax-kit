# Las reglas del kit

Tres reglas que el código cita una y otra vez. Están aquí porque **son la razón
de que el motor suene estable**, y quien toque una línea del camino de timing
tiene que conocerlas antes.

---

## 1. El dominio se valida en el tipo, no en cada sitio de uso

Los rangos musicales —Steps 1–16, Probability 0–100%, Tempo 20–300 bpm— se
comprueban **una vez, en el inicializador**, que por eso es fallible. Un `Steps`
o un `Tempo` que existe es siempre musicalmente válido, y ningún sitio de uso
vuelve a preguntar.

Ticks musicales, timestamps de host y valores MIDI **no son `Int`
intercambiables**: cada uno tiene su tipo, y mezclarlos no compila.

La consecuencia práctica: el camino del scheduler no valida nada, porque no hay
nada que validar.

---

## 2. El camino del scheduler — lo que nunca se hace ahí

Aplica a **todo código que corra en el hilo del scheduler MIDI**. Romperlas
produce jitter, que es exactamente el criterio de éxito del proyecto.

Ahí dentro, **nunca**:

- asignar memoria — sin `Array` que crezca, sin `String`, sin boxing de existenciales;
- tomar locks ni esperar en semáforos;
- usar `await` ni nada que pueda suspender;
- llamar a Objective-C dinámico, `print`, logging o I/O de fichero;
- tocar UIKit ni SwiftUI.

En su lugar:

- buffers preasignados y estructuras de tamaño fijo;
- lectura de un **snapshot inmutable**, publicado atómicamente desde el hilo de control;
- comunicación hacia la interfaz por valores publicados, **nunca** por callbacks síncronos.

**Y se marca en el código.** Toda función que corra en ese hilo lo declara:

```swift
/// Realtime: llamado desde el hilo del scheduler.
/// Sin asignaciones, sin locks, sin await.
```

Si ves ese comentario, estás en el camino crítico.

---

## 3. `Engine` es puro

El target `Engine` no importa CoreMIDI, SwiftUI, UIKit, Combine **ni Foundation**
— solo la stdlib de Swift. No es purismo: es lo que permite testearlo sin
simulador y lo que impide que la lógica musical se enrede con la plataforma.

**No depende de la disciplina.** `DependencyBoundaryTests` lee el código fuente
línea a línea y falla si alguien importa algo prohibido, y comprueba además que
el target no declare dependencias en el manifiesto.

Las funciones del motor son **deterministas**: para el mismo estado y la misma
semilla, la misma salida. El aleatorio entra siempre como PRNG sembrado y
explícito — **nunca `Int.random()` ni `.randomElement()`**, que rompen la
reproducibilidad.
