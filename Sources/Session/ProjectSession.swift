import Engine
import Foundation
import Persistence

/// El árbol de una sesión y su disco: dieciséis Banks, dónde se está mirando,
/// el portapapeles y cuándo se escribe.
///
/// **Es lo que `App/TransportModel.swift` no podía medir.** Aquí viven las dos
/// cosas capaces de perder el trabajo del usuario —el guardado y el pegado— y
/// hasta hoy estaban en la única capa sin tests. `ProjectStore` recibe el
/// sistema de ficheros y `Autosave` recibe el reloj, así que esto se ejerce
/// entero sin tocar disco real ni esperar el silencio del debounce.
///
/// **Dónde está la frontera con quien lo usa.** Esto gobierna el árbol y el
/// disco; no conoce el transporte, ni la entrada de control, ni la copia viva
/// del Pattern que el scheduler está leyendo. Cuando una operación deja trabajo
/// fuera del árbol —pegar encima del hueco cargado, o del que espera al
/// compás— **lo devuelve en vez de hacerlo**: la regla de qué hay que refrescar
/// vive en `PatternPasteRefresh`, en `Engine`, y ejecutarla es de quien tiene el
/// motor delante.
@MainActor
public final class ProjectSession {

    /// El árbol entero: dieciséis Banks, dónde se está mirando y los ajustes de
    /// sesión.
    public private(set) var project: Project

    /// El Pattern copiado, o `nil` si no se ha copiado nada todavía (FR1–FR4).
    ///
    /// **Vive en memoria y no se persiste**: no toca el formato de disco ni
    /// `schemaVersion` (FR3, NFR5). Se pierde al cerrar la app, que es lo que un
    /// portapapeles hace.
    public private(set) var clipboard: PatternClipboard?

    /// Los ficheros que se apartaron por ilegibles al abrir. **Vacío es el caso
    /// normal.**
    public let rescuedFiles: [String]

    /// El Pattern con el que abre la app.
    ///
    /// **Disco vacío arranca con el material de siempre, no con silencio.**
    /// `load()` devuelve un Project vacío cuando no hay nada que leer, que es
    /// correcto para el almacén: no se inventa material que nadie guardó. Quien
    /// decide con qué abre la app es esto.
    public let restoredPattern: Pattern

    private let store: ProjectStore
    private let autosave: Autosave

    /// Abre el disco. **Nunca falla**: si el fichero está corrupto o es de una
    /// versión desconocida se aparta con marca de tiempo y `rescuedFiles` lo
    /// dice. La app abre siempre (FR20, FR23).
    public init(store: ProjectStore = ProjectStore(), quietPeriod: TimeInterval = 2) {
        self.store = store
        self.autosave = Autosave(store: store, quietPeriod: quietPeriod)

        let restored = store.load()
        let loaded = restored.wasEmpty ? Project.initial : restored.project
        project = loaded
        rescuedFiles = restored.rescuedFiles
        restoredPattern =
            loaded.bank(at: loaded.selectedBank)?
            .pattern(at: loaded.selectedPattern) ?? Pattern.initial
    }

    // MARK: - El árbol

    /// El Bank vigente.
    public var bank: Bank { project.bank(at: project.selectedBank) ?? Bank() }

    public var selectedBankIndex: Int { project.selectedBank }
    public var selectedPatternIndex: Int { project.selectedPattern }

    /// El estado de los dieciséis huecos del Bank vigente (FR25).
    public func slotStates(queued: Int?, isRunning: Bool) -> [PatternSlotState] {
        bank.slotStates(playing: project.selectedPattern, queued: queued, isRunning: isRunning)
    }

    /// El material de un hueco del Bank vigente.
    public func pattern(at index: Int) -> Pattern? { bank.pattern(at: index) }

    /// Otro Bank, sin moverse a él.
    public func bank(at index: Int) -> Bank? { project.bank(at: index) }

    // MARK: - Mover la mirada

    /// Mueve la selección al hueco dado.
    public func selectPattern(_ index: Int) {
        project = project.selectingPattern(index)
        autosave.changedHeader(project)
    }

    /// Mueve la selección al Bank dado.
    public func selectBank(_ index: Int) {
        project = project.selectingBank(index)
        autosave.changedHeader(project)
    }

    /// Anota lo que el scheduler dice haber adoptado (FR8, FR10).
    ///
    /// Conserva el Bank y el hueco de entonces —no los vigentes—, para que
    /// cambiar de selección antes del poll no desincronice el árbol de lo que
    /// empezó a sonar.
    public func adopted(bank index: Int, pattern slot: Int) {
        project = project.selectingBank(index).selectingPattern(slot)
        autosave.changedHeader(project)
    }

    /// Marca la cabecera como sucia sin mover nada.
    ///
    /// Existe para el caso que suena: armar un hueco no mueve la selección, pero
    /// sí cambia lo que hay que recordar.
    public func headerChanged() {
        autosave.changedHeader(project)
    }

    /// Recuerda los extremos MIDI elegidos a mano (FR15).
    public func remember(destination: String?, source: String?) {
        project = project.remembering(destinationNamed: destination, sourceNamed: source)
        autosave.changedHeader(project)
    }

    /// Guarda el mapeo del controlador con los ajustes de sesión.
    ///
    /// **Va al Project y no a un fichero propio**: el mapeo es de sesión, como
    /// el reloj y el hardware recordado, y ahí ya está el camino del Autosave.
    public func remember(controlNumbers numbers: ControlNumbers?) {
        project = project.remembering(controlNumbers: numbers)
        autosave.changedHeader(project)
    }

    /// Escribe la copia viva en el hueco vigente del Bank.
    ///
    /// **Quien decide si hay que llamarla es el motor**, no esto: el gesto en
    /// curso —Temp, Ctrl All— superpone valores que vuelven solos al soltar, y
    /// escribirlos dejaría en disco un fill que nadie pidió conservar.
    public func record(_ pattern: Pattern) {
        project = project.replacing(
            bank.replacing(pattern, at: project.selectedPattern),
            at: project.selectedBank
        )
        autosave.changed(bank, at: project.selectedBank)
    }

    // MARK: - Guardado

    /// Si `Reload` se puede pulsar, y por qué no cuando no (FR17).
    public var reloadAvailability: ReloadAvailability {
        store.reloadAvailability(at: project.selectedBank)
    }

    /// Fija el punto de retorno del Bank vigente (FR16).
    public func saveBank() {
        try? store.saveRestorePoint(bank, at: project.selectedBank)
    }

    /// El punto de retorno del Bank vigente, si lo hay.
    public func restorePoint() -> Bank? {
        try? store.restorePoint(at: project.selectedBank)
    }

    /// Mete un Bank en el hueco vigente. Lo usa `Reload` (FR17).
    public func replaceSelectedBank(with saved: Bank) {
        project = project.replacing(saved, at: project.selectedBank)
        autosave.changed(saved, at: project.selectedBank)
    }

    /// Lo último que falló al escribir, si falló algo.
    public var saveFailure: Error? { store.lastSaveFailure }

    /// Escribe lo pendiente ahora. La llama el paso a segundo plano (FR14).
    public func flush() { try? autosave.flush() }

    /// Mira si toca escribir. Se llama una vez por segundo.
    public func tick() { try? autosave.tick() }

    // MARK: - El portapapeles

    /// Si `paste` se puede pulsar. Con el portapapeles vacío, no (FR4).
    public var canPaste: Bool { clipboard != nil }

    /// Qué hueco lleva la marca de origen en el Bank que se está mirando, o
    /// `nil` si no hay marca que dibujar aquí (FR12).
    public var copiedSlotIndex: Int? { clipboard?.markedSlot(inBank: project.selectedBank) }

    /// En qué hueco caería un pegado ahora mismo, o `nil` si no hay nada que
    /// pegar.
    ///
    /// **La pantalla lo necesita para el destello** (FR13): la celda que recibe
    /// el material tiene que decirlo, y con el transporte corriendo no es la
    /// seleccionada.
    public func pasteDestination(armed: Int?, isRunning: Bool) -> Int? {
        guard clipboard != nil else { return nil }
        return PatternClipboard.destination(
            selected: project.selectedPattern, armed: armed, isRunning: isRunning)
    }

    /// Carga el hueco vigente en el portapapeles (FR5, FR6).
    ///
    /// **Disponible siempre**, con el transporte parado y corriendo: copiar no
    /// destruye nada.
    ///
    /// **Toma el material guardado en el Bank, no la copia viva**, que lleva
    /// encima la superposición de un gesto en curso (FR6). Temp y Ctrl All
    /// superponen valores que vuelven solos al soltar; congelar en un hueco un
    /// fill que el usuario espera que se deshaga sería material que nadie pidió
    /// conservar.
    public func copyPattern() {
        guard let material = bank.pattern(at: project.selectedPattern) else { return }
        clipboard = PatternClipboard(
            pattern: material,
            bankIndex: project.selectedBank,
            slotIndex: project.selectedPattern
        )
    }

    /// Copia un Pattern en otro hueco del Bank vigente, con las dos puntas
    /// dichas, y **carga el portapapeles con el origen** (FR19).
    ///
    /// Es lo que produce el acorde de dos dedos: un solo portapapeles para los
    /// dos gestos, así que el backup hecho con dos dedos se puede llevar luego a
    /// otro Bank con `paste` sin repetir nada.
    public func copyPattern(from origin: Int, to destination: Int) {
        guard let material = bank.pattern(at: origin) else { return }
        project = project.copyingPattern(from: origin, to: destination)
        clipboard = PatternClipboard(
            pattern: material,
            bankIndex: project.selectedBank,
            slotIndex: origin
        )
        autosave.changed(bank, at: project.selectedBank)
    }

    /// Vacía un hueco (FR13).
    public func clearPattern(at index: Int) {
        project = project.clearingPattern(at: index)
        autosave.changed(bank, at: project.selectedBank)
    }

    /// Lo que un pegado deja por hacer fuera del árbol.
    ///
    /// **Se devuelve en vez de hacerse** porque toca la copia viva y el armado,
    /// que son del motor y no del disco. La regla de cuál de los dos toca vive
    /// en `PatternPasteRefresh`, en `Engine`, donde hay tests.
    public struct Paste: Equatable, Sendable {
        /// El material pegado.
        public let pattern: Pattern
        /// El hueco que lo recibió.
        public let index: Int
        /// Qué hay que refrescar fuera del árbol.
        public let refresh: PatternPasteRefresh
    }

    /// Escribe el portapapeles en su hueco de destino (FR7–FR11).
    ///
    /// **Escribe en el Bank vigente, venga el material del Bank que venga**
    /// (FR7): se pega donde se está mirando, y el Bank de origen no interviene.
    ///
    /// **No mueve la selección, no arma nada y no cancela una adopción
    /// pendiente** (FR10). Escribe material y nada más.
    ///
    /// **Se permite pegar encima del Pattern que suena** (FR9). El audio no se
    /// corta: el transporte tiene su propio snapshot publicado y no lo relee
    /// hasta la próxima adopción.
    ///
    /// Devuelve `nil` si no había nada que pegar.
    public func paste(armed: Int?, isRunning: Bool) -> Paste? {
        guard let clipboard else { return nil }

        let index = PatternClipboard.destination(
            selected: project.selectedPattern, armed: armed, isRunning: isRunning)
        project = project.replacing(clipboard.pattern, at: index)
        autosave.changed(bank, at: project.selectedBank)

        return Paste(
            pattern: clipboard.pattern,
            index: index,
            refresh: PatternPasteRefresh(
                destination: index, loaded: project.selectedPattern, armed: armed)
        )
    }
}
