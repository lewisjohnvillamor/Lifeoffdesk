import LifeOffDeskCore
import SwiftUI
import UIKit

/// Safety sheet: emergency call, your location in words, and the nearest police stations,
/// hospitals and fire stations from the offline OSM data with a route on the map.
struct HelpSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: HelpSnapshot?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    emergencyCard
                    NavigationLink {
                        SafetyChatView(onRoute: { dismiss() }).environmentObject(model)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "cross.case.fill").font(.title3).foregroundStyle(Theme.canvas)
                                .frame(width: 44, height: 44).background(Theme.primary, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ask the help assistant").font(.headline).foregroundStyle(Theme.ink)
                                Text("First aid, heat, floods, bites, lost, low battery · offline")
                                    .font(.caption).foregroundStyle(Theme.secondaryInk)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryInk)
                        }
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner))
                    }
                    .buttonStyle(.plain)
                    locationCard
                    if let snapshot, snapshot.position != nil {
                        ForEach(HelpKind.allCases, id: \.self) { kind in
                            section(kind, snapshot.places[kind] ?? [])
                        }
                    } else if snapshot != nil {
                        note("Waiting for GPS to list the nearest police stations, hospitals and fire stations.")
                    } else {
                        ProgressView("Looking in the offline map…").frame(maxWidth: .infinity)
                    }
                    note("Places come from OpenStreetMap and nobody has checked them: a station may have moved, " +
                         "closed or be closed now. The route follows mapped streets only. In an emergency, call first.")
                }
                .padding(Theme.inset)
            }
            .background(Theme.canvas)
            .navigationTitle("Get help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            // Runs again once a GPS fix arrives.
            .task(id: model.currentPosition == nil) { snapshot = await model.nearbyHelp() }
        }
    }

    private var emergencyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Link(destination: URL(string: "tel:911")!) {
                Label("Call 911", systemImage: "phone.fill")
                    .font(.title3.bold()).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.danger, in: RoundedRectangle(cornerRadius: 16))
            }
            .accessibilityHint("Philippine national emergency hotline")
            Text("911 is the Philippine emergency hotline. A call needs cell signal, not mobile data.")
                .font(.footnote).foregroundStyle(Theme.secondaryInk)
        }
    }

    @ViewBuilder private var locationCard: some View {
        if let text = snapshot?.locationText {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your location").font(.headline).foregroundStyle(Theme.ink)
                Text(text).font(.body.monospacedDigit()).foregroundStyle(Theme.ink).textSelection(.enabled)
                HStack(spacing: 12) {
                    Button(copied ? "Copied" : "Copy") {
                        UIPasteboard.general.string = text
                        copied = true
                    }
                    .buttonStyle(.bordered).frame(minHeight: Theme.minTarget)
                    ShareLink("Text it", item: "My location: \(text)")
                        .buttonStyle(.bordered).frame(minHeight: Theme.minTarget)
                }
                Text("Read it to the dispatcher or text it (SMS works without mobile data).")
                    .font(.footnote).foregroundStyle(Theme.secondaryInk)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner))
            .accessibilityElement(children: .contain)
        }
    }

    private func section(_ kind: HelpKind, _ places: [HelpPlace]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(kind.title, systemImage: PlaceIcon.symbol(kind)).font(.headline).foregroundStyle(Theme.ink)
            if places.isEmpty {
                Text("None mapped within 10 km in the offline map loaded now.")
                    .font(.footnote).foregroundStyle(Theme.secondaryInk)
            }
            ForEach(places) { help in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(help.place.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                        Text(PlannerCopy.distanceText(help.street, straightLine: help.straightLineMeters)
                             + (help.street?.throughRestricted == true ? " · via a private or gated way" : ""))
                            .font(.footnote).foregroundStyle(Theme.secondaryInk)
                    }
                    Spacer()
                    Button("Route") {
                        model.choose(help.place)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.primary)
                    .frame(minHeight: Theme.minTarget)
                    .accessibilityLabel("Show route to \(help.place.name)")
                }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(Theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
    }
}
