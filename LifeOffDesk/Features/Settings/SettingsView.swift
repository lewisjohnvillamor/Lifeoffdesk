import LifeOffDeskCore
import Network
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmErase = false
    @AppStorage("hasSeenIntro") private var hasSeenIntro = false

    var body: some View {
        NavigationStack {
            List {
                Section("Privacy") {
                    Text("No account. Walks, exploration and planner requests stay on this iPhone; inference runs on-device. iOS device backups may include app data.")
                        .font(.footnote).foregroundStyle(Theme.secondaryInk)
                    Button("Erase my adventures and exploration", role: .destructive) { confirmErase = true }
                        .foregroundStyle(Theme.danger)
                        .disabled(!model.canErase)
                    if !model.canErase {
                        Text("Finish the current adventure before erasing.").font(.footnote).foregroundStyle(Theme.secondaryInk)
                    }
                }
                PreferencesSection()
                Section("Starter maps") {
                    let loaded = model.content?.loadedIDs ?? []
                    ForEach(model.regions?.manifests ?? [], id: \.id) { region in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(region.name)
                                Spacer()
                                Text(model.loadingRegions.contains(region.id) ? "Loading…" : loaded.contains(region.id) ? "In memory" : "On demand")
                                    .font(.caption).foregroundStyle(Theme.secondaryInk)
                            }
                            Text(region.hasFullDetail
                                 ? "Streets, footpaths and named places. \(region.coverageStatus)."
                                 : "Main roads only; adventures are recorded anywhere. \(region.coverageStatus).")
                                .font(.footnote).foregroundStyle(Theme.secondaryInk)
                        }
                    }
                    Text("Cities load when the map, your location, a search or a past adventure reaches them, and are freed when far away.")
                        .font(.footnote).foregroundStyle(Theme.secondaryInk)
                    Text("Places are OpenStreetMap source records, not reviewed for hours, prices or access. Walks outside these areas are still recorded.")
                        .font(.footnote).foregroundStyle(Theme.secondaryInk)
                    Text("Map data © OpenStreetMap contributors, ODbL.").font(.footnote)
                    Link("openstreetmap.org/copyright", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                        .font(.footnote)
                }
                Section("Presentation") {
                    Button("Show intro again") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { hasSeenIntro = false }
                    }
                    Toggle("Demo map (sample adventures)", isOn: Binding(get: { model.demoMode },
                                                                    set: { model.setDemoMode($0) }))
                        .disabled(model.activeSession != nil)
                    Text("Shows bundled synthetic walks generated along real Makati and Muntinlupa streets so people can see a well-explored map. Clearly labelled, never saved to your walks. Turn off for your real map.")
                        .font(.footnote).foregroundStyle(Theme.secondaryInk)
                }
                Section("Build evidence") {
                    NavigationLink("On-device AI diagnostics") { AIDiagnosticsView(ai: model.ai).environmentObject(model) }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Erase all adventures and exploration on this iPhone?", isPresented: $confirmErase,
                                titleVisibility: .visible) {
                Button("Erase", role: .destructive) { model.erasePersonalData() }
            } message: {
                Text("The AI model and starter map stay installed. This cannot be undone.")
            }
        }
    }
}

/// Collects phone evidence for docs/BUILD-STATUS.md: model hash, load time, latency and
/// the 12 Taglish cases run through the real on-device planner.
struct AIDiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    /// Observed directly so load/hash state changes refresh this screen.
    @ObservedObject var ai: AIService
    @StateObject private var network = NetworkStatus()
    @State private var results: [PlannerEvaluation.CaseResult] = []
    @State private var running = false
    @State private var runSeconds: Double?
    @State private var firstRequestSeconds: Double?
    @State private var copied = false
    @State private var runError: String?

    var body: some View {
        List {
            Section("Device") {
                row("Device", DeviceInfo.modelIdentifier)
                row("iOS", UIDevice.current.systemVersion)
                row("Network path", network.description)
                Text("For the offline check: Airplane Mode on, Wi-Fi off, Mac disconnected.")
                    .font(.footnote).foregroundStyle(Theme.secondaryInk)
            }
            Section("Model") {
                row("File", AIService.modelURL()?.lastPathComponent ?? "missing")
                row("Location", AIService.modelURL().map { $0.path.contains("/Documents/") ? "Documents" : "App bundle" } ?? "—")
                if let info = ai.loadInfo {
                    row("Runtime", "llama.cpp \(info.runtimeVersion)")
                    row("Bytes", "\(info.modelBytes)")
                    row("Load time", String(format: "%.2f s", info.loadSeconds))
                    row("Context / threads / GPU layers", "\(info.contextLength) / \(info.threads) / \(info.gpuLayers)")
                }
                row("State", "\(ai.state)")
                Text("The model loads only when needed (planner, search, recap or this button) and unloads when an adventure starts.")
                    .font(.footnote).foregroundStyle(Theme.secondaryInk)
                Button(ai.state == .loading ? "Loading…" : "Load model now") { Task { await ai.preload() } }
                    .disabled(ai.state == .loading || ai.state == .ready || model.activeSession != nil)
                if let problem = ai.lastProblem { row("Last problem", problem) }
                if let interruption = ai.lastInterruption { row("Last interruption", interruption) }
                ForEach(model.content?.issues ?? [], id: \.self) { row("Data issue", $0) }
                row("Access facts loaded", "\(model.content?.evidence.count ?? 0)")
                row("Cities in memory", "\(model.content?.packs.count ?? 0) of \(model.regions?.manifests.count ?? 0)")
                Button("Verify SHA-256") { Task { await ai.verifyModelHash() } }
                if let hash = ai.hashResult { Text(hash).font(.footnote.monospaced()) }
            }
            Section("Taglish evaluation") {
                Button(running ? "Running on this iPhone…" : "Run 14 tuning cases") { Task { await runEvaluation("taglish-cases") } }
                    .disabled(running)
                Button("Run 60 held-out cases") { Task { await runEvaluation("taglish-heldout") } }
                    .disabled(running)
                if let runError { Text(runError).font(.footnote).foregroundStyle(Theme.danger) }
                if let first = firstRequestSeconds { row("First request after load", String(format: "%.2f s", first)) }
                if !results.isEmpty {
                    row("Schema-valid", "\(results.filter(\.schemaValid).count)/\(results.count)")
                    row("Intent pass", "\(results.filter(\.intentPass).count)/\(results.count)")
                    if let runSeconds { row("Total", String(format: "%.1f s", runSeconds)) }
                    Button(copied ? "Copied" : "Copy JSON report") { copyReport() }
                }
                ForEach(results, id: \.id) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("#\(r.id) \(r.intentPass ? "PASS" : "FAIL") · \(r.outcome) · \(r.attemptSeconds.map { String(format: "%.1fs", $0) }.joined(separator: "+"))")
                            .font(.footnote.weight(.semibold))
                        Text(r.prompt).font(.footnote)
                        Text(r.rawOutputs.last ?? "—").font(.caption.monospaced()).foregroundStyle(Theme.secondaryInk)
                        if !r.notes.isEmpty { Text(r.notes.joined(separator: "; ")).font(.caption).foregroundStyle(Theme.danger) }
                    }
                }
            }
        }
        .navigationTitle("AI diagnostics")
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(Theme.secondaryInk)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).foregroundStyle(Theme.ink)
        }
        .font(.footnote)
    }

    private func runEvaluation(_ file: String) async {
        guard let content = model.content,
              let url = Bundle.main.url(forResource: file, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let cases = try? JSONDecoder().decode(PlannerEvaluation.CaseFile.self, from: data).cases else { return }
        running = true
        defer { running = false }
        let catalog = content.catalog, center = content.region.center
        do {
            let warm = Date()
            _ = try await ai.run { await Planner(engine: $0).extract("Warm-up: gusto ko ng park.") }
            firstRequestSeconds = Date().timeIntervalSince(warm)
            let start = Date()
            // Same origin as the development run so results are comparable.
            results = try await ai.run { engine in
                await PlannerEvaluation.run(cases: cases, planner: Planner(engine: engine), catalog: catalog,
                                            origin: .areaCenter(center))
            }
            runSeconds = Date().timeIntervalSince(start)
        } catch {
            runError = "\(error)"
        }
    }

    private func copyReport() {
        struct Report: Encodable {
            var device: String, iOS: String, network: String, runtime: String?, modelBytes: Int64?
            var loadSeconds: Double?, firstRequestSeconds: Double?, hash: String?, results: [PlannerEvaluation.CaseResult]
        }
        let info = ai.loadInfo
        let report = Report(device: DeviceInfo.modelIdentifier, iOS: UIDevice.current.systemVersion,
                            network: network.description, runtime: info?.runtimeVersion, modelBytes: info?.modelBytes,
                            loadSeconds: info?.loadSeconds, firstRequestSeconds: firstRequestSeconds,
                            hash: ai.hashResult, results: results)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) {
            UIPasteboard.general.string = String(decoding: data, as: UTF8.self)
            copied = true
        }
    }
}

enum DeviceInfo {
    /// Hardware identifier, e.g. "iPhone13,4" is iPhone 12 Pro Max.
    static var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// Reports the current network path so offline runs can be recorded honestly.
final class NetworkStatus: ObservableObject {
    @Published private(set) var description = "checking…"
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let text: String
            switch path.status {
            case .satisfied: text = "online (\(path.availableInterfaces.map { "\($0.type)" }.joined(separator: ", ")))"
            case .unsatisfied: text = "offline (no network path)"
            case .requiresConnection: text = "requires connection"
            @unknown default: text = "unknown"
            }
            DispatchQueue.main.async { self?.description = text }
        }
        monitor.start(queue: DispatchQueue(label: "network-status"))
    }

    deinit { monitor.cancel() }
}

/// P0-14: explicit, editable preferences. Nothing is saved unless the user taps Save.
struct PreferencesSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = PreferenceProfile()
    @State private var loaded = false
    @State private var saved = false

    var body: some View {
        Section {
            if let locked = model.preferencesLocked {
                Text(locked).font(.footnote).foregroundStyle(Theme.danger)
            } else {
                categoryPicker
                Picker("Usual time", selection: Binding(get: { draft.durationMinutes ?? 0 },
                                                        set: { draft.durationMinutes = $0 == 0 ? nil : $0 })) {
                    Text("Not set").tag(0)
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker("Search radius", selection: Binding(get: { Int(draft.radiusMeters ?? 0) },
                                                           set: { draft.radiusMeters = $0 == 0 ? nil : Double($0) })) {
                    Text("Default (2 km)").tag(0)
                    ForEach([500, 1000, 2000, 3000, 5000], id: \.self) { Text(Format.distance(Double($0))).tag($0) }
                }
                Picker("Prefer", selection: $draft.novelty) {
                    Text("Anything").tag(PreferenceProfile.Novelty.any)
                    Text("New places").tag(PreferenceProfile.Novelty.new)
                    Text("Familiar places").tag(PreferenceProfile.Novelty.familiar)
                }
                Toggle("Step-free entrance required", isOn: need(.stepFreeEntrance))
                Toggle("Wheelchair access required", isOn: need(.wheelchair))
                if !draft.accessNeeds.isEmpty {
                    Text("Hard filter: only places with a reviewed, current record qualify. Few or none may show. The path to a place is never verified. Stored only on this iPhone; remove anytime.")
                        .font(.footnote).foregroundStyle(Theme.secondaryInk)
                }
                HStack {
                    Button(saved ? "Saved" : "Save preferences") { saved = model.savePreferences(draft) }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    Button("Reset", role: .destructive) {
                        model.resetPreferences()
                        draft = PreferenceProfile()
                        saved = false
                    }
                    .disabled(model.preferenceProfile == nil)
                }
                if let problem = model.preferencesProblem {
                    Text(problem).font(.footnote).foregroundStyle(Theme.danger)
                } else if !saved && draft != savedComparable {
                    Text("Unsaved changes").font(.footnote).foregroundStyle(Theme.secondaryInk)
                }
            }
        } header: {
            Text("My preferences")
        } footer: {
            Text("Used to fill gaps in a planner request; what you type always wins. Never learned from your routes or photos.")
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft = model.preferenceProfile ?? PreferenceProfile()
            draft.updatedAt = nil
        }
        .onChange(of: draft) { _, _ in saved = false }
    }

    /// The saved profile without its timestamp, to detect unsaved edits.
    private var savedComparable: PreferenceProfile {
        var p = model.preferenceProfile ?? PreferenceProfile()
        p.updatedAt = nil
        return p
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Favourite kinds of places (up to 3)").font(.subheadline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PlaceCategory.allCases, id: \.self) { category in
                        let on = draft.categories.contains(category)
                        Button(PlannerCopy.categoryWord(category).capitalized) {
                            if on { draft.categories.removeAll { $0 == category } }
                            else if draft.categories.count < 3 { draft.categories.append(category) }
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(on ? Theme.primary : Theme.surface, in: Capsule())
                        .foregroundStyle(on ? Theme.canvas : Theme.ink)
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func need(_ need: AccessNeed) -> Binding<Bool> {
        Binding(get: { draft.accessNeeds.contains(need) },
                set: { on in
                    if on { if !draft.accessNeeds.contains(need) { draft.accessNeeds.append(need) } }
                    else { draft.accessNeeds.removeAll { $0 == need } }
                })
    }
}
