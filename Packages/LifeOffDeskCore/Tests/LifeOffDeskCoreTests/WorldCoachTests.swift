import XCTest
@testable import LifeOffDeskCore

/// Synthetic adventures (metre offsets from the fixture origin); not real walks.
final class WorldCoachTests: XCTestCase {
    private let now = Fixture.t0.addingTimeInterval(40 * 86_400)
    private var home: Coordinate { Fixture.projection.unproject(MeterPoint(x: 0, y: 0)) }

    private func walk(daysAgo: Double, reach: Double) -> WalkSession {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        var session = WalkSession(startedAt: start)
        session.endedAt = start.addingTimeInterval(1800)
        session.segments = [[0.0, reach].enumerated().map { i, north in
            let c = Fixture.projection.unproject(MeterPoint(x: 0, y: north))
            return TrackSample(latitude: c.latitude, longitude: c.longitude,
                               timestamp: start.addingTimeInterval(Double(i) * 900), horizontalAccuracy: 5)
        }]
        return session
    }

    private func facts(_ walks: [WalkSession], newMeters: [UUID: Double] = [:]) -> WorldFacts {
        WorldFacts.compute(walks: walks, newMeters: newMeters, home: home, now: now,
                           frontier: "new streets pa-hilaga (450 m)", newPlace: "Salcedo Park")
    }

    func testShrinkingReachIsDetected() {
        let f = facts([walk(daysAgo: 20, reach: 2400), walk(daysAgo: 2, reach: 600)])
        XCTAssertEqual(f.signal, .shrinking)
        XCTAssertEqual(f.value(.reachNow), "600 m")
        XCTAssertEqual(f.value(.reachBefore), "2.40 km")
    }

    func testQuietGrowingSteadyAndStart() {
        XCTAssertEqual(facts([walk(daysAgo: 6, reach: 900)]).signal, .quiet)
        XCTAssertEqual(facts([walk(daysAgo: 20, reach: 500), walk(daysAgo: 1, reach: 2000)]).signal, .growing)
        XCTAssertEqual(facts([walk(daysAgo: 20, reach: 1000), walk(daysAgo: 1, reach: 1100)]).signal, .steady)
        XCTAssertEqual(facts([]).signal, .start)
        // Same reach, but far fewer new streets than before: still a shrinking world.
        let before = walk(daysAgo: 20, reach: 1000), recent = walk(daysAgo: 1, reach: 1000)
        let fewerNew = facts([before, recent], newMeters: [before.id: 1500, recent.id: 100])
        XCTAssertEqual(fewerNew.signal, .shrinking)
        XCTAssertEqual(fewerNew.value(.newStreetsBefore), "1.50 km")
    }

    func testAIChoiceRendersComputedValuesOnly() async {
        let f = facts([walk(daysAgo: 20, reach: 2400), walk(daysAgo: 2, reach: 600)])
        let engine = ScriptedEngine(replies: [#"{"facts":["reachNow","reachBefore"],"tone":"playful","quest":"frontier"}"#])
        let (outcome, _) = await CoachPrompt.choose(facts: f, engine: engine)
        guard case let .valid(choice) = outcome else { return XCTFail("expected valid") }
        let text = CoachRenderer.render(choice, facts: f)
        XCTAssertEqual(text, "Uy, lumiliit ang mundo mo! 600 m lang ang pinakamalayo mo nitong 2 linggo, at 2.40 km ang pinakamalayo mo noong nakaraang 2 linggo. Game? May new streets pa-hilaga (450 m).")
        XCTAssertTrue(engine.counter.prompts[0].contains("Trend: shrinking"))
    }

    func testInventedFactsOrQuestsAreRejectedThenRepaired() async {
        let f = WorldFacts.compute(walks: [walk(daysAgo: 6, reach: 900)], newMeters: [:], home: home, now: now,
                                   frontier: nil, newPlace: "Salcedo Park")
        let engine = ScriptedEngine(replies: [#"{"facts":["calories"],"tone":"gentle","quest":"frontier"}"#,
                                              #"{"facts":["daysSinceLast"],"tone":"gentle","quest":"newPlace"}"#])
        let (outcome, attempts) = await CoachPrompt.choose(facts: f, engine: engine)
        guard case let .valid(choice) = outcome else { return XCTFail("expected repaired") }
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(CoachRenderer.render(choice, facts: f),
                       "Matagal-tagal ka nang hindi lumalabas. 5 araw mula sa huling adventure mo. Tara? Hindi mo pa napupuntahan ang Salcedo Park.")
        XCTAssertFalse(CoachPrompt.grammar(for: f).contains("frontier"), "the grammar only offers available quests")
    }

    func testComputedFallbackNeedsNoAI() {
        let f = facts([walk(daysAgo: 20, reach: 2400), walk(daysAgo: 2, reach: 600)])
        XCTAssertEqual(CoachRenderer.computed(f)?.hasPrefix("Napansin ko, mas maliit ang mundo mo lately."), true)
        let none = WorldFacts.compute(walks: [], newMeters: [:], home: nil, now: now, frontier: nil, newPlace: nil)
        XCTAssertNil(CoachRenderer.computed(none), "no quest, no coach")
    }
}

/// Founder report: "Library, lakad lang" was read as a route-accessibility need and asked a step-free question.
final class AccessGroundingTests: XCTestCase {
    func testAccessNeedsCountOnlyWhenTheRequestMentionsAccess() {
        let misread = OutingPreferences(categories: [.library], accessNeeds: [.stepFreeEntrance], routeAccess: true)
        let plain = AccessWords.grounded(misread, in: "Library, lakad lang")
        XCTAssertFalse(plain.routeAccess)
        XCTAssertTrue(plain.accessNeeds.isEmpty)
        XCTAssertEqual(plain.categories, [.library])
        let asked = AccessWords.grounded(misread, in: "library na wheelchair accessible ang daan")
        XCTAssertTrue(asked.routeAccess)
        XCTAssertEqual(asked.accessNeeds, [.stepFreeEntrance])
    }

    func testAnswerDoesNotAskTheAccessQuestionForPlainWalking() {
        let place = Fixture.place("lib", .library, east: 100, north: 0)
        let misread = OutingPreferences(categories: [.library], routeAccess: true)
        let (response, _) = Planner.answer(.valid(misread), trace: PlannerTrace(), request: "Library, lakad lang",
                                           catalog: Fixture.catalog([place]),
                                           origin: .currentLocation(Fixture.projection.unproject(MeterPoint(x: 0, y: 0))))
        guard case let .suggestions(_, _, results) = response else { return XCTFail("expected suggestions, got \(response)") }
        XCTAssertEqual(results.map(\.place.id), ["lib"])
    }
}
