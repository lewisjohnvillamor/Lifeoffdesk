import LifeOffDeskCore
import SwiftUI

/// Me tab: lifetime totals, photo spots and settings.
struct MeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.demoMode {
                        Label("Sample adventures · not real GPS", systemImage: "sparkles")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.danger)
                    }
                    totals
                    Text("SPOTS").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryInk)
                    spots
                }
                .padding(Theme.inset)
            }
            .background(PaperStyle.island)
            .navigationTitle("Me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings and privacy")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(model) }
            #if targetEnvironment(simulator)
            .task {
                // Screenshot helper (simulator only).
                guard ProcessInfo.processInfo.arguments.contains("--open-settings") else { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                showSettings = true
            }
            #endif
        }
    }

    private var totals: some View {
        let stats = model.stats
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                MascotView(pose: .welcome, size: 52)
                    .background(Theme.revealedGround, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Life Off Desk").font(.headline)
                    Text(stats.firstWalkAt.map { "Since \($0.formatted(.dateTime.month(.abbreviated).year()))" } ?? "Your first adventure is waiting")
                        .font(.footnote).foregroundStyle(Theme.secondaryInk)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(String(format: "%.2f km", stats.totalNewDistanceMeters / 1000))
                    .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                Text(model.statsPending ? "Calculating your totals…" : "Total new streets")
                    .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                if model.offStreetMeters >= 10 {
                    Text("+ \(Format.distance(model.offStreetMeters)) off mapped streets (counts toward area, not streets)")
                        .font(.caption).foregroundStyle(Theme.secondaryInk).padding(.top, 2)
                }
            }
            HStack(spacing: 0) {
                total("\(stats.walkCount)", "Adventures")
                Divider().frame(height: 40)
                total("\(model.discoveredPlaceIDs.count)", "Places found")
                Divider().frame(height: 40)
                total(Format.area(stats.exploredSquareMeters), "Area explored")
            }
        }
        .foregroundStyle(PaperStyle.ink)
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.border))
    }

    private func total(_ value: String, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(Theme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var spots: some View {
        let shown = model.mapMoments.sorted { $0.takenAt > $1.takenAt }
        if shown.isEmpty {
            HStack(spacing: 12) {
                MascotView(pose: .takingPhotos, size: 60)
                Text("Photos you take on an adventure are pinned to the map and kept here.")
            }
                .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.border))
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(shown) { moment in
                    Group {
                        if let image = model.thumbnail(for: moment) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            PaperStyle.paper
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("Photo from \(moment.takenAt.formatted(date: .abbreviated, time: .shortened))")
                }
            }
        }
    }
}
