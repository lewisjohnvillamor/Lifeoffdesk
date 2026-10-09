import XCTest
@testable import LifeOffDeskCore

final class SafetyGuideTests: XCTestCase {
    func testKeywordNetRoutesTaglishAndFlagsEmergencies() {
        XCTAssertEqual(SafetyKeywords.topic(in: "Natapilok ako sa hagdan"), .sprain)
        XCTAssertEqual(SafetyKeywords.topic(in: "may nahimatay, hindi humihinga"), .cpr)
        XCTAssertEqual(SafetyKeywords.topic(in: "nakagat ako ng aso"), .animalBite)
        XCTAssertEqual(SafetyKeywords.topic(in: "nakagat ng ahas sa paa"), .snakeBite)
        XCTAssertEqual(SafetyKeywords.topic(in: "napaso ang kamay ko"), .burn)
        XCTAssertEqual(SafetyKeywords.topic(in: "pwede bang kainin itong kabute?"), .wildPlants)
        XCTAssertNil(SafetyKeywords.topic(in: "what is the capital of France"))
        XCTAssertTrue(SafetyKeywords.emergency(in: "Walang malay ang kasama ko"))
        XCTAssertFalse(SafetyKeywords.emergency(in: "natapilok ako"))
    }

    func testModelRoutesButCannotLowerAnEmergencyOrInventACard() async {
        let engine = ScriptedEngine(replies: [#"{"topic":"recipe","emergency":false}"#, #"{"topic":"fainting","emergency":false}"#])
        let (outcome, attempts) = await SafetyPrompt.classify("hindi humihinga ang lola ko", engine: engine)
        guard case let .valid(answer) = outcome else { return XCTFail("expected repaired answer") }
        XCTAssertEqual(attempts.count, 2, "an unknown card name is rejected")
        let final = SafetyPrompt.combine(model: answer, question: "hindi humihinga ang lola ko")
        XCTAssertTrue(final.emergency, "keyword net raises the emergency flag the model missed")
        XCTAssertEqual(final.topic, .fainting)
        XCTAssertEqual(SafetyPrompt.combine(model: nil, question: "nabulunan ang anak ko").topic, .choking)
    }

    func testBundledGuideHasACardWithASourceForEveryTopic() throws {
        let url = Fixture.repoRoot.appendingPathComponent("LifeOffDesk/Resources/StarterData/safety-guide.json")
        let guide = try SafetyGuide.decode(Data(contentsOf: url))
        for topic in SafetyTopic.allCases {
            let card = try XCTUnwrap(guide.card(topic), "missing card \(topic)")
            XCTAssertFalse(card.steps.isEmpty)
            XCTAssertTrue(card.sourceURL.hasPrefix("https://"), "\(topic) needs a source link")
        }
    }
}
