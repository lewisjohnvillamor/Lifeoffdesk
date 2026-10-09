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
let casesPath = args.firstIndex(of: "--cases").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "eval/taglish-cases.json"
let cases = try JSONDecoder().decode(PlannerEvaluation.CaseFile.self,
                                     from: Data(contentsOf: root.appendingPathComponent(casesPath))).cases

let engine = try LlamaEngine.load(path: modelPath)
let info = engine.info
print("runtime \(info.runtimeVersion) load \(String(format: "%.2f", info.loadSeconds))s ctx \(info.contextLength) threads \(info.threads) grammar \(useGrammar)")

// --task history|recap: the other local-AI tasks (P0-12, P0-13). Development diagnostics only.
if let task = args.firstIndex(of: "--task").flatMap({ $0 + 1 < args.count ? args[$0 + 1] : nil }) {
    try await runTask(task, engine: engine, root: root, casesPath: casesPath, outPath: outPath, modelPath: modelPath)
    exit(0)
}

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

struct TaskCaseResult: Encodable {
    var id: Int, input: String, rawOutputs: [String], seconds: [Double], schemaValid: Bool, pass: Bool, result: String, notes: [String]
}

func runTask(_ task: String, engine: LlamaEngine, root: URL, casesPath: String, outPath: String?, modelPath: String) async throws {
    let data = try Data(contentsOf: root.appendingPathComponent(casesPath))
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let cases = json["cases"] as! [[String: Any]]
    var results: [TaskCaseResult] = []
    switch task {
    case "history":
        let iso = ISO8601DateFormatter()
        let now = iso.date(from: json["referenceDate"] as! String)!
        let zone = TimeZone(identifier: json["timeZone"] as! String)!
        for c in cases {
            let question = c["question"] as! String, expect = c["expect"] as! [String: Any]
            let (outcome, attempts) = await HistoryQueryPrompt.extract(question, engine: engine, now: now, timeZone: zone)
            var notes: [String] = [], pass = true, text = ""
            switch outcome {
            case let .valid(.query(q)):
                text = "\(q)"
                if expect["clarify"] as? Bool == true { pass = false; notes.append("expected clarification") }
                for (key, want) in expect where key != "clarify" {
                    let ok: Bool
                    switch key {
                    case "period": ok = q.period.rawValue == want as? String
                    case "from": ok = q.from == want as? String
                    case "to": ok = q.to == want as? String
                    case "minActiveMinutes": ok = q.minActiveMinutes == want as? Int
                    case "maxActiveMinutes": ok = q.maxActiveMinutes == want as? Int
                    case "hasPhotos": ok = q.hasPhotos == want as? Bool
                    case "categories": ok = Set(want as? [String] ?? []).isSubset(of: Set(q.categories.map(\.rawValue)))
                    case "sort": ok = q.sort.rawValue == want as? String
                    case "limit": ok = q.limit == want as? Int
                    default: ok = false
                    }
                    if !ok { pass = false; notes.append("expected \(key)=\(want)") }
                }
            case let .valid(.clarify(question)):
                text = "clarify: \(question)"
                if expect["clarify"] as? Bool != true { pass = false; notes.append("unexpected clarification") }
            case .invalid: pass = false; text = "invalid"
            case let .engineError(m): pass = false; text = "engine error \(m)"
            }
            let schemaValid: Bool = { if case .valid = outcome { return true }; return false }()
            results.append(TaskCaseResult(id: c["id"] as! Int, input: question, rawOutputs: attempts.map(\.rawOutput),
                                          seconds: attempts.map(\.seconds), schemaValid: schemaValid, pass: pass,
                                          result: text, notes: notes))
        }
    case "recap":
        for c in cases {
            let facts = RecapFacts(sessionID: UUID(), facts: (c["facts"] as! [[String: String]]).map {
                RecapFacts.Fact(id: RecapFacts.FactID(rawValue: $0["id"]!)!, value: $0["value"]!)
            }, placeNames: c["placeNames"] as! [String])
            let (outcome, attempts) = await RecapNarrationPrompt.choose(facts: facts, engine: engine)
            var text = "", pass = false
            if case let .valid(choice) = outcome, let rendered = RecapNarrator.render(choice, facts: facts) {
                text = rendered; pass = true
            } else { text = "\(outcome)" }
            results.append(TaskCaseResult(id: c["id"] as! Int, input: facts.facts.map { "\($0.id.rawValue)=\($0.value)" }.joined(separator: ", "),
                                          rawOutputs: attempts.map(\.rawOutput), seconds: attempts.map(\.seconds),
                                          schemaValid: pass, pass: pass, result: text, notes: []))
        }
    default:
        print("unknown task \(task)"); exit(2)
    }
    for r in results {
        print("#\(r.id) \(r.pass ? "PASS" : "FAIL") \(r.seconds.map { String(format: "%.2f", $0) }.joined(separator: "+"))s | \(r.input)")
        print("    \(r.rawOutputs.last ?? "-")")
        print("    -> \(r.result)\(r.notes.isEmpty ? "" : "  notes: " + r.notes.joined(separator: "; "))")
    }
    print("\(task): schema-valid \(results.filter(\.schemaValid).count)/\(results.count), pass \(results.filter(\.pass).count)/\(results.count)")
    if let outPath {
        struct Report: Encodable { var label: String, task: String, model: String, results: [TaskCaseResult] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Report(label: "Development-machine diagnostic (Linux CPU). NOT iPhone evidence.", task: task,
                                  model: URL(fileURLWithPath: modelPath).lastPathComponent, results: results))
            .write(to: URL(fileURLWithPath: outPath))
    }
}
