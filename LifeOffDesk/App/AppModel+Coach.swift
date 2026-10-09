import Foundation
import LifeOffDeskCore

/// What the map shows: a Taglish nudge about your exploring trend and one real next step.
struct CoachCard: Equatable {
    enum Status: Equatable {
        case working
        /// The on-device model chose the facts, tone and quest; the text is rendered from computed values.
        case ai
        /// Computed fallback, with why the AI did not answer.
        case computed(reason: String)
    }

    var text: String
    var status: Status
    var signal: WorldFacts.Signal
    var idea: AdventureIdea
    var sample: Bool
}

extension AppModel {
    private static let dismissedDayKey = "coach.dismissedDay"

    private static func today() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// Computes the exploring trend and asks the on-device model what to say, at most once per
    /// distinct set of facts per day. Dismissing hides it until tomorrow.
    func refreshCoach() {
        guard activeSession == nil, UserDefaults.standard.string(forKey: Self.dismissedDayKey) != Self.today() else {
            return
        }
        let frontier = adventureIdeas.first { if case .frontier = $0.kind { return true }; return false }
        let place = adventureIdeas.first { if case .undiscoveredPlace = $0.kind { return true }; return false }
        var frontierLabel: String?
        if let frontier, case let .frontier(meters, bearing) = frontier.kind {
            frontierLabel = "\(Format.distance(meters)) ng bagong kalye pa-\(AdventureSuggester.compassWord(bearing))"
        }
        var placeName: String?
        if let place, case let .undiscoveredPlace(p) = place.kind { placeName = p.name }
        let walks = historyWalks
        let home = walks.min { $0.startedAt < $1.startedAt }?.segments.first?.first?.coordinate
        let newMeters = stats.recaps.mapValues(\.newDistanceMeters)
        let facts = WorldFacts.compute(walks: walks, newMeters: newMeters, home: home, now: Date(),
                                       frontier: frontierLabel, newPlace: placeName)
        guard !facts.quests.isEmpty else { coach = nil; return }
        let key = "\(Self.today())|\(facts.hash)|\(demoMode)"
        guard key != coachKey else { return }
        coachKey = key
        let sample = demoMode
        func idea(for quest: WorldFacts.Quest) -> AdventureIdea? { quest == .frontier ? frontier : place }
        guard let fallbackQuest = facts.quests.first, let fallbackIdea = idea(for: fallbackQuest) else { return }
        let computed = CoachRenderer.computed(facts) ?? ""
        coach = CoachCard(text: computed, status: .working, signal: facts.signal, idea: fallbackIdea, sample: sample)
        Task { [weak self] in
            guard let self else { return }
            var card = CoachCard(text: computed, status: .computed(reason: ""), signal: facts.signal,
                                 idea: fallbackIdea, sample: sample)
            do {
                let (outcome, _) = try await self.ai.run { await CoachPrompt.choose(facts: facts, engine: $0) }
                switch outcome {
                case let .valid(choice):
                    if let text = CoachRenderer.render(choice, facts: facts), let chosen = idea(for: choice.quest) {
                        card = CoachCard(text: text, status: .ai, signal: facts.signal, idea: chosen, sample: sample)
                    } else {
                        card.status = .computed(reason: "AI reply could not be rendered")
                    }
                case .invalid: card.status = .computed(reason: "AI reply was rejected")
                case let .engineError(message): card.status = .computed(reason: message)
                }
            } catch {
                card.status = .computed(reason: "On-device AI unavailable")
            }
            // A newer trend (or a dismissal) wins over this slower answer.
            guard self.coachKey == key, self.coach != nil else { return }
            self.coach = card
        }
    }

    func acceptCoach() {
        guard let card = coach else { return }
        choose(card.idea)
        dismissCoach()
    }

    func dismissCoach() {
        UserDefaults.standard.set(Self.today(), forKey: Self.dismissedDayKey)
        coach = nil
    }
}
