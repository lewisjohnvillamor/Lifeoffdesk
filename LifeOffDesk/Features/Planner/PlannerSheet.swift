import LifeOffDeskCore
import SwiftUI

/// Taglish planner. The on-device model extracts preferences; app code finds actual places.
struct PlannerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool

    /// Quick picks fill the request and still go through the on-device model.
    private let quickPicks: [(icon: String, text: String)] = [
        ("cup.and.saucer", "Kape muna, 30 mins"),
        ("leaf", "Tahimik na park"),
        ("building.columns", "Museum, may 1 hour ako"),
        ("books.vertical", "Library, lakad lang"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    inputBar
                    if showQuickPicks { quickPickRow }
                    stateView
                }
                .padding(Theme.inset)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .navigationTitle("Saan tayo?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { radiusMenu }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Places © OpenStreetMap · not verified")
                    .font(.caption2).foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(Theme.canvas)
            }
            .onAppear { if model.plannerText.isEmpty { inputFocused = true } }
        }
    }

    private var isBusy: Bool { model.plannerState == .loadingModel || model.plannerState == .thinking }
    private var showQuickPicks: Bool { model.plannerState == .idle }
    private var canAsk: Bool { !model.plannerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(PlannerCopy.placeholder, text: $model.plannerText, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.vertical, 12).padding(.leading, 14)
                .accessibilityLabel("Outing request")
            Group {
                if isBusy {
                    Button { model.cancelPlanning() } label: {
                        Image(systemName: "stop.fill").font(.system(size: 14, weight: .bold))
                    }
                    .accessibilityLabel("Cancel")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold))
                    }
                    .disabled(!canAsk)
                    .accessibilityLabel("Ask")
                }
            }
            .foregroundStyle(Theme.canvas)
            .frame(width: 36, height: 36)
            .background(canAsk || isBusy ? Theme.primary : Theme.border, in: Circle())
            .frame(width: Theme.minTarget, height: Theme.minTarget)
            .padding(.trailing, 2).padding(.bottom, 2)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.border))
    }

    private func send() {
        guard canAsk else { return }
        inputFocused = false
        model.ask()
    }

    private var quickPickRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickPicks, id: \.text) { pick in
                    Button {
                        model.plannerText = pick.text
                        send()
                    } label: {
                        Label(pick.text, systemImage: pick.icon)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 38)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(Theme.border))
                    }
                }
            }
        }
    }

    private var radiusMenu: some View {
        Menu {
            ForEach([1000.0, 2000, 3000, 5000], id: \.self) { meters in
                Button(Format.distance(meters)) { model.searchRadiusMeters = meters }
            }
        } label: {
            Label(Format.distance(model.searchRadiusMeters), systemImage: "scope")
                .labelStyle(.titleAndIcon).font(.subheadline)
        }
        .accessibilityLabel("Search radius \(Format.distance(model.searchRadiusMeters))")
    }

    @ViewBuilder private var stateView: some View {
        switch model.plannerState {
        case .idle:
            EmptyView()
        case .loadingModel, .thinking:
            HStack(spacing: 10) {
                ProgressView()
                Text(model.plannerState == .loadingModel ? "Loading…" : "Nag-iisip…").foregroundStyle(Theme.secondaryInk)
            }
            .accessibilityElement(children: .combine)
        case let .modelUnavailable(message):
            note(message)
            manualFilters
        case let .answered(response, usedAI):
            answer(response, usedAI: usedAI)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(Theme.ink)
    }

    @ViewBuilder private func answer(_ response: PlannerResponse, usedAI: Bool) -> some View {
        switch response {
        case let .suggestions(_, intro, suggestions):
            Text(usedAI ? intro : "Filter (no AI) · \(intro)")
                .font(.footnote).foregroundStyle(Theme.secondaryInk)
            VStack(spacing: 10) {
                ForEach(suggestions) { SuggestionCard(suggestion: $0) }
            }
        case .noMatch:
            note(PlannerCopy.noMatch)
            manualFilters
        case let .clarify(_, question):
            note(question)
        case .failed:
            note(PlannerCopy.modelFailure)
            manualFilters
        }
    }

    private var manualFilters: some View {
        HStack(spacing: 8) {
            ForEach([PlaceCategory.park, .cafe, .museum, .library], id: \.self) { category in
                Button(PlannerCopy.categoryWord(category).capitalized) { model.manualSearch(category: category) }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .frame(minHeight: Theme.minTarget)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filters without AI")
    }
}

struct SuggestionCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let suggestion: Suggestion
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 40, height: 40)
                    .background(Theme.revealedGround, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.place.name).font(.headline).foregroundStyle(Theme.ink).lineLimit(2)
                    Text(PlannerCopy.reason(suggestion)).font(.subheadline).foregroundStyle(Theme.secondaryInk)
                }
                Spacer(minLength: 8)
                Button(isChosen ? "Set" : "Go") {
                    model.choose(suggestion.place)
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.canvas)
                .padding(.horizontal, 18)
                .frame(minHeight: Theme.minTarget)
                .background(Theme.primary, in: Capsule())
                .accessibilityLabel("Set \(suggestion.place.name) as destination")
            }
            Button { withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text(PlannerCopy.caveat(suggestion))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
                }
                .font(.caption).foregroundStyle(Theme.secondaryInk)
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(suggestion.uncertainties, id: \.self) { Text("• " + PlannerCopy.label($0)) }
                    if let url = URL(string: suggestion.place.sourceURL) {
                        Link("Source record", destination: url).foregroundStyle(Theme.primary)
                    }
                }
                .font(.caption).foregroundStyle(Theme.secondaryInk)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border))
    }

    private var isChosen: Bool { model.destination?.id == suggestion.id }

    private var icon: String {
        switch suggestion.place.category {
        case .park: return "leaf.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .museum: return "building.columns.fill"
        case .library: return "books.vertical.fill"
        case .scenic: return "binoculars.fill"
        case .other: return "mappin"
        }
    }
}
