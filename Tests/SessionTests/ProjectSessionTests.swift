import Engine
import Foundation
import MIDI
import Persistence
import XCTest

@testable import Session

/// Un disco en memoria.
///
/// **Es lo que hace medible este paquete.** Los casos que importan aquí —abrir
/// con el disco vacío, abrir con basura, escribir sin esperar el debounce— se
/// provocan en una línea contra esto, y contra un disco real dejarían ficheros
/// entre pasadas.
private final class MemoryFileSystem: FileSystem, @unchecked Sendable {

    private let lock = NSLock()
    private var files: [URL: Data] = [:]

    /// Los `read` que deben devolver basura ilegible, por su último componente.
    var corrupt: Set<String> = []

    func read(_ url: URL) throws -> Data? {
        lock.withLock {
            if corrupt.contains(url.lastPathComponent) {
                return Data("no es json".utf8)
            }
            return files[url]
        }
    }

    func write(_ data: Data, to url: URL) throws {
        lock.withLock { files[url] = data }
    }

    func move(_ source: URL, to destination: URL) throws {
        lock.withLock {
            files[destination] = files[source]
            files[source] = nil
        }
    }

    func createDirectory(_ url: URL) throws {}

    var writtenNames: [String] {
        lock.withLock { files.keys.map(\.lastPathComponent).sorted() }
    }
}

@MainActor
final class ProjectSessionTests: XCTestCase {

    private var fileSystem: MemoryFileSystem!
    private var directory: URL!

    override func setUp() {
        super.setUp()
        fileSystem = MemoryFileSystem()
        directory = URL(fileURLWithPath: "/torax-test")
    }

    private func makeStore() -> ProjectStore {
        ProjectStore(fileSystem: fileSystem, directory: directory, timestamp: { "T" })
    }

    /// `quietPeriod` 0 para que un `tick()` escriba sin esperar dos segundos.
    private func makeSession() -> ProjectSession {
        ProjectSession(store: makeStore(), quietPeriod: 0)
    }

    // MARK: - Abrir

    func testEmptyDiskOpensWithTheUsualMaterial() {
        let session = makeSession()

        XCTAssertEqual(session.project, Project.initial)
        XCTAssertEqual(session.restoredPattern, Pattern.initial)
        XCTAssertTrue(session.rescuedFiles.isEmpty)
        XCTAssertTrue(session.restoredPattern.hasMaterial, "abrir mudo sería el defecto que esto evita")
    }

    func testRestoredPatternComesFromTheSelectedBankAndSlot() throws {
        let material = Pattern.initial
        let bank = Bank().replacing(material, at: 3)
        let project = Project.initial.replacing(bank, at: 2).selectingBank(2).selectingPattern(3)
        try makeStore().save(project)

        let session = makeSession()

        XCTAssertEqual(session.selectedBankIndex, 2)
        XCTAssertEqual(session.selectedPatternIndex, 3)
        XCTAssertEqual(session.restoredPattern, material)
    }

    func testUnreadableFileIsRescuedAndTheAppStillOpens() throws {
        try makeStore().save(Project.initial)
        fileSystem.corrupt = ["project.json"]

        let session = makeSession()

        XCTAssertFalse(session.rescuedFiles.isEmpty, "lo ilegible se aparta y se dice")
        XCTAssertNotNil(session.restoredPattern, "la app abre igual")
    }

    // MARK: - Mover la mirada

    func testSelectingAPatternMovesTheSelectionAndMarksTheHeader() {
        let session = makeSession()

        session.selectPattern(5)

        XCTAssertEqual(session.selectedPatternIndex, 5)
        session.tick()
        XCTAssertTrue(fileSystem.writtenNames.contains("project.json"))
    }

    func testSelectingABankMovesTheSelection() {
        let session = makeSession()

        session.selectBank(7)

        XCTAssertEqual(session.selectedBankIndex, 7)
    }

    func testAdoptedKeepsTheIndicesItWasGivenNotTheCurrentOnes() {
        let session = makeSession()
        session.selectBank(9)

        // Lo que sonó fue el Bank 1 hueco 2, aunque la mirada ya se movió.
        session.adopted(bank: 1, pattern: 2)

        XCTAssertEqual(session.selectedBankIndex, 1)
        XCTAssertEqual(session.selectedPatternIndex, 2)
    }

    func testRememberingEndpointsKeepsBothNames() {
        let session = makeSession()

        session.remember(destination: "BeatStep Pro", source: "Keystep")

        XCTAssertEqual(session.project.destinationName, "BeatStep Pro")
        XCTAssertEqual(session.project.sourceName, "Keystep")
    }

    func testBankAtReturnsAnotherBankWithoutMovingTheSelection() {
        let session = makeSession()

        XCTAssertNotNil(session.bank(at: 4))
        XCTAssertEqual(session.selectedBankIndex, 0, "mirar otro Bank no es ir a él")
        XCTAssertNil(session.bank(at: Project.bankCount), "fuera de rango es nil, no un crash")
    }

    func testHeaderChangedMarksTheHeaderWithoutMovingAnything() {
        let session = makeSession()
        let before = session.project

        session.headerChanged()
        session.tick()

        XCTAssertEqual(session.project, before, "armar un hueco no mueve la selección")
        XCTAssertTrue(fileSystem.writtenNames.contains("project.json"))
    }

    func testTheControllerMappingIsRememberedWithTheSessionSettings() {
        let session = makeSession()
        let numbers = ControlMapping.beatStepPro.numbers

        session.remember(controlNumbers: numbers)

        XCTAssertEqual(session.project.controlNumbers, numbers)
        session.tick()
        XCTAssertTrue(fileSystem.writtenNames.contains("project.json"))
    }

    // MARK: - Guardado

    func testReloadIsUnavailableUntilABankIsSaved() {
        let session = makeSession()
        XCTAssertFalse(session.reloadAvailability.isAvailable)

        session.saveBank()

        XCTAssertTrue(session.reloadAvailability.isAvailable)
    }

    func testRestorePointReturnsWhatWasSaved() {
        let session = makeSession()
        session.saveBank()

        XCTAssertEqual(session.restorePoint(), session.bank)
    }

    func testReplacingTheSelectedBankPutsTheSavedMaterialBack() {
        let session = makeSession()
        let saved = Bank().replacing(Pattern.initial, at: 4)

        session.replaceSelectedBank(with: saved)

        XCTAssertEqual(session.bank, saved)
    }

    func testFlushWritesWithoutWaitingForTheQuietPeriod() {
        let session = ProjectSession(store: makeStore(), quietPeriod: 3600)
        session.selectPattern(1)

        session.tick()
        XCTAssertFalse(
            fileSystem.writtenNames.contains("project.json"),
            "con el debounce largo, el tick todavía no escribe")

        session.flush()

        XCTAssertTrue(fileSystem.writtenNames.contains("project.json"))
    }

    func testSaveFailureIsNilWhenNothingFailed() {
        let session = makeSession()
        session.saveBank()

        XCTAssertNil(session.saveFailure)
    }

    func testRecordWritesTheLiveCopyIntoTheSelectedSlot() {
        let session = makeSession()
        session.selectPattern(7)
        let empty = Engine.Pattern()

        session.record(empty)

        XCTAssertEqual(session.pattern(at: 7), empty)
        session.tick()
        XCTAssertFalse(fileSystem.writtenNames.isEmpty, "grabar deja el Bank sucio")
    }

    func testRecordWritesTheBankItJustUpdatedNotTheStaleOne() {
        let session = makeSession()
        let empty = Engine.Pattern()
        // La cabecera también tiene que estar en disco: sin `project.json` el
        // almacén lee «no hay nada» y se abre con `Project.initial`, que es el
        // comportamiento que `testEmptyDiskOpensWithTheUsualMaterial` fija.
        session.selectPattern(0)

        session.record(empty)
        session.flush()

        // Releer del disco: si el autosave hubiera recibido el Bank anterior,
        // lo escrito no tendría el hueco vacío.
        let reloaded = ProjectSession(store: makeStore(), quietPeriod: 0)
        XCTAssertEqual(reloaded.pattern(at: session.selectedPatternIndex), empty)
    }

    // MARK: - El portapapeles

    func testNothingCanBePastedBeforeCopying() {
        let session = makeSession()

        XCTAssertFalse(session.canPaste)
        XCTAssertNil(session.copiedSlotIndex)
        XCTAssertNil(session.pasteDestination(armed: nil, isRunning: false))
        XCTAssertNil(session.paste(armed: nil, isRunning: false))
    }

    func testCopyingLoadsTheClipboardAndMarksItsSlot() {
        let session = makeSession()
        session.selectPattern(2)

        session.copyPattern()

        XCTAssertTrue(session.canPaste)
        XCTAssertEqual(session.copiedSlotIndex, 2)
    }

    func testTheCopyMarkOnlyShowsInItsOwnBank() {
        let session = makeSession()
        session.copyPattern()
        XCTAssertNotNil(session.copiedSlotIndex)

        session.selectBank(5)

        XCTAssertNil(session.copiedSlotIndex, "la marca es del Bank de origen")
    }

    func testPastingStoppedWritesTheSelectedSlotAndRefreshesTheLiveCopy() {
        let session = makeSession()
        session.copyPattern()
        session.selectPattern(6)

        let paste = session.paste(armed: nil, isRunning: false)

        XCTAssertEqual(paste?.index, 6)
        XCTAssertEqual(session.pattern(at: 6), paste?.pattern)
        XCTAssertTrue(paste?.refresh.refreshesLiveCopy ?? false)
    }

    func testPastingWhileRunningLandsOnTheArmedSlot() {
        let session = makeSession()
        session.copyPattern()
        session.selectPattern(1)

        let paste = session.paste(armed: 9, isRunning: true)

        XCTAssertEqual(paste?.index, 9)
        XCTAssertEqual(session.pattern(at: 9), paste?.pattern)
    }

    func testPasteDestinationAgreesWithWherePasteLands() {
        let session = makeSession()
        session.copyPattern()
        session.selectPattern(3)

        let predicted = session.pasteDestination(armed: 11, isRunning: true)
        let landed = session.paste(armed: 11, isRunning: true)?.index

        XCTAssertEqual(predicted, landed, "el destello y el pegado no pueden discrepar")
    }

    func testPastingDoesNotMoveTheSelection() {
        let session = makeSession()
        session.copyPattern()
        session.selectPattern(4)

        _ = session.paste(armed: 12, isRunning: true)

        XCTAssertEqual(session.selectedPatternIndex, 4, "FR10: pegar no mueve la selección")
    }

    func testCopyingBetweenSlotsAlsoLoadsTheClipboardWithTheOrigin() {
        let session = makeSession()

        session.copyPattern(from: 0, to: 8)

        XCTAssertEqual(session.pattern(at: 8), session.pattern(at: 0))
        XCTAssertEqual(session.copiedSlotIndex, 0, "FR19: el acorde deja el origen copiado")
    }

    func testClearingEmptiesTheSlot() {
        let session = makeSession()
        XCTAssertTrue(session.pattern(at: 0)?.hasMaterial ?? false)

        session.clearPattern(at: 0)

        XCTAssertFalse(session.pattern(at: 0)?.hasMaterial ?? true)
    }

    func testSlotStatesMarkThePlayingAndQueuedSlots() {
        let session = makeSession()
        session.selectPattern(0)

        let states = session.slotStates(queued: 5, isRunning: true)

        XCTAssertEqual(states.count, Bank.patternCount)
        XCTAssertNotEqual(states[0], states[5], "el que suena y el que espera no se dibujan igual")
    }
}
