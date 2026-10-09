import XCTest
@testable import LifeOffDeskCore

/// P0-13 grounded narration. Facts and IDs are synthetic.
final class RecapNarrationTests: XCTestCase {
    private func facts(newStreets: Double = 550, places: [Place] = [Fixture.place("p1", .park, east: 0, north: 0)],
                       photos: Int = 2) -> RecapFacts {
        let recap = WalkRecap(sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, distanceMeters: 2400,
                              activeDuration: 42 * 60, acceptedSamples: 300, segmentCount: 1,
                              newlyRevealedSquareMeters: 0, newDistanceMeters: newStreets,
                              destinationName: nil, wasRecovered: false)
        return RecapFacts.compute(recap: recap, placesPassed: places, photoCount: photos)
    }

    func testFactsOmitUnavailableValues() {
        let f = facts(newStreets: 0, places: [], photos: 0)
        XCTAssertEqual(f.available, [.activeTime, .distance])
        XCTAssertNil(f.value(.newStreets))
    }

    func testRendererUsesOnlyComputedValues() throws {
        let f = facts()
        guard case let .success(choice) = RecapNarrationValidator.validate(#"{"facts":["newStreets","placesPassed"],"tone":"proud"}"#, facts: f)
        else { return XCTFail() }
        let text = try XCTUnwrap(RecapNarrator.render(choice, facts: f))
        XCTAssertEqual(text, "Ang galing mo today! 550 m ng bagong kalye at dumaan ka malapit sa Synthetic p1.")
    }

    func testValidatorRejectsUnsuppliedFactsExtraKeysAndProse() {
        let f = facts(newStreets: 0, places: [], photos: 0)
        let cases = [
            #"{"facts":["newStreets"],"tone":"proud"}"#,                     // not supplied
            #"{"facts":["activeTime"],"tone":"proud","text":"You visited"}"#, // free prose key
            #"{"facts":[],"tone":"chill"}"#,
            #"{"facts":["activeTime","activeTime"],"tone":"chill"}"#,
            #"{"facts":["activeTime","distance","activeTime","distance"],"tone":"chill"}"#,
            #"{"facts":["activeTime"],"tone":"angry"}"#,
            #"{"facts":["calories"],"tone":"chill"}"#,
        ]
        for c in cases {
            guard case .failure = RecapNarrationValidator.validate(c, facts: f) else { return XCTFail("accepted \(c)") }
        }
    }

    func testFactsHashChangesWhenSourceChangesAndKeysDifferByModel() {
        XCTAssertEqual(facts().hash, facts().hash)
        XCTAssertNotEqual(facts().hash, facts(newStreets: 600).hash)
        XCTAssertNotEqual(NarrationRecord.key(facts: facts(), modelID: "a"), NarrationRecord.key(facts: facts(), modelID: "b"))
    }

    func testGrammarListsOnlySuppliedFacts() {
        let g = RecapNarrationPrompt.grammar(for: facts(newStreets: 0, places: [], photos: 0))
        XCTAssertTrue(g.contains(#""\"activeTime\"""#), g)
        XCTAssertFalse(g.contains("newStreets"))
    }

    func testCacheIsRemovedWithTheAdventureAndOnErase() throws {
        let store = try LocalStore(directory: Fixture.tempDirectory())
        let f = facts()
        let record = NarrationRecord(sessionID: f.sessionID, key: NarrationRecord.key(facts: f, modelID: "m"),
                                     choice: RecapNarrationChoice(factIDs: [.newStreets], tone: .chill), createdAt: Fixture.t0)
        try store.saveNarration(record)
        XCTAssertEqual(store.loadNarrations(), [record])
        try store.deleteFinished(f.sessionID)
        XCTAssertTrue(store.loadNarrations().isEmpty)
        try store.saveNarration(record)
        try store.erasePersonalData()
        XCTAssertTrue(store.loadNarrations().isEmpty)
    }

    func testChooseRunsOneRepair() async {
        let f = facts()
        let engine = ScriptedEngine(replies: [#"{"facts":["calories"],"tone":"chill"}"#, #"{"facts":["photos"],"tone":"chill"}"#])
        let (outcome, attempts) = await RecapNarrationPrompt.choose(facts: f, engine: engine)
        guard case let .valid(choice) = outcome else { return XCTFail() }
        XCTAssertEqual(choice.factIDs, [.photos])
        XCTAssertEqual(attempts.count, 2)
    }
}

/// P0-14 editable preferences.
final class PreferenceProfileTests: XCTestCase {
    func testSaveLoadResetAndErase() throws {
        let store = try LocalStore(directory: Fixture.tempDirectory())
        XCTAssertEqual(store.loadPreferences(), .none)
        let profile = PreferenceProfile(categories: [.park, .cafe], durationMinutes: 45, novelty: .new, accessNeeds: [.stepFreeEntrance])
        try store.savePreferences(profile)
        guard case let .loaded(loaded) = store.loadPreferences() else { return XCTFail() }
        XCTAssertEqual(loaded.categories, [.park, .cafe])
        XCTAssertEqual(loaded.accessNeeds, [.stepFreeEntrance])
        try store.resetPreferences()
        XCTAssertEqual(store.loadPreferences(), .none)
        try store.savePreferences(profile)
        try store.erasePersonalData()
        XCTAssertEqual(store.loadPreferences(), .none)
    }

    func testNewerSchemaIsPreservedAndNotOverwritten() throws {
        let directory = Fixture.tempDirectory()
        let store = try LocalStore(directory: directory)
        let future = #"{"schemaVersion":9,"somethingNew":{"x":1}}"#
        let url = directory.appendingPathComponent("preferences.json")
        try future.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(store.loadPreferences(), .newerSchema(9))
        XCTAssertThrowsError(try store.savePreferences(PreferenceProfile(durationMinutes: 30)))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), future)
    }

    func testCorruptFileFallsBackToBackup() throws {
        let directory = Fixture.tempDirectory()
        let store = try LocalStore(directory: directory)
        try store.savePreferences(PreferenceProfile(durationMinutes: 30))
        try store.savePreferences(PreferenceProfile(durationMinutes: 60))
        try "{broken".write(to: directory.appendingPathComponent("preferences.json"), atomically: true, encoding: .utf8)
        guard case let .loaded(p) = store.loadPreferences() else { return XCTFail() }
        XCTAssertEqual(p.durationMinutes, 30)
    }

    func testPrecedenceRequestBeatsSavedAndHardNeedsStay() {
        let saved = PreferenceProfile(categories: [.museum], durationMinutes: 45, radiusMeters: 1500, novelty: .new,
                                      accessNeeds: [.wheelchair])
        let request = OutingPreferences(durationMinutes: 20, categories: [.cafe])
        let r = PreferenceResolver.resolve(request: request, saved: saved, radiusMeters: nil)
        XCTAssertEqual(r.prefs.durationMinutes, 20)            // explicit request wins
        XCTAssertEqual(r.prefs.categories, [.cafe])           // request named a kind of place
        XCTAssertEqual(r.prefs.novelty, .new)                 // filled from saved
        XCTAssertEqual(r.prefs.accessNeeds, [.wheelchair])    // hard need stays
        XCTAssertEqual(r.radiusMeters, 1500)
        XCTAssertEqual(r.fromSaved, ["novelty", "radius", "access"])
        let explicitRadius = PreferenceResolver.resolve(request: request, saved: saved, radiusMeters: 800)
        XCTAssertEqual(explicitRadius.radiusMeters, 800)
        XCTAssertEqual(PreferenceResolver.resolve(request: request, saved: nil, radiusMeters: nil).fromSaved, [])
    }

    func testProfileFromPlannerResultIsNormalized() {
        let prefs = OutingPreferences(durationMinutes: 500, categories: [.park], novelty: .familiar)
        let p = PreferenceProfile.from(prefs, radiusMeters: 99_000)
        XCTAssertNil(p.durationMinutes)
        XCTAssertEqual(p.radiusMeters, SearchOptions.maxRadiusMeters)
        XCTAssertEqual(p.novelty, .familiar)
    }

    func testOlderPlannerJSONDecodesWithNeutralDefaults() throws {
        let old = #"{"durationMinutes":30,"budgetPHP":null,"categories":["park"],"moodTags":[],"keywords":[],"travelMode":"walk","needsClarification":false}"#
        let prefs = try JSONDecoder().decode(OutingPreferences.self, from: Data(old.utf8))
        XCTAssertEqual(prefs.novelty, .any)
        XCTAssertEqual(prefs.accessNeeds, [])
    }
}

/// P0-16 evidence fixtures (synthetic subjects only; nothing here verifies a real entrance).
final class EligibilityPolicyTests: XCTestCase {
    let now = Fixture.t0
    let venue = Fixture.place("venue", .museum, east: 0, north: 0)

    private func fact(_ id: String, value: EvidenceFactV1.AccessValue = .yes, review: EvidenceFactV1.ReviewStatus = .reviewed,
                      kind: EvidenceFactV1.Kind = .stepFreeEntrance, subject: EvidenceFactV1.SubjectKind = .entrance,
                      subjectID: String = "venue-entrance-1", placeID: String? = "venue", observedDaysAgo: Double = 10,
                      validForDays: Double? = 180, conditions: [String] = [], supersedes: String? = nil) -> EvidenceFactV1 {
        EvidenceFactV1(id: id, schemaVersion: 1, subjectID: subjectID, subjectKind: subject, placeID: placeID, kind: kind,
                       value: value, sourceType: .fieldObservation, sourceURL: "fixture", sourceRecordID: id,
                       license: "fixture", retrievedAt: now.addingTimeInterval(-86400 * observedDaysAgo),
                       observedAt: now.addingTimeInterval(-86400 * observedDaysAgo), reviewStatus: review,
                       reviewedAt: now.addingTimeInterval(-86400 * observedDaysAgo),
                       reviewerID: "reviewer-a", validUntil: validForDays.map { now.addingTimeInterval(86400 * ($0 - observedDaysAgo)) },
                       conditions: conditions, supersedesID: supersedes)
    }

    private func check(_ facts: [EvidenceFactV1]) -> Eligibility {
        EligibilityPolicy.evaluate(.stepFreeEntrance, place: venue, facts: facts, now: now)
    }

    func testOnlyReviewedScopedCurrentUnconditionalYesPasses() {
        XCTAssertTrue(check([fact("ok")]).isEligible)
    }

    func testEverythingElseFailsHardEligibility() {
        let failing: [String: [EvidenceFactV1]] = [
            "absent": [],
            "negative": [fact("n", value: .no)],
            "limited": [fact("l", value: .limited)],
            "source-only": [fact("s", review: .sourceOnly)],
            "conflicted": [fact("c", review: .conflicted)],
            "contradictory reviewed": [fact("a"), fact("b", value: .no, subjectID: "venue-entrance-2")],
            "expired": [fact("e", observedDaysAgo: 400, validForDays: 180)],
            "no validity": [fact("v", validForDays: nil)],
            "future observation": [fact("f", observedDaysAgo: -5)],
            "conditions": [fact("k", conditions: ["staff assistance"])],
            "wrong place": [fact("w", placeID: "other-venue")],
            "wrong kind": [fact("wk", kind: .wheelchair)],
            "street fact": [fact("st", subject: .street, subjectID: "venue", placeID: "venue")],
        ]
        for (name, facts) in failing {
            XCTAssertFalse(check(facts).isEligible, name)
        }
    }

    func testSupersededFactNoLongerCounts() {
        let old = fact("old", value: .no)
        let new = fact("new", supersedes: "old")
        XCTAssertTrue(check([old, new]).isEligible)
    }

    func testHardRequirementNeverRelaxedToFillCards() {
        let catalog = Fixture.catalog([venue, Fixture.place("other", .museum, east: 100, north: 0)])
        let prefs = OutingPreferences(categories: [.museum], accessNeeds: [.stepFreeEntrance])
        let none = PlaceSearch.suggest(prefs, catalog: catalog, origin: .currentLocation(Fixture.origin))
        XCTAssertTrue(none.isEmpty)
        let one = PlaceSearch.suggest(prefs, catalog: catalog, origin: .currentLocation(Fixture.origin),
                                      context: SearchContext(evidence: [fact("ok")], now: now))
        XCTAssertEqual(one.map(\.place.id), ["venue"])
        XCTAssertTrue(one[0].accessLabels[0].contains("Path to it: not verified"))
    }

    func testRouteAccessRequestIsExplainedNotAnswered() {
        let catalog = Fixture.catalog([venue])
        let response = Planner.respond(OutingPreferences(categories: [.museum], routeAccess: true), catalog: catalog,
                                       origin: .currentLocation(Fixture.origin), options: SearchOptions())
        guard case let .clarify(_, question) = response else { return XCTFail() }
        XCTAssertEqual(question, PlannerCopy.routeAccessUnsupported)
    }

    func testSidecarDecodesAndDropsUnknownSchemaFacts() throws {
        let json = """
        {"schemaVersion":1,"regionID":"fixture","note":"synthetic","facts":[
         {"id":"a","schemaVersion":1,"subjectID":"e1","subjectKind":"entrance","placeID":"venue","kind":"stepFreeEntrance","value":"yes","sourceType":"operator","sourceURL":"x","sourceRecordID":"x","license":"x","retrievedAt":"2026-10-01T00:00:00Z","reviewStatus":"reviewed","conditions":[]},
         {"id":"b","schemaVersion":7,"subjectID":"e1","subjectKind":"entrance","placeID":"venue","kind":"stepFreeEntrance","value":"yes","sourceType":"operator","sourceURL":"x","sourceRecordID":"x","license":"x","retrievedAt":"2026-10-01T00:00:00Z","reviewStatus":"reviewed","conditions":[]}
        ]}
        """
        let sidecar = try EvidenceSidecar.decode(Data(json.utf8))
        XCTAssertEqual(sidecar.facts.map(\.id), ["a"])
        // No validUntil: cannot establish current eligibility.
        XCTAssertFalse(EligibilityPolicy.evaluate(.stepFreeEntrance, place: venue, facts: sidecar.facts, now: now).isEligible)
    }
}

/// P0-15 adaptive ranking from computed exploration.
final class AdaptiveSuggestionTests: XCTestCase {
    func testNoveltyRanksUnpassedOrPassedPlacesFirst() {
        let near = Fixture.place("near-seen", .park, east: 100, north: 0)
        let far = Fixture.place("far-new", .park, east: 600, north: 0)
        let catalog = Fixture.catalog([near, far])
        let context = SearchContext(passedPlaceIDs: ["near-seen"])
        let origin = DistanceOrigin.currentLocation(Fixture.origin)
        let fresh = PlaceSearch.suggest(OutingPreferences(categories: [.park], novelty: .new), catalog: catalog,
                                        origin: origin, context: context)
        XCTAssertEqual(fresh.map(\.place.id), ["far-new", "near-seen"])
        XCTAssertTrue(PlannerCopy.reason(fresh[0]).contains("bago para sa'yo"))
        let familiar = PlaceSearch.suggest(OutingPreferences(categories: [.park], novelty: .familiar), catalog: catalog,
                                           origin: origin, context: context)
        XCTAssertEqual(familiar.map(\.place.id), ["near-seen", "far-new"])
        let any = PlaceSearch.suggest(OutingPreferences(categories: [.park]), catalog: catalog, origin: origin, context: context)
        XCTAssertEqual(any.map(\.place.id), ["near-seen", "far-new"])
        XCTAssertNil(any[0].passedBefore)
    }

    func testNoveltyAloneIsSearchable() {
        XCTAssertFalse(OutingPreferences(novelty: .new).isEmptyRequest)
    }

    func testSavedPreferencesFlowThroughThePlanner() async {
        let catalog = Fixture.catalog([Fixture.place("seen", .park, east: 100, north: 0), Fixture.place("new", .park, east: 500, north: 0)])
        let reply = #"{"durationMinutes":null,"budgetPHP":null,"categories":["park"],"moodTags":[],"keywords":[],"novelty":"any","accessNeeds":[],"routeAccess":false,"travelMode":"walk","needsClarification":false}"#
        let planner = Planner(engine: ScriptedEngine(replies: [reply]))
        let (response, _) = await planner.plan("park", catalog: catalog, origin: .currentLocation(Fixture.origin),
                                               context: SearchContext(passedPlaceIDs: ["seen"]),
                                               saved: PreferenceProfile(novelty: .new))
        guard case let .suggestions(prefs, _, results) = response else { return XCTFail() }
        XCTAssertEqual(prefs.novelty, .new)
        XCTAssertEqual(results.first?.place.id, "new")
    }
}
