import XCTest
@testable import LifeOffDeskCore

final class SafetyGuideTests: XCTestCase {
    override func setUpWithError() throws {
        let url = Fixture.repoRoot.appendingPathComponent("LifeOffDesk/Resources/StarterData/safety-lexicon.json")
        SafetyKeywords.lexicon = try SafetyLexicon.decode(Data(contentsOf: url))
    }

    /// Held-out cases written separately from the lexicon (eval/safety-routing-heldout.json).
    /// Emergencies must never be missed; topic routing must stay above 90%.
    func testHeldOutRoutingAccuracyAndEmergencyRecall() throws {
        struct Case: Decodable { var q: String; var topic: String?; var emergency: Bool }
        struct File: Decodable { var cases: [Case] }
        let url = Fixture.repoRoot.appendingPathComponent("eval/safety-routing-heldout.json")
        let cases = try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).cases
        var topicHits = 0, missedEmergencies: [String] = [], falseAlarms: [String] = [], wrong: [String] = []
        for c in cases {
            let answer = SafetyPrompt.combine(model: nil, question: c.q)
            if answer.topic?.rawValue == c.topic { topicHits += 1 } else { wrong.append("\(c.q) -> \(answer.topic?.rawValue ?? "nil") (want \(c.topic ?? "nil"))") }
            if c.emergency && !answer.emergency { missedEmergencies.append(c.q) }
            if !c.emergency && answer.emergency { falseAlarms.append(c.q) }
        }
        let accuracy = Double(topicHits) / Double(cases.count)
        print("SAFETY-ROUTING keywords-only: topic \(topicHits)/\(cases.count), missed emergencies \(missedEmergencies.count), false alarms \(falseAlarms.count)")
        wrong.forEach { print("  wrong: \($0)") }
        falseAlarms.forEach { print("  false alarm: \($0)") }
        XCTAssertEqual(missedEmergencies, [], "every emergency must show Call 911")
        XCTAssertGreaterThanOrEqual(accuracy, 0.9)
    }

    /// Second held-out set: run once as written. Reports the number; only emergencies are a hard gate.
    func testSecondHeldOutSetReport() throws {
        struct Case: Decodable { var q: String; var topic: String?; var emergency: Bool }
        struct File: Decodable { var cases: [Case] }
        let url = Fixture.repoRoot.appendingPathComponent("eval/safety-routing-heldout-v2.json")
        let cases = try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).cases
        var hits = 0, missed: [String] = [], alarms = 0
        for c in cases {
            let a = SafetyPrompt.combine(model: nil, question: c.q)
            if a.topic?.rawValue == c.topic { hits += 1 } else { print("  v2 wrong: \(c.q) -> \(a.topic?.rawValue ?? "nil") (want \(c.topic ?? "nil"))") }
            if c.emergency && !a.emergency { missed.append(c.q) }
            if !c.emergency && a.emergency { alarms += 1 }
        }
        print("SAFETY-ROUTING v2 keywords-only: topic \(hits)/\(cases.count), missed emergencies \(missed.count) \(missed), false alarms \(alarms)")
    }

    func testQuestionIsAnsweredFromTheCardsOwnSteps() throws {
        let url = Fixture.repoRoot.appendingPathComponent("LifeOffDesk/Resources/StarterData/safety-guide.json")
        let guide = try SafetyGuide.decode(Data(contentsOf: url))
        let lexicon = try XCTUnwrap(SafetyKeywords.lexicon)
        let question = "nag overheat ang makina, pwede ko bang buhusan ng tubig?"
        XCTAssertEqual(SafetyKeywords.topic(in: question), .overheating)
        let steps = lexicon.relevantSteps(in: try XCTUnwrap(guide.card(.overheating)), for: question)
        XCTAssertFalse(steps.isEmpty)
        XCTAssertTrue(steps.allSatisfy { $0.lowercased().contains("water") }, "\(steps)")
        XCTAssertTrue(lexicon.relevantSteps(in: try XCTUnwrap(guide.card(.flatTire)), for: "saan ilalagay ang jack?")
            .first?.contains("Jack") ?? false)
    }

    func testWholeWordMatchingAvoidsSubstringTraps() {
        XCTAssertNil(SafetyKeywords.topic(in: "paano po kayo"), "paano is not paa")
        XCTAssertNil(SafetyKeywords.topic(in: "I'm tired after the walk"), "tired is not tire")
        XCTAssertFalse(SafetyKeywords.emergency(in: "nakakuha ako ng anti rabies shot"))
        XCTAssertEqual(SafetyKeywords.topic(in: "na-plat yung gulong"), .flatTire)
        XCTAssertEqual(SafetyKeywords.topic(in: "flat battery ng kotse"), .carBattery, "longer phrase wins over 'flat'")
    }

    func testKeywordNetRoutesTaglishAndFlagsEmergencies() {
        XCTAssertEqual(SafetyKeywords.topic(in: "Natapilok ako sa hagdan"), .sprain)
        XCTAssertEqual(SafetyKeywords.topic(in: "may nahimatay, hindi humihinga"), .cpr)
        XCTAssertEqual(SafetyKeywords.topic(in: "nakagat ako ng aso"), .animalBite)
        XCTAssertEqual(SafetyKeywords.topic(in: "nakagat ng ahas sa paa"), .snakeBite)
        XCTAssertEqual(SafetyKeywords.topic(in: "napaso ang kamay ko"), .burn)
        XCTAssertEqual(SafetyKeywords.topic(in: "pwede bang kainin itong kabute?"), .wildPlants)
        XCTAssertNil(SafetyKeywords.topic(in: "what is the capital of France"))
        XCTAssertEqual(SafetyKeywords.topic(in: "nasira gulong ko"), .flatTire)
        XCTAssertEqual(SafetyKeywords.topic(in: "tumirik ang kotse sa EDSA"), .breakdown)
        XCTAssertEqual(SafetyKeywords.topic(in: "ayaw mag-start ng kotse"), .wontStart)
        XCTAssertEqual(SafetyKeywords.topic(in: "kailangan ng jump start, battery ng kotse"), .carBattery)
        XCTAssertEqual(SafetyKeywords.topic(in: "lowbat na phone ko"), .phoneBattery)
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
        XCTAssertEqual(final.topic, .cpr, "the user's words (not breathing) outrank the model's fainting")
        XCTAssertEqual(SafetyPrompt.combine(model: nil, question: "nabulunan ang anak ko").topic, .choking)
    }

    func testFounderPhoneCasesGetAnAnswer() {
        // Open fracture: emergency + broken-bone guidance.
        let bone = SafetyPrompt.combine(model: SafetyAnswer(topic: nil, emergency: false), question: "lumabas ang buto")
        XCTAssertTrue(bone.emergency)
        XCTAssertEqual(bone.topic, .sprain)
        // Follow-up continues the previous question.
        XCTAssertEqual(SafetyKeywords.topic(in: "numbing"), .sprain, "numbness is on the injury card")
        XCTAssertEqual(SafetyPrompt.followUp("paano na?", previous: "lumabas ang buto"), "lumabas ang buto paano na?")
        XCTAssertNil(SafetyPrompt.followUp("nasira gulong ko", previous: "lumabas ang buto"), "a new topic is not a follow-up")
        // Foot photo with "okay pa ba paa ko": generic labels dropped, routed to the injury card.
        XCTAssertEqual(PhotoHints.useful(["structure", "wood processed", "foot"]), ["foot"])
        XCTAssertEqual(SafetyPrompt.combine(model: nil, question: "okay pa ba paa ko", photoLabels: ["structure"]).topic, .sprain)
        // A swollen ankle is not an allergy.
        XCTAssertEqual(SafetyKeywords.topic(in: "namamaga ang paa ko"), .sprain)
        // No match: suggestions instead of a dead end.
        XCTAssertEqual(SafetyKeywords.suggestions(for: "may problema sa kotse").first, .breakdown)
    }

    func testPhotoLabelsAddContextButNeverDiagnose() async {
        XCTAssertEqual(PhotoHints.topic(for: ["Tire", "Car"]), .flatTire)
        XCTAssertEqual(PhotoHints.describe(["tire", "asphalt"]), "gulong (tire), asphalt")
        XCTAssertEqual(SafetyPrompt.combine(model: nil, question: "help", photoLabels: ["mushroom"]).topic, .wildPlants)
        let engine = ScriptedEngine(replies: [#"{"topic":"flatTire","emergency":false}"#])
        _ = await SafetyPrompt.classify("nasira ito", photoLabels: ["tire", "wheel"], engine: engine)
        XCTAssertTrue(engine.counter.prompts[0].contains("Photo shows: tire, wheel"))
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
