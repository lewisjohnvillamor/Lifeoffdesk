import XCTest
@testable import LifeOffDeskCore

final class ExplorationTests: XCTestCase {
    private func session(_ points: [[Double]]) -> WalkSession {
        var session = WalkSession(startedAt: Fixture.time(0))
        session.segments = points.map { segment in
            segment.enumerated().map { Fixture.sample(east: $0.element, north: 0, at: Double($0.offset)) }
        }
        return session
    }

    func testMergeIsIdempotentAndRevisitsAddNoArea() {
        let grid = ExplorationGrid(origin: Fixture.origin)
        let first = session([[0, 50, 100]])
        var exploration = Exploration(revealWidthMeters: 25)
        exploration.merge(first)
        exploration.merge(first)
        XCTAssertEqual(exploration.paths.count, 1)
        let area = grid.areaSquareMeters(grid.cells(for: exploration))

        let revisit = session([[100, 50, 0]])
        let recap = WalkRecap.compute(session: revisit, exploration: exploration, grid: grid, now: Fixture.time(10))
        XCTAssertEqual(recap.newlyRevealedSquareMeters, 0)
        XCTAssertEqual(recap.newDistanceMeters, 0, "Revisited streets are not new")
        let extended = session([[100, 200, 300]])
        let extendedRecap = WalkRecap.compute(session: extended, exploration: exploration, grid: grid, now: Fixture.time(10))
        XCTAssertEqual(extendedRecap.distanceMeters, 200, accuracy: 0.5)
        XCTAssertEqual(extendedRecap.newDistanceMeters, 187.5, accuracy: 5, "Only the part beyond the old corridor counts")
        exploration.merge(revisit)
        XCTAssertEqual(grid.areaSquareMeters(grid.cells(for: exploration)), area)
    }

    func testGapBetweenSegmentsIsNotRevealed() {
        let grid = ExplorationGrid(origin: Fixture.origin)
        var exploration = Exploration(revealWidthMeters: 25)
        exploration.merge(session([[0], [500]]))
        let cells = grid.cells(for: exploration)
        let midpoint = GridCell(x: Int((250 / grid.cellSize).rounded(.down)), y: 0)
        XCTAssertFalse(cells.contains(midpoint))
        // Two isolated discs of radius 12.5 m, not a 500 m corridor.
        XCTAssertLessThan(grid.areaSquareMeters(cells), 2 * .pi * 12.5 * 12.5 + 300)
    }

    func testCorridorIsNarrow() {
        let grid = ExplorationGrid(origin: Fixture.origin)
        var exploration = Exploration(revealWidthMeters: 25)
        exploration.merge(session([[0, 100]]))
        let cells = grid.cells(for: exploration)
        func cell(east: Double, north: Double) -> GridCell {
            GridCell(x: Int((east / grid.cellSize).rounded(.down)), y: Int((north / grid.cellSize).rounded(.down)))
        }
        XCTAssertTrue(cells.contains(cell(east: 50, north: 11)))
        XCTAssertFalse(cells.contains(cell(east: 50, north: 14)), "Nothing beyond half the corridor width")
        XCTAssertFalse(cells.contains(cell(east: 50, north: -14)))
    }
}

final class LocalStoreTests: XCTestCase {
    func testRoundTripAndFinishCommit() throws {
        let dir = Fixture.tempDirectory()
        let store = try LocalStore(directory: dir)
        var recorder = WalkRecorder.start(at: Fixture.time(0), destinationPlaceID: "osm:way:1", destinationName: "Park")
        let s = Fixture.sample(east: 0, north: 0, at: 1)
        recorder.ingest(s, receivedAt: s.timestamp)
        try store.saveActiveSession(recorder.session)
        XCTAssertEqual(store.loadActiveSession(), recorder.session)

        recorder.finish(at: Fixture.time(30))
        try store.commitFinished(recorder.session)
        XCTAssertNil(store.loadActiveSession())
        let reopened = try LocalStore(directory: dir)
        XCTAssertEqual(reopened.loadFinishedWalks(), [recorder.session])
    }

    func testCorruptFileFallsBackToPreviousCopy() throws {
        let dir = Fixture.tempDirectory()
        let store = try LocalStore(directory: dir)
        var exploration = Exploration()
        try store.saveExploration(exploration)
        exploration.paths.append(ExploredPath(sessionID: UUID(), points: [Fixture.origin]))
        try store.saveExploration(exploration)
        try Data("{not json".utf8).write(to: dir.appendingPathComponent("exploration.json"))

        let reopened = try LocalStore(directory: dir)
        XCTAssertEqual(reopened.loadExploration(), Exploration(), "Falls back to the previous good copy")
        XCTAssertEqual(reopened.issues.count, 2)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("exploration.json.corrupt-") }, "Corrupt data is set aside, not deleted")
    }

    func testNewerSchemaIsNotLoadedOrOverwritten() throws {
        let dir = Fixture.tempDirectory()
        let store = try LocalStore(directory: dir)
        var future = Exploration()
        future.schemaVersion = 99
        try store.saveExploration(future)
        let reopened = try LocalStore(directory: dir)
        XCTAssertNil(reopened.loadExploration())
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("exploration.json").path))
    }

    func testEraseRemovesPersonalDataOnly() throws {
        let root = Fixture.tempDirectory()
        let personal = root.appendingPathComponent("Personal")
        let model = root.appendingPathComponent("model.gguf")
        try Data("model".utf8).write(to: model)
        let store = try LocalStore(directory: personal)
        var session = WalkSession(startedAt: Fixture.time(0))
        try store.saveActiveSession(session)
        session.state = .finished
        try store.commitFinished(session)
        try store.saveExploration(Exploration())
        try store.saveMemoryPhoto(Data("jpeg".utf8), for: session.id)
        XCTAssertEqual(store.loadMemoryPhoto(for: session.id), Data("jpeg".utf8))
        try store.erasePersonalData()
        XCTAssertNil(store.loadMemoryPhoto(for: session.id), "Erase removes memory photos")
        XCTAssertNil(store.loadActiveSession())
        XCTAssertNil(store.loadExploration())
        XCTAssertTrue(store.loadFinishedWalks().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.path), "Model/catalog assets survive erase")
    }
}
