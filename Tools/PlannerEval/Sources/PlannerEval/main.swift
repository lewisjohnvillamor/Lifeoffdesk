import Foundation
import LifeOffDeskCore

// Usage: planner-eval <model.gguf> <repo-root> [--no-grammar] [--out results.json]
let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: planner-eval <model.gguf> <repo-root> [--no-grammar] [--out file]\n".utf8))
    exit(2)
}
let modelPath = args[1]
let root = URL(fileURLWithPath: args[2])
let useGrammar = !args.contains("--no-grammar")
let outPath = args.firstIndex(of: "--out").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }

// Evaluate against the primary (Makati) pack so results stay comparable across runs.
let pack = root.appendingPathComponent("LifeOffDesk/Resources/StarterData/makati-cbd-starter")
let catalog = try PlaceCatalog.decode(Data(contentsOf: pack.appendingPathComponent("places.json")))
let region = try JSONDecoder().decode(RegionManifest.self, from: Data(contentsOf: pack.appendingPathComponent("region.json")))
let cases = try JSONDecoder().decode(PlannerEvaluation.CaseFile.self,
                                     from: Data(contentsOf: root.appendingPathComponent("eval/taglish-cases.json"))).cases

let engine = try LlamaEngine.load(path: modelPath)
let info = engine.info
print("runtime \(info.runtimeVersion) load \(String(format: "%.2f", info.loadSeconds))s ctx \(info.contextLength) threads \(info.threads) grammar \(useGrammar)")

// Cold request is measured separately from the scored cases.
let planner = Planner(engine: engine, useGrammar: useGrammar)
let coldStart = Date()
_ = await planner.extract("Warm-up: gusto ko ng park.")
let coldSeconds = Date().timeIntervalSince(coldStart)
print("first request \(String(format: "%.2f", coldSeconds))s")

// Distances from the starter area reference point: this machine has no GPS fix.
let results = await PlannerEvaluation.run(cases: cases, planner: planner, catalog: catalog,
                                          origin: .areaCenter(region.center))
for r in results {
    let seconds = r.attemptSeconds.map { String(format: "%.2f", $0) }.joined(separator: "+")
    print("#\(r.id) \(r.intentPass ? "PASS" : "FAIL") schema=\(r.schemaValid) \(r.outcome) \(seconds)s | \(r.prompt)")
    print("    \(r.rawOutputs.last ?? "-")")
    if !r.notes.isEmpty { print("    notes: \(r.notes.joined(separator: "; "))") }
}
let schemaOK = results.filter(\.schemaValid).count, intentOK = results.filter(\.intentPass).count
print("schema-valid \(schemaOK)/\(results.count), intent pass \(intentOK)/\(results.count)")

if let outPath {
    struct Report: Encodable {
        var label: String, machine: String, runtime: String, modelPath: String, modelBytes: Int64
        var loadSeconds: Double, firstRequestSeconds: Double, grammar: Bool, results: [PlannerEvaluation.CaseResult]
    }
    #if os(Linux)
    let machine = "Linux \(ProcessInfo.processInfo.operatingSystemVersionString), CPU only"
    #else
    let machine = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    #endif
    let report = Report(label: "Development-machine diagnostic. NOT iPhone evidence.", machine: machine,
                        runtime: info.runtimeVersion, modelPath: URL(fileURLWithPath: modelPath).lastPathComponent,
                        modelBytes: info.modelBytes, loadSeconds: info.loadSeconds, firstRequestSeconds: coldSeconds,
                        grammar: useGrammar, results: results)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: URL(fileURLWithPath: outPath))
}
