import CoreMIDI
import MIDI

/// Los dos extremos de CoreMIDI de una sesión, y su elección.
///
/// **Es cableado, no pantalla.** Abrir la salida, abrir la entrada, vigilar qué
/// endpoints hay, recordar cuál se eligió la última vez y reconectar cuando el
/// sistema reenumera es exactamente igual en cualquier app que use este motor.
/// Vivía en `App/TransportModel.swift`, que es donde estaba mezclado con estado
/// observable; aquí no hay nada observable y nada de SwiftUI.
///
/// **Los dos extremos se abren por separado, y en ese orden**, porque así lo
/// exige quien los usa: la salida hace falta para construir el `Transport` —es
/// de donde sale su closure de envío—, y la entrada hace falta después, cuando
/// ya existe alguien a quien entregarle los mensajes. `init` abre la salida;
/// `connectInput(...)` abre la entrada.
///
/// **Ninguno de los dos es obligatorio.** Sin salida la app no suena pero abre;
/// sin entrada se queda en solo lectura y transporte, que es un estado previsto
/// por `product-guidelines.md` y no un fallo.
@MainActor
public final class MIDISession {

    // MARK: - Lo que se eligió

    /// A dónde se envía. Es `MIDIEndpointSelection`, no un endpoint: la
    /// ambigüedad —dos destinos y ninguna preferencia— es un estado que la
    /// pantalla tiene que poder nombrar.
    public private(set) var destination: MIDIEndpointSelection

    /// De dónde se recibe.
    public private(set) var source: MIDIEndpointSelection

    /// Solo se llena si CoreMIDI no arrancó, que es un fallo real y no una
    /// desconexión. Desenchufar el cable es un estado (`No MIDI device`), no
    /// esto.
    public private(set) var outputUnavailable: String?

    /// Si hay salida con la que sonar. La pantalla lo usa para decidir si `Play`
    /// se puede pulsar.
    public var hasOutput: Bool { output != nil }

    /// Avisa de que el **sistema** cambió el destino: se enchufó o se
    /// desenchufó algo. No se llama cuando el cambio lo pide la app con
    /// `select(_:)`, porque entonces quien llama ya lo sabe.
    public var onDestinationChange: ((MIDIEndpointSelection) -> Void)?

    /// Lo mismo para la fuente.
    public var onSourceChange: ((MIDIEndpointSelection) -> Void)?

    // MARK: - El aparato

    private var output: CoreMIDIOutput?
    private var watcher: MIDIEndpointWatcher?
    private var input: CoreMIDIInput?
    private var sourceWatcher: MIDIEndpointWatcher?

    /// Endpoint al que se está enviando, leído desde el hilo del scheduler.
    ///
    /// **Va en un atómico y no en una propiedad.** El destino cambia al enchufar
    /// o desenchufar, así que el hilo del scheduler tiene que poder leerlo
    /// mientras suena, y sin tomar nada que pueda bloquear o asignar.
    ///
    /// `0` es el objeto nulo de CoreMIDI, así que sirve como «ninguno».
    private let activeDestination = AtomicCounter(0)

    /// Lo que se hace justo antes de reconectar la fuente.
    ///
    /// **Existe por los modificadores** (FR8): si el cable se fue con un step
    /// button hundido, la soltada que lo levantaría ya no va a llegar por ningún
    /// sitio y el modificador se quedaría pegado para siempre. Quién sabe
    /// soltarlos es la entrada de control, que vive fuera de aquí.
    private var willReconnectSource: (@MainActor () -> Void)?

    // MARK: - Abrir la salida

    /// Abre la salida y elige destino, prefiriendo el que se recordó.
    ///
    /// - Parameter name: el destino guardado en disco, si lo hay. Lo recordado
    ///   sigue pendiente mientras no esté disponible y entra solo en cuanto
    ///   aparezca; una elección manual posterior lo cancela.
    public init(rememberingDestination name: String?) {
        destination = MIDIEndpointSelection(.destination)
        source = MIDIEndpointSelection(.source)

        do {
            let output = try CoreMIDIOutput()
            self.output = output

            let watcher = MIDIEndpointWatcher(
                .destination, enumerating: output.availableDestinations, remembering: name)
            self.watcher = watcher
            destination = watcher.selection
            activeDestination.value = UInt64(destination.selected?.endpoint ?? 0)

            watcher.onChange = { [weak self] selection in
                self?.destinationsChanged(to: selection)
            }
            // La notificación llega desde el hilo de CoreMIDI; el watcher ya
            // entrega el cambio en el principal.
            output.onSetupChanged = { [weak watcher] in watcher?.setupChanged() }
        } catch {
            outputUnavailable = "MIDI output unavailable"
        }
    }

    /// El closure de envío que espera `Transport`, o `nil` si no hay salida.
    ///
    /// **No captura la sesión, y eso es el punto entero.** Corre en el hilo del
    /// scheduler, donde no se puede tocar estado aislado al principal ni
    /// registrar una dependencia de observación. Captura exactamente dos cosas:
    /// la salida, que es `Sendable`, y el atómico del destino.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func makeSend() -> Transport.Send? {
        guard let output else { return nil }
        let destination = activeDestination
        return { message, hostTime in
            let endpoint = MIDIEndpointRef(destination.value)
            guard endpoint != 0 else { return }
            output.send(message, to: endpoint, atHostTime: hostTime)
        }
    }

    /// Elige otro destino, a mano.
    ///
    /// No dispara `onDestinationChange`: quien llama acaba de pedirlo, así que
    /// ya lo sabe. Persistir la elección es cosa suya — aquí no hay disco.
    public func select(_ endpoint: MIDIEndpointInfo) {
        destination = watcher?.selecting(endpoint) ?? destination.selecting(endpoint)
        activeDestination.value = UInt64(destination.selected?.endpoint ?? 0)
    }

    private func destinationsChanged(to selection: MIDIEndpointSelection) {
        destination = selection
        activeDestination.value = UInt64(selection.selected?.endpoint ?? 0)
        // Perder el destino no para el reloj: el transporte sigue corriendo y
        // vuelve a sonar solo en cuanto haya dónde enviar. Desenchufar es un
        // estado, no una interrupción de la sesión.
        onDestinationChange?(selection)
    }

    // MARK: - Abrir la entrada

    /// Abre la entrada, elige fuente y se conecta.
    ///
    /// - Parameters:
    ///   - name: la fuente guardada en disco, si la hay (FR15). Recordar la
    ///     última elección resuelve mejor que cualquier heurística.
    ///   - consumedByTransport: si el mensaje era del reloj. **Se resuelve en el
    ///     hilo de recepción, sin saltar al principal**: un tick vive de cuándo
    ///     llegó, y la cola del hilo principal metería su propio retraso en la
    ///     estimación del tempo. Devuelve `true` si no hay nada más que hacer
    ///     con el mensaje.
    ///   - receive: el resto de mensajes, ya en el hilo principal. El salto es
    ///     obligado porque ahí se muta estado que lee la interfaz, y es gratis
    ///     porque esto no está en el camino de timing.
    ///   - willReconnect: qué hacer justo antes de reconectar. Ver
    ///     `willReconnectSource`.
    public func connectInput(
        rememberingSource name: String?,
        consumedByTransport: @escaping @Sendable (MIDIMessage, MIDITimeStamp) -> Bool,
        receive: @escaping @Sendable @MainActor (MIDIMessage) -> Void,
        willReconnect: @escaping @MainActor () -> Void
    ) {
        willReconnectSource = willReconnect
        do {
            let input = try CoreMIDIInput { message, hostTime in
                if consumedByTransport(message, hostTime) { return }
                Task { @MainActor in receive(message) }
            }
            self.input = input

            let sourceWatcher = MIDIEndpointWatcher(
                .source, enumerating: input.availableSources, remembering: name)
            self.sourceWatcher = sourceWatcher
            source = sourceWatcher.selection
            connectToSelectedSource()

            sourceWatcher.onChange = { [weak self] selection in
                guard let self else { return }
                self.source = selection
                self.connectToSelectedSource()
                self.onSourceChange?(selection)
            }
            // **Además de reconsultar, se vuelve a conectar.** El watcher solo
            // avisa cuando la *elección* cambia, y CoreMIDI puede tirar la
            // conexión del puerto sin que la lista de fuentes cambie —el
            // dispositivo se reenumera y vuelve con el mismo nombre—. Sin esto,
            // la app se queda con un puerto conectado a nada: los knobs dejan de
            // llegar y no hay nada que la despierte. Conectar es idempotente y
            // desconecta la anterior, así que repetirlo no cuesta nada.
            input.onSetupChanged = { [weak sourceWatcher, weak self] in
                sourceWatcher?.setupChanged()
                Task { @MainActor in self?.connectToSelectedSource() }
            }
        } catch {
            // Sin entrada, la app se queda en solo lectura y transporte. Es un
            // estado previsto, no un fallo que haya que anunciar.
            input = nil
        }
    }

    /// Elige otra fuente, a mano. Como `select(_:)`, no avisa ni persiste.
    public func selectSource(_ endpoint: MIDIEndpointInfo) {
        source = sourceWatcher?.selecting(endpoint) ?? source.selecting(endpoint)
        connectToSelectedSource()
    }

    private func connectToSelectedSource() {
        willReconnectSource?()
        guard let endpoint = source.selected?.endpoint else {
            // La ambigüedad se comporta como «sin fuente»: conservar la conexión
            // automática anterior sería elegirla a escondidas.
            input?.disconnect()
            return
        }
        input?.connect(to: endpoint)
    }
}
