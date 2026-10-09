import LifeOffDeskCore
import Network
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmErase = false

    var body: some View {
        NavigationStack {
            List {
                Section("Privacy") {
                    Text("No account. Walks, exploration and planner requests stay on this iPhone; inference runs on-device. iOS device backups may include app data.")
                        .font(.footnote).foregroundStyle(Theme.secondaryInk)
                    Button("Erase my walks and exploration", role: .destructive) { confirmErase = true }
                        .foregroundStyle(Theme.danger)
                        .disabled(!model.canErase)
                    if !model.canErase {
                        Text("Finish the current walk before erasing.").font(.footnote).foregroundStyle(Theme.secondaryInk)
                    }
                }
                Section("Starter maps") {
                    ForEach(model.content?.packs ?? [], id: \.region.id) { pack in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pack.region.name)
                            Text(pack.region.hasFullDetail
                                 ? "Streets, footpaths and \(pack.catalog?.places.count ?? 0) places. \(pack.region.coverageStatus)."
                                 : "Main roads only; walks are recorded anywhere. \(pack.region.coverageStatus).")
                                .font(.footnote).foregroundStyle(Theme.secondaryInk)
                        }
                    }
                    Text("Places are OpenStreetMap source records, not reviewed for hours, prices or access. Walks outside these areas are still recorded.")
                        .font(.footnote).foregroundStyle(Theme.secondaryInk)
                    Text("Map data © OpenStreetMap contributors, ODbL.").font(.footnote)
                    Link("openstreetmap.org/copyright", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                        .font(.footnote)
                }
                Section("Build evidence") {
                    NavigationLink("On-device AI diagnostics") { AIDiagnosticsView(ai: model.ai).environmentObject(model) }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Erase all walks and exploration on this iPhone?", isPresented: $confirmErase,
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
                Button("Verify SHA-256") { Task { await ai.verifyModelHash() } }
                if let hash = ai.hashResult { Text(hash).font(.footnote.monospaced()) }
            }
            Section("Taglish evaluation (12 cases)") {
                Button(running ? "Running on this iPhone…" : "Run all cases") { Task { await runEvaluation() } }
                    .disabled(running)
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

    private func runEvaluation() async {
        guard let content = model.content,
              let url = Bundle.main.url(forResource: "taglish-cases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let cases = try? JSONDecoder().decode(PlannerEvaluation.CaseFile.self, from: data).cases else { return }
        running = true
        defer { running = false }
        guard let engine = await ai.ensureLoaded() else { return }
        let planner = Planner(engine: engine)
        let warm = Date()
        _ = await planner.extract("Warm-up: gusto ko ng park.")
        firstRequestSeconds = Date().timeIntervalSince(warm)
        let start = Date()
        // Same origin as the development run so results are comparable.
        results = await PlannerEvaluation.run(cases: cases, planner: planner, catalog: content.catalog,
                                              origin: .areaCenter(content.region.center))
        runSeconds = Date().timeIntervalSince(start)
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
