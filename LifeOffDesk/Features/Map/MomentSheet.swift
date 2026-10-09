import LifeOffDeskCore
import SwiftUI

/// A photo pin opened from the map: the photo, when and where it was taken, and its adventure.
struct MomentSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let memory: WalkMemory
    let openAdventure: (WalkSession) -> Void

    private var session: WalkSession? { model.historyWalks.first { $0.id == memory.sessionID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let image = model.photo(for: memory) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .accessibilityLabel("Photo from \(memory.takenAt.formatted(date: .abbreviated, time: .shortened))")
                    } else {
                        Text("Photo not available on this device.").foregroundStyle(Theme.secondaryInk)
                    }
                    Label(memory.takenAt.formatted(date: .complete, time: .shortened), systemImage: "clock")
                        .font(.subheadline).foregroundStyle(Theme.ink)
                    if model.isDemoMoment(memory) {
                        Text("Sample capture (illustration) on a sample adventure.").font(.caption).foregroundStyle(Theme.secondaryInk)
                    }
                    if let session {
                        ChoiceButton(title: "Open this adventure", systemImage: "map") { openAdventure(session) }
                    }
                }
                .padding(Theme.inset)
            }
            .background(Theme.canvas)
            .navigationTitle("Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
