import LifeOffDeskCore
import SwiftUI

/// Taglish planner. The on-device model extracts preferences; app code finds actual places.
struct PlannerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    input
                    radiusControl
                    stateView
                    attribution
                }
                .padding(Theme.inset)
            }
            .background(Theme.canvas)
            .navigationTitle("Help me choose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear { if model.plannerText.isEmpty { inputFocused = true } }
        }
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saan mo gustong pumunta?").font(.headline).foregroundStyle(Theme.ink)
            TextField(PlannerCopy.placeholder, text: $model.plannerText, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { model.ask() }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border))
                .accessibilityLabel("Outing request")
            Text("Halimbawa: “May 30 minutes ako, gusto ko ng quiet na park.”")
                .font(.footnote).foregroundStyle(Theme.secondaryInk)
            if isBusy {
                Button("Cancel") { model.cancelPlanning() }.buttonStyle(SecondaryButtonStyle())
            } else {
                Button("Ask") {
                    inputFocused = false
                    model.ask()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.plannerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var isBusy: Bool {
        model.plannerState == .loadingModel || model.plannerState == .thinking
    }

    private var radiusControl: some View {
        Stepper(value: $model.searchRadiusMeters, in: 500...SearchOptions.maxRadiusMeters, step: 500) {
            Text("Search within \(Format.distance(model.searchRadiusMeters)) straight-line")
                .font(.subheadline).foregroundStyle(Theme.ink)
        }
    }

    @ViewBuilder private var stateView: some View {
        switch model.plannerState {
        case .idle:
            EmptyView()
        case .loadingModel:
            progress("Loading the on-device model…")
        case .thinking:
            progress("Thinking on this iPhone…")
        case let .modelUnavailable(message):
            VStack(alignment: .leading, spacing: 12) {
                Text(message).foregroundStyle(Theme.ink)
                manualFilters
            }
        case let .answered(response, usedAI):
            answer(response, usedAI: usedAI)
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text).foregroundStyle(Theme.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func answer(_ response: PlannerResponse, usedAI: Bool) -> some View {
        if !usedAI {
            Label("Manual filter — not an AI suggestion", systemImage: "slider.horizontal.3")
                .font(.footnote).foregroundStyle(Theme.secondaryInk)
        }
        switch response {
        case let .suggestions(_, intro, suggestions):
            Text(intro).foregroundStyle(Theme.ink)
            ForEach(suggestions) { SuggestionCard(suggestion: $0) }
        case .noMatch:
            Text(PlannerCopy.noMatch).foregroundStyle(Theme.ink)
            manualFilters
        case let .clarify(_, question):
            Text(question).foregroundStyle(Theme.ink)
        case .failed:
            Text(PlannerCopy.modelFailure).foregroundStyle(Theme.ink)
            manualFilters
        }
    }

    private var manualFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or choose a filter (no AI):").font(.footnote).foregroundStyle(Theme.secondaryInk)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach([PlaceCategory.park, .cafe, .museum, .library], id: \.self) { category in
                        Button(PlannerCopy.categoryWord(category).capitalized) { model.manualSearch(category: category) }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 16)
                            .frame(minHeight: Theme.minTarget)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(Theme.border))
                    }
                }
            }
        }
    }

    private var attribution: some View {
        Text("Places: © OpenStreetMap contributors (ODbL). Source records are not independently verified; check hours and access before you go.")
            .font(.caption).foregroundStyle(Theme.secondaryInk)
    }
}

struct SuggestionCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let suggestion: Suggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(suggestion.place.name).font(.headline).foregroundStyle(Theme.ink)
            Text("\(PlannerCopy.categoryWord(suggestion.place.category).capitalized) · \(PlannerCopy.reason(suggestion))")
                .font(.subheadline).foregroundStyle(Theme.ink)
            ForEach(suggestion.uncertainties, id: \.self) { item in
                Label(PlannerCopy.label(item), systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(Theme.secondaryInk)
            }
            if let url = URL(string: suggestion.place.sourceURL) {
                Link("Source record", destination: url).font(.footnote).foregroundStyle(Theme.primary)
            }
            Button(model.destination?.id == suggestion.id ? "Chosen as destination" : "Set as destination") {
                model.choose(suggestion.place)
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .card()
    }
}
