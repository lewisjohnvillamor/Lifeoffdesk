import XCTest
@testable import LifeOffDeskCore

/// Fixture numbers below are placeholders, not real hotlines.
final class HotlinesTests: XCTestCase {
    private func line(_ id: String, _ group: Hotline.Group, _ aliases: [String]) -> Hotline {
        Hotline(id: id, group: group, name: id.uppercased(), numbers: ["000"], aliases: aliases, sourceName: "fixture",
                sourceURL: "https://example.org", retrieved: "fixture", confidence: "official")
    }
    private var directory: HotlineDirectory {
        HotlineDirectory(entries: [line("911", .national, ["911"]), line("redcross", .national, ["red cross"]),
                                   line("nlex", .expressway, ["nlex"]), line("hpg", .national, ["highway patrol", "hpg"]),
                                   line("makati", .lgu, ["makati"])],
                         regionLGU: ["makati-cbd-starter": "makati"])
    }

    func testHotlineQuestionsAreRecognised() {
        XCTAssertTrue(directory.isAsking("Ano ang number ng highway patrol"))
        XCTAssertTrue(directory.isAsking("hotline ng NLEX?"))
        XCTAssertTrue(directory.isAsking("sino tatawagan sa Makati"))
        XCTAssertFalse(directory.isAsking("na-flat ang gulong ko"))
    }

    func testNamedEntriesWinElseNationalPlusYourCity() {
        XCTAssertEqual(directory.answer(for: "number ng highway patrol", regionID: nil).map(\.id), ["hpg"])
        XCTAssertEqual(directory.answer(for: "NLEX hotline", regionID: nil).map(\.id), ["nlex"])
        XCTAssertEqual(directory.answer(for: "emergency number", regionID: "makati-cbd-starter").map(\.id),
                       ["911", "makati", "redcross", "hpg"])
        XCTAssertEqual(directory.forEmergency(regionID: "makati-cbd-starter").first?.id, "makati")
        XCTAssertFalse(directory.forEmergency(regionID: nil).contains { $0.id == "911" }, "911 already has its own button")
    }

    func testDialableKeepsDigitsOnly() {
        XCTAssertEqual(Hotline.dialable("(02) 8870-1000"), "0288701000")
    }
}
