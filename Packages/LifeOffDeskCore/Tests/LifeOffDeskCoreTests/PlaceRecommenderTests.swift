import XCTest
@testable import LifeOffDeskCore

/// Synthetic places around the fixture origin; not real venues.
final class PlaceRecommenderTests: XCTestCase {
    private let now = Fixture.t0
    private var origin: Coordinate { Fixture.projection.unproject(MeterPoint(x: 0, y: 0)) }

    private func place(_ id: String, _ category: PlaceCategory, east: Double, cuisine: String? = nil) -> Place {
        var p = Fixture.place(id, category, east: east, north: 0)
        p.sourceCuisine = cuisine
        return p
    }

    /// Passed before: three cafés (two "coffee") and one park.
    private var taste: PlaceRecommender.Taste {
        .init(places: [place("c1", .cafe, east: 5000, cuisine: "coffee"), place("c2", .cafe, east: 5100, cuisine: "coffee"),
                       place("c3", .cafe, east: 5200), place("p1", .park, east: 5300)])
    }

    private var catalog: PlaceCatalog {
        Fixture.catalog([place("newCafe", .cafe, east: 400, cuisine: "coffee"), place("newPark", .park, east: 300),
                         place("museum", .museum, east: 100), place("c1", .cafe, east: 5000, cuisine: "coffee"),
                         place("farCafe", .cafe, east: 9000)])
    }

    func testRecommendsUnvisitedPlacesMatchingTasteWithComputedReasons() {
        let result = PlaceRecommender.candidates(catalog: catalog, origin: origin, graph: nil, taste: taste,
                                                 discoveredIDs: ["c1", "c2", "c3", "p1"], history: .init(), now: now)
        XCTAssertEqual(result.map(\.id), ["newCafe", "newPark"], "taste first; untasted museum, visited and far places excluded")
        XCTAssertEqual(result[0].reasons[.likesCategory], "3 sa 4")
        XCTAssertEqual(result[0].reasons[.likesCuisine], "coffee")
        XCTAssertEqual(result[0].reasons[.nearby], "400 m")
    }

    func testNoRepeatsDismissedNeverAndCategoriesRotate() {
        var history = PlaceRecommender.History()
        history.record(place("newCafe", .cafe, east: 400), .shown, at: now)
        let afterShown = PlaceRecommender.candidates(catalog: catalog, origin: origin, graph: nil, taste: taste,
                                                     discoveredIDs: [], history: history, now: now.addingTimeInterval(3600))
        XCTAssertFalse(afterShown.map(\.id).contains("newCafe"), "shown in the last two weeks")
        let later = PlaceRecommender.candidates(catalog: catalog, origin: origin, graph: nil, taste: taste,
                                                discoveredIDs: [], history: history, now: now.addingTimeInterval(15 * 86_400))
        XCTAssertTrue(later.map(\.id).contains("newCafe"), "may come back after the cooldown")

        var dismissed = PlaceRecommender.History()
        dismissed.record(place("newCafe", .cafe, east: 400), .dismissed, at: now)
        let never = PlaceRecommender.candidates(catalog: catalog, origin: origin, graph: nil, taste: taste,
                                                discoveredIDs: [], history: dismissed, now: now.addingTimeInterval(60 * 86_400))
        XCTAssertFalse(never.map(\.id).contains("newCafe"))

        // Three café suggestions in a row push the park ahead of another café.
        let cafes = Fixture.catalog([place("cafeX", .cafe, east: 300), place("parkY", .park, east: 350)])
        var streak = PlaceRecommender.History()
        for i in 0..<3 { streak.record(place("old\(i)", .cafe, east: 0), .shown, at: now) }
        let rotated = PlaceRecommender.candidates(catalog: cafes, origin: origin, graph: nil, taste: taste,
                                                  discoveredIDs: [], history: streak, now: now)
        XCTAssertEqual(rotated.first?.id, "parkY")
    }

    func testAIPicksOnlyListedCandidatesAndReasons() async {
        let candidates = PlaceRecommender.candidates(catalog: catalog, origin: origin, graph: nil, taste: taste,
                                                     discoveredIDs: ["c1"], history: .init(), now: now)
        let engine = ScriptedEngine(replies: [#"{"pick":"C","reasons":["nearby"]}"#,
                                              #"{"pick":"A","reasons":["likesCuisine","nearby"]}"#])
        let (outcome, attempts) = await RecommendationPrompt.choose(candidates, engine: engine)
        guard case let .valid(choice) = outcome else { return XCTFail("expected a repaired valid pick") }
        XCTAssertEqual(attempts.count, 2, "pick C does not exist with two candidates")
        let text = RecommendationCopy.render(candidates[choice.index], reasons: choice.reasons)
        XCTAssertEqual(text, "Subukan mo ang Synthetic newCafe! Madalas kang dumaan sa mga coffee place. 400 m lang ang layo. Hindi mo pa ito napupuntahan.")
        XCTAssertTrue(engine.counter.prompts[0].contains("A: Synthetic newCafe (cafe)"))
    }

    func testNoHistoryStillRecommendsNearbyNewPlaces() {
        let fresh = PlaceRecommender.candidates(catalog: catalog, origin: origin, graph: nil, taste: .init(places: []),
                                                discoveredIDs: [], history: .init(), now: now)
        XCTAssertEqual(fresh.first?.id, "museum", "closest new place when there is no taste yet")
        XCTAssertNil(fresh.first?.reasons[.likesCategory])
        XCTAssertNotNil(RecommendationCopy.computed(fresh))
    }
}

final class RecommendationJudgeTests: XCTestCase {
    private func candidate() -> PlaceRecommender.Candidate {
        let place = Fixture.place("cafe", .cafe, east: 400, north: 0)
        return PlaceRecommender.Candidate(place: place, street: nil, straightLineMeters: 400, score: 1,
                                          reasons: [.likesCategory: "3 sa 4", .nearby: "400 m", .neverBeen: "oo"])
    }

    func testVerdictAndReasonMustAgreeAndPromptCarriesComputedTaste() async {
        let taste = PlaceRecommender.Taste(places: [Fixture.place("a", .cafe, east: 0, north: 0),
                                                    Fixture.place("b", .cafe, east: 1, north: 0),
                                                    Fixture.place("c", .park, east: 2, north: 0)])
        let engine = ScriptedEngine(replies: [#"{"verdict":"good","reason":"tooFar"}"#,
                                              #"{"verdict":"good","reason":"tasteMatch"}"#])
        let (outcome, attempts) = await JudgePrompt.check(candidate(), taste: taste, recent: [.park], engine: engine)
        guard case let .valid(verdict) = outcome else { return XCTFail("expected repaired verdict") }
        XCTAssertEqual(attempts.count, 2, "good + tooFar contradicts itself and is repaired")
        XCTAssertEqual(verdict, JudgeVerdict(verdict: .good, reason: .tasteMatch))
        XCTAssertTrue(engine.counter.prompts[0].contains("Taste: cafe 2 of 3, park 1 of 3"))
        XCTAssertTrue(engine.counter.prompts[0].contains("Recent suggestions: park"))
        XCTAssertEqual(JudgePrompt.label(verdict), "AI check: swak sa hilig mo")
    }
}
